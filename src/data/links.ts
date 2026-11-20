import type { BookingLink, TripDate } from '../types';

const pad = (n: number) => String(n).padStart(2, '0');

export const isoDate = (d: TripDate) => `${d.year}-${pad(d.month)}-${pad(d.day)}`;
const yymmdd = (d: TripDate) => `${String(d.year).slice(2)}${pad(d.month)}${pad(d.day)}`;

export const site = (label: string, url: string): BookingLink => ({ label, url: () => url });

export const googleFlights = (from: string, to: string): BookingLink => ({
  label: 'Google Flights',
  url: (d) =>
    `https://www.google.com/travel/flights?q=${encodeURIComponent(
      `Flights from ${from} to ${to} on ${isoDate(d)} one way`,
    )}`,
});

export const skyscanner = (from: string, to: string): BookingLink => ({
  label: 'Skyscanner',
  url: (d) =>
    `https://www.skyscanner.fr/transport/vols/${from.toLowerCase()}/${to.toLowerCase()}/${yymmdd(d)}/`,
});

export const kayak = (from: string, to: string): BookingLink => ({
  label: 'Kayak',
  url: (d) => `https://www.kayak.fr/flights/${from}-${to}/${isoDate(d)}`,
});

/** Liens standard pour un vol : site de la compagnie + comparateurs à la bonne date. */
export const flight = (from: string, to: string, official?: BookingLink): BookingLink[] => [
  ...(official ? [official] : []),
  googleFlights(from, to),
  skyscanner(from, to),
  kayak(from, to),
];

export const blablacar = (from: string, to: string): BookingLink => ({
  label: 'BlaBlaCar',
  url: (d) =>
    `https://www.blablacar.fr/search?fn=${encodeURIComponent(from)}&tn=${encodeURIComponent(
      to,
    )}&db=${isoDate(d)}&seats=1`,
});

export const googleSearch = (label: string, query: string): BookingLink => ({
  label,
  url: () => `https://www.google.com/search?q=${encodeURIComponent(query)}`,
});

export const SITES = {
  sncf: site('SNCF Connect', 'https://www.sncf-connect.com/'),
  trainline: site('Trainline', 'https://www.thetrainline.com/fr'),
  ouigo: site('OUIGO', 'https://www.ouigo.com/'),
  flixbus: site('FlixBus', 'https://www.flixbus.fr/'),
  airfrance: site('Air France', 'https://wwws.airfrance.fr/'),
  corsair: site('Corsair', 'https://www.flycorsair.com/'),
  ethiopian: site('Ethiopian', 'https://www.ethiopianairlines.com/fr'),
  kenya: site('Kenya Airways', 'https://www.kenya-airways.com/'),
  airmauritius: site('Air Mauritius', 'https://www.airmauritius.com/'),
  emirates: site('Emirates', 'https://www.emirates.com/fr/french/'),
  frenchbee: site('French Bee', 'https://www.frenchbee.com/'),
  airaustral: site('Air Austral', 'https://www.air-austral.com/'),
  ewa: site('Ewa Air', 'https://www.ewa-air.com/'),
  madagascar: site('Madagascar Airlines', 'https://madagascarairlines.com/'),
  airlink: site('Airlink', 'https://www.flyairlink.com/'),
  neos: site('Neos', 'https://www.neosair.it/'),
  easyjet: site('easyJet', 'https://www.easyjet.com/fr'),
  tisseo: site('Tisséo (tram T2)', 'https://www.tisseo.fr/'),
  ratp: site('RATP / RER B', 'https://www.ratp.fr/'),
};
