-- =====================================================================
-- 02_load_staging.sql — Carga cruda de los CSV a staging.
-- Se ejecuta con psql (usa \copy, del lado del cliente):
--
--   psql -v datadir="$(pwd)/data" -f sql/02_load_staging.sql
-- =====================================================================
\set ON_ERROR_STOP on

TRUNCATE staging.customers, staging.sellers, staging.category_translation,
         staging.products, staging.orders, staging.order_items,
         staging.order_payments, staging.order_reviews;

-- \copy no expande variables; por eso se cambia de directorio primero.
\cd :datadir

\copy staging.customers                  FROM 'olist_customers_dataset.csv' WITH (FORMAT csv, HEADER true)
\copy staging.sellers                    FROM 'olist_sellers_dataset.csv' WITH (FORMAT csv, HEADER true)
\copy staging.category_translation       FROM 'product_category_name_translation.csv' WITH (FORMAT csv, HEADER true)
\copy staging.products                   FROM 'olist_products_dataset.csv' WITH (FORMAT csv, HEADER true)
\copy staging.orders                     FROM 'olist_orders_dataset.csv' WITH (FORMAT csv, HEADER true)
\copy staging.order_items                FROM 'olist_order_items_dataset.csv' WITH (FORMAT csv, HEADER true)
\copy staging.order_payments             FROM 'olist_order_payments_dataset.csv' WITH (FORMAT csv, HEADER true)
\copy staging.order_reviews              FROM 'olist_order_reviews_dataset.csv' WITH (FORMAT csv, HEADER true)
