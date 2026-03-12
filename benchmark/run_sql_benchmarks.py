#!/usr/bin/env python3
import argparse
import csv
import json
import logging
import os
import statistics
import sys
import time
from pathlib import Path

try:
    import duckdb
except ImportError:
    print("Missing dependency: duckdb. Install with: python -m pip install duckdb", file=sys.stderr)
    sys.exit(1)

TABLE_FILES = {
    "dim_sector": "dim_sector.csv",
    "dim_country": "dim_country.csv",
    "dim_currency": "dim_currency.csv",
    "dim_exchange": "dim_exchange.csv",
    "dim_industry": "dim_industry.csv",
    "dim_issuer": "dim_issuer.csv",
    "dim_stock": "dim_stock.csv",
    "dim_broker": "dim_broker.csv",
    "dim_trader": "dim_trader.csv",
    "dim_account": "dim_account.csv",
    "fact_equity_trade": "fact_equity_trade.csv",
}


def split_sql_statements(sql_text: str):
    statements = []
    current = []
    in_single = False
    in_double = False
    for ch in sql_text:
        if ch == "'" and not in_double:
            in_single = not in_single
        elif ch == '"' and not in_single:
            in_double = not in_double
        if ch == ';' and not in_single and not in_double:
            stmt = ''.join(current).strip()
            if stmt:
                statements.append(stmt)
            current = []
        else:
            current.append(ch)
    tail = ''.join(current).strip()
    if tail:
        statements.append(tail)
    return [s for s in statements if s and not s.startswith('--')]


def read_query_blocks(path: Path):
    blocks = []
    current_comment = None
    current_lines = []
    for raw in path.read_text(encoding='utf-8').splitlines():
        line = raw.rstrip()
        if line.startswith('-- Q'):
            if current_lines:
                blocks.extend(_flush_block(current_comment, current_lines))
                current_lines = []
            current_comment = line[3:].strip()
        else:
            current_lines.append(line)
    if current_lines:
        blocks.extend(_flush_block(current_comment, current_lines))
    return blocks


def _flush_block(comment, lines):
    sql = '\n'.join(lines).strip()
    stmts = split_sql_statements(sql)
    out = []
    for idx, stmt in enumerate(stmts, start=1):
        label = comment or f"statement_{idx}"
        if len(stmts) > 1:
            label = f"{label} [{idx}]"
        out.append((label, stmt))
    return out


def create_views_from_csv(con, data_dir: Path):
    for table, filename in TABLE_FILES.items():
        csv_path = data_dir / filename
        if not csv_path.exists():
            raise FileNotFoundError(f"Expected file not found: {csv_path}")
        con.execute(f"CREATE OR REPLACE VIEW {table} AS SELECT * FROM read_csv_auto('{csv_path.as_posix()}', HEADER=TRUE)")


def fetch_single_value(con, sql: str):
    try:
        return con.execute(sql).fetchone()[0]
    except Exception:
        return None


def explain_query(con, sql: str):
    try:
        rows = con.execute(f"EXPLAIN {sql}").fetchall()
        return '\n'.join(str(r[0]) for r in rows)
    except Exception as exc:
        return f"EXPLAIN failed: {exc}"


def explain_analyze_query(con, sql: str):
    try:
        rows = con.execute(f"EXPLAIN ANALYZE {sql}").fetchall()
        return '\n'.join(str(r[0]) for r in rows)
    except Exception as exc:
        return f"EXPLAIN ANALYZE failed: {exc}"


def run_query(con, sql: str, repeats: int):
    timings_ms = []
    result_preview = None
    rowcount = None
    for i in range(repeats):
        t0 = time.perf_counter()
        rel = con.execute(sql)
        rows = rel.fetchmany(5)
        elapsed_ms = (time.perf_counter() - t0) * 1000.0
        timings_ms.append(elapsed_ms)
        if result_preview is None:
            result_preview = rows
            try:
                rowcount = fetch_single_value(con, f"SELECT COUNT(*) FROM ({sql}) q")
            except Exception:
                rowcount = None
    return {
        "timings_ms": timings_ms,
        "min_ms": min(timings_ms),
        "max_ms": max(timings_ms),
        "avg_ms": statistics.mean(timings_ms),
        "median_ms": statistics.median(timings_ms),
        "stdev_ms": statistics.pstdev(timings_ms) if len(timings_ms) > 1 else 0.0,
        "preview": result_preview,
        "rowcount": rowcount,
    }


def setup_logging(log_file: Path):
    log_file.parent.mkdir(parents=True, exist_ok=True)
    logger = logging.getLogger("sql_benchmark")
    logger.setLevel(logging.INFO)
    logger.handlers.clear()
    formatter = logging.Formatter("%(asctime)s | %(levelname)s | %(message)s")

    sh = logging.StreamHandler(sys.stdout)
    sh.setFormatter(formatter)
    logger.addHandler(sh)

    fh = logging.FileHandler(log_file, encoding='utf-8')
    fh.setFormatter(formatter)
    logger.addHandler(fh)
    return logger


