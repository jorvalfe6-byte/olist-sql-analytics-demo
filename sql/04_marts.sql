-- =====================================================================
-- 04_marts.sql — Capa semántica para análisis y dashboards.
--
-- Definiciones de negocio usadas en todo el proyecto:
--   * Pedido válido   : order_status NOT IN ('canceled','unavailable').
--   * Ingreso (GMV)   : SUM(price) de los ítems. El flete se reporta aparte.
--   * Cliente         : customer_unique_id (la persona), no customer_id.
--   * Entrega a tiempo: delivered_customer_at::date <= estimated_delivery_date.
-- =====================================================================
\set ON_ERROR_STOP on

DROP MATERIALIZED VIEW IF EXISTS mart.fact_order CASCADE;
DROP VIEW IF EXISTS mart.fact_item CASCADE;

-- ---------------------------------------------------------------------
-- mart.fact_order — grano: 1 fila por pedido.
-- Ítems, pagos y reviews se agregan por separado ANTES de unir: unirlos
-- crudos multiplicaría filas (un pedido con 3 ítems y 2 pagos daría 6).
-- ---------------------------------------------------------------------
CREATE MATERIALIZED VIEW mart.fact_order AS
WITH items_por_pedido AS (
    SELECT order_id,
           COUNT(*)              AS items_qty,
           COUNT(DISTINCT seller_id) AS sellers_qty,
           SUM(price)            AS merchandise_value,
           SUM(freight_value)    AS freight_value
    FROM core.order_item
    GROUP BY order_id
),
pagos_por_pedido AS (
    SELECT order_id,
           SUM(payment_value)    AS paid_value,
           MAX(installments)     AS max_installments,
           -- medio principal = el de mayor monto
           (ARRAY_AGG(payment_type ORDER BY payment_value DESC))[1] AS main_payment_type
    FROM core.order_payment
    GROUP BY order_id
),
review_por_pedido AS (
    -- 551 pedidos tienen más de una review: se toma la más reciente
    SELECT DISTINCT ON (order_id)
           order_id, score AS review_score
    FROM core.order_review
    ORDER BY order_id, answered_at DESC
)
SELECT o.order_id,
       c.customer_unique_id,
       c.state                                       AS customer_state,
       c.city                                        AS customer_city,
       o.order_status,
       o.order_status NOT IN ('canceled','unavailable') AS is_valid,
       o.purchased_at,
       DATE_TRUNC('month', o.purchased_at)::DATE     AS purchase_month,
       COALESCE(i.items_qty, 0)                      AS items_qty,
       COALESCE(i.sellers_qty, 0)                    AS sellers_qty,
       COALESCE(i.merchandise_value, 0)              AS merchandise_value,
       COALESCE(i.freight_value, 0)                  AS freight_value,
       COALESCE(p.paid_value, 0)                     AS paid_value,
       p.max_installments,
       p.main_payment_type,
       o.delivered_customer_at,
       o.estimated_delivery_date,
       CASE WHEN o.delivered_customer_at IS NOT NULL
            THEN ROUND(EXTRACT(EPOCH FROM o.delivered_customer_at - o.purchased_at) / 86400.0, 1)
       END                                           AS delivery_days,
       (o.estimated_delivery_date - o.purchased_at::DATE) AS promised_days,
       CASE WHEN o.delivered_customer_at IS NOT NULL
            THEN o.delivered_customer_at::DATE > o.estimated_delivery_date
       END                                           AS is_late,
       r.review_score
FROM core.orders AS o
JOIN core.customer         AS c ON c.customer_id = o.customer_id
LEFT JOIN items_por_pedido  AS i ON i.order_id = o.order_id
LEFT JOIN pagos_por_pedido  AS p ON p.order_id = o.order_id
LEFT JOIN review_por_pedido AS r ON r.order_id = o.order_id;

-- índice único: permite REFRESH MATERIALIZED VIEW CONCURRENTLY
CREATE UNIQUE INDEX ux_fact_order ON mart.fact_order (order_id);
CREATE INDEX ix_fact_order_month    ON mart.fact_order (purchase_month) WHERE is_valid;
CREATE INDEX ix_fact_order_customer ON mart.fact_order (customer_unique_id);

-- ---------------------------------------------------------------------
-- mart.fact_item — grano: 1 fila por ítem vendido, con categoría y
-- vendedor resueltos. Base para análisis de producto y vendedor.
-- ---------------------------------------------------------------------
CREATE VIEW mart.fact_item AS
SELECT oi.order_id,
       oi.order_item_id,
       oi.product_id,
       COALESCE(cat.category_name_en, 'sin_categoria') AS category,
       oi.seller_id,
       s.state                AS seller_state,
       s.city                 AS seller_city,
       fo.customer_state,
       fo.purchase_month,
       fo.is_valid,
       fo.is_late,
       fo.review_score,
       oi.price,
       oi.freight_value
FROM core.order_item AS oi
JOIN mart.fact_order  AS fo  ON fo.order_id  = oi.order_id
JOIN core.product     AS pr  ON pr.product_id = oi.product_id
JOIN core.seller      AS s   ON s.seller_id   = oi.seller_id
LEFT JOIN core.category AS cat ON cat.category_name = pr.category_name;

ANALYZE mart.fact_order;
