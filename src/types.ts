export type Mode =
  | 'avion'
  | 'train'
  | 'bus'
  | 'covoiturage'
  | 'bateau'
  | 'taxi-brousse'
  | 'voiture'
  | 'local';

export type PlaceId =
  | 'TLS_V'
  | 'TLS'
  | 'PAR'
  | 'CDG'
  | 'ORY'
  | 'MXP'
  | 'RUN'
  | 'DZA'
  | 'JNB'
  | 'TNR'
  | 'ANK'
  | 'NOS'
  | 'DIE';

export interface Place {
  id: PlaceId;
  name: string;
  short: string;
}

/** Date de voyage (mois 1-12). */
export interface TripDate {
  year: number;
  month: number;
  day: number;
}

export interface BookingLink {
  label: string;
  url: (date: TripDate) => string;
}

export interface Leg {
  id: string;
  from: PlaceId;
  to: PlaceId;
  mode: Mode;
  operator: string;
  /** Escales incluses dans un billet unique. */
  via?: string;
  /** Durée typique du segment, en minutes. */
  durationMin: number;
  /** Prix bas estimé, aller simple, 1 adulte, en euros. */
  priceMin: number;
  /** Prix courant estimé, aller simple, 1 adulte, en euros. */
  priceTypical: number;
  /** Prix par véhicule (taxi privé) : ne se multiplie pas par le nombre de voyageurs. */
  perVehicle?: boolean;
  frequency: string;
  /** Liaison peu fréquente (1 à 2 par semaine). */
  rare?: boolean;
  /** false = liaison signalée mais non confirmée pour la saison en cours. */
  verified: boolean;
  notes?: string;
  /** Segment utilisable seulement juste après un segment de ce mode. */
  onlyAfter?: Mode[];
  /** Requête de prix en direct (codes IATA ; airlines vide = toutes compagnies). */
  live?: { origin: string; destination: string; airlines: string[] };
  links: BookingLink[];
}
