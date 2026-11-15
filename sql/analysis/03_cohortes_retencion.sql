-- =====================================================================
-- 03_cohortes_retencion.sql — Retención por cohorte de primera compra.
-- Grano: 1 fila por (cohorte, meses desde la primera compra).
--
-- Cohorte = mes de la primera compra del cliente (customer_unique_id).
-- Retención mes N = clientes de la cohorte que volvieron a comprar en el
-- mes N / tamaño de la cohorte.
-- =====================================================================
WITH compras AS (
    SELECT customer_unique_id,
           purchase_month
    FROM mart.fact_order
    WHERE is_valid
    GROUP BY customer_unique_id, purchase_month       -- 1 fila por cliente-mes
),
primera AS (
    SELECT customer_unique_id,
           MIN(purchase_month) AS cohorte
    FROM compras
    GROUP BY customer_unique_id
),
actividad AS (
    SELECT p.cohorte,
           (EXTRACT(YEAR  FROM AGE(c.purchase_month, p.cohorte)) * 12
          + EXTRACT(MONTH FROM AGE(c.purchase_month, p.cohorte)))::INT AS mes_n,
           c.customer_unique_id
    FROM compras AS c
    JOIN primera AS p USING (customer_unique_id)
),
tamano AS (
    SELECT cohorte, COUNT(*) AS clientes_cohorte
    FROM primera
    GROUP BY cohorte
)
SELECT a.cohorte,
       t.clientes_cohorte,
       a.mes_n,
       COUNT(DISTINCT a.customer_unique_id)                                   AS clientes_activos,
       ROUND(100.0 * COUNT(DISTINCT a.customer_unique_id) / t.clientes_cohorte, 2) AS retencion_pct
FROM actividad AS a
JOIN tamano    AS t USING (cohorte)
WHERE a.cohorte >= DATE '2017-01-01'
  AND a.cohorte <  DATE '2018-09-01'
  AND a.mes_n BETWEEN 0 AND 12
GROUP BY a.cohorte, t.clientes_cohorte, a.mes_n
ORDER BY a.cohorte, a.mes_n;
