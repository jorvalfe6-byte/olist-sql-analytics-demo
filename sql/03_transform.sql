-- =====================================================================
-- 03_transform.sql — staging → core, en una sola transacción.
-- Idempotente: vacía core y lo vuelve a poblar. Cada tabla deja su
-- registro en audit.load_log (filas leídas vs. cargadas).
-- =====================================================================
\set ON_ERROR_STOP on

BEGIN;

TRUNCATE core.order_review, core.order_payment, core.order_item, core.orders,
         core.product, core.category, core.seller, core.customer;

-- ---------------------------------------------------------------------
-- category
-- Dos categorías aparecen en products pero no en la tabla de traducción;
-- se completan aquí para no romper la FK ni perder ventas.
-- ---------------------------------------------------------------------
INSERT INTO core.category (category_name, category_name_en)
SELECT TRIM(product_category_name), TRIM(product_category_name_english)
FROM staging.category_translation
UNION ALL
SELECT v.category_name, v.category_name_en
FROM (VALUES
        ('pc_gamer',                                      'pc_gamer'),
        ('portateis_cozinha_e_preparadores_de_alimentos', 'portable_kitchen_food_preparers')
     ) AS v (category_name, category_name_en)
WHERE NOT EXISTS (
    SELECT 1 FROM staging.category_translation AS t
    WHERE TRIM(t.product_category_name) = v.category_name
);

INSERT INTO audit.load_log (table_name, rows_staged, rows_loaded)
SELECT 'core.category',
       (SELECT COUNT(*) FROM staging.category_translation),
       (SELECT COUNT(*) FROM core.category AS c
        WHERE EXISTS (SELECT 1 FROM staging.category_translation AS t
                      WHERE TRIM(t.product_category_name) = c.category_name));
-- las 2 completadas a mano quedan registradas aparte
INSERT INTO audit.load_log (table_name, rows_staged, rows_loaded)
SELECT 'core.category (completadas)',
       COUNT(*), COUNT(*)
FROM core.category AS c
WHERE NOT EXISTS (SELECT 1 FROM staging.category_translation AS t
                  WHERE TRIM(t.product_category_name) = c.category_name);

-- ---------------------------------------------------------------------
-- customer / seller
-- ---------------------------------------------------------------------
INSERT INTO core.customer (customer_id, customer_unique_id, zip_code_prefix, city, state)
SELECT customer_id,
       customer_unique_id,
       LPAD(customer_zip_code_prefix, 5, '0'),
       customer_city,
       UPPER(customer_state)
FROM staging.customers;

INSERT INTO audit.load_log (table_name, rows_staged, rows_loaded)
SELECT 'core.customer', (SELECT COUNT(*) FROM staging.customers), (SELECT COUNT(*) FROM core.customer);

INSERT INTO core.seller (seller_id, zip_code_prefix, city, state)
SELECT seller_id,
       LPAD(seller_zip_code_prefix, 5, '0'),
       seller_city,
       UPPER(seller_state)
FROM staging.sellers;

INSERT INTO audit.load_log (table_name, rows_staged, rows_loaded)
SELECT 'core.seller', (SELECT COUNT(*) FROM staging.sellers), (SELECT COUNT(*) FROM core.seller);

-- ---------------------------------------------------------------------
-- product (corrige los nombres "lenght" del dataset original)
-- ---------------------------------------------------------------------
INSERT INTO core.product (product_id, category_name, name_length, description_length,
                          photos_qty, weight_g, length_cm, height_cm, width_cm)
SELECT product_id,
       NULLIF(TRIM(product_category_name), ''),
       product_name_lenght::NUMERIC::SMALLINT,
       product_description_lenght::NUMERIC::INTEGER,
       product_photos_qty::NUMERIC::SMALLINT,
       product_weight_g::NUMERIC::INTEGER,
       product_length_cm::NUMERIC::SMALLINT,
       product_height_cm::NUMERIC::SMALLINT,
       product_width_cm::NUMERIC::SMALLINT
FROM staging.products;

