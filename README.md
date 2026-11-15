# Olist SQL Analytics Demo

Demo de análisis de bases de datos sobre un caso real de e-commerce: ~100k pedidos
del marketplace brasileño Olist, modelados en PostgreSQL y analizados con SQL.

## Qué voy a mostrar

- Modelo relacional (9 tablas) con claves e índices
- Consultas analíticas: cohortes, RFM, funciones de ventana, series de tiempo
- KPIs de negocio: ingresos, ticket promedio, retención, tiempos de entrega
- Dashboard público que corre en el navegador (DuckDB-WASM sobre parquet)

## Estructura

```
sql/        esquema y consultas
data/       datos locales (no se versionan)
docs/       diagrama ER y capturas
```

## Datos

Dataset público de Olist (Kaggle), licencia CC BY-NC-SA 4.0. Uso no comercial y con atribución.
Los datos originales no se incluyen en el repositorio.

## Estado

En construcción.

---
Jorge Valencia · Automatizaciones y análisis de datos
