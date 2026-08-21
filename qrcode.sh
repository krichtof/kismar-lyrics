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
echo

# --- 1. Vérifier les dépendances ---
if ! command -v "qrencode" &> /dev/null; then
  echo "❌ '$cmd' n'est pas installé."
  exit 1
fi



# --- 8. Générer les QR codes ---
echo "→ Génération des QR codes..."
qrencode -o "$OUTPUT_DIR/url-qrcode.png" -s 10 "https://${DOMAIN}"

# --- 9. Générer les deux pages imprimables (Wi-Fi / Site) ---
echo "→ Génération des pages à imprimer..."
URL_B64=$(base64 -w 0 "$OUTPUT_DIR/url-qrcode.png")

TITRE="PIANO KISMAR"

# Style commun, pensé pour l'impression noir et blanc sur fond blanc
STYLE_COMMUN=$(cat << 'CSSEOF'
  @import url('https://fonts.googleapis.com/css2?family=Fredoka:wght@500;600&display=swap');
  body { font-family: Arial, Helvetica, sans-serif; background: #fff; color: #000;
         margin: 0; padding: 50px 30px; text-align: center; }
  h1 { font-family: 'Fredoka', 'Trebuchet MS', 'Comic Sans MS', sans-serif;
       font-weight: 600; font-size: 3.1em; margin: 0 0 0.3em 0; line-height: 1.3; }
  h2 { font-family: 'Fredoka', 'Trebuchet MS', 'Comic Sans MS', sans-serif;
       font-weight: 500; font-size: 2.4em; margin: 0 0 30px 0; color: #222; }
  .note { font-size: 1.15em; margin: 0 auto 30px auto; max-width: 500px; line-height: 1.5; }
  img { width: 340px; height: 340px; border: 2px solid #000; padding: 12px; }
  .details { margin-top: 30px; font-size: 2.3em; line-height: 1.8; }
  .details strong { font-weight: bold; }
CSSEOF
)

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
  <h2>On chante, on boit, on s'marre</h2>
  <h2>à Montpezat</h2>
  <p class="note">Scannez ce code pour accéder aux paroles.</p>
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
echo "  - page-site.html    (page à imprimer — accès au site)"
echo
echo "=== Prêt pour Kismar ! ==="
