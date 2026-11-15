-- =====================================================================
-- 02_ventas_mensuales.sql — Serie mensual con MoM, YoY, acumulado y
-- media móvil de 3 meses.
-- Grano: 1 fila por mes.
--
-- Se usa una tabla calendario (generate_series) para que un mes sin
-- ventas aparezca con 0 y no rompa LAG ni la media móvil.
-- 2016-09/12 y 2018-09/10 tienen muy pocos pedidos (inicio y corte del
-- dataset): se excluyen del análisis de tendencia.
-- =====================================================================
WITH calendario AS (
    SELECT generate_series(DATE '2017-01-01', DATE '2018-08-01', INTERVAL '1 month')::DATE AS mes
),
ventas AS (
    SELECT purchase_month              AS mes,
           COUNT(*)                    AS pedidos,
           SUM(merchandise_value)      AS gmv,
           COUNT(DISTINCT customer_unique_id) AS clientes
    FROM mart.fact_order
    WHERE is_valid
      AND purchased_at >= DATE '2017-01-01'
      AND purchased_at <  DATE '2018-09-01'     -- filtro semiabierto y sargable
    GROUP BY purchase_month
)
SELECT c.mes,
       COALESCE(v.pedidos, 0)                                       AS pedidos,
       ROUND(COALESCE(v.gmv, 0), 2)                                 AS gmv,
       ROUND(COALESCE(v.gmv, 0) / NULLIF(v.pedidos, 0), 2)          AS ticket_promedio,
       ROUND(100.0 * (v.gmv / NULLIF(LAG(v.gmv) OVER w, 0) - 1), 1) AS var_mom_pct,
       ROUND(100.0 * (v.gmv / NULLIF(LAG(v.gmv, 12) OVER w, 0) - 1), 1) AS var_yoy_pct,
       ROUND(SUM(COALESCE(v.gmv, 0)) OVER (PARTITION BY DATE_TRUNC('year', c.mes) ORDER BY c.mes), 2)
                                                                    AS gmv_ytd,
       ROUND(AVG(COALESCE(v.gmv, 0)) OVER (ORDER BY c.mes ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 2)
                                                                    AS gmv_media_movil_3m
FROM calendario AS c
LEFT JOIN ventas AS v ON v.mes = c.mes
WINDOW w AS (ORDER BY c.mes)
ORDER BY c.mes;
