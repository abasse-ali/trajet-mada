#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
TrajetMada : mise à jour automatique des prix et des horaires (serveur Oracle Cloud).

Récupère pour toute la période (mai à septembre de la prochaine saison par défaut) :
  - les prix des vols : Travelpayouts / Aviasales, allers simples et allers-retours ;
  - les prix FlixBus Toulouse <-> Paris, jour par jour ;
  - la grille officielle des prix SNCF (open data, sans clé) ;
  - les horaires SNCF (API SNCF) : jours déjà publiés et horaires types par jour de semaine ;
  - une vérification Google Flights (SerpApi) des meilleurs allers-retours, dans un budget quotidien.

Écrit trajetmada-data.json (lu par l'app iPhone) et rapport.md, puis publie sur la branche
« data » du dépôt GitHub (ou dans un dossier web).

Python 3.6 ou plus, sans dépendance.
Usage : python3 trajetmada_update.py [--config FICHIER] [--quick] [--no-publish]
"""
import argparse
import base64
import datetime as dt
import json
import os
import shutil
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor

FEED_VERSION = 1
USER_AGENT = "TrajetMada-update/1.0 (+https://github.com/abasse-ali/trajet-mada)"

# Lieux : mêmes identifiants que PlaceID dans l'app.
# PlaceID -> (code Travelpayouts, aéroports pour SerpApi)
AIRPORTS = {
    "TLS": ("TLS", "TLS"), "PAR": ("PAR", "CDG,ORY"), "MIL": ("MIL", "MXP,LIN,BGY"),
    "RUN": ("RUN", "RUN"), "DZA": ("DZA", "DZA"), "JNB": ("JNB", "JNB"),
    "TNR": ("TNR", "TNR"), "NOS": ("NOS", "NOS"), "DIE": ("DIE", "DIE"),
}
# Liaisons aériennes du réseau (premier lieu = côté France, sens de l'aller).
FLIGHTS = [
    ("TLS", "PAR"), ("TLS", "DIE"), ("TLS", "NOS"), ("TLS", "TNR"), ("TLS", "RUN"),
    ("PAR", "DIE"), ("PAR", "NOS"), ("PAR", "TNR"), ("PAR", "RUN"), ("PAR", "DZA"),
    ("PAR", "JNB"), ("PAR", "MIL"),
    ("RUN", "NOS"), ("RUN", "DIE"), ("RUN", "TNR"), ("RUN", "DZA"),
    ("DZA", "DIE"), ("DZA", "NOS"), ("JNB", "NOS"), ("MIL", "NOS"),
    ("TNR", "DIE"), ("TNR", "NOS"), ("NOS", "DIE"),
]
# Allers-retours à vérifier en priorité sur Google Flights (SerpApi).
# Allers-retours vérifiés sur Google Flights (aller côté France). Pas de Toulouse-Diego ni Paris-Diego :
# Google Flights ne vend aucun billet jusqu'à Antsiranana depuis la France.
SERP_ROUND_TRIPS = [("TLS", "NOS"), ("PAR", "TNR"), ("PAR", "NOS"), ("MIL", "NOS"), ("TLS", "TNR")]
# Vols intérieurs à Madagascar (Madagascar Airlines) sondés en aller simple.
SERP_ONE_WAYS = [("TNR", "DIE"), ("DIE", "TNR"), ("TNR", "NOS"), ("NOS", "TNR")]
FLIXBUS_CITIES = {"TLS_V": "40dfd612-8646-11e6-9066-549f350fcb0c",
                  "PAR_G": "40de8964-8646-11e6-9066-549f350fcb0c"}
SNCF_IDS = {"TLS_V": "stop_area:SNCF:87611004", "PAR_G": "admin:fr:75056",
            "MIL": "stop_area:SNCF:83016451"}
SNCF_ROUTES = [("TLS_V", "PAR_G"), ("PAR_G", "TLS_V"), ("PAR_G", "MIL"), ("MIL", "PAR_G")]
TOULOUSE_UIC = "87611004"
OPEN_DATA = "https://ressources.data.sncf.com/api/explore/v2.1/catalog/datasets/"
SECRET_PARAMS = ("token", "api_key", "apikey", "key")


# --------------------------------------------------------------------------- outils

class Logger(object):
    def __init__(self):
        self.lock = threading.Lock()
        self.errors = []
        self.warnings = []

    def _emit(self, level, msg):
        line = "%s [%s] %s" % (dt.datetime.now().strftime("%Y-%m-%d %H:%M:%S"), level, msg)
        with self.lock:
            print(line, flush=True)

    def info(self, msg):
        self._emit("INFO", msg)

    def warning(self, msg):
        self.warnings.append(msg)
        self._emit("ALERTE", msg)

    def error(self, msg):
        self.errors.append(msg)
        self._emit("ERREUR", msg)


def redact(url):
    parts = urllib.parse.urlsplit(url)
    query = urllib.parse.parse_qsl(parts.query, keep_blank_values=True)
    clean = [(k, "***" if k.lower() in SECRET_PARAMS else v) for k, v in query]
    return urllib.parse.urlunsplit(parts._replace(query=urllib.parse.urlencode(clean)))


class Http(object):
    """GET JSON avec espacement des requêtes par site, une relance et journalisation."""

    def __init__(self, log):
        self.log = log
        self.lock = threading.Lock()
        self.next_slot = {}
        self.requests = 0
        self.failures = 0

    def _wait(self, host, interval):
        with self.lock:
            now = time.time()
            slot = max(now, self.next_slot.get(host, 0.0))
            self.next_slot[host] = slot + interval
        delay = slot - now
        if delay > 0:
            time.sleep(delay)

    def get_json(self, url, label, headers=None, interval=0.2, timeout=45, quiet=False):
        host = urllib.parse.urlsplit(url).netloc
        for attempt in (1, 2):
            self._wait(host, interval)
            request = urllib.request.Request(url, headers=dict({"User-Agent": USER_AGENT,
                                                                "Accept": "application/json"}, **(headers or {})))
            started = time.time()
            try:
                with self.lock:
                    self.requests += 1
                with urllib.request.urlopen(request, timeout=timeout) as response:
                    body = response.read()
                return json.loads(body.decode("utf-8"))
            except urllib.error.HTTPError as exc:
                raw = exc.read()
                text = raw[:300].decode("utf-8", "replace")
                if exc.code in (429, 500, 502, 503, 504) and attempt == 1:
                    time.sleep(3)
                    continue
                if exc.code == 400 or exc.code == 404:
                    # L'API répond parfois 400/404 avec un JSON d'erreur exploitable (pas de trajet).
                    try:
                        return json.loads(raw.decode("utf-8"))
                    except ValueError:
                        pass
                with self.lock:
                    self.failures += 1
                if not quiet:
                    self.log.warning("%s : HTTP %s (%s) %s" % (label, exc.code, redact(url), text[:120]))
                return None
            except Exception as exc:  # réseau, délai, JSON invalide
                if attempt == 1:
                    time.sleep(2)
                    continue
                with self.lock:
                    self.failures += 1
                if not quiet:
                    self.log.warning("%s : %s après %.1f s" % (label, exc, time.time() - started))
                return None
        return None


def parse_day(text):
    return dt.date(int(text[0:4]), int(text[5:7]), int(text[8:10]))


def utc_now():
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0, tzinfo=None)


def iso_now():
    return utc_now().isoformat() + "Z"


def swift_weekday(day):
    """Jour de semaine au format de l'app : 1 = dimanche ... 7 = samedi."""
    return day.isoweekday() % 7 + 1


def days_between(start, end):
    current = start
    while current <= end:
        yield current
        current += dt.timedelta(days=1)


def months_between(start, end):
    y, m = start.year, start.month
    result = []
    while (y, m) <= (end.year, end.month):
        result.append("%04d-%02d" % (y, m))
        m += 1
        if m > 12:
            m, y = 1, y + 1
    return result


def euro(value):
    return ("%d" % round(value)).replace(",", " ") + " €"


def load_config(path):
    config = {}
    candidates = [path] if path else [os.environ.get("TRAJETMADA_CONFIG"),
                                      os.path.expanduser("~/.config/trajetmada/config.env"),
                                      "/etc/trajetmada/config.env"]
    for candidate in candidates:
        if candidate and os.path.isfile(candidate):
            with open(candidate, encoding="utf-8") as handle:
                for line in handle:
                    line = line.strip()
                    if not line or line.startswith("#") or "=" not in line:
                        continue
                    name, value = line.split("=", 1)
                    config[name.strip()] = value.strip().strip('"').strip("'")
            config["_path"] = candidate
            break
    prefixes = ("TRAVELPAYOUTS_", "SERPAPI_", "SNCF_", "PERIOD_", "STAY_", "ADULTS", "OUTPUT_", "PUBLISH_")
    for name, value in os.environ.items():
        if name.startswith(prefixes):
            config[name] = value
    return config


def period_from(config, today):
    if config.get("PERIOD_START") and config.get("PERIOD_END"):
        return parse_day(config["PERIOD_START"]), parse_day(config["PERIOD_END"])
    year = today.year if today < dt.date(today.year, 5, 1) else today.year + 1
    return dt.date(year, 5, 1), dt.date(year, 9, 30)


# --------------------------------------------------------------------------- sources

def fetch_sncf_grid(http, log):
    """Grille officielle des prix SNCF Toulouse <-> Paris (2nde classe, tarif normal)."""
    grid = {}
    tgv_where = ('classe="2" and profil_tarifaire="Tarif Normal" and '
                 '((gare_origine_code_uic="%s" and startswith(gare_destination, "PARIS")) or '
                 '(gare_destination_code_uic="%s" and startswith(gare_origine, "PARIS")))' % (TOULOUSE_UIC, TOULOUSE_UIC))
    data = http.get_json(OPEN_DATA + "tarifs-tgv-inoui-ouigo/records?limit=50&where=" + urllib.parse.quote(tgv_where),
                         "Grille SNCF TGV/OUIGO")
    for option_id, carrier in (("tgv", "TGV INOUI"), ("ouigo", "OUIGO")):
        rows = [r for r in (data or {}).get("results", []) if r.get("transporteur") == carrier
                and r.get("prix_minimum") is not None and r.get("prix_maximum") is not None]
        montparnasse = [r for r in rows if "MONTPARNASSE" in (r.get("gare_origine", "") + r.get("gare_destination", ""))]
        rows = montparnasse or rows
        if rows:
            grid[option_id] = {"min": min(r["prix_minimum"] for r in rows), "max": max(r["prix_maximum"] for r in rows),
                               "source": "open data SNCF (tarifs TGV INOUI et OUIGO)"}
    night_where = ('classe="2" and profil_tarifaire="Tarif Normal" and type_place="couchette" and '
                   '(origine_uic8="%s" or destination_uic8="%s") and '
                   '(startswith(origine, "PARIS") or startswith(destination, "PARIS"))' % (TOULOUSE_UIC, TOULOUSE_UIC))
    data = http.get_json(OPEN_DATA + "tarifs-intercites/records?limit=50&where=" + urllib.parse.quote(night_where),
                         "Grille SNCF Intercités de nuit")
    rows = [r for r in (data or {}).get("results", []) if r.get("prix_min") is not None]
    if rows:
        grid["intercites-nuit"] = {"min": min(r["prix_min"] for r in rows), "max": max(r["prix_max"] for r in rows),
                                   "source": "open data SNCF (tarifs Intercités, couchette)"}
    log.info("Grille SNCF : " + ", ".join("%s %s à %s" % (k, euro(v["min"]), euro(v["max"])) for k, v in sorted(grid.items())))
    return grid


def fetch_flixbus(http, log, start, end, adults, quick):
    """Prix FlixBus réels Toulouse <-> Paris pour chaque jour de la période."""
    days = list(days_between(start, end))
    if quick:
        days = days[:2]
    jobs = []
    for day in days:
        jobs.append(("TLS_V", "PAR_G", day))
        jobs.append(("PAR_G", "TLS_V", day))

    def one(job):
        origin, destination, day = job
        params = urllib.parse.urlencode({
            "from_city_id": FLIXBUS_CITIES[origin], "to_city_id": FLIXBUS_CITIES[destination],
            "departure_date": day.strftime("%d.%m.%Y"), "products": json.dumps({"adult": adults}),
            "currency": "EUR", "locale": "fr", "search_by": "cities", "include_after_midnight_rides": "1"})
        data = http.get_json("https://global.api.flixbus.com/search/service/v4/search?" + params,
                             "FlixBus %s>%s %s" % (origin, destination, day), interval=0.35)
        best = None
        for trip in (data or {}).get("trips", []):
            for ride in (trip.get("results") or {}).values():
                total = (ride.get("price") or {}).get("total")
                if ride.get("status", "available") != "available" or not total:
                    continue
                if best is None or total < best["price"]["total"]:
                    best = ride
        if best is None:
            return None
        dep = (best.get("departure") or {}).get("date", "")
        arr = (best.get("arrival") or {}).get("date", "")
        seats = (best.get("available") or {}).get("seats")
        detail = " · ".join(x for x in ["départ " + dep[11:16] if dep else "", "arrivée " + arr[11:16] if arr else "",
                                        ("%s places" % seats) if seats else ""] if x)
        link = "https://shop.flixbus.fr/search?" + urllib.parse.urlencode({
            "departureCity": FLIXBUS_CITIES[origin], "arrivalCity": FLIXBUS_CITIES[destination],
            "rideDate": day.strftime("%d.%m.%Y"), "adult": adults, "_locale": "fr"})
        return {"from": origin, "to": destination, "day": day.isoformat(),
                "price": round(best["price"]["total"] / max(1, adults), 2), "source": "flixbus",
                "carrier": "FlixBus", "detail": detail, "link": link, "fetchedAt": iso_now()}

    with ThreadPoolExecutor(max_workers=2) as pool:
        results = [r for r in pool.map(one, jobs) if r]
    log.info("FlixBus : %d prix sur %d trajets demandés" % (len(results), len(jobs)))
    return results


def fetch_travelpayouts(http, log, token, start, end, quick):
    """Prix des vols vus par les utilisateurs d'Aviasales (allers simples et allers-retours)."""
    months = months_between(start, end)
    if quick:
        months = months[:1]
    jobs = []
    for a, b in FLIGHTS:
        for month in months:
            jobs.append((a, b, month, None))
            jobs.append((b, a, month, None))
        for i, month in enumerate(months):
            jobs.append((a, b, month, month))
            if i + 1 < len(months):
                jobs.append((a, b, month, months[i + 1]))
    log.info("Travelpayouts : %d requêtes" % len(jobs))
    fetched = iso_now()

    def one(job):
        origin, destination, month, back_month = job
        params = {"origin": AIRPORTS[origin][0], "destination": AIRPORTS[destination][0], "departure_at": month,
                  "one_way": "true" if back_month is None else "false", "direct": "false", "currency": "eur",
                  "sorting": "price", "limit": "1000", "token": token}
        if back_month:
            params["return_at"] = back_month
        data = http.get_json("https://api.travelpayouts.com/aviasales/v3/prices_for_dates?" + urllib.parse.urlencode(params),
                             "Travelpayouts %s-%s %s%s" % (origin, destination, month, "/" + back_month if back_month else ""),
                             interval=0.12)
        return job, (data or {}).get("data") or []

    one_way, round_trip = {}, {}
    with ThreadPoolExecutor(max_workers=4) as pool:
        for job, tickets in pool.map(one, jobs):
            origin, destination, _month, back_month = job
            for t in tickets:
                price, dep = t.get("price"), t.get("departure_at")
                if not price or not dep:
                    continue
                parts = [x for x in [((t.get("airline") or "") + (" %s" % t["flight_number"] if t.get("flight_number") else "")).strip(),
                                     ("direct" if t.get("transfers") == 0 else "%s escale(s)" % t.get("transfers"))
                                     if t.get("transfers") is not None else ""] if x]
                entry = {"from": origin, "to": destination, "day": dep[:10], "price": float(price),
                         "source": "travelpayouts", "carrier": t.get("airline"), "transfers": t.get("transfers"),
                         "detail": " · ".join(parts), "fetchedAt": fetched,
                         "link": "https://www.aviasales.com" + t["link"] if t.get("link") else None}
                if back_month:
                    ret = t.get("return_at")
                    if not ret:
                        continue
                    entry["out"] = entry.pop("day")
                    entry["back"] = ret[:10]
                    key = (origin, destination, entry["out"], entry["back"])
                    if key not in round_trip or price < round_trip[key]["price"]:
                        round_trip[key] = entry
                else:
                    key = (origin, destination, entry["day"])
                    if key not in one_way or price < one_way[key]["price"]:
                        one_way[key] = entry
    log.info("Travelpayouts : %d prix aller simple, %d prix aller-retour" % (len(one_way), len(round_trip)))
    return list(one_way.values()), list(round_trip.values())


def parse_journeys(data):
    journeys, seen = [], set()
    for j in (data or {}).get("journeys", []) or []:
        dep, arr = j.get("departure_date_time", ""), j.get("arrival_date_time", "")
        if len(dep) < 13 or len(arr) < 13:
            continue
        sections = [s for s in j.get("sections", []) if s.get("type") == "public_transport"]
        trains = [" ".join(x for x in [(s.get("display_informations") or {}).get("commercial_mode"),
                                       (s.get("display_informations") or {}).get("headsign")] if x) for s in sections]
        offset = (dt.date(int(arr[0:4]), int(arr[4:6]), int(arr[6:8])) - dt.date(int(dep[0:4]), int(dep[4:6]), int(dep[6:8]))).days
        fare = j.get("fare") or {}
        price = None
        if fare.get("found"):
            try:
                price = float((fare.get("total") or {}).get("value") or 0) or None
            except ValueError:
                price = None
        item = {"departure": dep[9:11] + ":" + dep[11:13], "arrival": arr[9:11] + ":" + arr[11:13],
                "arrivalDayOffset": offset, "durationMin": int(j.get("duration", 0)) // 60,
                "transfers": int(j.get("nb_transfers", 0)), "trains": trains,
                "modes": [(s.get("display_informations") or {}).get("commercial_mode") for s in sections
                          if (s.get("display_informations") or {}).get("commercial_mode")],
                "fare": price}
        key = item["departure"] + item["arrival"] + "+".join(trains)
        if key not in seen:
            seen.add(key)
            journeys.append(item)
    return sorted(journeys, key=lambda x: x["departure"])


def fetch_sncf_schedules(http, log, key, start, end, today, quick):
    """Horaires SNCF : jours publiés de la période, et horaires types pour chaque jour de semaine."""
    headers = {"Authorization": "Basic " + base64.b64encode((key + ":").encode()).decode()}
    base = "https://api.sncf.com/v1/coverage/sncf"
    coverage = http.get_json(base, "SNCF période des horaires", headers=headers)
    regions = (coverage or {}).get("regions") or []
    if not regions:
        log.error("API SNCF : période des horaires illisible (clé valide ?)")
        return [], None
    w_start = dt.datetime.strptime(regions[0]["start_production_date"], "%Y%m%d").date()
    w_end = dt.datetime.strptime(regions[0]["end_production_date"], "%Y%m%d").date()
    log.info("API SNCF : horaires publiés du %s au %s" % (w_start, w_end))

    jobs = []
    exact_days = [d for d in days_between(max(start, w_start), min(end, w_end))]
    for origin, destination in SNCF_ROUTES:
        for day in exact_days:
            jobs.append((origin, destination, day, True))
        references = {}
        for day in days_between(max(w_start, today + dt.timedelta(days=1)), w_end):
            references.setdefault(swift_weekday(day), day)
        weekdays = sorted(references.items())
        if quick:
            weekdays = weekdays[:1]
        for _weekday, day in weekdays:
            jobs.append((origin, destination, day, False))

    def one(job):
        origin, destination, day, exact = job
        params = urllib.parse.urlencode({"from": SNCF_IDS[origin], "to": SNCF_IDS[destination],
                                         "datetime": day.strftime("%Y%m%d") + "T050000", "count": 20,
                                         "min_nb_journeys": 12, "data_freshness": "base_schedule"})
        data = http.get_json(base + "/journeys?" + params, "SNCF %s>%s %s" % (origin, destination, day),
                             headers=headers, interval=0.3)
        return {"from": origin, "to": destination, "day": day.isoformat() if exact else None,
                "weekday": swift_weekday(day), "referenceDay": day.isoformat(), "exact": exact,
                "journeys": parse_journeys(data)}

    with ThreadPoolExecutor(max_workers=2) as pool:
        schedules = list(pool.map(one, jobs))
    log.info("API SNCF : %d horaires (%d jours exacts, %d horaires types)"
             % (len(schedules), sum(1 for s in schedules if s["exact"]), sum(1 for s in schedules if not s["exact"])))
    return schedules, {"start": w_start.isoformat(), "end": w_end.isoformat()}


SERP_KEEP_DAYS = 10
CALENDAR_MAX_AGE_DAYS = 4
# Identifiant unique par lieu pour le calendrier Google Flights (Paris : toutes ses aérogares).
CALENDAR_IDS = {"PAR": "/m/05qtj", "MIL": "MXP"}


def fresh(entries, stamp_field, now):
    """Entrées de moins de SERP_KEEP_DAYS jours."""
    kept = []
    for entry in entries:
        try:
            age = now - dt.datetime.strptime(entry[stamp_field], "%Y-%m-%dT%H:%M:%SZ")
        except (KeyError, ValueError, TypeError):
            continue
        if age < dt.timedelta(days=SERP_KEEP_DAYS):
            kept.append(entry)
    return kept


def calendar_jobs(start, end, stay_min, stay_max):
    """Tous les calendriers de prix : chaque grand axe pour chaque durée de séjour, et chaque vol
    intérieur en aller simple (environ 20 recherches pour couvrir toute la période)."""
    last_back = end - dt.timedelta(days=1)
    jobs = []
    for stay in range(min(stay_min, stay_max), max(stay_min, stay_max) + 1):
        last_out = last_back - dt.timedelta(days=stay)
        if last_out < start:
            continue
        for a, b in SERP_ROUND_TRIPS:
            jobs.append({"from": a, "to": b, "stay": stay, "start": start, "end": last_out,
                         "key": "%s>%s#%d" % (a, b, stay)})
    for a, b in SERP_ONE_WAYS:
        jobs.append({"from": a, "to": b, "stay": None, "start": start, "end": last_back,
                     "key": "%s>%s#aller" % (a, b)})
    return jobs


def calendar_plan(jobs, fetched, budget, now):
    """Calendriers jamais relevés, puis les plus anciens, s'ils datent de plus de 4 jours."""
    def last(job):
        try:
            return dt.datetime.strptime(fetched[job["key"]], "%Y-%m-%dT%H:%M:%SZ")
        except (KeyError, ValueError, TypeError):
            return dt.datetime.min
    due = [(last(job), index, job) for index, job in enumerate(jobs)
           if now - last(job) >= dt.timedelta(days=CALENDAR_MAX_AGE_DAYS)]
    due.sort(key=lambda item: (item[0], item[1]))
    return [job for _, _, job in due[:max(0, budget)]]


def fetch_calendars(http, log, key, budget, adults, previous, fetched, start, end, stay_min, stay_max):
    """Calendriers de prix Google Flights (SerpApi) : un prix réel par date de départ de la période.
    Renvoie les prix Google Flights à publier, les dates de relevé et le nombre de recherches utilisées."""
    now = utc_now()
    plan = calendar_plan(calendar_jobs(start, end, stay_min, stay_max), fetched, budget, now)
    if not plan:
        log.info("Calendriers Google Flights : tous relevés depuis moins de %d jours" % CALENDAR_MAX_AGE_DAYS)
    quotes = fresh(previous, "fetchedAt", now)
    used = 0
    for job in plan:
        query = {"engine": "google_flights_calendar", "type": "2" if job["stay"] is None else "1",
                 "departure_id": CALENDAR_IDS.get(job["from"], AIRPORTS[job["from"]][0]),
                 "arrival_id": CALENDAR_IDS.get(job["to"], AIRPORTS[job["to"]][0]),
                 "date_range_start": job["start"].isoformat(), "date_range_end": job["end"].isoformat(),
                 "currency": "EUR", "hl": "fr", "gl": "fr", "adults": adults, "api_key": key}
        if job["stay"] is not None:
            query["round_trip_days"] = job["stay"]
        label = "%s-%s %s" % (job["from"], job["to"], ("%d jours" % job["stay"]) if job["stay"] else "aller simple")
        used += 1
        data = http.get_json("https://serpapi.com/search.json?" + urllib.parse.urlencode(query),
                             "Calendrier Google Flights " + label, timeout=120)
        if data is None or (data.get("error") and "returned any results" not in data.get("error", "")):
            log.warning("Calendrier Google Flights %s : %s" % (label, (data or {}).get("error", "pas de réponse")))
            continue
        stamp = iso_now()
        fetched[job["key"]] = stamp
        # Les nouveaux prix remplacent ceux du même calendrier.
        if job["stay"] is None:
            quotes = [q for q in quotes if not (q["from"] == job["from"] and q["to"] == job["to"] and not q.get("back"))]
        else:
            quotes = [q for q in quotes if not (q["from"] == job["from"] and q["to"] == job["to"] and q.get("back")
                                                 and (parse_day(q["back"]) - parse_day(q["out"])).days == job["stay"])]
        found = []
        for entry in data.get("prices") or []:
            price, out = entry.get("price"), entry.get("outbound_date")
            if not price or not out:
                continue
            quote = {"from": job["from"], "to": job["to"], "price": round(float(price) / max(1, adults), 2),
                     "source": "serpapi", "detail": "Google Flights, calendrier des prix", "fetchedAt": stamp}
            if job["stay"] is None:
                quote["day"] = out
            else:
                if not entry.get("return_date"):
                    continue
                quote["out"], quote["back"] = out, entry["return_date"]
            found.append(quote)
        quotes.extend(found)
        if found:
            best = min(found, key=lambda q: q["price"])
            when = best.get("day") or "%s - %s" % (best["out"], best["back"])
            log.info("Calendrier Google Flights %s : %d dates, dès %s (%s)" % (label, len(found), euro(best["price"] * adults), when))
        else:
            log.warning("Calendrier Google Flights %s : aucun vol trouvé" % label)
    account = http.get_json("https://serpapi.com/account.json?" + urllib.parse.urlencode({"api_key": key}),
                            "SerpApi quota", quiet=True) or {}
    return quotes, fetched, used, account.get("total_searches_left", account.get("plan_searches_left"))


def fetch_rate(http, log):
    """Taux de change réel euro/ariary (open.er-api.com, gratuit, sans clé)."""
    data = http.get_json("https://open.er-api.com/v6/latest/EUR", "Taux de change euro/ariary") or {}
    rate = (data.get("rates") or {}).get("MGA")
    if data.get("result") != "success" or not rate:
        log.warning("Taux de change euro/ariary indisponible")
        return None, None
    stamp = dt.datetime.fromtimestamp(data.get("time_last_update_unix", time.time()), dt.timezone.utc)
    log.info("Taux de change : 1 EUR = %s MGA" % round(rate))
    return rate, stamp.replace(tzinfo=None, microsecond=0).isoformat() + "Z"


# --------------------------------------------------------------------------- sorties

def write_report(path, feed, log, serp_left):
    lines = ["# TrajetMada : données du %s (UTC)" % feed["generatedAt"].replace("T", " ").rstrip("Z"), "",
             "Période : %s au %s, séjour %s à %s jours, %s adulte(s)."
             % (feed["period"]["start"], feed["period"]["end"], feed["stay"]["min"], feed["stay"]["max"], feed["adults"]), ""]
    stats = feed["stats"]
    lines += ["| Source | Prix ou horaires |", "|---|---|",
              "| Vols aller simple (Aviasales) | %d |" % stats["oneWay"],
              "| Vols aller-retour (Aviasales) | %d |" % stats["roundTrip"],
              "| Vols Google Flights (calendriers) | %d |" % stats["serpapi"],
              "| FlixBus | %d |" % stats["bus"],
              "| Horaires SNCF | %d |" % stats["schedules"], ""]
    stay_min, stay_max = feed["stay"]["min"], feed["stay"]["max"]
    lines += ["## Aller-retour avion le moins cher par axe", "", "| Axe | Aller | Retour | Prix | Source |", "|---|---|---|---|---|"]
    for a, b in SERP_ROUND_TRIPS + [("PAR", "RUN"), ("PAR", "DZA")]:
        options = [e for e in feed["roundTrip"] if e["from"] == a and e["to"] == b
                   and stay_min <= (parse_day(e["back"]) - parse_day(e["out"])).days <= stay_max]
        if options:
            best = min(options, key=lambda e: e["price"])
            lines.append("| %s-%s | %s | %s | %s | %s |" % (a, b, best["out"], best["back"], euro(best["price"]), best["source"]))
        else:
            lines.append("| %s-%s | | | pas de prix | |" % (a, b))
    lines += ["", "## Vols intérieurs à Madagascar (aller simple le moins cher)", ""]
    for a, b in SERP_ONE_WAYS:
        options = [e for e in feed["oneWay"] if e["from"] == a and e["to"] == b]
        if options:
            best = min(options, key=lambda e: e["price"])
            lines.append("- %s-%s : %s le %s (%s)" % (a, b, euro(best["price"]), best["day"], best["source"]))
        else:
            lines.append("- %s-%s : pas de prix" % (a, b))
    if feed["bus"]:
        cheapest = sorted(feed["bus"], key=lambda e: e["price"])[:5]
        lines += ["", "## FlixBus les moins chers", ""]
        lines += ["- %s %s>%s : %s (%s)" % (e["day"], e["from"], e["to"], euro(e["price"]), e["detail"]) for e in cheapest]
    if feed["trainGrid"]:
        lines += ["", "## Grille officielle SNCF (2nde, tarif normal)", ""]
        lines += ["- %s : %s à %s" % (k, euro(v["min"]), euro(v["max"])) for k, v in sorted(feed["trainGrid"].items())]
    if feed.get("mgaPerEur"):
        lines += ["", "Taux de change : 1 € = %d Ar (%s)." % (round(feed["mgaPerEur"]), feed.get("mgaRateAt") or "")]
    if feed.get("calendarFetched"):
        lines += ["", "## Calendriers Google Flights relevés", ""]
        lines += ["- %s : %s" % (k, v) for k, v in sorted(feed["calendarFetched"].items())]
    if serp_left is not None:
        lines += ["", "Recherches SerpApi restantes ce mois-ci : %s." % serp_left]
    if log.errors or log.warnings:
        lines += ["", "## Erreurs et alertes", ""] + ["- " + m for m in (log.errors + log.warnings)[:40]]
    with open(path, "w", encoding="utf-8") as handle:
        handle.write("\n".join(lines) + "\n")


def run(cmd, log, check=True):
    result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if check and result.returncode != 0:
        raise RuntimeError("%s : %s" % (" ".join(cmd[:4]), result.stderr.decode("utf-8", "replace").strip()[:300]))
    return result


def publish_git(directory, files, log, stamp):
    for path in files:
        shutil.copy2(path, directory)
    run(["git", "-C", directory, "add", "-A"], log)
    has_head = run(["git", "-C", directory, "rev-parse", "--verify", "HEAD"], log, check=False).returncode == 0
    message = "Données TrajetMada du " + stamp
    # Un seul commit gardé sur la branche data : l'historique ne grossit pas.
    if has_head:
        run(["git", "-C", directory, "commit", "-q", "--amend", "--allow-empty", "-m", message], log)
    else:
        run(["git", "-C", directory, "commit", "-q", "-m", message], log)
    run(["git", "-C", directory, "push", "-q", "--force", "origin", "HEAD:data"], log)
    log.info("Publié sur la branche data du dépôt GitHub")


def main():
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description="Met à jour les prix et horaires de TrajetMada.")
    parser.add_argument("--config", help="fichier de configuration (clé=valeur)")
    parser.add_argument("--quick", action="store_true", help="test rapide sur quelques dates seulement")
    parser.add_argument("--no-publish", action="store_true", help="n'envoie pas les données")
    args = parser.parse_args()

    log = Logger()
    http = Http(log)
    config = load_config(args.config)
    today = dt.date.today()
    start, end = period_from(config, today)
    stay_min, stay_max = int(config.get("STAY_MIN") or 28), int(config.get("STAY_MAX") or 30)
    adults = int(config.get("ADULTS") or 1)
    output = os.path.expanduser(config.get("OUTPUT_DIR") or "~/trajetmada/data")
    os.makedirs(output, exist_ok=True)
    feed_path = os.path.join(output, "trajetmada-data.json")
    log.info("Configuration : %s" % config.get("_path", "variables d'environnement"))
    log.info("Période %s au %s, séjour %d-%d jours, %d adulte(s)" % (start, end, stay_min, stay_max, adults))

    previous = {}
    if os.path.isfile(feed_path):
        try:
            with open(feed_path, encoding="utf-8") as handle:
                previous = json.load(handle)
        except (OSError, ValueError):
            previous = {}

    feed = {"version": FEED_VERSION, "generatedAt": iso_now(),
            "period": {"start": start.isoformat(), "end": end.isoformat()},
            "stay": {"min": stay_min, "max": stay_max}, "adults": adults,
            "oneWay": [], "roundTrip": [], "bus": [], "trainGrid": {}, "schedules": [], "sncfWindow": None,
            "mgaPerEur": None, "mgaRateAt": None, "calendarFetched": {}}

    try:
        feed["trainGrid"] = fetch_sncf_grid(http, log)
    except Exception as exc:
        log.error("Grille SNCF : %s" % exc)
    try:
        feed["bus"] = fetch_flixbus(http, log, start, end, adults, args.quick)
    except Exception as exc:
        log.error("FlixBus : %s" % exc)
    token = config.get("TRAVELPAYOUTS_TOKEN", "")
    if token:
        try:
            feed["oneWay"], feed["roundTrip"] = fetch_travelpayouts(http, log, token, start, end, args.quick)
        except Exception as exc:
            log.error("Travelpayouts : %s" % exc)
    else:
        log.warning("Pas de jeton Travelpayouts : prix des vols non mis à jour")
    sncf_key = config.get("SNCF_API_KEY", "")
    if sncf_key:
        try:
            feed["schedules"], feed["sncfWindow"] = fetch_sncf_schedules(http, log, sncf_key, start, end, today, args.quick)
        except Exception as exc:
            log.error("Horaires SNCF : %s" % exc)
    else:
        log.warning("Pas de clé SNCF : horaires des trains non mis à jour")
    feed["mgaPerEur"], feed["mgaRateAt"] = fetch_rate(http, log)
    serp_key = config.get("SERPAPI_KEY", "")
    serp_left = None
    previous_serp = [e for e in previous.get("roundTrip", []) + previous.get("oneWay", []) if e.get("source") == "serpapi"]
    serp_quotes = fresh(previous_serp, "fetchedAt", utc_now())
    feed["calendarFetched"] = dict(previous.get("calendarFetched") or {})
    if serp_key and not args.quick:
        try:
            budget = int(config.get("SERPAPI_DAILY_LIMIT") or 5)
            serp_quotes, feed["calendarFetched"], used, serp_left = fetch_calendars(
                http, log, serp_key, budget, adults, previous_serp, feed["calendarFetched"],
                start, end, stay_min, stay_max)
            log.info("SerpApi : %d recherche(s) utilisée(s), %s restante(s)" % (used, serp_left))
        except Exception as exc:
            log.error("SerpApi : %s" % exc)
    feed["roundTrip"] = feed["roundTrip"] + [e for e in serp_quotes if e.get("back")]
    feed["oneWay"] = feed["oneWay"] + [e for e in serp_quotes if not e.get("back")]
    feed["stats"] = {"oneWay": len(feed["oneWay"]), "roundTrip": len(feed["roundTrip"]), "serpapi": len(serp_quotes),
                     "bus": len(feed["bus"]), "schedules": len(feed["schedules"]),
                     "requests": http.requests, "failures": http.failures,
                     "errors": len(log.errors), "warnings": len(log.warnings)}

    tmp = feed_path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as handle:
        json.dump(feed, handle, ensure_ascii=False, separators=(",", ":"))
    os.replace(tmp, feed_path)
    report_path = os.path.join(output, "rapport.md")
    write_report(report_path, feed, log, serp_left)
    log.info("Écrit %s (%d Ko) et %s" % (feed_path, os.path.getsize(feed_path) // 1024, report_path))

    if not args.no_publish:
        target = config.get("PUBLISH_DIR")
        if target:
            try:
                os.makedirs(os.path.expanduser(target), exist_ok=True)
                for path in (feed_path, report_path):
                    shutil.copy2(path, os.path.expanduser(target))
                log.info("Copié dans %s" % target)
            except OSError as exc:
                log.error("Copie vers %s : %s" % (target, exc))
        git_dir = config.get("PUBLISH_GIT_DIR")
        if git_dir:
            try:
                publish_git(os.path.expanduser(git_dir), (feed_path, report_path), log, feed["generatedAt"])
            except Exception as exc:
                log.error("Publication GitHub impossible (clé de déploiement ajoutée au dépôt ?) : %s" % exc)

    total = feed["stats"]["oneWay"] + feed["stats"]["roundTrip"] + feed["stats"]["bus"] + feed["stats"]["schedules"]
    log.info("Terminé : %d prix et horaires, %d requêtes, %d erreur(s)" % (total, http.requests, len(log.errors)))
    return 0 if total > 0 else 1


if __name__ == "__main__":
    sys.exit(main())
