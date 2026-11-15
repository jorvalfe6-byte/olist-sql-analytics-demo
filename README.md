# Olist: análisis de e-commerce con PostgreSQL

Tomé el dataset público de Olist, un marketplace brasileño con 99.441 pedidos reales entre 2016 y 2018, lo cargué en PostgreSQL y le hice las preguntas que le haría el dueño de una tienda online: cuánto vende, quién vuelve a comprar, cuánto le cuestan los retrasos y de dónde sale la plata.

**Dashboard en vivo:** https://jorvalfe6-byte.github.io/olist-sql-analytics-demo/

El dashboard es una sola página estática. Lee un JSON de 24 KB con resultados ya agregados y dibuja los gráficos sin librerías externas.

## Lo que encontré

- **El negocio creció rápido y después se estabilizó.** El GMV mensual pasó de R$ 120 mil en enero de 2017 a R$ 1,0 millón en noviembre del mismo año (Black Friday). En 2018 se movió entre R$ 838 mil y R$ 994 mil por mes.
- **Casi nadie vuelve a comprar.** Solo el 3,0 % de los 94.990 clientes hizo más de un pedido, y en ninguna cohorte vuelve más del 0,71 % en un mismo mes. Para mí este es el problema principal del negocio, por encima de cualquier otro número de esta lista.
- **Los retrasos son pocos, pero salen caros.** El 6,8 % de las entregas llegó después de la fecha prometida. Cuando el pedido llega a tiempo, el 10,1 % de las reseñas es negativa (1 o 2 estrellas). Con 4 a 7 días de retraso sube al 67,7 %, y con 8 días o más, al 79,3 %.
- **El nordeste es donde más se falla.** Alagoas tiene 21,4 % de entregas tarde y Maranhão 17,4 %. São Paulo, que concentra 40.494 de las 96.470 entregas, está en 4,5 %.
- **Las ventas están concentradas.** 18 de 74 categorías hacen el 80 % del GMV, y el 10 % de los vendedores vende el 67,5 %.
- **La tarjeta de crédito mueve el 78,5 % del dinero.** Y entre más cuotas, más alto el ticket: R$ 96 promedio de contado contra R$ 332 en 7 cuotas o más.

## Cómo está armado

```
CSV ──\copy──▶ staging ──transform──▶ core ──▶ mart ──▶ dashboard.json ──▶ docs/index.html
(texto crudo)    (todo TEXT)    (tipado, PK/FK/CHECK)  (vistas)   (solo agregados)
                                      │
                                      └──▶ audit.load_log (filas leídas vs. cargadas)
```

| Capa | Qué hace |
|---|---|
| `staging` | Recibe los 8 CSV tal cual, todo como texto. Así la carga no se cae por un formato raro y los errores aparecen después, en un lugar donde se pueden revisar. |
| `core` | Modelo tipado con claves primarias, foráneas, `CHECK` y `NUMERIC` para el dinero. La transformación corre en una sola transacción y es idempotente (se puede repetir sin duplicar nada). |
| `audit` | Una fila por tabla en cada carga: cuántas filas entraron y cuántas quedaron. |
| `mart` | `fact_order` (vista materializada, una fila por pedido) y `fact_item` (una fila por ítem). Toda la analítica sale de aquí. |

### Modelo de datos

```mermaid
erDiagram
    customer ||--|| orders : "hace"
    orders ||--|{ order_item : "contiene"
    orders ||--|{ order_payment : "se paga con"
    orders ||--o{ order_review : "recibe"
    product ||--o{ order_item : "se vende en"
    seller ||--o{ order_item : "despacha"
    category |o--o{ product : "agrupa"

    customer { char customer_id PK
               char customer_unique_id
               char zip_code_prefix
               char state }
    orders { char order_id PK
             char customer_id FK
             text order_status
             timestamp purchased_at
             timestamp delivered_customer_at
             date estimated_delivery_date }
    order_item { char order_id PK
                 smallint order_item_id PK
                 char product_id FK
                 char seller_id FK
                 numeric price
                 numeric freight_value }
    order_payment { char order_id PK
                    smallint payment_sequential PK
                    text payment_type
                    smallint installments
                    numeric payment_value }
    order_review { char review_id PK
                   char order_id PK
                   smallint score }
    product { char product_id PK
              text category_name FK }
    seller { char seller_id PK
             char state }
    category { text category_name PK
               text category_name_en }
```

## Las consultas

Cada archivo de `sql/analysis/` se puede correr por separado, y en el encabezado dice qué representa cada fila del resultado.

