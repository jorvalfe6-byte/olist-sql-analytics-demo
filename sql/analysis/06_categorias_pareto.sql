-- =====================================================================
-- 06_categorias_pareto.sql — Participación por categoría y curva ABC.
-- Grano: 1 fila por categoría.
--
-- Clase A: categorías que suman el primer 80 % del GMV; B: hasta 95 %;
-- C: el resto.
-- =====================================================================
WITH por_categoria AS (
    SELECT category,
           COUNT(*)                   AS items,
           COUNT(DISTINCT order_id)   AS pedidos,
           SUM(price)                 AS gmv,
           AVG(price)                 AS precio_prom,
           AVG(review_score)          AS review_prom
    FROM mart.fact_item
    WHERE is_valid
    GROUP BY category
),
acumulado AS (
    SELECT *,
           100.0 * gmv / SUM(gmv) OVER ()                         AS pct_gmv,
           100.0 * SUM(gmv) OVER (ORDER BY gmv DESC, category
                                  ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
                 / SUM(gmv) OVER ()                               AS pct_acumulado,
           RANK() OVER (ORDER BY gmv DESC)                        AS ranking
    FROM por_categoria
)
SELECT ranking,
       category,
       items,
       pedidos,
       ROUND(gmv, 2)            AS gmv,
       ROUND(precio_prom, 2)    AS precio_prom,
       ROUND(review_prom, 2)    AS review_prom,
       ROUND(pct_gmv, 2)        AS pct_gmv,
       ROUND(pct_acumulado, 2)  AS pct_acumulado,
       -- se clasifica con el acumulado ANTERIOR para que la categoría que
       -- cruza el 80 % quede en A
       CASE WHEN pct_acumulado - pct_gmv < 80 THEN 'A'
            WHEN pct_acumulado - pct_gmv < 95 THEN 'B'
            ELSE 'C' END        AS clase_abc
FROM acumulado
ORDER BY ranking;
