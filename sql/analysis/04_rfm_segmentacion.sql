-- =====================================================================
-- 04_rfm_segmentacion.sql — Segmentación RFM de clientes.
-- Grano: 1 fila por segmento (el detalle por cliente está en la CTE rfm).
--
-- Recencia: días entre la última compra y la fecha de corte del dataset.
-- Frecuencia: pedidos válidos. Valor: GMV del cliente.
-- Como el 97 % de los clientes compra una sola vez, la frecuencia se
-- puntúa con reglas fijas (1, 2, 3+) en vez de quintiles: NTILE sobre
-- una columna casi constante repartiría empates al azar.
-- =====================================================================
WITH corte AS (
    SELECT MAX(purchased_at)::DATE + 1 AS fecha_corte
    FROM mart.fact_order
    WHERE is_valid
),
base AS (
    SELECT fo.customer_unique_id,
           (SELECT fecha_corte FROM corte) - MAX(fo.purchased_at)::DATE AS recencia_dias,
           COUNT(*)                                                     AS frecuencia,
           SUM(fo.merchandise_value)                                    AS valor
    FROM mart.fact_order AS fo
    WHERE fo.is_valid
    GROUP BY fo.customer_unique_id
),
rfm AS (
    SELECT customer_unique_id,
           recencia_dias,
           frecuencia,
           valor,
           6 - NTILE(5) OVER (ORDER BY recencia_dias) AS r,   -- más reciente = 5
           CASE WHEN frecuencia >= 3 THEN 5
                WHEN frecuencia  = 2 THEN 4
                ELSE 1 END                            AS f,
           NTILE(5) OVER (ORDER BY valor)             AS m
    FROM base
),
segmentos AS (
    SELECT *,
           CASE
               WHEN f >= 4 AND r >= 4 AND m >= 4 THEN '1. Campeones'
               WHEN f >= 4                       THEN '2. Leales'
               WHEN r >= 4 AND m >= 4            THEN '3. Nuevos de alto valor'
               WHEN r >= 4                       THEN '4. Nuevos'
               WHEN r  = 3                       THEN '5. Por enfriarse'
               WHEN m >= 4                       THEN '6. Alto valor en riesgo'
               ELSE                                   '7. Perdidos'
           END AS segmento
    FROM rfm
)
SELECT segmento,
       COUNT(*)                                            AS clientes,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)  AS pct_clientes,
       ROUND(SUM(valor), 2)                                AS gmv,
       ROUND(100.0 * SUM(valor) / SUM(SUM(valor)) OVER (), 1) AS pct_gmv,
       ROUND(AVG(recencia_dias))                           AS recencia_prom_dias,
       ROUND(AVG(frecuencia), 2)                           AS frecuencia_prom,
       ROUND(AVG(valor), 2)                                AS valor_prom
FROM segmentos
GROUP BY segmento
ORDER BY segmento;
