#!/usr/bin/env bash
# Carga completa: esquema → staging → core → marts → validación.
# Uso:
#   export PGHOST=localhost PGUSER=postgres PGDATABASE=olist
#   ./scripts/load.sh            # usa ./data por defecto
#   ./scripts/load.sh /ruta/csv
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DATA_DIR="${1:-$ROOT/data}"

# Antes de tocar la base: ¿están los 8 CSV?
faltan=()
for f in olist_customers_dataset olist_sellers_dataset product_category_name_translation \
         olist_products_dataset olist_orders_dataset olist_order_items_dataset \
         olist_order_payments_dataset olist_order_reviews_dataset; do
    [[ -f "$DATA_DIR/$f.csv" ]] || faltan+=("$f.csv")
done
if (( ${#faltan[@]} )); then
    echo "Faltan CSV en $DATA_DIR:" >&2
    printf '  %s\n' "${faltan[@]}" >&2
    echo "Descárgalos de https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce" >&2
    echo "o corre ./scripts/download_data.sh" >&2
    exit 1
fi
DATA_DIR="$(cd "$DATA_DIR" && pwd)"
PSQL=(psql -X -q -v ON_ERROR_STOP=1)

echo "→ esquema";   "${PSQL[@]}" -f "$ROOT/sql/01_schema.sql"
echo "→ staging";   "${PSQL[@]}" -v datadir="$DATA_DIR" -f "$ROOT/sql/02_load_staging.sql"
echo "→ core";      "${PSQL[@]}" -f "$ROOT/sql/03_transform.sql"
echo "→ marts";     "${PSQL[@]}" -f "$ROOT/sql/04_marts.sql"
echo "→ dashboard"; "${PSQL[@]}" -f "$ROOT/sql/05_dashboard_views.sql"
echo "→ validación"
controles="$("${PSQL[@]}" -f "$ROOT/sql/analysis/00_calidad_datos.sql")"
echo "$controles"
if grep -q 'REVISAR' <<<"$controles"; then
    echo "Hay controles de calidad en REVISAR: la carga no coincide con el dataset esperado." >&2
    exit 1
fi
echo "Listo."
