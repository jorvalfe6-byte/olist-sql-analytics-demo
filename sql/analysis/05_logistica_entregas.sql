-- =====================================================================
-- 05_logistica_entregas.sql — Desempeño logístico y su efecto en la
-- satisfacción.
-- =====================================================================

-- (a) Por estado del cliente. Grano: 1 fila por estado.
--     GROUPING SETS agrega la fila de total nacional en la misma consulta.
SELECT COALESCE(customer_state, 'BRASIL')                       AS estado,
       COUNT(*)                                                 AS entregas,
       ROUND(AVG(delivery_days), 1)                             AS dias_reales,
       ROUND(AVG(promised_days), 1)                             AS dias_prometidos,
       ROUND(PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY delivery_days)::NUMERIC, 1)
                                                                AS p90_dias,
       ROUND(100.0 * AVG(is_late::INT), 1)                      AS pct_tarde,
       ROUND(AVG(review_score), 2)                              AS review_prom
FROM mart.fact_order
WHERE is_valid
  AND delivered_customer_at IS NOT NULL
GROUP BY GROUPING SETS ((customer_state), ())
ORDER BY GROUPING(customer_state), pct_tarde DESC;

-- (b) Satisfacción según el retraso. Grano: 1 fila por tramo de retraso.
SELECT CASE
           WHEN atraso <= -10 THEN '1. 10+ días antes'
           WHEN atraso <= 0   THEN '2. A tiempo'
           WHEN atraso <= 3   THEN '3. 1-3 días tarde'
           WHEN atraso <= 7   THEN '4. 4-7 días tarde'
           ELSE                    '5. 8+ días tarde'
       END                                          AS tramo,
       COUNT(*)                                     AS pedidos,
       ROUND(AVG(review_score), 2)                  AS review_prom,
       ROUND(100.0 * AVG((review_score <= 2)::INT), 1) AS pct_reviews_negativas
FROM (
    SELECT delivered_customer_at::DATE - estimated_delivery_date AS atraso,
           review_score
    FROM mart.fact_order
    WHERE is_valid
      AND delivered_customer_at IS NOT NULL
      AND review_score IS NOT NULL
) AS t
GROUP BY 1
ORDER BY 1;
