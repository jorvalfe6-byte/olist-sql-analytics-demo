-- =====================================================================
-- 05_dashboard_views.sql — Vistas compactas que alimentan el dashboard.
-- Cada una es la versión resumida de una consulta de sql/analysis/.
-- scripts/export_dashboard.sh las vuelca a docs/data/dashboard.json.
-- =====================================================================
\set ON_ERROR_STOP on
SET client_min_messages = warning;

DROP VIEW IF EXISTS mart.dash_kpis, mart.dash_mensual, mart.dash_cohortes,
                    mart.dash_rfm, mart.dash_estados, mart.dash_atraso_review,
                    mart.dash_categorias, mart.dash_pagos, mart.dash_vendedores CASCADE;

-- KPIs generales (ver analysis/01)
CREATE VIEW mart.dash_kpis AS
SELECT COUNT(*)                                         AS pedidos,
       COUNT(DISTINCT customer_unique_id)               AS clientes,
       ROUND(SUM(merchandise_value), 2)                 AS gmv,
       ROUND(AVG(merchandise_value), 2)                 AS ticket_promedio,
       ROUND(100.0 * COUNT(DISTINCT customer_unique_id) FILTER (WHERE compras > 1)
                   / COUNT(DISTINCT customer_unique_id), 1) AS pct_recompra,
       ROUND(100.0 * AVG(is_late::INT) FILTER (WHERE is_late IS NOT NULL), 1) AS pct_tarde,
       ROUND(AVG(delivery_days), 1)                     AS dias_entrega,
       ROUND(AVG(review_score), 2)                      AS review,
       MIN(purchased_at)::DATE                          AS desde,
       MAX(purchased_at)::DATE                          AS hasta
FROM (SELECT fo.*, COUNT(*) OVER (PARTITION BY customer_unique_id) AS compras
      FROM mart.fact_order AS fo WHERE is_valid) AS t;

-- Serie mensual (ver analysis/02)
CREATE VIEW mart.dash_mensual AS
WITH calendario AS (
    SELECT generate_series(DATE '2017-01-01', DATE '2018-08-01', INTERVAL '1 month')::DATE AS mes
),
ventas AS (
    SELECT purchase_month AS mes, COUNT(*) AS pedidos, SUM(merchandise_value) AS gmv
    FROM mart.fact_order
    WHERE is_valid AND purchased_at >= DATE '2017-01-01' AND purchased_at < DATE '2018-09-01'
    GROUP BY purchase_month
)
SELECT c.mes,
       COALESCE(v.pedidos, 0)          AS pedidos,
       ROUND(COALESCE(v.gmv, 0), 2)    AS gmv,
       ROUND(AVG(COALESCE(v.gmv, 0)) OVER (ORDER BY c.mes ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 2)
                                       AS gmv_mm3
FROM calendario AS c LEFT JOIN ventas AS v USING (mes);

-- Retención por cohorte, meses 1 a 6 (ver analysis/03)
CREATE VIEW mart.dash_cohortes AS
WITH compras AS (
    SELECT customer_unique_id, purchase_month
    FROM mart.fact_order WHERE is_valid
    GROUP BY customer_unique_id, purchase_month
),
primera AS (
    SELECT customer_unique_id, MIN(purchase_month) AS cohorte
    FROM compras GROUP BY customer_unique_id
),
actividad AS (
    SELECT p.cohorte,
           (EXTRACT(YEAR FROM AGE(c.purchase_month, p.cohorte)) * 12
          + EXTRACT(MONTH FROM AGE(c.purchase_month, p.cohorte)))::INT AS mes_n,
           c.customer_unique_id
    FROM compras AS c JOIN primera AS p USING (customer_unique_id)
),
tamano AS (SELECT cohorte, COUNT(*) AS clientes FROM primera GROUP BY cohorte),
grilla AS (   -- cohorte x mes, para que las celdas vacías salgan en 0
    SELECT t.cohorte, t.clientes, m.mes_n
    FROM tamano AS t CROSS JOIN generate_series(1, 6) AS m (mes_n)
    WHERE t.cohorte >= DATE '2017-01-01' AND t.cohorte <= DATE '2018-02-01'
)
SELECT g.cohorte, g.clientes, g.mes_n,
       COUNT(DISTINCT a.customer_unique_id)                                 AS activos,
       ROUND(100.0 * COUNT(DISTINCT a.customer_unique_id) / g.clientes, 2)  AS retencion_pct
FROM grilla AS g
LEFT JOIN actividad AS a ON a.cohorte = g.cohorte AND a.mes_n = g.mes_n
GROUP BY g.cohorte, g.clientes, g.mes_n;

-- Segmentos RFM (ver analysis/04)
CREATE VIEW mart.dash_rfm AS
WITH corte AS (SELECT MAX(purchased_at)::DATE + 1 AS fecha FROM mart.fact_order WHERE is_valid),
base AS (
    SELECT customer_unique_id,
           (SELECT fecha FROM corte) - MAX(purchased_at)::DATE AS recencia,
           COUNT(*) AS frecuencia, SUM(merchandise_value) AS valor
    FROM mart.fact_order WHERE is_valid GROUP BY customer_unique_id
),
rfm AS (
    SELECT *, 6 - NTILE(5) OVER (ORDER BY recencia) AS r,
           CASE WHEN frecuencia >= 3 THEN 5 WHEN frecuencia = 2 THEN 4 ELSE 1 END AS f,
           NTILE(5) OVER (ORDER BY valor) AS m
    FROM base
),
seg AS (
    SELECT *, CASE
               WHEN f >= 4 AND r >= 4 AND m >= 4 THEN 'Campeones'
               WHEN f >= 4                       THEN 'Leales'
               WHEN r >= 4 AND m >= 4            THEN 'Nuevos de alto valor'
               WHEN r >= 4                       THEN 'Nuevos'
               WHEN r  = 3                       THEN 'Por enfriarse'
               WHEN m >= 4                       THEN 'Alto valor en riesgo'
               ELSE                                   'Perdidos' END AS segmento,
           CASE
               WHEN f >= 4 AND r >= 4 AND m >= 4 THEN 1 WHEN f >= 4 THEN 2
               WHEN r >= 4 AND m >= 4 THEN 3 WHEN r >= 4 THEN 4 WHEN r = 3 THEN 5
               WHEN m >= 4 THEN 6 ELSE 7 END AS orden
    FROM rfm
)
SELECT orden, segmento,
       COUNT(*) AS clientes,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)        AS pct_clientes,
       ROUND(100.0 * SUM(valor) / SUM(SUM(valor)) OVER (), 1)    AS pct_gmv,
       ROUND(AVG(recencia))                                      AS recencia_dias,
       ROUND(AVG(valor), 2)                                      AS valor_prom
