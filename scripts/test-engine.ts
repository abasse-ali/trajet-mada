/** Vérifie le moteur d'itinéraires sans lancer l'app : npm run test:engine */
import { LEGS, PLACES } from '../src/data/network';
import { duration, euro } from '../src/engine/format';
import { findItineraries, groupItineraries, highlights, sortItineraries } from '../src/engine/routes';
import type { Mode } from '../src/types';

const ALL_MODES: Mode[] = ['avion', 'train', 'bus', 'covoiturage', 'bateau', 'taxi-brousse', 'voiture'];
let failures = 0;
const check = (cond: boolean, msg: string) => {
  if (!cond) {
    failures += 1;
    console.error('ÉCHEC :', msg);
  }
};

// Cohérence des données
const ids = new Set<string>();
for (const leg of LEGS) {
  check(!ids.has(leg.id), `identifiant en double : ${leg.id}`);
  ids.add(leg.id);
  check(leg.from in PLACES && leg.to in PLACES, `lieu inconnu dans ${leg.id}`);
  check(leg.priceMin <= leg.priceTypical, `prix min > typique dans ${leg.id}`);
  check(leg.links.length > 0, `aucun lien de réservation pour ${leg.id}`);
}

for (const dest of [['DIE'], ['NOS'], ['DIE', 'NOS']] as const) {
  const its = findItineraries({
    destinations: [...dest],
    modes: ALL_MODES,
    includeUnverified: true,
    passengers: 1,
  });
  const groups = groupItineraries(its, 'prix');
  const h = highlights(its);
  console.log(`\n=== ${dest.join(' + ')} : ${its.length} combinaisons, ${groups.length} itinéraires distincts ===`);
  for (const it of sortItineraries(its, 'prix').slice(0, 5)) {
    const chain = it.legs.map((l) => `${l.leg.operator} → ${PLACES[l.leg.to].short}`).join(' | ');
    console.log(`${euro(it.priceMin).padStart(9)}  ${duration(it.durationMin).padEnd(9)} ${chain}`);
  }
  console.log('Plus rapide :', duration(h.fastest!.durationMin), euro(h.fastest!.priceMin), h.fastest!.id);
  console.log('Plus simple :', h.simplest!.tickets, 'billet(s)', euro(h.simplest!.priceMin), h.simplest!.id);

  check(its.length > 0, `aucun itinéraire vers ${dest.join('+')}`);
  for (const it of its) {
    check(dest.includes(it.destination as never), `${it.id} finit ailleurs`);
    check(it.legs[0].leg.from === 'TLS_V', `${it.id} ne part pas de Toulouse`);
    const places = [it.legs[0].leg.from, ...it.legs.map((l) => l.leg.to)];
    check(new Set(places).size === places.length, `${it.id} repasse par un même lieu`);
    for (let i = 1; i < it.legs.length; i++) {
      check(it.legs[i].leg.from === it.legs[i - 1].leg.to, `${it.id} : segments non contigus`);
    }
  }
}

// Filtres
const noFlight = findItineraries({
  destinations: ['DIE'],
  modes: ['train', 'bus', 'covoiturage', 'bateau', 'taxi-brousse', 'voiture'],
  includeUnverified: true,
  passengers: 1,
});
check(noFlight.length === 0, 'sans avion il ne devrait y avoir aucun itinéraire');

const verifiedOnly = findItineraries({ destinations: ['DIE'], modes: ALL_MODES, includeUnverified: false, passengers: 1 });
check(verifiedOnly.every((it) => it.unverified === 0), 'liaison non vérifiée malgré le filtre');

const two = findItineraries({ destinations: ['DIE'], modes: ALL_MODES, includeUnverified: true, passengers: 2 });
const one = findItineraries({ destinations: ['DIE'], modes: ALL_MODES, includeUnverified: true, passengers: 1 });
const car1 = one.find((it) => it.legs.some((l) => l.leg.perVehicle))!;
const car2 = two.find((it) => it.id === car1.id)!;
const perVehicle = car1.legs.filter((l) => l.leg.perVehicle).reduce((s, l) => s + l.priceMin, 0);
check(Math.abs(car2.priceMin - (2 * car1.priceMin - perVehicle)) < 0.01, 'prix par véhicule multiplié à tort');

// Prix en direct : remplace le prix estimé
const live = findItineraries(
  { destinations: ['DIE'], modes: ALL_MODES, includeUnverified: true, passengers: 1 },
  { 'cdg-tnr-af': { price: 111, airline: 'AF', departureAt: '2027-01-10', transfers: 0 } },
);
const withLive = live.find((it) => it.legs.some((l) => l.leg.id === 'cdg-tnr-af'))!;
check(withLive.legs.find((l) => l.leg.id === 'cdg-tnr-af')!.priceMin === 111, 'prix en direct ignoré');

console.log(failures === 0 ? '\nOK : toutes les vérifications passent.' : `\n${failures} échec(s).`);
process.exit(failures === 0 ? 0 : 1);
