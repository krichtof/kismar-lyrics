#!/bin/bash
#
# lancer-kismar.sh — Lance le hotspot Wi-Fi pour Piano Kismar, configure le DNS
# local, démarre Jekyll, redirige le port 80 vers Jekyll, et génère les QR codes.
#
# Usage : ./lancer-kismar.sh <sous-domaine> [ssid] [mot-de-passe] [port-jekyll] [dossier-jekyll]
# Exemple : ./lancer-kismar.sh oasif.kismar.net PIANO-KISMAR untruclong123 4000 .

set -euo pipefail

# --- Paramètres ---
DOMAIN="${1:?Usage: $0 <sous-domaine> [ssid] [mot-de-passe] [port-jekyll] [dossier-jekyll]}"
SSID="${2:-PIANO-KISMAR}"
WIFI_PASS="${3:-je chante}"
JEKYLL_PORT="${4:-4000}"
JEKYLL_DIR="${5:-.}"
IFACE="wlo1"
HOTSPOT_PROFILE="Hotspot"
HOTSPOT_IP="10.42.0.1"
OUTPUT_DIR="$HOME/kismar-qrcodes"
JEKYLL_LOG="$OUTPUT_DIR/jekyll.log"
JEKYLL_PID_FILE="$OUTPUT_DIR/jekyll.pid"

mkdir -p "$OUTPUT_DIR"

echo "=== Configuration de Kismar ==="
echo "Domaine cible   : $DOMAIN"
echo "SSID            : $SSID"
echo "Interface       : $IFACE"
echo "Port Jekyll     : $JEKYLL_PORT"
echo "Dossier Jekyll  : $JEKYLL_DIR"
echo

# --- 1. Vérifier les dépendances ---
for cmd in nmcli qrencode bundle iptables; do
  if ! command -v "$cmd" &> /dev/null; then
    echo "❌ '$cmd' n'est pas installé."
    exit 1
  fi
done

if [ ! -f "$JEKYLL_DIR/Gemfile" ]; then
  echo "❌ Aucun Gemfile trouvé dans '$JEKYLL_DIR' — vérifie le chemin du projet Jekyll."
  exit 1
fi

# --- 2. Configurer le DNS local (dnsmasq partagé par le hotspot) ---
echo "→ Configuration du DNS local (${DOMAIN} → ${HOTSPOT_IP})"
sudo mkdir -p /etc/NetworkManager/dnsmasq-shared.d
sudo tee /etc/NetworkManager/dnsmasq-shared.d/piano.conf > /dev/null << EOF
address=/${DOMAIN}/${HOTSPOT_IP}
EOF

# --- 3. Créer ou mettre à jour le profil hotspot ---
if nmcli connection show "$HOTSPOT_PROFILE" &> /dev/null; then
  echo "→ Profil '$HOTSPOT_PROFILE' déjà existant, mise à jour..."
  nmcli connection modify "$HOTSPOT_PROFILE" \
    802-11-wireless.ssid "$SSID" \
    wifi-sec.psk "$WIFI_PASS" \
    ipv4.addresses "${HOTSPOT_IP}/24" \
    connection.autoconnect no
else
  echo "→ Création du profil '$HOTSPOT_PROFILE'..."
  nmcli device wifi hotspot ifname "$IFACE" con-name "$HOTSPOT_PROFILE" ssid "$SSID" password "$WIFI_PASS"
  nmcli connection modify "$HOTSPOT_PROFILE" \
    ipv4.addresses "${HOTSPOT_IP}/24" \
    connection.autoconnect no
  nmcli connection down "$HOTSPOT_PROFILE" &> /dev/null || true
fi

# --- 4. Activer le hotspot ---
echo "→ Activation du hotspot..."
nmcli connection up "$HOTSPOT_PROFILE"
echo "✓ Hotspot actif : $SSID"
echo "✓ IP du serveur : $HOTSPOT_IP"
echo "✓ DNS local     : ${DOMAIN} → ${HOTSPOT_IP}"
echo

# --- 5. Lancer Jekyll en arrière-plan ---
echo "→ Démarrage de Jekyll (port ${JEKYLL_PORT})..."

# On coupe d'abord une éventuelle instance déjà lancée par un run précédent
if [ -f "$JEKYLL_PID_FILE" ] && kill -0 "$(cat "$JEKYLL_PID_FILE")" 2> /dev/null; then
  echo "  Une instance Jekyll tournait déjà (PID $(cat "$JEKYLL_PID_FILE")), arrêt..."
  kill "$(cat "$JEKYLL_PID_FILE")" 2> /dev/null || true
  sleep 1
fi

(
  cd "$JEKYLL_DIR"
  nohup bundle exec jekyll serve --host "${HOTSPOT_IP}" --port "$JEKYLL_PORT" \
    > "$JEKYLL_LOG" 2>&1 &
  echo $! > "$JEKYLL_PID_FILE"
)

# --- 6. Attendre que Jekyll soit prêt à répondre ---
echo "→ Attente du démarrage de Jekyll..."
READY=0
for i in $(seq 1 30); do
  if curl -s -o /dev/null "http://${HOTSPOT_IP}:${JEKYLL_PORT}"; then
    READY=1
    break
  fi
  sleep 1
