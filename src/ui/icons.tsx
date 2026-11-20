/**
 * Icônes SVG (trait 24×24). Plusieurs tracés sont adaptés de Lucide (licence ISC).
 */
import type { ReactNode } from 'react';
import Svg, { Circle, Path, Rect } from 'react-native-svg';
import type { Mode } from '../types';

export interface IconProps {
  size?: number;
  color: string;
  strokeWidth?: number;
}

function Base({ size = 20, color, strokeWidth = 1.9, children }: IconProps & { children: ReactNode }) {
  return (
    <Svg
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      stroke={color}
      strokeWidth={strokeWidth}
      strokeLinecap="round"
      strokeLinejoin="round"
    >
      {children}
    </Svg>
  );
}

export const PlaneIcon = (p: IconProps) => (
  <Base {...p}>
    <Path d="M17.8 19.2 16 11l3.5-3.5C21 6 21.5 4 21 3c-1-.5-3 0-4.5 1.5L13 8 4.8 6.2c-.5-.1-.9.1-1.1.5l-.3.5c-.2.5-.1 1 .3 1.3L9 12l-2 3H4l-1 1 3 2 2 3 1-1v-3l3-2 3.5 5.3c.3.4.8.5 1.3.3l.5-.2c.4-.3.6-.7.5-1.2z" />
  </Base>
);

export const TrainIcon = (p: IconProps) => (
  <Base {...p}>
    <Path d="M8 3.1V7a4 4 0 0 0 8 0V3.1" />
    <Path d="m9 15-1-1" />
    <Path d="m15 15 1-1" />
    <Path d="M9 19c-2.8 0-5-2.2-5-5v-4a8 8 0 0 1 16 0v4c0 2.8-2.2 5-5 5Z" />
    <Path d="m8 19-2 3" />
    <Path d="m16 19 2 3" />
  </Base>
);

export const BusIcon = (p: IconProps) => (
  <Base {...p}>
    <Path d="M8 6v6" />
    <Path d="M15 6v6" />
    <Path d="M2 12h19.6" />
    <Path d="M18 18h3s.5-1.7.8-2.8c.1-.4.2-.8.2-1.2 0-.4-.1-.8-.2-1.2l-1.4-5C20.1 6.8 19.1 6 18 6H4a2 2 0 0 0-2 2v10h3" />
    <Circle cx="7" cy="18" r="2" />
    <Path d="M9 18h5" />
    <Circle cx="16" cy="18" r="2" />
  </Base>
);

export const CarIcon = (p: IconProps) => (
  <Base {...p}>
    <Path d="M19 17h2c.6 0 1-.4 1-1v-3c0-.9-.7-1.7-1.5-1.9C18.7 10.6 16 10 16 10s-1.3-1.4-2.2-2.3c-.5-.4-1.1-.7-1.8-.7H5c-.6 0-1.1.4-1.4.9l-1.4 2.9A3.7 3.7 0 0 0 2 12v4c0 .6.4 1 1 1h2" />
    <Circle cx="7" cy="17" r="2" />
    <Path d="M9 17h6" />
    <Circle cx="17" cy="17" r="2" />
  </Base>
);

export const ShipIcon = (p: IconProps) => (
  <Base {...p}>
    <Path d="M12 10.2V14" />
    <Path d="M12 2v3" />
    <Path d="M19 13V7a2 2 0 0 0-2-2H7a2 2 0 0 0-2 2v6" />
    <Path d="M19.4 20A11.6 11.6 0 0 0 21 14l-8.2-3.6a2 2 0 0 0-1.6 0L3 14a11.6 11.6 0 0 0 2.8 7.8" />
    <Path d="M2 21c.6.5 1.2 1 2.5 1 2.5 0 2.5-2 5-2 1.3 0 1.9.5 2.5 1s1.2 1 2.5 1c2.5 0 2.5-2 5-2 1.3 0 1.9.5 2.5 1" />
  </Base>
);

