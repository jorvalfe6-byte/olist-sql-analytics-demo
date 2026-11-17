-- =====================================================================
-- 06_powerbi_views.sql — Modelo en estrella para el informe de Power BI.
--
-- Sale de mart.fact_order y mart.fact_item, así que usa las mismas
-- definiciones de negocio (pedido válido, GMV, cliente, entrega a tiempo).
-- scripts/export_powerbi.sh guarda cada vista como CSV en powerbi/data/.
--
--   fact_pedido   grano: 1 fila por pedido
--   fact_item     grano: 1 fila por ítem vendido
--   dim_fecha     calendario continuo, 1 fila por día
--   dim_estado    27 estados de Brasil con su región
--   dim_categoria 1 fila por categoría (en inglés, como en el dataset)
-- =====================================================================
\set ON_ERROR_STOP on
SET client_min_messages = warning;

DROP SCHEMA IF EXISTS powerbi CASCADE;
CREATE SCHEMA powerbi;

CREATE VIEW powerbi.fact_pedido AS
SELECT order_id                                   AS pedido_id,
       customer_unique_id                         AS cliente_id,
       purchased_at::DATE                         AS fecha_compra,
       customer_state                             AS estado_cliente,
       order_status                               AS estado_pedido,
       is_valid::INT                              AS es_valido,
       items_qty                                  AS items,
       merchandise_value                          AS valor_mercancia,
       freight_value                              AS flete,
       paid_value                                 AS valor_pagado,
       COALESCE(main_payment_type, 'sin_pago')    AS medio_pago,
       max_installments                           AS cuotas,
       CASE WHEN max_installments IS NULL THEN 'Sin pago'
            WHEN max_installments <= 1 THEN '1. Contado'
            WHEN max_installments <= 3 THEN '2. 2-3 cuotas'
            WHEN max_installments <= 6 THEN '3. 4-6 cuotas'
            ELSE '4. 7 o más cuotas' END          AS tramo_cuotas,
       delivery_days                              AS dias_entrega,
       promised_days                              AS dias_prometidos,
       (delivered_customer_at IS NOT NULL)::INT   AS entregado,
       is_late::INT                               AS tarde,
       delivered_customer_at::DATE - estimated_delivery_date AS dias_atraso,
       CASE
           WHEN delivered_customer_at IS NULL THEN NULL
           WHEN delivered_customer_at::DATE - estimated_delivery_date <= -10 THEN '1. 10+ días antes'
           WHEN delivered_customer_at::DATE - estimated_delivery_date <= 0   THEN '2. A tiempo'
           WHEN delivered_customer_at::DATE - estimated_delivery_date <= 3   THEN '3. 1-3 días tarde'
           WHEN delivered_customer_at::DATE - estimated_delivery_date <= 7   THEN '4. 4-7 días tarde'
           ELSE '5. 8+ días tarde'
       END                                        AS tramo_atraso,
       review_score                               AS resena
FROM mart.fact_order;

CREATE VIEW powerbi.fact_item AS
SELECT fi.order_id                                AS pedido_id,
       fi.order_item_id                           AS item_n,
       fo.purchased_at::DATE                      AS fecha_compra,
       fi.category                                AS categoria,
       fi.seller_id                               AS vendedor_id,
       fi.seller_state                            AS estado_vendedor,
       fi.customer_state                          AS estado_cliente,
       fi.is_valid::INT                           AS es_valido,
       fi.price                                   AS precio,
       fi.freight_value                           AS flete
FROM mart.fact_item AS fi
JOIN mart.fact_order AS fo ON fo.order_id = fi.order_id;

CREATE VIEW powerbi.dim_fecha AS
SELECT d::DATE                                    AS fecha,
       EXTRACT(YEAR FROM d)::INT                  AS anio,
       EXTRACT(QUARTER FROM d)::INT               AS trimestre,
       EXTRACT(MONTH FROM d)::INT                 AS mes_num,
       TO_CHAR(d, 'YYYY-MM')                      AS anio_mes,
       (ARRAY['ene','feb','mar','abr','may','jun','jul','ago','sep','oct','nov','dic'])
           [EXTRACT(MONTH FROM d)::INT]           AS mes,
       EXTRACT(ISODOW FROM d)::INT                AS dia_semana_num,
       (ARRAY['lun','mar','mié','jue','vie','sáb','dom'])
           [EXTRACT(ISODOW FROM d)::INT]          AS dia_semana,
       -- meses con operación completa (como en el análisis de ventas mensuales):
       -- 2016 tiene pocos pedidos de prueba y septiembre de 2018 viene cortado
       (d >= DATE '2017-01-01' AND d < DATE '2018-09-01')::INT AS mes_completo
FROM GENERATE_SERIES(
         (SELECT DATE_TRUNC('year', MIN(purchased_at)) FROM mart.fact_order),
         (SELECT DATE_TRUNC('year', MAX(purchased_at)) + INTERVAL '1 year - 1 day' FROM mart.fact_order),
         INTERVAL '1 day') AS d;

CREATE VIEW powerbi.dim_estado AS
SELECT e.estado, e.nombre, e.region
FROM (VALUES
    ('AC','Acre','Norte'), ('AL','Alagoas','Nordeste'), ('AM','Amazonas','Norte'),
    ('AP','Amapá','Norte'), ('BA','Bahia','Nordeste'), ('CE','Ceará','Nordeste'),
    ('DF','Distrito Federal','Centro-Oeste'), ('ES','Espírito Santo','Sudeste'),
    ('GO','Goiás','Centro-Oeste'), ('MA','Maranhão','Nordeste'), ('MG','Minas Gerais','Sudeste'),
    ('MS','Mato Grosso do Sul','Centro-Oeste'), ('MT','Mato Grosso','Centro-Oeste'),
    ('PA','Pará','Norte'), ('PB','Paraíba','Nordeste'), ('PE','Pernambuco','Nordeste'),
    ('PI','Piauí','Nordeste'), ('PR','Paraná','Sur'), ('RJ','Rio de Janeiro','Sudeste'),
    ('RN','Rio Grande do Norte','Nordeste'), ('RO','Rondônia','Norte'), ('RR','Roraima','Norte'),
    ('RS','Rio Grande do Sul','Sur'), ('SC','Santa Catarina','Sur'), ('SE','Sergipe','Nordeste'),
    ('SP','São Paulo','Sudeste'), ('TO','Tocantins','Norte')
) AS e(estado, nombre, region);

CREATE VIEW powerbi.dim_categoria AS
SELECT DISTINCT category AS categoria
FROM mart.fact_item;

-- Control: ningún estado ni categoría de los hechos queda sin dimensión.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM powerbi.fact_pedido f
               LEFT JOIN powerbi.dim_estado e ON e.estado = f.estado_cliente
               WHERE e.estado IS NULL) THEN
        RAISE EXCEPTION 'powerbi: hay estados de cliente sin fila en dim_estado';
    END IF;
END $$;
