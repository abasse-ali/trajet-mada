/**
 * Énumère tous les itinéraires possibles (parcours en profondeur sur le réseau)
 * et calcule prix, durée et risques de chacun.
 */
import { LEGS, START } from '../data/network';
import type { Leg, Mode, PlaceId } from '../types';
import type { LivePrices, LiveQuote } from './live';

export interface PricedLeg {
  leg: Leg;
  /** Prix bas pour tous les voyageurs (prix en direct s'il existe). */
  priceMin: number;
  /** Prix courant pour tous les voyageurs. */
  priceTypical: number;
  live?: LiveQuote;
  /** Minutes écoulées depuis le départ de Toulouse au début de ce segment. */
  startOffsetMin: number;
}

export interface Itinerary {
  id: string;
  signature: string;
  destination: PlaceId;
  legs: PricedLeg[];
  priceMin: number;
  priceTypical: number;
  durationMin: number;
  /** Nombre de billets à acheter (hors transports urbains). */
  tickets: number;
  /** Correspondances avion → avion sur billets séparés (non protégées). */
  unprotected: number;
  unverified: number;
  rare: number;
  liveLegs: number;
}

export interface SearchOptions {
  destinations: PlaceId[];
  modes: Mode[];
  includeUnverified: boolean;
  passengers: number;
  maxLegs?: number;
}

export type SortKey = 'prix' | 'typique' | 'duree' | 'simple';

/** Marge de correspondance entre deux segments achetés séparément. */
function connectionBuffer(prev: Leg, next: Leg): number {
  if (next.mode === 'avion') return prev.mode === 'avion' ? 180 : 120;
  if (prev.mode === 'avion') return 60;
  if (next.mode === 'local' || prev.mode === 'local') return 15;
  return 45;
}

function build(path: Leg[], passengers: number, live: LivePrices): Itinerary {
  let t = 0;
  let priceMin = 0;
  let priceTypical = 0;
  let unprotected = 0;
  const legs: PricedLeg[] = path.map((leg, i) => {
    if (i > 0) t += connectionBuffer(path[i - 1], leg);
    const quote = live[leg.id];
    const mult = leg.perVehicle ? 1 : passengers;
    const min = (quote ? quote.price : leg.priceMin) * mult;
    const typ = (quote ? Math.max(quote.price, leg.priceTypical) : leg.priceTypical) * mult;
    const priced: PricedLeg = { leg, priceMin: min, priceTypical: typ, live: quote, startOffsetMin: t };
    t += leg.durationMin;
    priceMin += min;
    priceTypical += typ;
    if (i > 0 && path[i - 1].mode === 'avion' && leg.mode === 'avion') unprotected += 1;
    return priced;
  });
  return {
    id: path.map((l) => l.id).join('+'),
    signature: [START, ...path.map((l) => l.to)].join('>'),
    destination: path[path.length - 1].to,
    legs,
    priceMin,
    priceTypical,
    durationMin: t,
    tickets: path.filter((l) => l.mode !== 'local').length,
    unprotected,
    unverified: path.filter((l) => !l.verified).length,
    rare: path.filter((l) => l.rare).length,
    liveLegs: legs.filter((l) => l.live).length,
  };
}

export function findItineraries(opts: SearchOptions, live: LivePrices = {}): Itinerary[] {
  const allowed = new Set<Mode>([...opts.modes, 'local']);
  const byFrom = new Map<PlaceId, Leg[]>();
  for (const leg of LEGS) {
    if (!allowed.has(leg.mode)) continue;
    if (!opts.includeUnverified && !leg.verified) continue;
    const list = byFrom.get(leg.from) ?? [];
    list.push(leg);
    byFrom.set(leg.from, list);
  }

  const dest = new Set(opts.destinations);
  const maxLegs = opts.maxLegs ?? 8;
  const passengers = Math.max(1, opts.passengers);
  const results: Itinerary[] = [];
  const path: Leg[] = [];
  const visited = new Set<PlaceId>([START]);

  const walk = (at: PlaceId) => {
    if (path.length > 0 && dest.has(at)) {
      results.push(build(path, passengers, live));
      return;
    }
    if (path.length >= maxLegs) return;
    for (const leg of byFrom.get(at) ?? []) {
      if (visited.has(leg.to)) continue;
      if (leg.onlyAfter) {
        const prev = path[path.length - 1];
        if (!prev || !leg.onlyAfter.includes(prev.mode)) continue;
      }
      visited.add(leg.to);
      path.push(leg);
      walk(leg.to);
      path.pop();
      visited.delete(leg.to);
    }
  };
  walk(START);
  return results;
}

const comparators: Record<SortKey, (a: Itinerary, b: Itinerary) => number> = {
  prix: (a, b) => a.priceMin - b.priceMin || a.durationMin - b.durationMin,
  typique: (a, b) => a.priceTypical - b.priceTypical || a.priceMin - b.priceMin,
  duree: (a, b) => a.durationMin - b.durationMin || a.priceMin - b.priceMin,
  simple: (a, b) =>
    a.tickets - b.tickets ||
    a.unprotected - b.unprotected ||
    a.unverified - b.unverified ||
    a.priceMin - b.priceMin,
};

export function sortItineraries(list: Itinerary[], key: SortKey): Itinerary[] {
  return [...list].sort(comparators[key]);
}

export interface RouteGroup {
  signature: string;
  best: Itinerary;
  variants: Itinerary[];
}

/** Regroupe les itinéraires qui passent par les mêmes lieux (seuls les opérateurs changent). */
export function groupItineraries(list: Itinerary[], key: SortKey): RouteGroup[] {
  const map = new Map<string, Itinerary[]>();
  for (const it of list) {
    const arr = map.get(it.signature) ?? [];
    arr.push(it);
    map.set(it.signature, arr);
  }
  const groups = [...map.values()].map((arr) => {
    const variants = sortItineraries(arr, key);
    return { signature: variants[0].signature, best: variants[0], variants };
  });
  return groups.sort((a, b) => comparators[key](a.best, b.best));
}

export interface Highlights {
  cheapest?: Itinerary;
  fastest?: Itinerary;
  simplest?: Itinerary;
}

export function highlights(list: Itinerary[]): Highlights {
  if (list.length === 0) return {};
  return {
    cheapest: sortItineraries(list, 'prix')[0],
    fastest: sortItineraries(list, 'duree')[0],
    simplest: sortItineraries(list, 'simple')[0],
  };
}
