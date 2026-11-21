#!/usr/bin/env bash
# Installe la mise à jour quotidienne des prix et horaires TrajetMada sur un serveur Linux
# (Oracle Cloud : Oracle Linux ou Ubuntu). Aucun droit administrateur nécessaire.
#
#   curl -fsSL https://raw.githubusercontent.com/abasse-ali/trajet-mada/main/server/install.sh | bash
#
# Relancer la commande met à jour le script sans toucher aux clés déjà enregistrées.
set -euo pipefail

REPO_HTTPS="https://github.com/abasse-ali/trajet-mada.git"
REPO_SSH="git@github.com:abasse-ali/trajet-mada.git"
BASE="$HOME/trajetmada"
CONF_DIR="$HOME/.config/trajetmada"
CONF="$CONF_DIR/config.env"
KEY="$HOME/.ssh/trajetmada_deploy"
HOUR="${TRAJETMADA_HOUR:-6}"

say() { printf '\n== %s\n' "$*"; }

ask_secret() {
  local prompt="$1" value=""
  if [ -r /dev/tty ]; then
    printf '%s' "$prompt" > /dev/tty
    IFS= read -r -s value < /dev/tty || true
    printf '\n' > /dev/tty
  fi
  printf '%s' "$value"
}

say "Vérifications"
if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 manquant. Installez-le :  sudo dnf install -y python3   (Oracle Linux)   ou   sudo apt install -y python3   (Ubuntu)"
  exit 1
fi
python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 6) else 1)' || { echo "Python 3.6 ou plus requis."; exit 1; }
if ! command -v git >/dev/null 2>&1; then
  echo "git manquant. Installez-le :  sudo dnf install -y git   ou   sudo apt install -y git"
  exit 1
fi
if ! command -v crontab >/dev/null 2>&1; then
  echo "crontab manquant. Installez-le :  sudo dnf install -y cronie && sudo systemctl enable --now crond"
  echo "                              ou  sudo apt install -y cron"
  exit 1
fi
echo "python3 $(python3 -c 'import platform; print(platform.python_version())'), $(git --version)"

say "Récupération du script"
mkdir -p "$BASE"
if [ -d "$BASE/app/.git" ]; then
  git -C "$BASE/app" pull -q --ff-only
else
  git clone -q --depth 1 "$REPO_HTTPS" "$BASE/app"
fi
echo "Script : $BASE/app/server/trajetmada_update.py"

say "Clés d'API (gardées dans $CONF, lisible par vous seul)"
mkdir -p "$CONF_DIR"
chmod 700 "$CONF_DIR"
if [ -f "$CONF" ]; then
  echo "Configuration existante conservée. Pour changer une clé : nano $CONF"
else
  echo "Appuyez sur Entrée pour laisser une clé vide et l'ajouter plus tard."
  TP="$(ask_secret 'Jeton Travelpayouts : ')"
  SERP="$(ask_secret 'Clé SerpApi : ')"
  SNCF="$(ask_secret 'Clé API SNCF : ')"
  umask 077
  cat > "$CONF" <<EOF
# Configuration TrajetMada : gardez ce fichier privé.
TRAVELPAYOUTS_TOKEN=$TP
SERPAPI_KEY=$SERP
SNCF_API_KEY=$SNCF
# Recherches Google Flights (SerpApi) par jour. Offre gratuite : 250 par mois.
SERPAPI_DAILY_LIMIT=5
# Période (vide = 1er mai au 30 septembre de la prochaine saison) et séjour.
PERIOD_START=
PERIOD_END=
STAY_MIN=28
STAY_MAX=30
ADULTS=1
OUTPUT_DIR=$BASE/data
PUBLISH_GIT_DIR=$BASE/publish
# Ou copie dans un dossier servi par un serveur web :
# PUBLISH_DIR=/var/www/html/trajetmada
EOF
  chmod 600 "$CONF"
  echo "Enregistré : $CONF"
fi

say "Clé de publication vers GitHub"
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
[ -f "$KEY" ] || ssh-keygen -q -t ed25519 -N "" -C "trajetmada-oracle" -f "$KEY"
GIT_SSH="ssh -i $KEY -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"
if [ ! -d "$BASE/publish/.git" ]; then
  git init -q "$BASE/publish"
  git -C "$BASE/publish" remote add origin "$REPO_SSH"
  git -C "$BASE/publish" checkout -q --orphan data
fi
git -C "$BASE/publish" config core.sshCommand "$GIT_SSH"
git -C "$BASE/publish" config user.name "TrajetMada (serveur Oracle)"
git -C "$BASE/publish" config user.email "trajetmada@users.noreply.github.com"

say "Tâche planifiée : tous les jours à ${HOUR} h (heure du serveur)"
LINE="0 $HOUR * * * cd $BASE/app && git pull -q --ff-only; python3 $BASE/app/server/trajetmada_update.py >> $BASE/update.log 2>&1"
( crontab -l 2>/dev/null | grep -v 'trajetmada_update.py' || true; echo "$LINE" ) | crontab -
crontab -l | grep 'trajetmada_update.py'

say "Premier lancement (2 à 5 minutes)"
python3 "$BASE/app/server/trajetmada_update.py" 2>&1 | tee -a "$BASE/update.log" | tail -n 15 || true

printf '\n== Terminé\n\n'
if ssh -i "$KEY" -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new -o BatchMode=yes -T git@github.com 2>&1 \
     | grep -q "successfully authenticated"; then
  echo "Publication vers GitHub : autorisée. Les données sont mises à jour chaque jour à ${HOUR} h."
else
  cat <<EOF
Il reste une étape, une seule fois : autoriser ce serveur à publier sur GitHub.
Ajoutez cette clé publique au dépôt abasse-ali/trajet-mada :
  Settings > Deploy keys > Add deploy key, titre « Oracle », cochez « Allow write access ».

$(cat "$KEY.pub")

Ensuite, testez la publication :
  python3 $BASE/app/server/trajetmada_update.py
EOF
fi

cat <<EOF

Journal des mises à jour : $BASE/update.log
Résumé lisible du dernier passage : $BASE/data/rapport.md
Clés : nano $CONF
EOF
