-- =====================================================================
-- 07_vendedores_ranking.sql — Top 3 vendedores por estado (top-N por
-- grupo) y concentración de la oferta.
-- =====================================================================

-- (a) Top 3 por estado del vendedor. Grano: 1 fila por vendedor rankeado.
WITH por_vendedor AS (
    SELECT seller_id,
           seller_state,
           COUNT(DISTINCT order_id)  AS pedidos,
           SUM(price)                AS gmv,
           AVG(review_score)         AS review_prom,
           AVG(is_late::INT)         AS tasa_tarde
    FROM mart.fact_item
    WHERE is_valid
    GROUP BY seller_id, seller_state
),
rankeado AS (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY seller_state ORDER BY gmv DESC, seller_id) AS puesto,
           100.0 * gmv / SUM(gmv) OVER (PARTITION BY seller_state)                   AS pct_del_estado
    FROM por_vendedor
)
SELECT seller_state                     AS estado,
       puesto,
       LEFT(seller_id, 8) || '…'        AS vendedor,
       pedidos,
       ROUND(gmv, 2)                    AS gmv,
       ROUND(pct_del_estado, 1)         AS pct_del_estado,
       ROUND(review_prom, 2)            AS review_prom,
       ROUND(100.0 * tasa_tarde, 1)     AS pct_tarde
FROM rankeado
WHERE puesto <= 3
  AND seller_state IN (SELECT seller_state FROM por_vendedor
                       GROUP BY seller_state HAVING COUNT(*) >= 10)
ORDER BY SUM(gmv) OVER (PARTITION BY seller_state) DESC, puesto;

-- (b) Concentración: qué % del GMV hacen el top 1 %, 10 % y 20 % de
--     vendedores. Grano: 1 fila.
WITH por_vendedor AS (
    SELECT seller_id, SUM(price) AS gmv
    FROM mart.fact_item
    WHERE is_valid
    GROUP BY seller_id
),
percentil AS (
    SELECT gmv,
           PERCENT_RANK() OVER (ORDER BY gmv DESC) AS pr
    FROM por_vendedor
)
SELECT COUNT(*)                                                          AS vendedores,
       ROUND(100.0 * SUM(gmv) FILTER (WHERE pr < 0.01) / SUM(gmv), 1)    AS pct_gmv_top1,
       ROUND(100.0 * SUM(gmv) FILTER (WHERE pr < 0.10) / SUM(gmv), 1)    AS pct_gmv_top10,
       ROUND(100.0 * SUM(gmv) FILTER (WHERE pr < 0.20) / SUM(gmv), 1)    AS pct_gmv_top20
FROM percentil;
