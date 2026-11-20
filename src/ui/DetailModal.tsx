import { useEffect, useState } from 'react';
import { Linking, Modal, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { PLACES } from '../data/network';
import { duration, euro, legDate, shortDate } from '../engine/format';
import type { Itinerary, PricedLeg } from '../engine/routes';
import type { TripDate } from '../types';
import { AlertIcon, ArrowIcon, BoltIcon, ExternalIcon, ModeIcon } from './icons';
import { ItineraryBadges, RouteChain } from './ItineraryCard';
import { MODE_LABEL, type Theme } from './theme';

function LegRow({ pl, start, passengers, t }: { pl: PricedLeg; start: TripDate; passengers: number; t: Theme }) {
  const { leg, live } = pl;
  const { date, dayOffset } = legDate(start, pl.startOffsetMin);
  const unit = leg.perVehicle ? 'par véhicule' : passengers > 1 ? `pour ${passengers} pers.` : 'par pers.';
  return (
    <View style={[styles.leg, { borderColor: t.border, backgroundColor: t.cardAlt }]}>
      <View style={styles.legHead}>
        <View style={[styles.legIcon, { backgroundColor: t.accentSoft }]}>
          <ModeIcon mode={leg.mode} size={20} color={t.accent} />
        </View>
        <View style={styles.flex}>
          <View style={styles.legTitleRow}>
            <Text style={[styles.legTitle, { color: t.text }]}>{PLACES[leg.from].short}</Text>
            <ArrowIcon size={14} color={t.sub} strokeWidth={2.2} />
            <Text style={[styles.legTitle, { color: t.text }]}>{PLACES[leg.to].short}</Text>
          </View>
          <Text style={[styles.legSub, { color: t.sub }]}>
            {MODE_LABEL[leg.mode]} · {leg.operator}
            {leg.via && leg.via !== 'direct' ? ` · via ${leg.via}` : leg.via === 'direct' ? ' · direct' : ''}
          </Text>
        </View>
        <View style={styles.legPriceBox}>
          <Text style={[styles.legPrice, { color: live ? t.live : t.text }]}>{euro(pl.priceMin)}</Text>
          <Text style={[styles.legUnit, { color: t.sub }]}>{unit}</Text>
        </View>
      </View>
      <Text style={[styles.legInfo, { color: t.sub }]}>
        {shortDate(date)}
        {dayOffset > 0 ? ` (J+${dayOffset})` : ''} · {duration(leg.durationMin)} · {leg.frequency}
      </Text>
      <Text style={[styles.legInfo, { color: t.sub }]}>
        {live
          ? `Prix en direct : ${euro(live.price)} par pers. (${live.airline}, le ${live.departureAt.slice(0, 10)}${
              live.transfers > 0 ? `, ${live.transfers} escale${live.transfers > 1 ? 's' : ''}` : ''
            }). Prix courant ≈ ${euro(pl.priceTypical)}.`
          : `Estimation : ${euro(pl.priceMin)} à ${euro(pl.priceTypical)} ${unit}.`}
      </Text>
      {!leg.verified && (
        <View style={styles.legWarnRow}>
          <AlertIcon size={14} color={t.warn} strokeWidth={2.2} />
          <Text style={[styles.legWarn, { color: t.warn }]}>Liaison à vérifier pour la saison en cours.</Text>
        </View>
      )}
      {leg.notes ? <Text style={[styles.legNote, { color: t.text }]}>{leg.notes}</Text> : null}
      <View style={styles.links}>
        {live?.url && (
          <Pressable
            onPress={() => Linking.openURL(live.url!)}
            style={[styles.linkBtn, { backgroundColor: t.live }]}
            accessibilityRole="link"
          >
            <BoltIcon size={14} color={t.onAccent} strokeWidth={2.2} />
            <Text style={[styles.linkText, { color: t.onAccent }]}>Offre Aviasales</Text>
          </Pressable>
        )}
        {leg.links.map((l) => (
          <Pressable
            key={l.label}
            onPress={() => Linking.openURL(l.url(date))}
            style={[styles.linkBtn, { backgroundColor: t.accentSoft }]}
            accessibilityRole="link"
          >
            <Text style={[styles.linkText, { color: t.accent }]}>{l.label}</Text>
            <ExternalIcon size={13} color={t.accent} strokeWidth={2.2} />
          </Pressable>
        ))}
      </View>
    </View>
  );
}

export function DetailModal(props: {
  variants: Itinerary[] | null;
  start: TripDate;
  passengers: number;
  t: Theme;
  onClose: () => void;
}) {
  const { variants, start, passengers, t, onClose } = props;
  const [index, setIndex] = useState(0);
  useEffect(() => setIndex(0), [variants]);
  const it = variants?.[Math.min(index, (variants?.length ?? 1) - 1)];

  return (
    <Modal visible={!!it} animationType="slide" presentationStyle="pageSheet" onRequestClose={onClose}>
      <SafeAreaView style={[styles.flex, { backgroundColor: t.bg }]} edges={['top', 'bottom']}>
        <View style={[styles.header, { borderColor: t.border }]}>
          <Text style={[styles.headerTitle, { color: t.text }]}>Détail du trajet</Text>
          <Pressable onPress={onClose} accessibilityRole="button" hitSlop={12}>
            <Text style={[styles.close, { color: t.accent }]}>Fermer</Text>
          </Pressable>
        </View>
        {it && (
          <ScrollView contentContainerStyle={styles.body}>
            <RouteChain it={it} t={t} large />
            <View style={styles.totals}>
              <View style={styles.flex}>
                <Text style={[styles.total, { color: t.text }]}>dès {euro(it.priceMin)}</Text>
                <Text style={[styles.totalSub, { color: t.sub }]}>
                  prix courant ≈ {euro(it.priceTypical)}
                  {passengers > 1 ? ` · ${passengers} voyageurs` : ''}
                </Text>
              </View>
              <View style={styles.right}>
                <Text style={[styles.totalDur, { color: t.text }]}>{duration(it.durationMin)}</Text>
                <Text style={[styles.totalSub, { color: t.sub }]}>correspondances incluses</Text>
              </View>
            </View>
            <ItineraryBadges it={it} t={t} />

            {(it.unprotected > 0 || it.rare > 0) && (
              <View style={[styles.alert, { backgroundColor: t.warnSoft }]}>
                {it.unprotected > 0 && (
                  <Text style={[styles.alertText, { color: t.warn }]}>
                    Billets séparés entre deux vols : si le premier est en retard, le second n’attend pas. Prévoyez au
                    moins 3 h (idéalement une nuit) entre les deux, ou cherchez un billet unique.
                  </Text>
                )}
                {it.rare > 0 && (
                  <Text style={[styles.alertText, { color: t.warn }]}>
                    Ce trajet contient un vol 1 à 2 fois par semaine : la durée réelle peut inclure des jours d’attente.
                    Calez d’abord la date de ce vol.
                  </Text>
                )}
              </View>
            )}

            <Text style={[styles.section, { color: t.sub }]}>ÉTAPES (départ de Toulouse à 8 h le {shortDate(start)})</Text>
            {it.legs.map((pl) => (
              <LegRow key={pl.leg.id} pl={pl} start={start} passengers={passengers} t={t} />
            ))}

            {variants && variants.length > 1 && (
              <>
                <Text style={[styles.section, { color: t.sub }]}>
                  VARIANTES DE CE TRAJET ({variants.length})
                </Text>
                {variants.map((v, i) => (
                  <Pressable
                    key={v.id}
                    onPress={() => setIndex(i)}
                    style={[
                      styles.variant,
                      {
                        borderColor: i === index ? t.accent : t.border,
                        backgroundColor: i === index ? t.accentSoft : t.card,
                      },
                    ]}
                  >
                    <Text style={[styles.variantPrice, { color: t.text }]}>{euro(v.priceMin)}</Text>
                    <Text style={[styles.variantOps, { color: t.sub }]} numberOfLines={2}>
                      {duration(v.durationMin)} ·{' '}
                      {v.legs
                        .filter((l) => l.leg.mode !== 'local')
                        .map((l) => l.leg.operator)
                        .join(' · ')}
                    </Text>
                  </Pressable>
                ))}
              </>
            )}
            <Text style={[styles.disclaimer, { color: t.sub }]}>
              Les prix sans la mention « direct » sont des estimations. Vérifiez toujours sur le site du transporteur
              avant d’acheter. Les liens s’ouvrent à la date estimée de chaque étape.
            </Text>
          </ScrollView>
        )}
      </SafeAreaView>
    </Modal>
  );
}

const styles = StyleSheet.create({
  flex: { flex: 1 },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 16,
    paddingVertical: 12,
    borderBottomWidth: StyleSheet.hairlineWidth,
  },
  headerTitle: { fontSize: 17, fontWeight: '700' },
  close: { fontSize: 16, fontWeight: '600' },
  body: { padding: 16, paddingBottom: 40 },
  totals: { flexDirection: 'row', marginTop: 12 },
  right: { alignItems: 'flex-end' },
  total: { fontSize: 26, fontWeight: '700', fontVariant: ['tabular-nums'] },
  totalSub: { fontSize: 13 },
  totalDur: { fontSize: 18, fontWeight: '600' },
  alert: { borderRadius: 10, padding: 12, marginTop: 12 },
  alertText: { fontSize: 13, lineHeight: 19, marginBottom: 4 },
  section: { fontSize: 12, fontWeight: '700', letterSpacing: 0.5, marginTop: 22, marginBottom: 8 },
  leg: { borderRadius: 12, borderWidth: StyleSheet.hairlineWidth, padding: 12, marginBottom: 10 },
  legHead: { flexDirection: 'row', alignItems: 'flex-start' },
  legIcon: {
    width: 36,
    height: 36,
    borderRadius: 18,
    alignItems: 'center',
    justifyContent: 'center',
    marginRight: 10,
  },
  legTitleRow: { flexDirection: 'row', alignItems: 'center', flexWrap: 'wrap', gap: 6 },
  legTitle: { fontSize: 15, fontWeight: '600' },
  legSub: { fontSize: 13, marginTop: 2, lineHeight: 18 },
  legPriceBox: { alignItems: 'flex-end', marginLeft: 8 },
  legPrice: { fontSize: 16, fontWeight: '700', fontVariant: ['tabular-nums'] },
  legUnit: { fontSize: 11 },
  legInfo: { fontSize: 13, marginTop: 8, lineHeight: 18 },
  legWarnRow: { flexDirection: 'row', alignItems: 'center', gap: 6, marginTop: 6 },
  legWarn: { fontSize: 13, fontWeight: '600', flex: 1 },
  legNote: { fontSize: 13, marginTop: 6, lineHeight: 18 },
  links: { flexDirection: 'row', flexWrap: 'wrap', marginTop: 10 },
  linkBtn: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    paddingHorizontal: 10,
    paddingVertical: 8,
    borderRadius: 8,
    marginRight: 8,
    marginBottom: 8,
  },
  linkText: { fontSize: 13, fontWeight: '600' },
  variant: { borderRadius: 10, borderWidth: 1, padding: 10, marginBottom: 8 },
  variantPrice: { fontSize: 15, fontWeight: '700' },
  variantOps: { fontSize: 12, marginTop: 2, lineHeight: 17 },
  disclaimer: { fontSize: 12, lineHeight: 18, marginTop: 20 },
});
