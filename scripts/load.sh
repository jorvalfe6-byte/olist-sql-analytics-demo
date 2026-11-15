#!/usr/bin/env bash
# Carga completa: esquema → staging → core → marts → validación.
# Uso:
#   export PGHOST=localhost PGUSER=postgres PGDATABASE=olist
#   ./scripts/load.sh            # usa ./data por defecto
#   ./scripts/load.sh /ruta/csv
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DATA_DIR="$(cd "${1:-$ROOT/data}" && pwd)"
PSQL=(psql -X -q -v ON_ERROR_STOP=1)

echo "→ esquema";   "${PSQL[@]}" -f "$ROOT/sql/01_schema.sql"
echo "→ staging";   "${PSQL[@]}" -v datadir="$DATA_DIR" -f "$ROOT/sql/02_load_staging.sql"
echo "→ core";      "${PSQL[@]}" -f "$ROOT/sql/03_transform.sql"
echo "→ marts";     "${PSQL[@]}" -f "$ROOT/sql/04_marts.sql"
echo "→ dashboard"; "${PSQL[@]}" -f "$ROOT/sql/05_dashboard_views.sql"
echo "→ validación"
"${PSQL[@]}" -f "$ROOT/sql/analysis/00_calidad_datos.sql"
echo "Listo."