FROM seg GROUP BY orden, segmento;

-- Entregas por estado (ver analysis/05a)
CREATE VIEW mart.dash_estados AS
SELECT customer_state AS estado,
       COUNT(*) AS entregas,
       ROUND(AVG(delivery_days), 1)  AS dias_reales,
       ROUND(AVG(promised_days), 1)  AS dias_prometidos,
       ROUND(100.0 * AVG(is_late::INT), 1) AS pct_tarde,
       ROUND(AVG(review_score), 2)   AS review
FROM mart.fact_order
WHERE is_valid AND delivered_customer_at IS NOT NULL
GROUP BY customer_state;

-- Review según atraso (ver analysis/05b)
CREATE VIEW mart.dash_atraso_review AS
SELECT CASE WHEN atraso <= -10 THEN 1 WHEN atraso <= 0 THEN 2
            WHEN atraso <= 3 THEN 3 WHEN atraso <= 7 THEN 4 ELSE 5 END AS orden,
       CASE WHEN atraso <= -10 THEN '10+ días antes' WHEN atraso <= 0 THEN 'A tiempo'
            WHEN atraso <= 3 THEN '1-3 días tarde' WHEN atraso <= 7 THEN '4-7 días tarde'
            ELSE '8+ días tarde' END AS tramo,
       COUNT(*) AS pedidos,
       ROUND(AVG(review_score), 2) AS review,
       ROUND(100.0 * AVG((review_score <= 2)::INT), 1) AS pct_negativas
FROM (SELECT delivered_customer_at::DATE - estimated_delivery_date AS atraso, review_score
      FROM mart.fact_order
      WHERE is_valid AND delivered_customer_at IS NOT NULL AND review_score IS NOT NULL) AS t
GROUP BY 1, 2;

-- Categorías con curva ABC (ver analysis/06)
CREATE VIEW mart.dash_categorias AS
WITH c AS (
    SELECT category, SUM(price) AS gmv, COUNT(*) AS items, AVG(review_score) AS review
    FROM mart.fact_item WHERE is_valid GROUP BY category
),
a AS (
    SELECT *, 100.0 * gmv / SUM(gmv) OVER () AS pct,
           100.0 * SUM(gmv) OVER (ORDER BY gmv DESC, category ROWS UNBOUNDED PRECEDING) / SUM(gmv) OVER () AS acum,
           ROW_NUMBER() OVER (ORDER BY gmv DESC, category) AS ranking
    FROM c
)
SELECT ranking, category, items, ROUND(gmv, 2) AS gmv, ROUND(review, 2) AS review,
       ROUND(pct, 2) AS pct_gmv, ROUND(acum, 2) AS pct_acumulado,
       CASE WHEN acum - pct < 80 THEN 'A' WHEN acum - pct < 95 THEN 'B' ELSE 'C' END AS clase_abc
FROM a;

-- Medios de pago (ver analysis/08a)
CREATE VIEW mart.dash_pagos AS
SELECT p.payment_type AS medio,
       COUNT(DISTINCT p.order_id) AS pedidos,
       ROUND(100.0 * SUM(p.payment_value) / SUM(SUM(p.payment_value)) OVER (), 1) AS pct_monto,
       ROUND(AVG(p.payment_value), 2) AS monto_prom
FROM core.order_payment AS p
JOIN core.orders AS o ON o.order_id = p.order_id
WHERE o.order_status NOT IN ('canceled','unavailable')
GROUP BY p.payment_type;

-- Concentración de vendedores (ver analysis/07b)
CREATE VIEW mart.dash_vendedores AS
WITH v AS (SELECT seller_id, SUM(price) AS gmv FROM mart.fact_item WHERE is_valid GROUP BY seller_id),
p AS (SELECT gmv, PERCENT_RANK() OVER (ORDER BY gmv DESC) AS pr FROM v)
SELECT COUNT(*) AS vendedores,
       ROUND(100.0 * SUM(gmv) FILTER (WHERE pr < 0.01) / SUM(gmv), 1) AS pct_top1,
       ROUND(100.0 * SUM(gmv) FILTER (WHERE pr < 0.10) / SUM(gmv), 1) AS pct_top10,
       ROUND(100.0 * SUM(gmv) FILTER (WHERE pr < 0.20) / SUM(gmv), 1) AS pct_top20
FROM p;
