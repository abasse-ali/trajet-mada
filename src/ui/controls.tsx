import type { ReactNode } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import { MinusIcon, PlusIcon } from './icons';
import type { Theme } from './theme';

export function Chip(props: {
  label: string;
  active: boolean;
  onPress: () => void;
  t: Theme;
  icon?: (color: string) => ReactNode;
}) {
  const { label, active, onPress, t, icon } = props;
  const fg = active ? t.onAccent : t.text;
  return (
    <Pressable
      onPress={onPress}
      accessibilityRole="button"
      accessibilityState={{ selected: active }}
      style={[
        styles.chip,
        { backgroundColor: active ? t.accent : t.chip, borderColor: active ? t.accent : t.border },
      ]}
    >
      {icon ? <View style={styles.chipIcon}>{icon(fg)}</View> : null}
      <Text style={[styles.chipText, { color: fg }]}>{label}</Text>
    </Pressable>
  );
}

export function Segmented<T extends string>(props: {
  options: { value: T; label: string }[];
  value: T;
  onChange: (v: T) => void;
  t: Theme;
}) {
  const { options, value, onChange, t } = props;
  return (
    <View style={[styles.segment, { backgroundColor: t.chip, borderColor: t.border }]}>
      {options.map((o) => {
        const active = o.value === value;
        return (
          <Pressable
            key={o.value}
            onPress={() => onChange(o.value)}
            accessibilityRole="button"
            accessibilityState={{ selected: active }}
            style={[styles.segmentItem, active && { backgroundColor: t.card }]}
          >
            <Text
              numberOfLines={1}
              style={[styles.segmentText, { color: active ? t.text : t.sub }, active && styles.bold]}
            >
              {o.label}
            </Text>
          </Pressable>
        );
      })}
    </View>
  );
}

export function Stepper(props: {
  label: string;
  value: number;
  min: number;
  max: number;
  onChange: (v: number) => void;
  t: Theme;
}) {
  const { label, value, min, max, onChange, t } = props;
  const btn = (plus: boolean) => {
    const disabled = plus ? value >= max : value <= min;
    return (
      <Pressable
        onPress={() => !disabled && onChange(plus ? value + 1 : value - 1)}
        accessibilityRole="button"
        accessibilityLabel={`${label} ${plus ? 'plus' : 'moins'}`}
        hitSlop={6}
        style={[styles.stepBtn, { backgroundColor: t.chip, opacity: disabled ? 0.4 : 1 }]}
      >
        {plus ? <PlusIcon size={18} color={t.text} strokeWidth={2.2} /> : <MinusIcon size={18} color={t.text} strokeWidth={2.2} />}
      </Pressable>
    );
  };
  return (
    <View style={styles.stepper}>
      <Text style={[styles.stepLabel, { color: t.sub }]}>{label}</Text>
      <View style={styles.stepRow}>
        {btn(false)}
        <Text style={[styles.stepValue, { color: t.text }]}>{value}</Text>
        {btn(true)}
      </View>
    </View>
  );
}

export function Badge(props: { label: string; color: string; bg: string; icon?: ReactNode }) {
  return (
    <View style={[styles.badge, { backgroundColor: props.bg }]}>
      {props.icon ? <View style={styles.badgeIcon}>{props.icon}</View> : null}
      <Text style={[styles.badgeText, { color: props.color }]}>{props.label}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  chip: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 12,
    paddingVertical: 7,
    borderRadius: 999,
    borderWidth: StyleSheet.hairlineWidth,
    marginRight: 8,
    marginBottom: 8,
  },
  chipIcon: { marginRight: 6 },
  chipText: { fontSize: 14 },
  segment: {
    flexDirection: 'row',
    borderRadius: 10,
    padding: 3,
    borderWidth: StyleSheet.hairlineWidth,
  },
  segmentItem: { flex: 1, paddingVertical: 8, borderRadius: 8, alignItems: 'center' },
  segmentText: { fontSize: 14 },
  bold: { fontWeight: '600' },
  stepper: { flex: 1 },
  stepLabel: { fontSize: 12, marginBottom: 6 },
  stepRow: { flexDirection: 'row', alignItems: 'center' },
  stepBtn: { width: 36, height: 36, borderRadius: 18, alignItems: 'center', justifyContent: 'center' },
  stepValue: { minWidth: 44, textAlign: 'center', fontSize: 16, fontWeight: '600', fontVariant: ['tabular-nums'] },
  badge: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 8,
    paddingVertical: 3,
    borderRadius: 6,
    marginRight: 6,
    marginTop: 6,
  },
  badgeIcon: { marginRight: 4 },
  badgeText: { fontSize: 12, fontWeight: '600' },
});