def main():
    parser = argparse.ArgumentParser(description="Run verbose SQL benchmarks against synthetic equity trade CSV data using DuckDB.")
    parser.add_argument("--data-dir", required=True, help="Directory containing the CSV files.")
    parser.add_argument("--sql-file", default="benchmark_queries.sql", help="SQL file containing benchmark queries.")
    parser.add_argument("--db-file", default=":memory:", help="DuckDB database file, or :memory:.")
    parser.add_argument("--repeats", type=int, default=3, help="How many times to run each query.")
    parser.add_argument("--log-file", default="sql_benchmark_verbose.log", help="Verbose log output file.")
    parser.add_argument("--json-summary", default="sql_benchmark_summary.json", help="JSON summary output file.")
    args = parser.parse_args()

    data_dir = Path(args.data_dir).resolve()
    sql_file = Path(args.sql_file).resolve() if Path(args.sql_file).exists() else (Path.cwd() / args.sql_file).resolve()
    log_file = Path(args.log_file).resolve()
    json_summary = Path(args.json_summary).resolve()

    logger = setup_logging(log_file)
    logger.info("Starting SQL benchmark run")
    logger.info("Data directory: %s", data_dir)
    logger.info("SQL file: %s", sql_file)
    logger.info("DuckDB database: %s", args.db_file)
    logger.info("Repeats per query: %s", args.repeats)

    con = duckdb.connect(args.db_file)
    con.execute("PRAGMA threads=4")
    con.execute("PRAGMA enable_profiling='no_output'")

    create_views_from_csv(con, data_dir)
    logger.info("Loaded CSV-backed views: %s", ', '.join(TABLE_FILES.keys()))

    table_counts = {}
    for table in TABLE_FILES:
        cnt = fetch_single_value(con, f"SELECT COUNT(*) FROM {table}")
        table_counts[table] = cnt
        logger.info("Table %-18s row_count=%s", table, cnt)

    blocks = read_query_blocks(sql_file)
    logger.info("Discovered %d SQL benchmark queries", len(blocks))

    summary = {
        "data_dir": str(data_dir),
        "sql_file": str(sql_file),
        "db_file": args.db_file,
        "repeats": args.repeats,
        "table_counts": table_counts,
        "queries": [],
    }

    all_avg = []
    grand_start = time.perf_counter()

    for idx, (label, sql) in enumerate(blocks, start=1):
        logger.info("=" * 100)
        logger.info("Query %02d | %s", idx, label)
        logger.info("SQL:\n%s", sql)

        plan = explain_query(con, sql)
        logger.info("EXPLAIN plan:\n%s", plan)

        metrics = run_query(con, sql, args.repeats)
        all_avg.append(metrics["avg_ms"])

        analyze = explain_analyze_query(con, sql)
        logger.info("EXPLAIN ANALYZE:\n%s", analyze)
        logger.info(
            "Timing metrics | min_ms=%.3f | max_ms=%.3f | avg_ms=%.3f | median_ms=%.3f | stdev_ms=%.3f",
            metrics["min_ms"], metrics["max_ms"], metrics["avg_ms"], metrics["median_ms"], metrics["stdev_ms"]
        )
        logger.info("Output metrics | preview_rows=%s | estimated_rowcount=%s", len(metrics["preview"] or []), metrics["rowcount"])
        if metrics["preview"]:
            logger.info("Result preview: %s", metrics["preview"])

        summary["queries"].append({
            "query_number": idx,
            "label": label,
            "sql": sql,
            "min_ms": metrics["min_ms"],
            "max_ms": metrics["max_ms"],
            "avg_ms": metrics["avg_ms"],
            "median_ms": metrics["median_ms"],
            "stdev_ms": metrics["stdev_ms"],
            "rowcount": metrics["rowcount"],
            "preview": [list(r) if isinstance(r, tuple) else r for r in (metrics["preview"] or [])],
        })

    total_ms = (time.perf_counter() - grand_start) * 1000.0
    summary["run_total_ms"] = total_ms
    summary["avg_of_avg_ms"] = statistics.mean(all_avg) if all_avg else 0.0
    summary["slowest_query_avg_ms"] = max(all_avg) if all_avg else 0.0
    summary["fastest_query_avg_ms"] = min(all_avg) if all_avg else 0.0

    json_summary.write_text(json.dumps(summary, indent=2, default=str), encoding='utf-8')
    logger.info("=" * 100)
    logger.info("Completed benchmark run | query_count=%d | run_total_ms=%.3f | avg_of_avg_ms=%.3f", len(blocks), total_ms, summary["avg_of_avg_ms"])
    logger.info("JSON summary written to %s", json_summary)
    logger.info("Verbose log written to %s", log_file)


if __name__ == "__main__":
    main()
