import { useColorScheme } from 'react-native';
import type { Mode } from '../types';

export interface Theme {
  dark: boolean;
  bg: string;
  card: string;
  cardAlt: string;
  text: string;
  sub: string;
  border: string;
  accent: string;
  onAccent: string;
  accentSoft: string;
  highlight: string;
  chip: string;
  warn: string;
  warnSoft: string;
  live: string;
  liveSoft: string;
}

const light: Theme = {
  dark: false,
  bg: '#F5F2EC',
  card: '#FFFFFF',
  cardAlt: '#FAF8F4',
  text: '#1C1B19',
  sub: '#6B675F',
  border: '#E4DFD5',
  accent: '#0F766E',
  onAccent: '#FFFFFF',
  accentSoft: '#DDF1EE',
  highlight: '#C2410C',
  chip: '#ECE7DD',
  warn: '#9A5B00',
  warnSoft: '#FDF1DC',
  live: '#166534',
  liveSoft: '#DCF5E3',
};

const dark: Theme = {
  dark: true,
  bg: '#121315',
  card: '#1C1E21',
  cardAlt: '#222528',
  text: '#ECEAE6',
  sub: '#A3A09A',
  border: '#2E3135',
  accent: '#2DD4BF',
  onAccent: '#0B2925',
  accentSoft: '#133B37',
  highlight: '#FB923C',
  chip: '#272A2E',
  warn: '#F5B451',
  warnSoft: '#3A2C12',
  live: '#4ADE80',
  liveSoft: '#14331F',
};

export function useTheme(): Theme {
  return useColorScheme() === 'dark' ? dark : light;
}

export const MODE_LABEL: Record<Mode, string> = {
  avion: 'Avion',
  train: 'Train',
  bus: 'Bus',
  covoiturage: 'Covoiturage',
  bateau: 'Bateau',
  'taxi-brousse': 'Taxi-brousse',
  voiture: 'Taxi privé',
  local: 'Transport urbain',
};

export const FILTERABLE_MODES: Mode[] = [
  'avion',
  'train',
  'bus',
  'covoiturage',
  'bateau',
  'taxi-brousse',
  'voiture',
];