INSERT INTO audit.load_log (table_name, rows_staged, rows_loaded)
SELECT 'core.product', (SELECT COUNT(*) FROM staging.products), (SELECT COUNT(*) FROM core.product);

-- ---------------------------------------------------------------------
-- orders
-- ---------------------------------------------------------------------
INSERT INTO core.orders (order_id, customer_id, order_status, purchased_at, approved_at,
                         delivered_carrier_at, delivered_customer_at, estimated_delivery_date)
SELECT order_id,
       customer_id,
       order_status,
       order_purchase_timestamp::TIMESTAMP,
       order_approved_at::TIMESTAMP,
       order_delivered_carrier_date::TIMESTAMP,
       order_delivered_customer_date::TIMESTAMP,
       order_estimated_delivery_date::TIMESTAMP::DATE
FROM staging.orders;

INSERT INTO audit.load_log (table_name, rows_staged, rows_loaded)
SELECT 'core.orders', (SELECT COUNT(*) FROM staging.orders), (SELECT COUNT(*) FROM core.orders);

-- ---------------------------------------------------------------------
-- order_item / order_payment / order_review
-- ---------------------------------------------------------------------
INSERT INTO core.order_item (order_id, order_item_id, product_id, seller_id,
                             shipping_limit_at, price, freight_value)
SELECT order_id,
       order_item_id::SMALLINT,
       product_id,
       seller_id,
       shipping_limit_date::TIMESTAMP,
       price::NUMERIC(10,2),
       freight_value::NUMERIC(10,2)
FROM staging.order_items;

INSERT INTO audit.load_log (table_name, rows_staged, rows_loaded)
SELECT 'core.order_item', (SELECT COUNT(*) FROM staging.order_items), (SELECT COUNT(*) FROM core.order_item);

INSERT INTO core.order_payment (order_id, payment_sequential, payment_type, installments, payment_value)
SELECT order_id,
       payment_sequential::SMALLINT,
       payment_type,
       payment_installments::SMALLINT,
       payment_value::NUMERIC(10,2)
FROM staging.order_payments;

INSERT INTO audit.load_log (table_name, rows_staged, rows_loaded)
SELECT 'core.order_payment', (SELECT COUNT(*) FROM staging.order_payments), (SELECT COUNT(*) FROM core.order_payment);

INSERT INTO core.order_review (review_id, order_id, score, comment_title, comment_message,
                               created_date, answered_at)
SELECT review_id,
       order_id,
       review_score::SMALLINT,
       NULLIF(TRIM(review_comment_title), ''),
       NULLIF(TRIM(review_comment_message), ''),
       review_creation_date::TIMESTAMP::DATE,
       review_answer_timestamp::TIMESTAMP
FROM staging.order_reviews;

INSERT INTO audit.load_log (table_name, rows_staged, rows_loaded)
SELECT 'core.order_review', (SELECT COUNT(*) FROM staging.order_reviews), (SELECT COUNT(*) FROM core.order_review);

COMMIT;

-- ---------------------------------------------------------------------
-- Índices: se crean después de la carga (más rápido que mantenerlos
-- fila a fila). Cubren las FK y los filtros por fecha de los análisis.
-- ---------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS ix_customer_unique      ON core.customer   (customer_unique_id);
CREATE INDEX IF NOT EXISTS ix_customer_state       ON core.customer   (state);
CREATE INDEX IF NOT EXISTS ix_orders_purchased_at  ON core.orders     (purchased_at) INCLUDE (order_status);
CREATE INDEX IF NOT EXISTS ix_orders_status        ON core.orders     (order_status);
CREATE INDEX IF NOT EXISTS ix_item_product         ON core.order_item (product_id);
CREATE INDEX IF NOT EXISTS ix_item_seller          ON core.order_item (seller_id);
CREATE INDEX IF NOT EXISTS ix_product_category     ON core.product    (category_name);
CREATE INDEX IF NOT EXISTS ix_review_order         ON core.order_review (order_id);

ANALYZE;
