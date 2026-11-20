import type { TripDate } from '../types';

const NBSP = ' ';

export function euro(n: number): string {
  const s = String(Math.round(n)).replace(/\B(?=(\d{3})+(?!\d))/g, NBSP);
  return `${s}${NBSP}€`;
}

export function duration(min: number): string {
  const m = Math.round(min);
  const d = Math.floor(m / 1440);
  const h = Math.floor((m % 1440) / 60);
  const r = m % 60;
  if (d > 0) return h > 0 ? `${d} j ${h} h` : `${d} j`;
  if (h > 0) return r > 0 ? `${h} h ${String(r).padStart(2, '0')}` : `${h} h`;
  return `${r} min`;
}

export const MONTHS_SHORT = [
  'janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin',
  'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.',
];

export function daysInMonth(year: number, month: number): number {
  return new Date(year, month, 0).getDate();
}

/** Les 12 prochains mois à partir d'aujourd'hui. */
export function nextMonths(count = 12): { year: number; month: number; label: string; key: string }[] {
  const now = new Date();
  return Array.from({ length: count }, (_, i) => {
    const d = new Date(now.getFullYear(), now.getMonth() + i, 1);
    const year = d.getFullYear();
    const month = d.getMonth() + 1;
    return {
      year,
      month,
      label: `${MONTHS_SHORT[month - 1]} ${year}`,
      key: `${year}-${String(month).padStart(2, '0')}`,
    };
  });
}

/** Date d'un segment : départ de Toulouse à 8 h + décalage en minutes. */
export function legDate(start: TripDate, offsetMin: number): { date: TripDate; dayOffset: number } {
  const base = new Date(start.year, start.month - 1, start.day, 8, 0);
  const d = new Date(base.getTime() + offsetMin * 60000);
  const startDay = new Date(start.year, start.month - 1, start.day).getTime();
  const legDay = new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
  return {
    date: { year: d.getFullYear(), month: d.getMonth() + 1, day: d.getDate() },
    dayOffset: Math.round((legDay - startDay) / 86400000),
  };
}

export function shortDate(d: TripDate): string {
  return `${d.day} ${MONTHS_SHORT[d.month - 1]}`;
}
