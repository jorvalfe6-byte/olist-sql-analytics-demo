-- =====================================================================
-- 00_calidad_datos.sql — Controles de calidad después de cada carga.
-- Cada fila es un control: 'OK' o 'REVISAR' con el valor encontrado.
-- Los esperados corresponden al dataset público de Olist (Kaggle).
-- =====================================================================
WITH controles AS (
    SELECT 'pedidos cargados'                        AS control,
           (SELECT COUNT(*) FROM core.orders)        AS valor,
           99441                                     AS esperado
    UNION ALL
    SELECT 'ítems cargados',      (SELECT COUNT(*) FROM core.order_item),    112650
    UNION ALL
    SELECT 'pagos cargados',      (SELECT COUNT(*) FROM core.order_payment), 103886
    UNION ALL
    SELECT 'reviews cargadas',    (SELECT COUNT(*) FROM core.order_review),  99224
    UNION ALL
    SELECT 'clientes únicos',     (SELECT COUNT(DISTINCT customer_unique_id) FROM core.customer), 96096
    UNION ALL
    -- GMV en centavos para comparar enteros
    SELECT 'GMV total (centavos)', (SELECT (SUM(price) * 100)::BIGINT FROM core.order_item), 1359164370
    UNION ALL
    SELECT 'filas rechazadas en la carga',
           -- toda la última carga corre en una transacción: comparte now()
           (SELECT COALESCE(SUM(rows_rejected), 0)
            FROM audit.load_log
            WHERE loaded_at = (SELECT MAX(loaded_at) FROM audit.load_log)), 0
    UNION ALL
    -- integridad que la FK no cubre: pedido entregado sin fecha de entrega
    SELECT 'entregados sin fecha de entrega',
           (SELECT COUNT(*) FROM core.orders
            WHERE order_status = 'delivered' AND delivered_customer_at IS NULL), 8
    UNION ALL
    -- fechas imposibles: entrega antes de la compra
    SELECT 'entregas anteriores a la compra',
           (SELECT COUNT(*) FROM core.orders
            WHERE delivered_customer_at < purchased_at), 0
)
SELECT control,
       valor,
       esperado,
       CASE WHEN valor = esperado THEN 'OK' ELSE 'REVISAR' END AS estado
FROM controles;

-- Hallazgos conocidos del dataset (no son errores de carga):
--   * 775 pedidos sin ítems (la mayoría cancelados o no disponibles).
--   * 1 pedido sin registro de pago.
--   * 8 pedidos 'delivered' sin fecha de entrega al cliente.
--   * 551 pedidos con más de una review; 814 review_id compartidos.
--   * 610 productos sin categoría.
