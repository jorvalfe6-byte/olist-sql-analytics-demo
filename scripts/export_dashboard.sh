#!/usr/bin/env bash
# Exporta las vistas mart.dash_* a un único JSON que lee el dashboard.
# Solo salen agregados: ningún dato a nivel de cliente o pedido.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/docs/data/dashboard.json"
mkdir -p "$(dirname "$OUT")"

psql -X -q -At -v ON_ERROR_STOP=1 > "$OUT" <<'SQL'
SELECT json_build_object(
    'generado',    to_char(now(), 'YYYY-MM-DD'),
    'kpis',        (SELECT row_to_json(k) FROM mart.dash_kpis k),
    'mensual',     (SELECT json_agg(m ORDER BY mes)               FROM mart.dash_mensual m),
    'cohortes',    (SELECT json_agg(c ORDER BY cohorte, mes_n)    FROM mart.dash_cohortes c),
    'rfm',         (SELECT json_agg(r ORDER BY orden)             FROM mart.dash_rfm r),
    'estados',     (SELECT json_agg(e ORDER BY pct_tarde DESC)    FROM mart.dash_estados e),
    'atraso',      (SELECT json_agg(a ORDER BY orden)             FROM mart.dash_atraso_review a),
    'categorias',  (SELECT json_agg(c ORDER BY ranking)           FROM mart.dash_categorias c),
    'pagos',       (SELECT json_agg(p ORDER BY pct_monto DESC)    FROM mart.dash_pagos p),
    'vendedores',  (SELECT row_to_json(v) FROM mart.dash_vendedores v)
);
SQL

echo "→ $OUT ($(wc -c < "$OUT") bytes)"