/** Minibus avec bagages sur le toit. */
export const VanIcon = (p: IconProps) => (
  <Base {...p}>
    <Path d="M18.5 17H21a1 1 0 0 0 1-1v-3.6a1 1 0 0 0-.6-.9L20 11l-3.8-4.2a2 2 0 0 0-1.5-.8H4a2 2 0 0 0-2 2v8a1 1 0 0 0 1 1h2" />
    <Path d="M9 17h5.5" />
    <Path d="M2 11h18" />
    <Path d="M8 6v5" />
    <Path d="M13.5 6v5" />
    <Path d="M5 3.5h8" />
    <Circle cx="7" cy="17" r="2" />
    <Circle cx="16.5" cy="17" r="2" />
  </Base>
);

export const TaxiIcon = (p: IconProps) => (
  <Base {...p}>
    <Path d="M10 2h4" />
    <Path d="m21 8-2 2-1.5-3.7A2 2 0 0 0 15.6 5H8.4a2 2 0 0 0-1.9 1.3L5 10 3 8" />
    <Path d="M7 14h.01" />
    <Path d="M17 14h.01" />
    <Rect x="3" y="10" width="18" height="8" rx="2" />
    <Path d="M5 18v2" />
    <Path d="M19 18v2" />
  </Base>
);

export const MetroIcon = (p: IconProps) => (
  <Base {...p}>
    <Rect x="4" y="3" width="16" height="16" rx="2" />
    <Path d="M4 11h16" />
    <Path d="M12 3v8" />
    <Path d="m8 19-2 3" />
    <Path d="m18 22-2-3" />
    <Path d="M8 15h.01" />
    <Path d="M16 15h.01" />
  </Base>
);

export const SlidersIcon = (p: IconProps) => (
  <Base {...p}>
    <Path d="M4 6h9" />
    <Path d="M17 6h3" />
    <Path d="M4 12h3" />
    <Path d="M11 12h9" />
    <Path d="M4 18h11" />
    <Path d="M19 18h1" />
    <Circle cx="15" cy="6" r="2" />
    <Circle cx="9" cy="12" r="2" />
    <Circle cx="17" cy="18" r="2" />
  </Base>
);

export const AlertIcon = (p: IconProps) => (
  <Base {...p}>
    <Path d="M10.3 3.9 1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z" />
    <Path d="M12 9v4" />
    <Path d="M12 17h.01" />
  </Base>
);

export const ExternalIcon = (p: IconProps) => (
  <Base {...p}>
    <Path d="M15 3h6v6" />
    <Path d="M10 14 21 3" />
    <Path d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6" />
  </Base>
);

export const ChevronIcon = (p: IconProps) => (
  <Base {...p}>
    <Path d="m9 18 6-6-6-6" />
  </Base>
);

export const ArrowIcon = (p: IconProps) => (
  <Base {...p}>
    <Path d="M5 12h14" />
    <Path d="m12 5 7 7-7 7" />
  </Base>
);

export const PlusIcon = (p: IconProps) => (
  <Base {...p}>
    <Path d="M12 5v14" />
    <Path d="M5 12h14" />
  </Base>
);

export const MinusIcon = (p: IconProps) => (
  <Base {...p}>
    <Path d="M5 12h14" />
  </Base>
);

export const ClockIcon = (p: IconProps) => (
  <Base {...p}>
    <Circle cx="12" cy="12" r="9" />
    <Path d="M12 7v5l3 2" />
  </Base>
);

export const BoltIcon = (p: IconProps) => (
  <Base {...p}>
    <Path d="M13 2 4 14h7l-1 8 9-12h-7z" />
  </Base>
);

const MODE_ICONS: Record<Mode, (p: IconProps) => ReactNode> = {
  avion: PlaneIcon,
  train: TrainIcon,
  bus: BusIcon,
  covoiturage: CarIcon,
  bateau: ShipIcon,
  'taxi-brousse': VanIcon,
  voiture: TaxiIcon,
  local: MetroIcon,
};

export function ModeIcon({ mode, ...p }: IconProps & { mode: Mode }) {
  const Icon = MODE_ICONS[mode];
  return <Icon {...p} />;
}
