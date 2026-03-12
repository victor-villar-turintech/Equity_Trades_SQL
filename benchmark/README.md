# SQL benchmark kit for synthetic equity trade data

This package gives you deliberately **non-optimised SQL** queries plus a **verbose local runner** so you can benchmark your original schema before Artemis rewrites or consolidates dimensions.

## Files

- `benchmark_queries.sql` — 30 intentionally non-optimised SQL queries
- `run_sql_benchmarks.py` — runs the SQL with verbose logging and timing metrics
- `README.md` — usage notes

## What gets logged

For each query, the runner logs:

- full SQL text
- `EXPLAIN` plan
- `EXPLAIN ANALYZE`
- min / max / average / median / stdev execution time in ms
- preview rows
- output row count when possible
- overall benchmark totals

## Recommended local setup

```bash
python -m pip install duckdb
```

## Example run

If your extracted dataset CSV files live in `/path/to/equity_data`:

```bash
python run_sql_benchmarks.py \
  --data-dir /path/to/equity_data \
  --sql-file benchmark_queries.sql \
  --repeats 3 \
  --log-file sql_benchmark_verbose.log \
  --json-summary sql_benchmark_summary.json
```

## Notes

- The runner creates DuckDB views directly from the CSVs, so you do not need to pre-load the tables into another database.
- These queries are intentionally not tuned. They include broad joins, correlated subqueries, repeated casts, repeated enrichment, self-joins, redundant DISTINCT/UNION patterns, and wide aggregations.
- This is ideal for comparing:
  - original schema performance
  - Artemis-transformed schema performance
  - before/after output equality checks

## Good comparison workflow

1. Run this package against the original schema/data.
2. Let Artemis consolidate the dimensions and rewrite downstream queries.
3. Run the Artemis-generated equivalent benchmark set.
4. Compare:
   - query timings
   - row counts
   - aggregate outputs
   - explain plans

