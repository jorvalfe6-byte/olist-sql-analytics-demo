-- =====================================================================
-- 01_kpis_generales.sql — Resumen ejecutivo del período completo.
-- Grano del resultado: 1 fila.
-- =====================================================================
SELECT COUNT(*)                                             AS pedidos_validos,
       COUNT(DISTINCT customer_unique_id)                   AS clientes,
       ROUND(SUM(merchandise_value), 2)                     AS gmv,
       ROUND(SUM(freight_value), 2)                         AS flete,
       ROUND(AVG(merchandise_value), 2)                     AS ticket_promedio,
       ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY merchandise_value)::NUMERIC, 2)
                                                            AS ticket_mediana,
       ROUND(AVG(items_qty), 2)                             AS items_por_pedido,
       -- % de clientes que compraron más de una vez
       ROUND(100.0 * COUNT(DISTINCT customer_unique_id) FILTER (WHERE compras > 1)
                   / COUNT(DISTINCT customer_unique_id), 2) AS pct_clientes_recompra,
       ROUND(100.0 * AVG(is_late::INT) FILTER (WHERE is_late IS NOT NULL), 2)
                                                            AS pct_entregas_tarde,
       ROUND(AVG(delivery_days), 1)                         AS dias_entrega_prom,
       ROUND(AVG(review_score), 2)                          AS review_promedio
FROM (
    SELECT fo.*,
           COUNT(*) OVER (PARTITION BY customer_unique_id) AS compras
    FROM mart.fact_order AS fo
    WHERE is_valid
) AS pedidos;