| Archivo | Qué responde | Técnicas |
|---|---|---|
| `00_calidad_datos.sql` | ¿La carga quedó completa? | 9 controles contra los totales del dataset original |
| `01_kpis_generales.sql` | Resumen ejecutivo | `PERCENTILE_CONT`, `FILTER`, ventana para contar recompras |
| `02_ventas_mensuales.sql` | Tendencia mensual | Calendario con `generate_series`, `LAG` para MoM y YoY, acumulado anual, media móvil |
| `03_cohortes_retencion.sql` | ¿Vuelven los clientes? | Cohortes por mes de primera compra |
| `04_rfm_segmentacion.sql` | ¿Qué clientes valen más? | RFM con `NTILE` y reglas fijas donde los quintiles no sirven |
| `05_logistica_entregas.sql` | ¿Dónde fallan las entregas y qué cuesta? | `GROUPING SETS` para el total nacional, percentil 90 |
| `06_categorias_pareto.sql` | ¿Qué categorías importan? | Curva ABC con suma acumulada |
| `07_vendedores_ranking.sql` | Mejores vendedores por estado | Top-N por grupo con `ROW_NUMBER`, `PERCENT_RANK` |
| `08_pagos.sql` | Medios de pago y cuotas | Pivot con `FILTER` |

## Decisiones y problemas que encontré en los datos

- **El cliente real es `customer_unique_id`, no `customer_id`.** Olist le da un `customer_id` nuevo a cada pedido. Si se cuenta por esa columna, parece que nadie repite nunca. Por eso todo lo de clientes usa `customer_unique_id` (96.096 personas).
- **`review_id` no es único.** Hay 814 repetidos, porque la misma encuesta quedó asociada a varios pedidos. La clave primaria es `(review_id, order_id)`, y cuando un pedido tiene más de una reseña se toma la más reciente.
- **Ítems y pagos se agregan antes del JOIN.** Si se unen crudos con el pedido, uno con 3 ítems y 2 pagos queda en 6 filas y el monto sale duplicado. En `fact_order` cada lado se resume en su propia CTE.
- **Dos categorías no tenían traducción** (`pc_gamer` y `portateis_cozinha_e_preparadores_de_alimentos`). Las agregué en la transformación para no romper la clave foránea, y quedan registradas aparte en la auditoría.
- **Las fechas no traen zona horaria.** Por eso uso `TIMESTAMP` y no `TIMESTAMPTZ`: prefiero dejarlo dicho a inventar un desfase.
- **Pedido válido** es todo pedido que no esté cancelado ni marcado como no disponible. Quedan 98.207.
- **Lo que no se cargó:** la tabla de geolocalización (coordenadas por código postal). Para los análisis por estado no hace falta, porque clientes y vendedores ya traen el estado y la ciudad.

## Cómo correrlo

Necesitas PostgreSQL 14 o más reciente y `psql`.

1. Descarga el dataset de [Kaggle](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce) y descomprime los CSV en `data/`.
2. Crea la base y carga todo:

```bash
createdb olist
export PGDATABASE=olist          # más PGHOST / PGUSER si hace falta
./scripts/load.sh                # esquema, carga, transformación, vistas y controles
./scripts/export_dashboard.sh    # regenera docs/data/dashboard.json
```

En mi máquina la carga completa tarda unos 8 segundos. Al final imprime los controles de calidad, y todos deben decir `OK`.

3. Para ver el dashboard en local:

```bash
python3 -m http.server --directory docs
```

## Estructura

```
sql/
  01_schema.sql            esquemas, tablas y restricciones
  02_load_staging.sql      \copy de los CSV
  03_transform.sql         staging → core, auditoría e índices
  04_marts.sql             fact_order y fact_item
  05_dashboard_views.sql   vistas que alimentan el dashboard
  analysis/                consultas de análisis, una por pregunta
scripts/
  load.sh                  carga completa de punta a punta
  export_dashboard.sh      exporta los agregados a JSON
docs/
  index.html               dashboard (GitHub Pages)
  data/dashboard.json      resultados agregados
data/                      CSV originales (no se suben al repo)
```

## Licencias

- **Datos:** [Brazilian E-Commerce Public Dataset by Olist](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce), licencia [CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/). Los CSV originales no están en el repositorio. Los agregados de `docs/data/` se publican bajo la misma licencia.
- **Código** (SQL, scripts y página): MIT, ver [LICENSE](LICENSE).

---

**Jorge Valencia**, automatizaciones y análisis de datos. Si tienes datos de tu negocio en hojas de cálculo o en un sistema que no te da reportes, este es el tipo de trabajo que hago.
