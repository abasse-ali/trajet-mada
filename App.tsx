import AsyncStorage from '@react-native-async-storage/async-storage';
import { StatusBar } from 'expo-status-bar';
import { useEffect, useMemo, useState } from 'react';
import { ActivityIndicator, FlatList, Pressable, ScrollView, StyleSheet, Switch, Text, View } from 'react-native';
import { SafeAreaProvider, SafeAreaView } from 'react-native-safe-area-context';
import { DATA_DATE } from './src/data/network';
import { daysInMonth, nextMonths } from './src/engine/format';
import { fetchLivePrices, type LivePrices } from './src/engine/live';
import {
  findItineraries,
  groupItineraries,
  highlights,
  sortItineraries,
  type Itinerary,
  type SortKey,
} from './src/engine/routes';
import type { Mode, PlaceId, TripDate } from './src/types';
import { Chip, Segmented, Stepper } from './src/ui/controls';
import { DetailModal } from './src/ui/DetailModal';
import { ItineraryCard } from './src/ui/ItineraryCard';
import { SettingsModal } from './src/ui/SettingsModal';
import { ArrowIcon, ModeIcon, SlidersIcon } from './src/ui/icons';
import { FILTERABLE_MODES, MODE_LABEL, useTheme } from './src/ui/theme';

type DestChoice = 'DIE' | 'NOS' | 'BOTH';
const TOKEN_KEY = 'travelpayouts_token';
const EMPTY_PRICES: LivePrices = {};
const PAGE = 40;

export default function App() {
  return (
    <SafeAreaProvider>
      <Main />
    </SafeAreaProvider>
  );
}

