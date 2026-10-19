#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────
# fim-titulos.sh — Imprime SOLO los títulos de los episodios de una temporada
# Uso:       ./fim-titulos.sh <número_de_temporada>
# Salida:    un título por línea, sin numeración ni mensajes; el mismo
#            contenido se guarda idéntico en eps.txt
# Nota:      cualquier error va a stderr, así que stdout y eps.txt quedan limpios
# Requisitos: bash, jq y curl (curl solo si hay que descargar db.json)
# ──────────────────────────────────────────────────────────────────────

set -euo pipefail

# ── 1. Configuración ──────────────────────────────────────────────────
DB_URL="https://fim.heartshine.gay/db.json"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DB_FILE="${DB_FILE:-$SCRIPT_DIR/db.json}"   # db.json junto al script
OUT_FILE="${OUT_FILE:-eps.txt}"             # eps.txt en la carpeta desde donde se ejecuta

error() { echo "Error: $*" >&2; }

# ── 2. Validación del argumento ───────────────────────────────────────
if [[ $# -ne 1 || ! "$1" =~ ^[0-9]+$ ]]; then
  echo "Uso: $0 <número_de_temporada>" >&2
  exit 1
fi
SEASON=$((10#$1))   # normaliza "03" -> 3

# ── 3. Dependencias ───────────────────────────────────────────────────
if ! command -v jq >/dev/null 2>&1; then
  error "jq no está instalado."
  exit 1
fi

# ── 4. Descarga silenciosa de db.json si no existe ────────────────────
if [[ ! -f "$DB_FILE" ]]; then
  if ! command -v curl >/dev/null 2>&1; then
    error "No existe $DB_FILE y curl no está instalado."
    exit 1
  fi
  TMP_FILE="$(mktemp "$DB_FILE.XXXXXX")"   # temporal: evita dejar un db.json a medias
  if ! curl -fsSL --retry 3 -o "$TMP_FILE" "$DB_URL"; then
    rm -f "$TMP_FILE"
    error "No se pudo descargar $DB_URL"
    exit 1
  fi
  chmod 644 "$TMP_FILE"
  mv "$TMP_FILE" "$DB_FILE"
fi

# ── 5. Extracción de títulos con jq ───────────────────────────────────
# Se guarda primero en una variable: si algo falla, eps.txt no se toca.
if ! TITLES="$(jq -r --argjson n "$SEASON" '
  .series.seasons[]
  | select(.seasNum == $n)
  | .episodes | sort_by(.epNum) | .[].epTitle
' "$DB_FILE")"; then
  error "No se pudo leer $DB_FILE (¿JSON inválido? bórralo para volver a descargarlo)."
  exit 1
fi

if [[ -z "$TITLES" ]]; then
  error "No se encontró la temporada $SEASON."
  exit 1
fi

# ── 6. Salida: pantalla y eps.txt, con contenido idéntico ─────────────
printf '%s\n' "$TITLES" | tee "$OUT_FILE"
