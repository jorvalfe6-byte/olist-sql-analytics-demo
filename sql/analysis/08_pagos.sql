-- =====================================================================
-- 08_pagos.sql — Medios de pago y uso de cuotas.
-- =====================================================================

-- (a) Mezcla de medios de pago. Grano: 1 fila por medio de pago.
--     Se mide sobre core.order_payment (un pedido puede tener varios pagos).
SELECT p.payment_type                                          AS medio,
       COUNT(DISTINCT p.order_id)                              AS pedidos,
       ROUND(SUM(p.payment_value), 2)                          AS monto,
       ROUND(100.0 * SUM(p.payment_value) / SUM(SUM(p.payment_value)) OVER (), 1) AS pct_monto,
       ROUND(AVG(p.payment_value), 2)                          AS monto_prom
FROM core.order_payment AS p
JOIN core.orders        AS o ON o.order_id = p.order_id
WHERE o.order_status NOT IN ('canceled','unavailable')
GROUP BY p.payment_type
ORDER BY monto DESC;

-- (b) Cuotas en tarjeta de crédito vs. ticket. Grano: 1 fila por tramo.
--     Pivot portable con FILTER: % de pedidos de cada tramo por rango de ticket.
SELECT CASE
           WHEN installments <= 1  THEN '1. Contado'
           WHEN installments <= 3  THEN '2. 2-3 cuotas'
           WHEN installments <= 6  THEN '3. 4-6 cuotas'
           ELSE                         '4. 7+ cuotas'
       END                                                       AS tramo_cuotas,
       COUNT(*)                                                  AS pagos,
       ROUND(AVG(payment_value), 2)                              AS ticket_prom,
       ROUND(100.0 * COUNT(*) FILTER (WHERE payment_value <  100) / COUNT(*), 1) AS pct_menos_100,
       ROUND(100.0 * COUNT(*) FILTER (WHERE payment_value >= 100
                                        AND payment_value <  300) / COUNT(*), 1) AS pct_100_300,
       ROUND(100.0 * COUNT(*) FILTER (WHERE payment_value >= 300) / COUNT(*), 1) AS pct_300_mas
FROM core.order_payment AS p
JOIN core.orders        AS o ON o.order_id = p.order_id
WHERE p.payment_type = 'credit_card'
  AND o.order_status NOT IN ('canceled','unavailable')
GROUP BY 1
ORDER BY 1;
