-- =====================================================================
-- 01_schema.sql — Modelo relacional Olist (PostgreSQL 14+)
--
-- Capas:
--   staging : copia 1:1 de los CSV, todo TEXT. Nunca falla por tipos.
--   core    : modelo tipado y normalizado con PK, FK y CHECK.
--   mart    : vistas analíticas (ver 04_marts.sql).
--   audit   : bitácora de cada carga.
--
-- Las fechas del dataset no traen zona horaria (hora local de Brasil),
-- por eso se usa TIMESTAMP y no TIMESTAMPTZ: inventar un offset sería
-- peor que declararlo.
-- =====================================================================

SET client_min_messages = warning;  -- silencia los avisos de DROP ... CASCADE

DROP SCHEMA IF EXISTS mart    CASCADE;
DROP SCHEMA IF EXISTS core    CASCADE;
DROP SCHEMA IF EXISTS staging CASCADE;
DROP SCHEMA IF EXISTS audit   CASCADE;

CREATE SCHEMA staging;
CREATE SCHEMA core;
CREATE SCHEMA mart;
CREATE SCHEMA audit;

-- ---------------------------------------------------------------------
-- audit
-- ---------------------------------------------------------------------
CREATE TABLE audit.load_log (
    load_id        BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    table_name     TEXT        NOT NULL,
    rows_staged    BIGINT      NOT NULL,
    rows_loaded    BIGINT      NOT NULL,
    rows_rejected  BIGINT      GENERATED ALWAYS AS (rows_staged - rows_loaded) STORED,
    loaded_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------
-- staging: mismo nombre de columnas que los CSV originales
-- (incluidos los typos "lenght" del dataset).
-- ---------------------------------------------------------------------
CREATE TABLE staging.customers (
    customer_id TEXT, customer_unique_id TEXT, customer_zip_code_prefix TEXT,
    customer_city TEXT, customer_state TEXT
);

CREATE TABLE staging.sellers (
    seller_id TEXT, seller_zip_code_prefix TEXT, seller_city TEXT, seller_state TEXT
);

CREATE TABLE staging.category_translation (
    product_category_name TEXT, product_category_name_english TEXT
);

CREATE TABLE staging.products (
    product_id TEXT, product_category_name TEXT, product_name_lenght TEXT,
    product_description_lenght TEXT, product_photos_qty TEXT, product_weight_g TEXT,
    product_length_cm TEXT, product_height_cm TEXT, product_width_cm TEXT
);

CREATE TABLE staging.orders (
    order_id TEXT, customer_id TEXT, order_status TEXT, order_purchase_timestamp TEXT,
    order_approved_at TEXT, order_delivered_carrier_date TEXT,
    order_delivered_customer_date TEXT, order_estimated_delivery_date TEXT
);

CREATE TABLE staging.order_items (
    order_id TEXT, order_item_id TEXT, product_id TEXT, seller_id TEXT,
    shipping_limit_date TEXT, price TEXT, freight_value TEXT
);

CREATE TABLE staging.order_payments (
    order_id TEXT, payment_sequential TEXT, payment_type TEXT,
    payment_installments TEXT, payment_value TEXT
);

CREATE TABLE staging.order_reviews (
    review_id TEXT, order_id TEXT, review_score TEXT, review_comment_title TEXT,
    review_comment_message TEXT, review_creation_date TEXT, review_answer_timestamp TEXT
);

-- ---------------------------------------------------------------------
-- core: dimensiones
-- ---------------------------------------------------------------------
CREATE TABLE core.category (
    category_name     TEXT PRIMARY KEY,
    category_name_en  TEXT NOT NULL
);

-- Grano: una fila por customer_id. Ojo: en Olist cada pedido genera un
-- customer_id nuevo; la persona real es customer_unique_id.
CREATE TABLE core.customer (
    customer_id         CHAR(32)  PRIMARY KEY,
    customer_unique_id  CHAR(32)  NOT NULL,
    zip_code_prefix     CHAR(5)   NOT NULL,
    city                TEXT      NOT NULL,
    state               CHAR(2)   NOT NULL
);

CREATE TABLE core.seller (
    seller_id        CHAR(32) PRIMARY KEY,
    zip_code_prefix  CHAR(5)  NOT NULL,
    city             TEXT     NOT NULL,
    state            CHAR(2)  NOT NULL
);

CREATE TABLE core.product (
    product_id           CHAR(32) PRIMARY KEY,
    category_name        TEXT REFERENCES core.category (category_name) ON DELETE RESTRICT,
    name_length          SMALLINT,
    description_length   INTEGER,
    photos_qty           SMALLINT,
    weight_g             INTEGER  CHECK (weight_g  >= 0),
    length_cm            SMALLINT CHECK (length_cm >= 0),
    height_cm            SMALLINT CHECK (height_cm >= 0),
    width_cm             SMALLINT CHECK (width_cm  >= 0)
);

-- ---------------------------------------------------------------------
-- core: hechos
-- ---------------------------------------------------------------------
CREATE TABLE core.orders (
    order_id                 CHAR(32)  PRIMARY KEY,
    customer_id              CHAR(32)  NOT NULL UNIQUE
                                       REFERENCES core.customer (customer_id) ON DELETE RESTRICT,
    order_status             TEXT      NOT NULL CHECK (order_status IN
                               ('created','approved','invoiced','processing',
                                'shipped','delivered','canceled','unavailable')),
    purchased_at             TIMESTAMP NOT NULL,
    approved_at              TIMESTAMP,
    delivered_carrier_at     TIMESTAMP,
    delivered_customer_at    TIMESTAMP,
    estimated_delivery_date  DATE      NOT NULL
);

-- Grano: una fila por unidad vendida dentro del pedido.
CREATE TABLE core.order_item (
    order_id          CHAR(32)      NOT NULL REFERENCES core.orders  (order_id)   ON DELETE CASCADE,
    order_item_id     SMALLINT      NOT NULL CHECK (order_item_id >= 1),
    product_id        CHAR(32)      NOT NULL REFERENCES core.product (product_id) ON DELETE RESTRICT,
    seller_id         CHAR(32)      NOT NULL REFERENCES core.seller  (seller_id)  ON DELETE RESTRICT,
    shipping_limit_at TIMESTAMP     NOT NULL,
    price             NUMERIC(10,2) NOT NULL CHECK (price >= 0),
    freight_value     NUMERIC(10,2) NOT NULL CHECK (freight_value >= 0),
    PRIMARY KEY (order_id, order_item_id)
);

CREATE TABLE core.order_payment (
    order_id            CHAR(32)      NOT NULL REFERENCES core.orders (order_id) ON DELETE CASCADE,
    payment_sequential  SMALLINT      NOT NULL CHECK (payment_sequential >= 1),
    payment_type        TEXT          NOT NULL CHECK (payment_type IN
                          ('credit_card','boleto','voucher','debit_card','not_defined')),
    installments        SMALLINT      NOT NULL CHECK (installments >= 0),
    payment_value       NUMERIC(10,2) NOT NULL CHECK (payment_value >= 0),
    PRIMARY KEY (order_id, payment_sequential)
);

-- review_id NO es único en el dataset (814 repetidos: la misma encuesta
-- se asoció a varios pedidos). La clave real es (review_id, order_id).
CREATE TABLE core.order_review (
    review_id        CHAR(32)  NOT NULL,
    order_id         CHAR(32)  NOT NULL REFERENCES core.orders (order_id) ON DELETE CASCADE,
    score            SMALLINT  NOT NULL CHECK (score BETWEEN 1 AND 5),
    comment_title    TEXT,
    comment_message  TEXT,
    created_date     DATE      NOT NULL,
    answered_at      TIMESTAMP NOT NULL,
    PRIMARY KEY (review_id, order_id)
);