function Main() {
  const t = useTheme();
  const months = useMemo(() => nextMonths(12), []);
  const today = new Date();

  const [dest, setDest] = useState<DestChoice>('DIE');
  const [monthIdx, setMonthIdx] = useState(1);
  const [day, setDay] = useState(15);
  const [pax, setPax] = useState(1);
  const [modes, setModes] = useState<Mode[]>(FILTERABLE_MODES);
  const [includeUnverified, setIncludeUnverified] = useState(true);
  const [grouped, setGrouped] = useState(true);
  const [sort, setSort] = useState<SortKey>('prix');
  const [limit, setLimit] = useState(PAGE);
  const [token, setToken] = useState('');
  const [live, setLive] = useState<{ month: string; prices: LivePrices } | null>(null);
  const [liveState, setLiveState] = useState<{ loading: boolean; text?: string; error?: boolean }>({
    loading: false,
  });
  const [detail, setDetail] = useState<Itinerary[] | null>(null);
  const [showSettings, setShowSettings] = useState(false);

  useEffect(() => {
    AsyncStorage.getItem(TOKEN_KEY)
      .then((v) => v && setToken(v))
      .catch(() => {});
  }, []);

  const month = months[monthIdx];
  const minDay = monthIdx === 0 ? today.getDate() : 1;
  const maxDay = daysInMonth(month.year, month.month);
  const safeDay = Math.min(Math.max(day, minDay), maxDay);
  const start: TripDate = { year: month.year, month: month.month, day: safeDay };
  const livePrices = live && live.month === month.key ? live.prices : EMPTY_PRICES;

  const destinations: PlaceId[] = dest === 'BOTH' ? ['DIE', 'NOS'] : [dest];
  const destKey = destinations.join(',');
  const itineraries = useMemo(
    () => findItineraries({ destinations, modes, includeUnverified, passengers: pax }, livePrices),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [destKey, modes, includeUnverified, pax, livePrices],
  );
  const rows: Itinerary[][] = useMemo(
    () =>
      grouped
        ? groupItineraries(itineraries, sort).map((g) => g.variants)
        : sortItineraries(itineraries, sort).map((it) => [it]),
    [itineraries, grouped, sort],
  );
  const best = useMemo(() => highlights(itineraries), [itineraries]);

  useEffect(() => setLimit(PAGE), [destKey, modes, includeUnverified, grouped, sort]);

  const openWithVariants = (it: Itinerary) =>
    setDetail(sortItineraries(itineraries.filter((x) => x.signature === it.signature), 'prix'));

  const toggleMode = (m: Mode) =>
    setModes((cur) => (cur.includes(m) ? cur.filter((x) => x !== m) : [...cur, m]));

  const saveToken = (v: string) => {
    setToken(v);
    setShowSettings(false);
    (v ? AsyncStorage.setItem(TOKEN_KEY, v) : AsyncStorage.removeItem(TOKEN_KEY)).catch(() => {});
    if (!v) setLive(null);
  };

  const refreshLive = async () => {
    if (!token) {
      setShowSettings(true);
      return;
    }
    setLiveState({ loading: true, text: 'Connexion…' });
    try {
      const res = await fetchLivePrices(token, month.key, (done, total) =>
        setLiveState({ loading: true, text: `Routes interrogées : ${done}/${total}` }),
      );
      setLive({ month: month.key, prices: res.prices });
      const updated = Object.keys(res.prices).length;
      const errs = res.errors.length ? ` · ${res.errors.length} erreur(s), ex. ${res.errors[0]}` : '';
      setLiveState({
        loading: false,
        error: res.routesOk === 0,
        text:
          res.routesOk === 0
            ? `Aucune réponse de l’API${errs}`
            : `${updated} segments avec un prix en direct pour ${month.label}${errs}`,
      });
    } catch (e) {
      setLiveState({ loading: false, error: true, text: e instanceof Error ? e.message : String(e) });
    }
  };

  const header = (
    <View>
      <View style={styles.titleRow}>
        <View style={styles.flex}>
          <View style={styles.titleLine}>
            <Text style={[styles.title, { color: t.text }]}>Toulouse</Text>
            <ArrowIcon size={22} color={t.accent} strokeWidth={2.4} />
            <Text style={[styles.title, { color: t.text }]}>Madagascar</Text>
          </View>
          <Text style={[styles.subtitle, { color: t.sub }]}>
            Tous les trajets vers Diego-Suarez et Nosy Be, du moins cher au plus cher
          </Text>
        </View>
        <Pressable
          onPress={() => setShowSettings(true)}
          style={[styles.gear, { backgroundColor: t.chip }]}
          accessibilityRole="button"
          accessibilityLabel="Réglages"
        >
          <SlidersIcon size={20} color={t.text} />
        </Pressable>
      </View>

      <View style={[styles.panel, { backgroundColor: t.card, borderColor: t.border }]}>
        <Text style={[styles.label, { color: t.sub }]}>Destination</Text>
        <Segmented
          t={t}
          value={dest}
          onChange={setDest}
          options={[
            { value: 'DIE', label: 'Antsiranana' },
            { value: 'NOS', label: 'Nosy Be' },
            { value: 'BOTH', label: 'Les deux' },
          ]}
        />

        <Text style={[styles.label, styles.mt, { color: t.sub }]}>Mois de départ</Text>
        <ScrollView horizontal showsHorizontalScrollIndicator={false}>
          {months.map((m, i) => (
            <Chip key={m.key} t={t} label={m.label} active={i === monthIdx} onPress={() => setMonthIdx(i)} />
          ))}
        </ScrollView>

        <View style={[styles.row, styles.mtSmall]}>
          <Stepper t={t} label="Jour" value={safeDay} min={minDay} max={maxDay} onChange={setDay} />
          <Stepper t={t} label="Voyageurs" value={pax} min={1} max={9} onChange={setPax} />
        </View>

        <Text style={[styles.label, styles.mt, { color: t.sub }]}>Moyens de transport</Text>
        <View style={styles.wrap}>
          {FILTERABLE_MODES.map((m) => (
            <Chip
              key={m}
              t={t}
              label={MODE_LABEL[m]}
              icon={(color) => <ModeIcon mode={m} size={16} color={color} />}
              active={modes.includes(m)}
              onPress={() => toggleMode(m)}
            />
          ))}
        </View>

        <View style={styles.switchRow}>
          <Text style={[styles.switchLabel, { color: t.text }]}>Inclure les liaisons à vérifier</Text>
          <Switch
            value={includeUnverified}
            onValueChange={setIncludeUnverified}
            trackColor={{ true: t.accent, false: t.chip }}
          />
        </View>
        <View style={styles.switchRow}>
          <Text style={[styles.switchLabel, { color: t.text }]}>Regrouper les variantes d’un même trajet</Text>
          <Switch value={grouped} onValueChange={setGrouped} trackColor={{ true: t.accent, false: t.chip }} />
        </View>
      </View>

      <View style={[styles.panel, { backgroundColor: t.card, borderColor: t.border }]}>
        <View style={styles.row}>
          <View style={styles.flex}>
            <Text style={[styles.liveTitle, { color: t.text }]}>Prix des vols en direct</Text>
            <Text style={[styles.liveText, { color: liveState.error ? t.warn : t.sub }]}>
              {liveState.text ??
                (token
                  ? `Met à jour les vols pour ${month.label}.`
                  : `Sans jeton API : estimations de ${DATA_DATE}. Ajoutez un jeton gratuit dans les réglages.`)}
            </Text>
          </View>
          <Pressable
            onPress={refreshLive}
            disabled={liveState.loading}
            style={[styles.liveBtn, { backgroundColor: t.accent }]}
            accessibilityRole="button"
          >
            {liveState.loading ? (
              <ActivityIndicator color={t.onAccent} />
            ) : (
              <Text style={[styles.liveBtnText, { color: t.onAccent }]}>{token ? 'Actualiser' : 'Configurer'}</Text>
            )}
          </Pressable>
        </View>
      </View>

      {itineraries.length > 0 && (
        <>
          <Text style={[styles.count, { color: t.sub }]}>
            {itineraries.length} combinaisons trouvées
            {grouped ? ` · ${rows.length} itinéraires distincts` : ''}
          </Text>
          {best.cheapest && (
            <ItineraryCard t={t} it={best.cheapest} tag="Le moins cher" onPress={() => openWithVariants(best.cheapest!)} />
          )}
          {best.fastest && best.fastest.id !== best.cheapest?.id && (
            <ItineraryCard t={t} it={best.fastest} tag="Le plus rapide" onPress={() => openWithVariants(best.fastest!)} />
          )}
          {best.simplest && best.simplest.id !== best.cheapest?.id && best.simplest.id !== best.fastest?.id && (
            <ItineraryCard
              t={t}
              it={best.simplest}
              tag="Le plus simple (moins de billets)"
              onPress={() => openWithVariants(best.simplest!)}
            />
          )}

          <Text style={[styles.section, { color: t.text }]}>Tous les trajets</Text>
          <Segmented
            t={t}
            value={sort}
            onChange={setSort}
            options={[
              { value: 'prix', label: 'Prix bas' },
              { value: 'typique', label: 'Prix courant' },
              { value: 'duree', label: 'Durée' },
              { value: 'simple', label: 'Simplicité' },
            ]}
          />
          <View style={styles.mtSmall} />
        </>
      )}
    </View>
  );

  const empty = (
    <View style={[styles.panel, { backgroundColor: t.card, borderColor: t.border }]}>
      <Text style={[styles.emptyTitle, { color: t.text }]}>Aucun trajet avec ces filtres</Text>
      <Text style={[styles.liveText, { color: t.sub }]}>
        {modes.includes('avion')
          ? 'Réactivez d’autres moyens de transport ou les liaisons à vérifier.'
          : 'Il n’existe pas de liaison maritime régulière de passagers entre la France et Madagascar : l’avion est indispensable pour au moins une étape.'}
      </Text>
    </View>
  );

  const footer =
    rows.length > limit ? (
      <Pressable
        onPress={() => setLimit((l) => l + PAGE)}
        style={[styles.more, { backgroundColor: t.chip }]}
        accessibilityRole="button"
      >
        <Text style={[styles.moreText, { color: t.text }]}>Afficher plus ({rows.length - limit} restants)</Text>
      </Pressable>
    ) : rows.length > 0 ? (
      <Text style={[styles.end, { color: t.sub }]}>
        Fin de la liste. Prix estimés ({DATA_DATE}) sauf mention « prix en direct » : vérifiez toujours avant
        d’acheter.
      </Text>
    ) : undefined;

  return (
    <SafeAreaView style={[styles.flex, { backgroundColor: t.bg }]} edges={['top', 'left', 'right']}>
      <StatusBar style={t.dark ? 'light' : 'dark'} />
      <FlatList
        data={rows.slice(0, limit)}
        keyExtractor={(item) => item[0].id}
        ListHeaderComponent={header}
        ListEmptyComponent={empty}
        ListFooterComponent={footer}
        contentContainerStyle={styles.list}
        renderItem={({ item, index }) => (
          <ItineraryCard
            t={t}
            it={item[0]}
            rank={index + 1}
            variants={grouped ? item.length : undefined}
            onPress={() => (grouped ? setDetail(item) : openWithVariants(item[0]))}
          />
        )}
      />
      <DetailModal variants={detail} start={start} passengers={pax} t={t} onClose={() => setDetail(null)} />
      <SettingsModal
        visible={showSettings}
        token={token}
        onSave={saveToken}
        onClose={() => setShowSettings(false)}
        t={t}
      />
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  flex: { flex: 1 },
  list: { padding: 16, paddingBottom: 48, width: '100%', maxWidth: 760, alignSelf: 'center' },
  titleRow: { flexDirection: 'row', alignItems: 'flex-start', marginBottom: 14 },
  titleLine: { flexDirection: 'row', alignItems: 'center', flexWrap: 'wrap', gap: 8 },
  title: { fontSize: 26, fontWeight: '800' },
  subtitle: { fontSize: 14, marginTop: 4, lineHeight: 19 },
  gear: { width: 40, height: 40, borderRadius: 20, alignItems: 'center', justifyContent: 'center', marginLeft: 12 },
  panel: { borderRadius: 14, borderWidth: StyleSheet.hairlineWidth, padding: 14, marginBottom: 12 },
  label: { fontSize: 12, fontWeight: '700', letterSpacing: 0.4, marginBottom: 8, textTransform: 'uppercase' },
  mt: { marginTop: 16 },
  mtSmall: { marginTop: 10 },
  row: { flexDirection: 'row', alignItems: 'center' },
  wrap: { flexDirection: 'row', flexWrap: 'wrap' },
  switchRow: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', marginTop: 10 },
  switchLabel: { fontSize: 14, flex: 1, marginRight: 12 },
  liveTitle: { fontSize: 15, fontWeight: '700' },
  liveText: { fontSize: 13, marginTop: 3, lineHeight: 18 },
  liveBtn: { paddingHorizontal: 14, paddingVertical: 10, borderRadius: 10, marginLeft: 12, minWidth: 100, alignItems: 'center' },
  liveBtnText: { fontSize: 14, fontWeight: '700' },
  count: { fontSize: 13, marginVertical: 8 },
  section: { fontSize: 18, fontWeight: '700', marginTop: 14, marginBottom: 10 },
  emptyTitle: { fontSize: 16, fontWeight: '700' },
  more: { borderRadius: 12, paddingVertical: 12, alignItems: 'center', marginTop: 4 },
  moreText: { fontSize: 15, fontWeight: '600' },
  end: { fontSize: 12, lineHeight: 18, marginTop: 8, textAlign: 'center' },
});
