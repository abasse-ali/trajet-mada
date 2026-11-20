/**
 * Prix des vols en direct via l'API Data d'Aviasales (Travelpayouts).
 * Jeton gratuit : https://www.travelpayouts.com (Profil → API token).
 * Les prix sont ceux vus récemment par les utilisateurs d'Aviasales (cache de 2 à 7 jours).
 */
import { LEGS } from '../data/network';

export interface LiveQuote {
  price: number;
  airline: string;
  departureAt: string;
  transfers: number;
  url?: string;
}

/** Prix en direct par identifiant de segment. */
export type LivePrices = Record<string, LiveQuote>;

export interface LiveResult {
  prices: LivePrices;
  routesOk: number;
  routesTotal: number;
  errors: string[];
}

interface TpTicket {
  price: number;
  airline: string;
  departure_at: string;
  transfers: number;
  link?: string;
}

const API = 'https://api.travelpayouts.com/aviasales/v3/prices_for_dates';

async function fetchRoute(
  token: string,
  origin: string,
  destination: string,
  month: string,
  signal: AbortSignal,
): Promise<TpTicket[]> {
  const params = [
    `origin=${origin}`,
    `destination=${destination}`,
    `departure_at=${month}`,
    'one_way=true',
    'direct=false',
    'currency=eur',
    'sorting=price',
    'limit=30',
    `token=${encodeURIComponent(token)}`,
  ].join('&');
  const res = await fetch(`${API}?${params}`, { signal, headers: { Accept: 'application/json' } });
  if (res.status === 401) throw new Error('jeton refusé (401)');
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  const json = (await res.json()) as { success?: boolean; error?: string; data?: unknown };
  if (json.success === false) throw new Error(json.error || 'réponse invalide');
  return Array.isArray(json.data) ? (json.data as TpTicket[]) : [];
}

/** month au format AAAA-MM. */
export async function fetchLivePrices(
  token: string,
  month: string,
  onProgress?: (done: number, total: number) => void,
): Promise<LiveResult> {
  const legs = LEGS.filter((l) => l.live);
  const routes = [...new Set(legs.map((l) => `${l.live!.origin}-${l.live!.destination}`))];
  const tickets = new Map<string, TpTicket[]>();
  const errors: string[] = [];
  const queue = [...routes];
  let done = 0;

  const worker = async () => {
    while (queue.length > 0) {
      const key = queue.shift()!;
      const [origin, destination] = key.split('-');
      const ctrl = new AbortController();
      const timer = setTimeout(() => ctrl.abort(), 15000);
      try {
        tickets.set(key, await fetchRoute(token, origin, destination, month, ctrl.signal));
      } catch (e) {
        const msg = ctrl.signal.aborted ? 'délai dépassé' : e instanceof Error ? e.message : String(e);
        errors.push(`${origin}-${destination} : ${msg}`);
      } finally {
        clearTimeout(timer);
        done += 1;
        onProgress?.(done, routes.length);
      }
    }
  };
  await Promise.all(Array.from({ length: 4 }, worker));

  const prices: LivePrices = {};
  for (const leg of legs) {
    const { origin, destination, airlines } = leg.live!;
    const list = tickets.get(`${origin}-${destination}`) ?? [];
    const matching = list.filter(
      (t) =>
        typeof t.price === 'number' &&
        t.price > 0 &&
        (airlines.length === 0 || airlines.includes(t.airline)),
    );
    if (matching.length === 0) continue;
    const best = matching.reduce((a, b) => (b.price < a.price ? b : a));
    prices[leg.id] = {
      price: best.price,
      airline: best.airline,
      departureAt: best.departure_at,
      transfers: best.transfers,
      url: best.link ? `https://www.aviasales.com${best.link}` : undefined,
    };
  }
  return { prices, routesOk: tickets.size, routesTotal: routes.length, errors };
}
