import { Pressable, StyleSheet, Text, View } from 'react-native';
import { PLACES } from '../data/network';
import { duration, euro } from '../engine/format';
import type { Itinerary } from '../engine/routes';
import { Badge } from './controls';
import { AlertIcon, BoltIcon, ChevronIcon, ClockIcon, ModeIcon } from './icons';
import type { Theme } from './theme';

export function RouteChain({ it, t, large }: { it: Itinerary; t: Theme; large?: boolean }) {
  const fontSize = large ? 15 : 14;
  return (
    <View style={styles.chain}>
      <Text style={[styles.place, { color: t.text, fontSize }]}>{PLACES[it.legs[0].leg.from].short}</Text>
      {it.legs.map((l) => (
        <View key={l.leg.id} style={styles.step}>
          <ChevronIcon size={13} color={t.sub} strokeWidth={2.2} />
          <View style={styles.stepIcon}>
            <ModeIcon mode={l.leg.mode} size={large ? 17 : 16} color={t.accent} />
          </View>
          <Text style={[styles.place, { color: t.text, fontSize }]}>{PLACES[l.leg.to].short}</Text>
        </View>
      ))}
    </View>
  );
}

export function ItineraryBadges({ it, t }: { it: Itinerary; t: Theme }) {
  const warn = <AlertIcon size={12} color={t.warn} strokeWidth={2.2} />;
  return (
    <View style={styles.badges}>
      <Badge label={`${it.tickets} billet${it.tickets > 1 ? 's' : ''}`} color={t.sub} bg={t.chip} />
      {it.liveLegs > 0 && (
        <Badge
          label="prix en direct"
          color={t.live}
          bg={t.liveSoft}
          icon={<BoltIcon size={12} color={t.live} strokeWidth={2.2} />}
        />
      )}
      {it.unprotected > 0 && (
        <Badge
          label={`${it.unprotected} correspondance${it.unprotected > 1 ? 's' : ''} non protégée${it.unprotected > 1 ? 's' : ''}`}
          color={t.warn}
          bg={t.warnSoft}
          icon={warn}
        />
      )}
      {it.rare > 0 && <Badge label="vol peu fréquent" color={t.warn} bg={t.warnSoft} icon={warn} />}
      {it.unverified > 0 && <Badge label="liaison à vérifier" color={t.warn} bg={t.warnSoft} icon={warn} />}
    </View>
  );
}

export function ItineraryCard(props: {
  it: Itinerary;
  rank?: number;
  variants?: number;
  tag?: string;
  t: Theme;
  onPress: () => void;
}) {
  const { it, rank, variants, tag, t, onPress } = props;
  const operators = it.legs
    .filter((l) => l.leg.mode !== 'local')
    .map((l) => l.leg.operator)
    .join(' · ');
  return (
    <Pressable
      onPress={onPress}
      accessibilityRole="button"
      style={({ pressed }) => [
        styles.card,
        { backgroundColor: t.card, borderColor: t.border, opacity: pressed ? 0.85 : 1 },
      ]}
    >
      <View style={styles.top}>
        <View style={styles.flex}>
          {tag ? (
            <Text style={[styles.tag, { color: t.highlight }]}>{tag}</Text>
          ) : rank !== undefined ? (
            <Text style={[styles.rank, { color: t.sub }]}>
              #{rank} · vers {PLACES[it.destination].short}
            </Text>
          ) : null}
          <Text style={[styles.price, { color: t.text }]}>dès {euro(it.priceMin)}</Text>
          <Text style={[styles.typical, { color: t.sub }]}>prix courant ≈ {euro(it.priceTypical)}</Text>
        </View>
        <View style={styles.right}>
          <View style={styles.durRow}>
            <ClockIcon size={15} color={t.sub} />
            <Text style={[styles.duration, { color: t.text }]}>{duration(it.durationMin)}</Text>
          </View>
          <Text style={[styles.durationLabel, { color: t.sub }]}>porte à porte</Text>
        </View>
      </View>
      <RouteChain it={it} t={t} />
      <Text style={[styles.ops, { color: t.sub }]} numberOfLines={2}>
        {operators}
      </Text>
      <ItineraryBadges it={it} t={t} />
      {variants !== undefined && variants > 1 && (
        <Text style={[styles.variants, { color: t.accent }]}>
          + {variants - 1} variante{variants > 2 ? 's' : ''} (autres trains, bus ou compagnies)
        </Text>
      )}
    </Pressable>
  );
}

const styles = StyleSheet.create({
  card: {
    borderRadius: 14,
    borderWidth: StyleSheet.hairlineWidth,
    padding: 14,
    marginBottom: 10,
  },
  top: { flexDirection: 'row', alignItems: 'flex-start' },
  flex: { flex: 1 },
  right: { alignItems: 'flex-end', marginLeft: 12 },
  durRow: { flexDirection: 'row', alignItems: 'center', gap: 5 },
  tag: { fontSize: 12, fontWeight: '700', textTransform: 'uppercase', letterSpacing: 0.5, marginBottom: 2 },
  rank: { fontSize: 12, marginBottom: 2 },
  price: { fontSize: 22, fontWeight: '700', fontVariant: ['tabular-nums'] },
  typical: { fontSize: 13, marginTop: 1 },
  duration: { fontSize: 16, fontWeight: '600' },
  durationLabel: { fontSize: 12 },
  chain: { flexDirection: 'row', flexWrap: 'wrap', alignItems: 'center', marginTop: 10, rowGap: 4 },
  step: { flexDirection: 'row', alignItems: 'center', marginLeft: 4 },
  stepIcon: { marginHorizontal: 4 },
  place: { fontWeight: '500' },
  ops: { fontSize: 12, marginTop: 6, lineHeight: 17 },
  badges: { flexDirection: 'row', flexWrap: 'wrap', marginTop: 4 },
  variants: { fontSize: 13, marginTop: 8, fontWeight: '500' },
});
