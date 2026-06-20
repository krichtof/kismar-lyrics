#!/bin/bash
#
# arreter-kismar.sh — Coupe Jekyll, la redirection de port, et le hotspot Wi-Fi de Kismar.
#
# Usage : ./arreter-kismar.sh [port-jekyll]

HOTSPOT_PROFILE="Hotspot"
IFACE="wlo1"
JEKYLL_PORT="${1:-4000}"
OUTPUT_DIR="$HOME/kismar-qrcodes"
JEKYLL_PID_FILE="$OUTPUT_DIR/jekyll.pid"

# --- 1. Arrêter Jekyll ---
if [ -f "$JEKYLL_PID_FILE" ]; then
  PID="$(cat "$JEKYLL_PID_FILE")"
  if kill -0 "$PID" 2> /dev/null; then
    kill "$PID"
    echo "✓ Jekyll arrêté (PID $PID)."
  else
    echo "Jekyll n'était déjà plus actif (PID $PID introuvable)."
  fi
  rm -f "$JEKYLL_PID_FILE"
else
  echo "Pas de PID Jekyll enregistré."
fi
# Filet de sécurité : tue aussi tout process jekyll serve resté orphelin sur ce port
pkill -f "jekyll serve.*--port ${JEKYLL_PORT}" 2> /dev/null || true

# --- 2. Retirer la redirection iptables ---
sudo iptables -t nat -D PREROUTING -i "$IFACE" -p tcp --dport 80 -j REDIRECT --to-port "$JEKYLL_PORT" 2> /dev/null && \
    echo "✓ Redirection port 80 → ${JEKYLL_PORT} retirée." || \
    echo "Pas de redirection active à retirer."

# --- 3. Couper le hotspot ---
if nmcli connection show --active | grep -q "$HOTSPOT_PROFILE"; then
    nmcli connection down "$HOTSPOT_PROFILE"
    echo "✓ Hotspot '$HOTSPOT_PROFILE' arrêté."
else
    echo "Le hotspot '$HOTSPOT_PROFILE' n'était pas actif."
fi