done

if [ "$READY" -eq 0 ]; then
  echo "❌ Jekyll ne répond pas après 30s. Vérifie les logs : $JEKYLL_LOG"
  exit 1
fi
echo "✓ Jekyll est prêt (PID $(cat "$JEKYLL_PID_FILE"))"
echo "  Logs : $JEKYLL_LOG"
echo

# --- 7. Rediriger le port 80 vers le port Jekyll ---
echo "→ Redirection du port 80 vers le port ${JEKYLL_PORT}..."
sudo iptables -t nat -D PREROUTING -i "$IFACE" -p tcp --dport 80 -j REDIRECT --to-port "$JEKYLL_PORT" 2> /dev/null || true
sudo iptables -t nat -A PREROUTING -i "$IFACE" -p tcp --dport 80 -j REDIRECT --to-port "$JEKYLL_PORT"
echo "✓ Redirection active : port 80 (${IFACE}) → port ${JEKYLL_PORT}"
echo

# --- 8. Générer les QR codes ---
echo "→ Génération des QR codes..."
qrencode -o "$OUTPUT_DIR/wifi-qrcode.png" -s 10 "WIFI:T:WPA;S:${SSID};P:${WIFI_PASS};;"
qrencode -o "$OUTPUT_DIR/url-qrcode.png" -s 10 "http://${DOMAIN}"

# --- 9. Générer les deux pages imprimables (Wi-Fi / Site) ---
echo "→ Génération des pages à imprimer..."
WIFI_B64=$(base64 -w 0 "$OUTPUT_DIR/wifi-qrcode.png")
URL_B64=$(base64 -w 0 "$OUTPUT_DIR/url-qrcode.png")

TITRE="Le piano Kismar : on chante, on boit, on s'marre"

# Style commun, pensé pour l'impression noir et blanc sur fond blanc
STYLE_COMMUN=$(cat << 'CSSEOF'
  @import url('https://fonts.googleapis.com/css2?family=Fredoka:wght@500;600&display=swap');
  body { font-family: Arial, Helvetica, sans-serif; background: #fff; color: #000;
         margin: 0; padding: 50px 30px; text-align: center; }
  h1 { font-family: 'Fredoka', 'Trebuchet MS', 'Comic Sans MS', sans-serif;
       font-weight: 600; font-size: 2.1em; margin: 0 0 0.3em 0; line-height: 1.3; }
  h2 { font-family: 'Fredoka', 'Trebuchet MS', 'Comic Sans MS', sans-serif;
       font-weight: 500; font-size: 1.4em; margin: 0 0 30px 0; color: #222; }
  .note { font-size: 1.15em; margin: 0 auto 30px auto; max-width: 500px; line-height: 1.5; }
  img { width: 340px; height: 340px; border: 2px solid #000; padding: 12px; }
  .details { margin-top: 30px; font-size: 1.3em; line-height: 1.8; }
  .details strong { font-weight: bold; }
CSSEOF
)

# --- Page 1 : Wi-Fi ---
cat > "$OUTPUT_DIR/page-wifi.html" << HTMLEOF
<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="UTF-8">
<title>Piano Kismar — Wi-Fi</title>
<style>
${STYLE_COMMUN}
</style>
</head>
<body>
  <h1>${TITRE}</h1>
  <h2>Connexion Wi-Fi</h2>
  <p class="note">Pas de réseau mobile ici ? Scannez ce code pour vous connecter au Wi-Fi de la salle.</p>
  <img src="data:image/png;base64,${WIFI_B64}" alt="QR Wi-Fi">
  <div class="details">
    <div>Réseau : <strong>${SSID}</strong></div>
    <div>Mot de passe : <strong>${WIFI_PASS}</strong></div>
  </div>
</body>
</html>
HTMLEOF

# --- Page 2 : Site ---
cat > "$OUTPUT_DIR/page-site.html" << HTMLEOF
<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="UTF-8">
<title>Piano Kismar — Accéder au site</title>
<style>
${STYLE_COMMUN}
</style>
</head>
<body>
  <h1>${TITRE}</h1>
  <h2>Accéder aux paroles</h2>
  <p class="note">Scannez ce code pour ouvrir le site.</p>
  <img src="data:image/png;base64,${URL_B64}" alt="QR Site">
  <div class="details">
    <div>${DOMAIN}</div>
  </div>
</body>
</html>
HTMLEOF

echo
echo "✓ QR codes générés dans : $OUTPUT_DIR"
echo "  - wifi-qrcode.png   (image seule)"
echo "  - url-qrcode.png    (image seule)"
echo "  - page-wifi.html    (page à imprimer — connexion Wi-Fi)"
echo "  - page-site.html    (page à imprimer — accès au site)"
echo
echo "=== Prêt pour Kismar ! ==="
echo "Jekyll tourne en arrière-plan (PID $(cat "$JEKYLL_PID_FILE")) — utilise ./arreter-kismar.sh pour tout arrêter."
