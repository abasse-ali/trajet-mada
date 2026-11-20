import { useEffect, useState } from 'react';
import { Linking, Modal, Pressable, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { DATA_DATE, LEGS } from '../data/network';
import { ExternalIcon } from './icons';
import type { Theme } from './theme';

export function SettingsModal(props: {
  visible: boolean;
  token: string;
  onSave: (token: string) => void;
  onClose: () => void;
  t: Theme;
}) {
  const { visible, token, onSave, onClose, t } = props;
  const [draft, setDraft] = useState(token);
  useEffect(() => {
    if (visible) setDraft(token);
  }, [visible, token]);
  const flights = LEGS.filter((l) => l.live).length;

  return (
    <Modal visible={visible} animationType="slide" presentationStyle="pageSheet" onRequestClose={onClose}>
      <SafeAreaView style={[styles.flex, { backgroundColor: t.bg }]} edges={['top', 'bottom']}>
        <View style={[styles.header, { borderColor: t.border }]}>
          <Text style={[styles.title, { color: t.text }]}>Réglages</Text>
          <Pressable onPress={onClose} hitSlop={12} accessibilityRole="button">
            <Text style={[styles.close, { color: t.accent }]}>Fermer</Text>
          </Pressable>
        </View>
        <ScrollView contentContainerStyle={styles.body} keyboardShouldPersistTaps="handled">
          <Text style={[styles.h, { color: t.text }]}>Prix des vols en direct</Text>
          <Text style={[styles.p, { color: t.sub }]}>
            L’app peut interroger l’API gratuite Aviasales / Travelpayouts pour remplacer les estimations des {flights}{' '}
            segments en avion par les meilleurs prix récemment trouvés pour le mois choisi. Créez un compte gratuit,
            puis copiez votre jeton (menu Profil, rubrique API token).
          </Text>
          <Pressable
            onPress={() => Linking.openURL('https://www.travelpayouts.com/')}
            accessibilityRole="link"
            style={styles.linkRow}
          >
            <Text style={[styles.link, { color: t.accent }]}>Ouvrir travelpayouts.com</Text>
            <ExternalIcon size={14} color={t.accent} strokeWidth={2.2} />
          </Pressable>
          <TextInput
            value={draft}
            onChangeText={setDraft}
            placeholder="Jeton API Travelpayouts"
            placeholderTextColor={t.sub}
            autoCapitalize="none"
            autoCorrect={false}
            style={[styles.input, { color: t.text, borderColor: t.border, backgroundColor: t.card }]}
          />
          <View style={styles.row}>
            <Pressable
              onPress={() => onSave(draft.trim())}
              style={[styles.btn, { backgroundColor: t.accent }]}
              accessibilityRole="button"
            >
              <Text style={[styles.btnText, { color: t.onAccent }]}>Enregistrer</Text>
            </Pressable>
            {token ? (
              <Pressable
                onPress={() => onSave('')}
                style={[styles.btn, { backgroundColor: t.chip }]}
                accessibilityRole="button"
              >
                <Text style={[styles.btnText, { color: t.text }]}>Effacer</Text>
              </Pressable>
            ) : null}
          </View>
          <Text style={[styles.p, { color: t.sub }]}>Le jeton reste sur ce téléphone.</Text>

          <Text style={[styles.h, { color: t.text }]}>Comment le calcul marche</Text>
          <Text style={[styles.p, { color: t.sub }]}>
            L’app connaît {LEGS.length} liaisons (trains, bus, covoiturage, avions, bateaux, taxis-brousse) entre
            Toulouse, Paris, Milan, La Réunion, Mayotte, Johannesburg, Tana, Ankify, Nosy Be et Diego. Elle combine
            toutes celles qui se suivent, sans repasser deux fois au même endroit, puis additionne prix et durées.
          </Text>
          <Text style={[styles.p, { color: t.sub }]}>
            La durée inclut une marge à chaque correspondance (3 h entre deux vols sur billets séparés, 2 h avant un
            vol). Elle n’inclut pas l’attente d’un vol hebdomadaire.
          </Text>
          <Text style={[styles.p, { color: t.sub }]}>
            Estimations relevées en {DATA_DATE}. Les prix en ariary sont convertis à environ 1 € = 5 000 à 5 300 Ar.
            Une liaison « à vérifier » a été signalée mais pas confirmée pour la saison en cours.
          </Text>
        </ScrollView>
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
  title: { fontSize: 17, fontWeight: '700' },
  close: { fontSize: 16, fontWeight: '600' },
  body: { padding: 16, paddingBottom: 40 },
  h: { fontSize: 16, fontWeight: '700', marginTop: 16, marginBottom: 6 },
  p: { fontSize: 14, lineHeight: 20, marginBottom: 8 },
  linkRow: { flexDirection: 'row', alignItems: 'center', gap: 6, marginBottom: 10 },
  link: { fontSize: 14, fontWeight: '600' },
  input: { borderWidth: 1, borderRadius: 10, paddingHorizontal: 12, paddingVertical: 10, fontSize: 15 },
  row: { flexDirection: 'row', marginTop: 10, marginBottom: 6 },
  btn: { paddingHorizontal: 16, paddingVertical: 10, borderRadius: 10, marginRight: 10 },
  btnText: { fontSize: 15, fontWeight: '600' },
});
