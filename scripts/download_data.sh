#!/usr/bin/env bash
# Baja los 8 CSV de Olist desde el repositorio público de la propia empresa
# en GitHub (los mismos archivos que Kaggle, sin necesidad de cuenta).
# Fijado a un commit para que la descarga sea siempre la misma.
# Uso: ./scripts/download_data.sh [carpeta_destino]   (por defecto ./data)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${1:-$ROOT/data}"
BASE="https://raw.githubusercontent.com/olist/work-at-olist-data/d9e49802f3e92d09ee94ab9ccc5e457f207a8959/datasets"
mkdir -p "$DEST"

for f in olist_customers_dataset olist_sellers_dataset product_category_name_translation \
         olist_products_dataset olist_orders_dataset olist_order_items_dataset \
         olist_order_payments_dataset olist_order_reviews_dataset; do
    echo "→ $f.csv"
    curl -fsSL --retry 3 -o "$DEST/$f.csv" "$BASE/$f.csv"
done
echo "Listo: CSV en $DEST"
