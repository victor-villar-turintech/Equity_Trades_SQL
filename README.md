# Equity Trade Synthetic Benchmark

Synthetic benchmark repository for testing schema simplification and downstream ETL/query validation.

## Repository structure

```text
Equity_Trades_SQL/
├── benchmark/
│   ├── README.md
│   ├── benchmark_queries.sql
│   └── run_sql_benchmarks.py
├── db/
│   ├── README.txt
│   ├── dim_account.csv
│   ├── dim_broker.csv
│   ├── dim_country.csv
│   ├── dim_currency.csv
│   ├── dim_exchange.csv
│   ├── dim_industry.csv
│   ├── dim_issuer.csv
│   ├── dim_sector.csv
│   ├── dim_stock.csv
│   ├── dim_trader.csv
│   ├── fact_equity_trade.csv
│   └── schema.sql
├── .gitignore
└── README.md
```

## Contents

- 100,000 synthetic equity trade records
- Dimension tables for stocks, issuers, industries, sectors, exchanges, countries, currencies, brokers, traders, and accounts
- Original schema SQL
- 30 deliberately non-optimised benchmark SQL queries
- Verbose Python benchmark runner for execution timing and query diagnostics

## Purpose

This repository is intended to test workflows where multiple stock-related dimensions are consolidated into a single dimension table, and downstream fact and mart logic is rewritten and validated.

## Database contents

The `db/` folder contains the original synthetic source data used for testing:

- `fact_equity_trade.csv` — synthetic fact table with 100,000 trade records
- `dim_stock.csv` — stock-level reference data
- `dim_issuer.csv` — issuer/company reference data
- `dim_industry.csv` — industry reference data
- `dim_sector.csv` — sector reference data
- `dim_exchange.csv` — exchange reference data
- `dim_country.csv` — country reference data
- `dim_currency.csv` — currency reference data
- `dim_broker.csv` — broker reference data
- `dim_trader.csv` — trader reference data
- `dim_account.csv` — account reference data
- `schema.sql` — original schema definition
- `README.txt` — notes on dataset generation and intended usage

The fact table intentionally includes several stock-related foreign keys so Artemis can identify overlapping descriptive dimensions and test consolidation into a single richer dimension.

## Benchmark contents

The `benchmark/` folder contains the local SQL performance test kit:

- `benchmark_queries.sql` — 30 intentionally non-optimised SQL queries
- `run_sql_benchmarks.py` — verbose benchmark runner
- `README.md` — benchmark-specific notes

The benchmark runner is designed to help compare the original schema against Artemis-transformed versions by logging execution details in a verbose and reproducible way.

## Benchmark goals

- Identify downstream dependencies on multiple dimensions
- Consolidate related dimensions into one dimension table
- Rewrite joins and foreign keys in downstream tables
- Compare before and after results for data equivalence
- Compare before and after ETL and query performance

## Run benchmarks

Install DuckDB first:

```bash
python -m pip install duckdb
```

Then run the benchmark runner from the repository root:

```bash
python benchmark/run_sql_benchmarks.py \
  --data-dir ./db \
  --sql-file ./benchmark/benchmark_queries.sql \
  --repeats 3 \
  --log-file sql_benchmark_verbose.log \
  --json-summary sql_benchmark_summary.json
```

## Suggested workflow

1. Run the benchmark suite against the original schema and source files in `db/`.
2. Use Artemis to identify related dimension tables and consolidate them.
3. Rewrite downstream SQL and table dependencies to use the new consolidated dimension.
4. Re-run the benchmark suite on the transformed version.
5. Compare row counts, output equivalence, query plans, and timing metrics before and after transformation.

## Notes

- This dataset is synthetic and intended for schema, SQL transformation, and ETL/query performance testing.
- It is not intended for market-accurate analytics or production trading analysis.
- The data was generated to be reproducible and suitable for local benchmarking.
