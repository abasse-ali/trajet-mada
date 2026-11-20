#!/bin/bash
# Lance l'app dans un simulateur iPhone (iOS 26) et capture chaque écran. Utilisé par le CI.
# Usage : tools/simulator-screenshots.sh chemin/vers/TrajetMada.app [dossier_sortie]
set -euo pipefail
APP="$1"
OUT="${2:-screenshots}"
BUNDLE=com.trajetmada.app
mkdir -p "$OUT"

UDID=$(xcrun simctl list devices available -j | python3 -c '
import json, re, sys
devices = json.load(sys.stdin)["devices"]
plain, other = None, None
for runtime, items in sorted(devices.items()):
    if "iOS" not in runtime:
        continue
    for d in items:
        if re.fullmatch(r"iPhone \d+", d["name"]):
            plain = d
        elif d["name"].startswith("iPhone"):
            other = d
choice = plain or other
print(choice["udid"] + " " + choice["name"] if choice else "")
')
NAME="${UDID#* }"
UDID="${UDID%% *}"
echo "Simulateur : $NAME ($UDID)"

xcrun simctl boot "$UDID" || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl install "$UDID" "$APP"
xcrun simctl status_bar "$UDID" override --time 9:41 --batteryState charged --batteryLevel 100 \
  --cellularBars 4 --wifiBars 3 || true

shot() {
  local name="$1" wait="$2" appearance="$3"
  shift 3
  xcrun simctl ui "$UDID" appearance "$appearance"
  xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
  xcrun simctl launch "$UDID" "$BUNDLE" "$@"
  sleep "$wait"
  xcrun simctl io "$UDID" screenshot "$OUT/$name.png"
  echo "Capture : $name"
}

shot 01-recherche 45 light -autoSearch YES
shot 02-resultats 15 light -scrollResults YES
shot 03-detail 15 light -openFirst YES
shot 04-journal 8 light -tab 1
shot 05-reglages 8 light -tab 2
shot 06-resultats-sombre 15 dark -scrollResults YES
shot 07-detail-sombre 15 dark -openFirst YES

# Journal interne de l'app, journal système et éventuels rapports de plantage.
DATA=$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data || true)
cp "$DATA/Library/Application Support/journal.jsonl" "$OUT/journal-app.jsonl" 2>/dev/null || echo "Pas de journal interne"
xcrun simctl spawn "$UDID" log show --last 20m --style compact --predicate 'process == "TrajetMada"' \
  > "$OUT/systeme.log" 2>&1 || true
if ls ~/Library/Logs/DiagnosticReports/ 2>/dev/null | grep -qi trajet; then
  cp ~/Library/Logs/DiagnosticReports/*[Tt]rajet* "$OUT/" || true
  echo "ATTENTION : rapport de plantage trouvé"
else
  echo "Aucun plantage détecté"
fi
