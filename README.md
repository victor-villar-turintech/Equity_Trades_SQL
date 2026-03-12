# Equity Trade Synthetic Benchmark

Synthetic benchmark repository for testing schema simplification and downstream ETL/query validation.

## Contents

- 100,000 synthetic equity trade records
- Dimension tables for stocks, issuers, industries, sectors, exchanges, countries, currencies, brokers, traders, and accounts
- Original schema SQL
- 30 deliberately non-optimised benchmark SQL queries
- Verbose Python benchmark runner for execution timing and query diagnostics

## Purpose

This repository is intended to test workflows where multiple stock-related dimensions are consolidated into a single dimension table, and downstream fact/mart logic is rewritten and validated.

## Benchmark goals

- Identify downstream dependencies on multiple dimensions
- Consolidate related dimensions
- Rewrite joins and foreign keys
- Compare before/after results for data equivalence
- Compare before/after ETL and query performance

## Run benchmarks

```bash
python -m pip install duckdb

python scripts/run_sql_benchmarks.py \
  --data-dir ./data \
  --sql-file ./sql/benchmark_queries.sql \
  --repeats 3 \
  --log-file sql_benchmark_verbose.log \
  --json-summary sql_benchmark_summary.json
