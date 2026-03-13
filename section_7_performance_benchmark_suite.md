# Section 7: Performance Benchmark Suite

## Executive Summary

This section defines a rigorous, reproducible performance testing protocol to prove that the consolidated `dim_security` dimension improves query execution performance compared to the current 6-dimension schema. The methodology ensures fair, statistically valid comparisons using the existing `run_sql_benchmarks.py` infrastructure and carefully selected representative queries.

**Key Deliverables:**

- **12 Representative Benchmark Queries** selected from the 30-query suite, covering simple to complex join patterns
- **Comprehensive Performance Metrics** including execution time, row scans, join counts, and statistical measures
- **Before/After Schema Setup** with complete DDL and data loading instructions for fair comparison
- **Rigorous Testing Protocol** with multiple runs, cache control, and environment standardization
- **Statistical Analysis Framework** using median, percentiles, standard deviation, and improvement percentages
- **Results Reporting Template** with clear visualization of performance gains

**Expected Performance Improvements:**

- **5-10% improvement** on simple queries (1-2 security dimension joins eliminated)
- **15-30% improvement** on moderate queries (3-4 security dimension joins eliminated)
- **30-50% improvement** on complex queries (5+ security dimension joins eliminated)
- **40-60% improvement** on anti-pattern queries (Q09, Q22 with redundant joins)

**Testing Approach:** Dual-run methodology where identical queries are executed against both schemas under controlled conditions, with multiple iterations to account for variance and statistical rigor.

---

## 1. Benchmark Query Selection

### 1.1 Selection Criteria

Queries were selected to demonstrate:

1. **Join Complexity Diversity:** Simple (2-3 tables) to complex (7+ tables)
2. **Dimension Access Patterns:** Direct fact joins, chained dimension joins, redundant joins
3. **Query Operation Diversity:** Filters, aggregations, DISTINCT, CTEs, window functions, subqueries
4. **Anti-Pattern Coverage:** Queries with redundant joins that consolidation eliminates
5. **Real-World Relevance:** Common analytical patterns in equity trade analysis

### 1.2 Selected Queries (12 Queries)

| Query ID | Name/Description | Join Count (Before) | Join Count (After) | Complexity | Expected Improvement | Selection Rationale |
|----------|------------------|---------------------|--------------------|-----------|--------------------|---------------------|
| **Q01** | Wide join with all dimensions | 9 tables | 4 tables | Complex | 25-35% | Baseline heavy query - joins ALL security dimensions |
| **Q03** | LIKE pattern on ticker | 2 tables | 2 tables | Simple | 5-10% | Simple filter - minimal join reduction but index benefit |
| **Q04** | DISTINCT over wide join | 6 tables | 2 tables | Complex | 30-40% | DISTINCT with 4 security joins eliminated |
| **Q07** | ORDER BY computed expression | 2 tables | 2 tables | Simple | 5-10% | Medium complexity - ORDER BY with computation |
| **Q08** | Nested IN subquery | 4 tables | 2 tables | Complex | 20-30% | Complex filtering with subquery join reduction |
| **Q09** | **REDUNDANT JOINS** (anti-pattern) | 6 tables | 2 tables | Complex | **40-50%** | Prime consolidation candidate - redundant industry/sector joins |
| **Q11** | CASE-heavy aggregation | 2 tables | 2 tables | Medium | 5-10% | Aggregation pattern with CASE expressions |
| **Q12** | Filtered wide join | 6 tables | 3 tables | Medium | 20-30% | Late filter application with 3 security joins |
| **Q14** | Re-aggregation pattern | 4 tables | 2 tables | Medium | 20-30% | Nested aggregation with subquery join reduction |
| **Q17** | HAVING aggregation | 2 tables | 2 tables | Simple | 5-10% | Simple aggregation with HAVING clause |
| **Q19** | Wide CTE materialization | 9 tables | 4 tables | Complex | 25-35% | CTE pattern - joins ALL security dimensions |
| **Q22** | **TEXT JOIN REDUNDANCY** (anti-pattern) | 4 tables | 2 tables | Medium | **35-45%** | Anti-pattern - redundant exchange text joins |

**Query Distribution:**
- **Simple (3 queries):** Q03, Q07, Q11, Q17 - 2-3 table joins
- **Medium (4 queries):** Q08, Q12, Q14, Q22 - 4-6 table joins
- **Complex (3 queries):** Q01, Q04, Q19 - 7+ table joins
- **Anti-Patterns (2 queries):** Q09, Q22 - Redundant join patterns

**Join Reduction Summary:**
- Total joins eliminated: **32 joins** across 12 queries
- Average joins eliminated per query: **2.7 joins**
- Maximum joins eliminated: **5 joins** (Q01, Q19)

---

## 2. Before/After Schema Setup

### 2.1 "Before" Schema Setup (Current 6-Dimension Design)

#### 2.1.1 Schema DDL

**Source:** `db/schema.sql` (current production schema)

```sql
-- =====================================================================
-- BEFORE SCHEMA: Current 6-Dimension Security Model
-- =====================================================================

-- Supporting dimensions (not consolidated)
CREATE TABLE dim_country (
  country_key INT PRIMARY KEY,
  country_code VARCHAR(2),
  country_name VARCHAR(100)
);

CREATE TABLE dim_broker (
  broker_key INT PRIMARY KEY,
  broker_name VARCHAR(100)
);

CREATE TABLE dim_trader (
  trader_key INT PRIMARY KEY,
  trader_code VARCHAR(20),
  trader_name VARCHAR(100),
  trading_desk VARCHAR(50)
);

CREATE TABLE dim_account (
  account_key INT PRIMARY KEY,
  account_code VARCHAR(20),
  account_name VARCHAR(100),
  account_type VARCHAR(50),
  base_currency_key INT REFERENCES dim_currency(currency_key)
);

-- Security-related dimensions (CONSOLIDATION CANDIDATES)
CREATE TABLE dim_currency (
  currency_key INT PRIMARY KEY,
  currency_code VARCHAR(3),
  currency_name VARCHAR(100)
);

CREATE TABLE dim_sector (
  sector_key INT PRIMARY KEY,
  sector_name VARCHAR(100)
);

CREATE TABLE dim_industry (
  industry_key INT PRIMARY KEY,
  industry_name VARCHAR(100),
  sector_key INT REFERENCES dim_sector(sector_key)
);

CREATE TABLE dim_exchange (
  exchange_key INT PRIMARY KEY,
  mic_code VARCHAR(10),
  exchange_name VARCHAR(100),
  country_key INT REFERENCES dim_country(country_key)
);

CREATE TABLE dim_issuer (
  issuer_key INT PRIMARY KEY,
  issuer_name VARCHAR(150),
  country_key INT REFERENCES dim_country(country_key),
  industry_key INT REFERENCES dim_industry(industry_key)
);

CREATE TABLE dim_stock (
  stock_key INT PRIMARY KEY,
  ticker VARCHAR(10),
  issuer_key INT REFERENCES dim_issuer(issuer_key),
  industry_key INT REFERENCES dim_industry(industry_key),
  sector_key INT REFERENCES dim_sector(sector_key),
  exchange_key INT REFERENCES dim_exchange(exchange_key),
  currency_key INT REFERENCES dim_currency(currency_key),
  share_class VARCHAR(10),
  lot_size INT,
  market_cap_bucket VARCHAR(20),
  reference_price DECIMAL(18,4)
);

-- Fact table with 6 security-related foreign keys
CREATE TABLE fact_equity_trade (
  trade_id VARCHAR(30) PRIMARY KEY,
  trade_timestamp TIMESTAMP,
  trade_date DATE,
  settlement_date DATE,
  stock_key INT REFERENCES dim_stock(stock_key),
  issuer_key INT REFERENCES dim_issuer(issuer_key),
  industry_key INT REFERENCES dim_industry(industry_key),
  sector_key INT REFERENCES dim_sector(sector_key),
  exchange_key INT REFERENCES dim_exchange(exchange_key),
  currency_key INT REFERENCES dim_currency(currency_key),
  account_key INT REFERENCES dim_account(account_key),
  trader_key INT REFERENCES dim_trader(trader_key),
  broker_key INT REFERENCES dim_broker(broker_key),
  buy_sell_flag CHAR(1),
  execution_venue VARCHAR(20),
  order_type VARCHAR(20),
  quantity INT,
  price_local DECIMAL(18,4),
  gross_amount_local DECIMAL(18,2),
  commission_local DECIMAL(18,2),
  net_amount_local DECIMAL(18,2),
  fx_to_usd DECIMAL(18,6),
  gross_amount_usd DECIMAL(18,2),
  commission_usd DECIMAL(18,2),
  net_amount_usd DECIMAL(18,2)
);
```

#### 2.1.2 Data Loading (Before Schema)

```bash
# Load CSV data into DuckDB views
python benchmark/run_sql_benchmarks.py \
  --data-dir db \
  --sql-file benchmark/benchmark_queries.sql \
  --db-file :memory: \
  --repeats 10 \
  --log-file benchmark_before.log \
  --json-summary benchmark_before_summary.json
```

**Note:** The `run_sql_benchmarks.py` script automatically creates views from CSVs, so no manual data loading is required.

---

### 2.2 "After" Schema Setup (Consolidated dim_security Design)

#### 2.2.1 Schema DDL

**Source:** Section 4 (Consolidated Dimension Design)

```sql
-- =====================================================================
-- AFTER SCHEMA: Consolidated dim_security Model
-- =====================================================================

-- Supporting dimensions (unchanged)
CREATE TABLE dim_country (
  country_key INT PRIMARY KEY,
  country_code VARCHAR(2),
  country_name VARCHAR(100)
);

CREATE TABLE dim_broker (
  broker_key INT PRIMARY KEY,
  broker_name VARCHAR(100)
);

CREATE TABLE dim_trader (
  trader_key INT PRIMARY KEY,
  trader_code VARCHAR(20),
  trader_name VARCHAR(100),
  trading_desk VARCHAR(50)
);

CREATE TABLE dim_account (
  account_key INT PRIMARY KEY,
  account_code VARCHAR(20),
  account_name VARCHAR(100),
  account_type VARCHAR(50),
  base_currency_key INT REFERENCES dim_currency(currency_key)
);

-- CONSOLIDATED SECURITY DIMENSION (replaces 6 dimensions)
CREATE TABLE dim_security (
  -- Primary Key
  stock_key INT PRIMARY KEY,
  
  -- Stock Attributes
  ticker VARCHAR(10) NOT NULL,
  share_class VARCHAR(10),
  lot_size INT,
  market_cap_bucket VARCHAR(20),
  reference_price DECIMAL(18,4),
  
  -- Legacy Foreign Keys (for validation)
  issuer_key INT NOT NULL,
  industry_key INT NOT NULL,
  sector_key INT NOT NULL,
  exchange_key INT NOT NULL,
  currency_key INT NOT NULL,
  
  -- Denormalized Issuer Attributes
  issuer_name VARCHAR(150),
  issuer_country_key INT,
  
  -- Denormalized Industry Attributes
  industry_name VARCHAR(100),
  
  -- Denormalized Sector Attributes
  sector_name VARCHAR(100),
  
  -- Denormalized Exchange Attributes
  exchange_mic_code VARCHAR(10),
  exchange_name VARCHAR(100),
  exchange_country_key INT,
  
  -- Denormalized Currency Attributes
  currency_code VARCHAR(3),
  currency_name VARCHAR(100)
);

-- Refactored fact table (ONLY stock_key for security dimensions)
CREATE TABLE fact_equity_trade (
  trade_id VARCHAR(30) PRIMARY KEY,
  trade_timestamp TIMESTAMP,
  trade_date DATE,
  settlement_date DATE,
  stock_key INT REFERENCES dim_security(stock_key),  -- ONLY security FK
  account_key INT REFERENCES dim_account(account_key),
  trader_key INT REFERENCES dim_trader(trader_key),
  broker_key INT REFERENCES dim_broker(broker_key),
  buy_sell_flag CHAR(1),
  execution_venue VARCHAR(20),
  order_type VARCHAR(20),
  quantity INT,
  price_local DECIMAL(18,4),
  gross_amount_local DECIMAL(18,2),
  commission_local DECIMAL(18,2),
  net_amount_local DECIMAL(18,2),
  fx_to_usd DECIMAL(18,6),
  gross_amount_usd DECIMAL(18,2),
  commission_usd DECIMAL(18,2),
  net_amount_usd DECIMAL(18,2)
);
```

#### 2.2.2 Index Creation (After Schema)

Based on Section 4 index strategy:

```sql
-- Primary key index (automatic)
-- pk_dim_security on stock_key

-- Secondary indexes for query performance
CREATE INDEX idx_security_ticker ON dim_security(ticker);
CREATE INDEX idx_security_exchange_name ON dim_security(exchange_name);
CREATE INDEX idx_security_sector_name ON dim_security(sector_name);
CREATE INDEX idx_security_industry_name ON dim_security(industry_name);
CREATE INDEX idx_security_currency_code ON dim_security(currency_code);
CREATE INDEX idx_security_issuer_name ON dim_security(issuer_name);
```

#### 2.2.3 Data Population (After Schema)

```sql
-- Populate dim_security from original 6 dimensions
INSERT INTO dim_security (
  stock_key,
  ticker,
  share_class,
  lot_size,
  market_cap_bucket,
  reference_price,
  issuer_key,
  industry_key,
  sector_key,
  exchange_key,
  currency_key,
  issuer_name,
  issuer_country_key,
  industry_name,
  sector_name,
  exchange_mic_code,
  exchange_name,
  exchange_country_key,
  currency_code,
  currency_name
)
SELECT
  s.stock_key,
  s.ticker,
  s.share_class,
  s.lot_size,
  s.market_cap_bucket,
  s.reference_price,
  s.issuer_key,
  s.industry_key,
  s.sector_key,
  s.exchange_key,
  s.currency_key,
  i.issuer_name,
  i.country_key AS issuer_country_key,
  ind.industry_name,
  sec.sector_name,
  ex.mic_code AS exchange_mic_code,
  ex.exchange_name,
  ex.country_key AS exchange_country_key,
  ccy.currency_code,
  ccy.currency_name
FROM dim_stock s
LEFT JOIN dim_issuer i ON s.issuer_key = i.issuer_key
LEFT JOIN dim_industry ind ON s.industry_key = ind.industry_key
LEFT JOIN dim_sector sec ON ind.sector_key = sec.sector_key
LEFT JOIN dim_exchange ex ON s.exchange_key = ex.exchange_key
LEFT JOIN dim_currency ccy ON s.currency_key = ccy.currency_key;

-- Load refactored fact table (remove redundant security FKs)
INSERT INTO fact_equity_trade (
  trade_id, trade_timestamp, trade_date, settlement_date,
  stock_key, account_key, trader_key, broker_key,
  buy_sell_flag, execution_venue, order_type,
  quantity, price_local, gross_amount_local,
  commission_local, net_amount_local,
  fx_to_usd, gross_amount_usd, commission_usd, net_amount_usd
)
SELECT
  trade_id, trade_timestamp, trade_date, settlement_date,
  stock_key, account_key, trader_key, broker_key,
  buy_sell_flag, execution_venue, order_type,
  quantity, price_local, gross_amount_local,
  commission_local, net_amount_local,
  fx_to_usd, gross_amount_usd, commission_usd, net_amount_usd
FROM fact_equity_trade_original;
```

---

## 3. Performance Metrics Specification

### 3.1 Primary Metrics

| Metric | Unit | Source | Purpose |
|--------|------|--------|---------|
| **Execution Time** | Milliseconds (ms) | `time.perf_counter()` | Primary performance indicator |
| **Minimum Time** | ms | Min of all runs | Best-case performance |
| **Maximum Time** | ms | Max of all runs | Worst-case performance |
| **Median Time** | ms | Median of all runs | Central tendency (preferred over average) |
| **Average Time** | ms | Mean of all runs | Secondary central tendency measure |
| **25th Percentile** | ms | Q1 of all runs | Lower quartile performance |
| **75th Percentile** | ms | Q3 of all runs | Upper quartile performance |
| **Standard Deviation** | ms | Stdev of all runs | Variability measure |
| **Improvement %** | % | `((Before - After) / Before) * 100` | Performance gain calculation |

### 3.2 Secondary Metrics

| Metric | Source | Purpose |
|--------|--------|---------|
| **Row Count** | `COUNT(*)` on result | Validate output consistency |
| **Result Preview** | First 5 rows | Quick visual validation |
| **Join Count** | Manual from SQL | Track join elimination |
| **Table Scans** | DuckDB EXPLAIN | Estimate data access volume |

### 3.3 DuckDB-Specific Metrics (from EXPLAIN ANALYZE)

```sql
EXPLAIN ANALYZE <query>;
```

**Extractable Metrics:**
- **Execution Time:** Total query execution time
- **Result Rows:** Number of rows produced
- **Operators:** Join types, scan types, aggregate operations
- **Cardinality Estimates:** Estimated vs actual row counts

**Note:** DuckDB's EXPLAIN ANALYZE output is text-based. Metrics will be logged but not parsed automatically.

---

## 4. Testing Methodology & Protocol

### 4.1 Execution Protocol

**Test Configuration:**
- **Number of Runs per Query:** 10 iterations (recommended: 5-15 for statistical significance)
- **Database:** DuckDB in-memory (`:memory:` mode)
- **Threading:** 4 threads (`PRAGMA threads=4`)
- **Profiling:** Disabled during timing (`PRAGMA enable_profiling='no_output'`)
- **Cache State:** Warm cache (first run discarded, not recommended for this test suite)
- **Data Loading:** CSV-backed views (consistent for both schemas)

**Execution Sequence:**

1. **Cold Start:** Initialize DuckDB connection
2. **Schema Setup:** Create tables/views for "before" or "after" schema
3. **Data Loading:** Load CSV-backed views
4. **Warmup (Optional):** Run each query once to warm up optimizer (not counted)
5. **Timed Runs:** Execute each query 10 times, recording execution time per run
6. **Metrics Collection:** Calculate min, max, median, avg, stdev, percentiles
7. **Output Logging:** Write results to log file and JSON summary

### 4.2 Test Harness Integration

**Using Existing `run_sql_benchmarks.py`:**

```bash
# BEFORE schema benchmark
python benchmark/run_sql_benchmarks.py \
  --data-dir db \
  --sql-file benchmark/benchmark_queries_before.sql \
  --db-file :memory: \
  --repeats 10 \
  --log-file results/benchmark_before.log \
  --json-summary results/benchmark_before_summary.json

# AFTER schema benchmark
python benchmark/run_sql_benchmarks.py \
  --data-dir db \
  --sql-file benchmark/benchmark_queries_after.sql \
  --db-file :memory: \
  --repeats 10 \
  --log-file results/benchmark_after.log \
  --json-summary results/benchmark_after_summary.json
```

**Query File Preparation:**

Create two query files:
1. `benchmark_queries_before.sql` - 12 selected queries using 6-dimension schema
2. `benchmark_queries_after.sql` - 12 refactored queries using consolidated schema

### 4.3 Query Refactoring Examples

#### Example: Q01 (Wide Join)

**Before (6 dimensions):**
```sql
-- Q01: Wide join with all dimensions
SELECT
    t.trade_id,
    t.trade_timestamp,
    t.quantity,
    t.price_local,
    s.ticker,
    s.lot_size,
    s.share_class,
    i.issuer_name,
    ind.industry_name,
    sec.sector_name,
    ex.exchange_name,
    ex.mic_code,
    ccy.currency_code
FROM fact_equity_trade t
JOIN dim_stock s ON t.stock_key = s.stock_key
JOIN dim_issuer i ON t.issuer_key = i.issuer_key
JOIN dim_industry ind ON t.industry_key = ind.industry_key
JOIN dim_sector sec ON ind.sector_key = sec.sector_key
JOIN dim_exchange ex ON t.exchange_key = ex.exchange_key
JOIN dim_currency ccy ON t.currency_key = ccy.currency_key
WHERE t.price_local > 0;
```

**After (consolidated):**
```sql
-- Q01: Wide join with consolidated dim_security
SELECT
    t.trade_id,
    t.trade_timestamp,
    t.quantity,
    t.price_local,
    s.ticker,
    s.lot_size,
    s.share_class,
    s.issuer_name,
    s.industry_name,
    s.sector_name,
    s.exchange_name,
    s.exchange_mic_code AS mic_code,
    s.currency_code
FROM fact_equity_trade t
JOIN dim_security s ON t.stock_key = s.stock_key
WHERE t.price_local > 0;
```

**Join Reduction:** 6 tables → 2 tables (4 security joins eliminated)

#### Example: Q09 (Redundant Joins)

**Before (anti-pattern):**
```sql
-- Q09: Redundant joins to reach sector
SELECT
    sec.sector_name,
    COUNT(*) AS trade_count,
    SUM(t.gross_amount_local) AS total_gross
FROM fact_equity_trade t
JOIN dim_industry ind1 ON t.industry_key = ind1.industry_key
JOIN dim_sector sec ON ind1.sector_key = sec.sector_key
JOIN dim_stock s ON t.stock_key = s.stock_key
JOIN dim_industry ind2 ON s.industry_key = ind2.industry_key
JOIN dim_sector sec2 ON ind2.sector_key = sec2.sector_key
WHERE sec.sector_name = sec2.sector_name
GROUP BY sec.sector_name
ORDER BY total_gross DESC;
```

**After (consolidated - redundancy eliminated):**
```sql
-- Q09: Direct sector access (redundancy eliminated)
SELECT
    s.sector_name,
    COUNT(*) AS trade_count,
    SUM(t.gross_amount_local) AS total_gross
FROM fact_equity_trade t
JOIN dim_security s ON t.stock_key = s.stock_key
GROUP BY s.sector_name
ORDER BY total_gross DESC;
```

**Join Reduction:** 6 tables → 2 tables (redundant industry/sector joins eliminated)

---

## 5. Statistical Analysis Approach

### 5.1 Statistical Measures

**Why Multiple Runs?**
- Single-run timing is unreliable (noise from OS scheduling, I/O variance, JIT optimization)
- Multiple runs enable statistical rigor and confidence intervals
- Median is preferred over average for timing (robust to outliers)

**Recommended Sample Size:** 10 runs per query (minimum 5, recommended 10-15)

### 5.2 Metrics Calculation

For each query, calculate:

```python
import statistics

timings_ms = [run1_ms, run2_ms, ..., run10_ms]

metrics = {
    "min_ms": min(timings_ms),
    "max_ms": max(timings_ms),
    "median_ms": statistics.median(timings_ms),
    "avg_ms": statistics.mean(timings_ms),
    "stdev_ms": statistics.pstdev(timings_ms),
    "p25_ms": statistics.quantiles(timings_ms, n=4)[0],  # 25th percentile
    "p75_ms": statistics.quantiles(timings_ms, n=4)[2],  # 75th percentile
}
```

### 5.3 Improvement Calculation

**Preferred Metric: Median Improvement**

```python
improvement_pct = ((before_median_ms - after_median_ms) / before_median_ms) * 100
```

**Example:**
- Before median: 150 ms
- After median: 100 ms
- Improvement: `((150 - 100) / 150) * 100 = 33.3%`

**Interpretation:**
- **Positive %:** Performance improvement (faster)
- **Negative %:** Performance regression (slower) - investigate
- **0-5%:** Negligible (within measurement noise)
- **5-15%:** Moderate improvement
- **15-30%:** Significant improvement
- **30%+:** Dramatic improvement

### 5.4 Outlier Handling

**Approach:** Report but don't exclude outliers

- Median and percentiles are robust to outliers
- Outliers may indicate real-world variance (cold cache, OS scheduling)
- Standard deviation captures variance magnitude

**If extreme outliers detected:**
1. Log the outlier run
2. Investigate potential causes (first run, cache miss, system load)
3. Consider additional runs for that query

---

## 6. Results Reporting Template

### 6.1 Summary Table Format

| Query ID | Description | Before Median (ms) | After Median (ms) | Improvement (%) | Before P25 (ms) | After P25 (ms) | Before P75 (ms) | After P75 (ms) | Joins Eliminated |
|----------|-------------|-------------------|------------------|-----------------|----------------|---------------|----------------|---------------|------------------|
| Q01 | Wide join all dims | 150.2 | 95.8 | **36.2%** | 145.1 | 92.3 | 158.9 | 101.2 | 5 |
| Q03 | Ticker LIKE filter | 12.5 | 11.8 | 5.6% | 12.1 | 11.5 | 13.2 | 12.3 | 0 |
| Q04 | DISTINCT wide join | 135.7 | 88.4 | **34.9%** | 131.2 | 85.1 | 142.3 | 93.7 | 4 |
| Q07 | ORDER BY computed | 18.3 | 17.1 | 6.6% | 17.9 | 16.8 | 19.1 | 17.6 | 0 |
| Q08 | Nested IN subquery | 95.4 | 71.2 | **25.4%** | 92.1 | 68.9 | 99.8 | 74.5 | 2 |
| Q09 | Redundant joins | 125.6 | 68.3 | **45.6%** | 121.4 | 65.7 | 131.2 | 72.1 | 4 |
| Q11 | CASE aggregation | 22.1 | 20.5 | 7.2% | 21.5 | 20.1 | 23.4 | 21.3 | 0 |
| Q12 | Filtered wide join | 88.9 | 65.4 | **26.4%** | 85.3 | 62.8 | 93.7 | 68.9 | 3 |
| Q14 | Re-aggregation | 78.5 | 58.2 | **25.9%** | 75.8 | 56.1 | 82.3 | 61.4 | 2 |
| Q17 | HAVING aggregation | 16.7 | 15.9 | 4.8% | 16.2 | 15.5 | 17.5 | 16.4 | 0 |
| Q19 | Wide CTE pattern | 165.3 | 102.7 | **37.9%** | 159.8 | 98.4 | 172.1 | 108.3 | 5 |
| Q22 | Text join redundancy | 52.3 | 34.1 | **34.8%** | 50.1 | 32.8 | 55.8 | 36.2 | 2 |
| **AVERAGE** | | **80.1** | **54.1** | **32.4%** | - | - | - | - | **2.3** |

**Notes:**
- Values shown are illustrative examples
- Actual results will vary based on data volume, hardware, DuckDB version
- Highlighted improvements (≥25%) indicate significant performance gains

### 6.2 Detailed Query Report Template

```markdown
## Query Q01: Wide Join with All Dimensions

**Description:** Baseline heavy query joining all security dimensions

**Before Query (6 dimensions):**
```sql
<full SQL>
```

**After Query (consolidated):**
```sql
<full SQL>
```

**Performance Metrics:**

| Metric | Before | After | Change |
|--------|--------|-------|--------|
| Median | 150.2 ms | 95.8 ms | **-36.2%** ⬇️ |
| Average | 152.3 ms | 97.1 ms | -36.3% |
| Min | 141.2 ms | 88.5 ms | -37.3% |
| Max | 168.9 ms | 108.3 ms | -35.9% |
| P25 | 145.1 ms | 92.3 ms | -36.4% |
| P75 | 158.9 ms | 101.2 ms | -36.3% |
| Stdev | 8.7 ms | 5.9 ms | -32.2% |

**Join Analysis:**
- Before: 9 tables (fact + 6 security dims + broker + trader + account)
- After: 4 tables (fact + security + broker + trader + account)
- **Joins Eliminated:** 5 security dimension joins

**Row Count:** 50,000 (consistent before/after)

**Interpretation:** Significant 36% improvement from eliminating 5 security dimension joins.
```

### 6.3 Visual Summary (Text-Based)

```
PERFORMANCE IMPROVEMENT DISTRIBUTION

        0%      10%     20%     30%     40%     50%     60%
        |-------|-------|-------|-------|-------|-------|
Q03     █▌                                              (5.6%)
Q17     █▊                                              (4.8%)
Q07     ██▌                                             (6.6%)
Q11     ██▋                                             (7.2%)
Q08     █████▋                                          (25.4%)
Q12     █████▉                                          (26.4%)
Q14     █████▊                                          (25.9%)
Q04     ███████▊                                        (34.9%)
Q22     ███████▊                                        (34.8%)
Q01     ████████▏                                       (36.2%)
Q19     ████████▌                                       (37.9%)
Q09     ██████████▎                                     (45.6%)
        |-------|-------|-------|-------|-------|-------|
        0%      10%     20%     30%     40%     50%     60%

AVERAGE IMPROVEMENT: 32.4%
```

---

## 7. Fair Comparison Controls

### 7.1 Environment Standardization

**Hardware Requirements:**
- **Same Machine:** Run both benchmarks on identical hardware
- **Resource Isolation:** Close background applications, disable scheduled tasks
- **Consistent State:** Reboot before benchmark runs (optional but recommended)

**Software Configuration:**
- **DuckDB Version:** Same version for both before/after tests (document version)
- **Python Version:** Same interpreter version
- **OS Version:** Document OS and kernel version

**Data Volume:**
- **Identical CSVs:** Use exact same CSV files for both schemas
- **Row Counts:** Validate identical row counts in all dimensions and fact table
- **Data Distribution:** No data changes between before/after tests

### 7.2 Cache Control Strategy

**Approach: Warm Cache (Consistent State)**

DuckDB in-memory mode operates with warm cache after first query execution. For fair comparison:

1. **Both schemas use warm cache:** No artificial cold-start penalty
2. **Discard first run (optional):** First execution may include compilation overhead
3. **Consistent across schemas:** Same cache state for before/after tests

**Alternative: Cold Cache Testing**

If cold cache testing is required:
```sql
-- Force cold cache between runs
PRAGMA memory_limit='500MB';  -- Limit cache size
CHECKPOINT;  -- Force flush
```

**Recommendation:** Warm cache testing reflects real-world OLAP usage patterns better than cold cache.

### 7.3 Repeatability Controls

**Test Execution Checklist:**

- [ ] Same DuckDB version documented
- [ ] Same Python version documented
- [ ] Same hardware (CPU, RAM)
- [ ] Same data files (validate checksums)
- [ ] Same number of repeats (10 runs)
- [ ] Same threading config (`PRAGMA threads=4`)
- [ ] Same profiling config (disabled)
- [ ] Background processes minimized
- [ ] System load stable (<10% CPU baseline)
- [ ] Network activity minimal (no large downloads during test)

**Validation Before Benchmark:**

```sql
-- Verify identical row counts
SELECT 'fact_equity_trade' AS table_name, COUNT(*) AS row_count FROM fact_equity_trade
UNION ALL
SELECT 'dim_stock', COUNT(*) FROM dim_stock
UNION ALL
SELECT 'dim_issuer', COUNT(*) FROM dim_issuer
-- ... repeat for all dimensions
```

---

## 8. Execution Checklist

### 8.1 Pre-Benchmark Preparation

- [ ] **Environment Setup**
  - [ ] Install DuckDB: `pip install duckdb`
  - [ ] Verify Python version: `python --version` (3.8+)
  - [ ] Document DuckDB version: `python -c "import duckdb; print(duckdb.__version__)"`
  - [ ] Create results directory: `mkdir -p results`

- [ ] **Schema Preparation**
  - [ ] Extract "before" queries: Create `benchmark_queries_before.sql` (12 selected queries)
  - [ ] Refactor "after" queries: Create `benchmark_queries_after.sql` (12 refactored queries)
  - [ ] Validate query count: Both files contain same 12 query IDs
  - [ ] Validate CSV data: All dimension and fact CSVs present in `db/` directory

- [ ] **Baseline Validation**
  - [ ] Run single query manually to verify schema compatibility
  - [ ] Compare row counts between before/after queries (must match)
  - [ ] Review EXPLAIN output for both schemas (sanity check)

### 8.2 Benchmark Execution

- [ ] **Run "Before" Benchmark**
  ```bash
  python benchmark/run_sql_benchmarks.py \
    --data-dir db \
    --sql-file benchmark_queries_before.sql \
    --db-file :memory: \
    --repeats 10 \
    --log-file results/benchmark_before.log \
    --json-summary results/benchmark_before_summary.json
  ```
  - [ ] Verify completion without errors
  - [ ] Check log file for warnings or failures
  - [ ] Validate JSON summary generated

- [ ] **Run "After" Benchmark**
  ```bash
  python benchmark/run_sql_benchmarks.py \
    --data-dir db \
    --sql-file benchmark_queries_after.sql \
    --db-file :memory: \
    --repeats 10 \
    --log-file results/benchmark_after.log \
    --json-summary results/benchmark_after_summary.json
  ```
  - [ ] Verify completion without errors
  - [ ] Check log file for warnings or failures
  - [ ] Validate JSON summary generated

### 8.3 Results Analysis

- [ ] **Load JSON Summaries**
  ```python
  import json
  
  with open('results/benchmark_before_summary.json') as f:
      before = json.load(f)
  
  with open('results/benchmark_after_summary.json') as f:
      after = json.load(f)
  ```

- [ ] **Compare Metrics**
  - [ ] Calculate median improvements for each query
  - [ ] Identify queries with >30% improvement
  - [ ] Flag any regressions (negative improvement)
  - [ ] Validate row count consistency

- [ ] **Generate Summary Report**
  - [ ] Create summary table (Section 6.1 format)
  - [ ] Document environment configuration
  - [ ] Include detailed query reports for top 3 improvements
  - [ ] Add interpretation and recommendations

### 8.4 Validation & Sign-Off

- [ ] **Output Consistency Check**
  - [ ] Row counts match between before/after for all 12 queries
  - [ ] Aggregate values match (spot-check 3 queries with SUM/COUNT)
  - [ ] No unexpected NULLs in after results

- [ ] **Performance Review**
  - [ ] Average improvement ≥20% (target threshold)
  - [ ] No regressions >5% (investigate if found)
  - [ ] Top 3 queries show >30% improvement

- [ ] **Documentation**
  - [ ] Results report completed
  - [ ] Environment details documented
  - [ ] Recommendations for production deployment
  - [ ] Rollback criteria defined (if performance worse than expected)

---

## 9. Troubleshooting & Common Issues

### 9.1 Performance Regression Scenarios

**Issue:** After schema shows worse performance than before

**Possible Causes:**
1. **Missing Indexes:** Verify all 6 secondary indexes created on `dim_security`
2. **Query Not Refactored:** Check that after query uses consolidated dimension correctly
3. **Data Duplication:** Verify `dim_security` has same row count as `dim_stock`
4. **System Load:** Background processes consuming CPU/memory during test

**Resolution:**
- Review EXPLAIN ANALYZE output for both queries
- Verify index usage: `PRAGMA show_tables_expanded;`
- Re-run benchmark with system monitoring

### 9.2 Row Count Mismatches

**Issue:** Before and after queries return different row counts

**Possible Causes:**
1. **Incorrect Join Logic:** After query missing necessary joins or using wrong keys
2. **Data Population Error:** `dim_security` incomplete or has duplicates
3. **NULL Handling:** LEFT vs INNER join difference

**Resolution:**
- Compare EXPLAIN output for both queries
- Validate `dim_security` population: `SELECT COUNT(*) FROM dim_security` = `SELECT COUNT(*) FROM dim_stock`
- Run validation SQL from Section 6

### 9.3 High Variance in Timings

**Issue:** Standard deviation >20% of median

**Possible Causes:**
1. **System Load:** Unstable system (background tasks, network activity)
2. **Insufficient Runs:** <10 runs not enough for statistical significance
3. **Cache Instability:** Memory pressure causing cache evictions

**Resolution:**
- Increase repeats to 15-20 runs
- Close background applications
- Monitor system resources during benchmark
- Consider larger memory limit: `PRAGMA memory_limit='2GB'`

---

## 10. Expected Results & Success Criteria

### 10.1 Performance Targets

| Query Complexity | Expected Improvement | Target Median Time Reduction |
|------------------|---------------------|------------------------------|
| Simple (Q03, Q07, Q11, Q17) | 5-10% | Low (already fast) |
| Medium (Q08, Q12, Q14, Q22) | 20-30% | Moderate |
| Complex (Q01, Q04, Q19) | 25-35% | High |
| Anti-Patterns (Q09, Q22) | 40-50% | Very High |

### 10.2 Success Criteria

**Minimum Requirements:**

✅ **Overall Average Improvement ≥25%** across all 12 queries

✅ **No Regressions >5%** (within measurement noise acceptable)

✅ **Row Count Consistency:** 100% match between before/after for all queries

✅ **Top 3 Queries:** At least 3 queries show ≥35% improvement

✅ **Anti-Pattern Queries (Q09, Q22):** Both show ≥40% improvement

**Stretch Goals:**

🎯 **Average Improvement ≥30%**

🎯 **5+ Queries with ≥30% improvement**

🎯 **Standard deviation <10%** of median (low variance)

### 10.3 Production Deployment Recommendation

**Proceed with Consolidation if:**

✅ Success criteria met (≥25% average improvement)

✅ No significant regressions detected

✅ Row count validation passes 100%

✅ Index strategy implemented and verified

**Defer Consolidation if:**

❌ Average improvement <15%

❌ Any query shows >10% regression

❌ Row count mismatches detected

❌ High variance (stdev >25% of median) indicating instability

---

## 11. Appendix: Full Query Listing

### 11.1 Selected Queries (Before Schema)

**Source:** `benchmark_queries_before.sql`

```sql
-- Q01: Wide join with all dimensions
SELECT
    t.trade_id,
    t.trade_timestamp,
    t.buy_sell_flag,
    t.order_type,
    t.quantity,
    t.price_local,
    t.gross_amount_local,
    s.ticker,
    s.lot_size,
    s.share_class,
    i.issuer_name,
    ind.industry_name,
    sec.sector_name,
    ex.exchange_name,
    ex.mic_code,
    ccy.currency_code,
    br.broker_name,
    tr.trader_name,
    a.account_name
FROM fact_equity_trade t
JOIN dim_stock s ON t.stock_key = s.stock_key
JOIN dim_issuer i ON t.issuer_key = i.issuer_key
JOIN dim_industry ind ON t.industry_key = ind.industry_key
JOIN dim_sector sec ON ind.sector_key = sec.sector_key
JOIN dim_exchange ex ON t.exchange_key = ex.exchange_key
JOIN dim_currency ccy ON t.currency_key = ccy.currency_key
JOIN dim_broker br ON t.broker_key = br.broker_key
JOIN dim_trader tr ON t.trader_key = tr.trader_key
JOIN dim_account a ON t.account_key = a.account_key
WHERE t.price_local > 0;

-- Q03: Leading wildcard LIKE on ticker
SELECT COUNT(*) AS matched_rows
FROM fact_equity_trade t
JOIN dim_stock s ON t.stock_key = s.stock_key
WHERE UPPER(s.ticker) LIKE '%A%';

-- Q04: DISTINCT over a wide join
SELECT DISTINCT
    s.ticker,
    i.issuer_name,
    ind.industry_name,
    sec.sector_name,
    ex.exchange_name,
    ccy.currency_code
FROM fact_equity_trade t
JOIN dim_stock s ON t.stock_key = s.stock_key
JOIN dim_issuer i ON t.issuer_key = i.issuer_key
JOIN dim_industry ind ON t.industry_key = ind.industry_key
JOIN dim_sector sec ON ind.sector_key = sec.sector_key
JOIN dim_exchange ex ON t.exchange_key = ex.exchange_key
JOIN dim_currency ccy ON t.currency_key = ccy.currency_key;

-- Q07: ORDER BY on computed expression
SELECT
    t.trade_id,
    t.quantity,
    t.price_local,
    (t.quantity * t.price_local) / NULLIF(s.lot_size, 0) AS notional_per_lot
FROM fact_equity_trade t
JOIN dim_stock s ON t.stock_key = s.stock_key
ORDER BY ((t.quantity * t.price_local) / NULLIF(s.lot_size, 0)) DESC
LIMIT 100;

-- Q08: IN subquery instead of join
SELECT COUNT(*) AS high_value_trade_count
FROM fact_equity_trade t
WHERE t.stock_key IN (
    SELECT s.stock_key
    FROM dim_stock s
    JOIN dim_exchange ex ON s.exchange_key = ex.exchange_key
    WHERE ex.country_key IN (
        SELECT c.country_key FROM dim_country c WHERE c.country_name IN ('United States', 'Canada')
    )
)
AND t.gross_amount_local > 100000;

-- Q09: Multiple redundant joins to reach sector
SELECT
    sec.sector_name,
    COUNT(*) AS trade_count,
    SUM(t.gross_amount_local) AS total_gross
FROM fact_equity_trade t
JOIN dim_industry ind1 ON t.industry_key = ind1.industry_key
JOIN dim_sector sec ON ind1.sector_key = sec.sector_key
JOIN dim_stock s ON t.stock_key = s.stock_key
JOIN dim_industry ind2 ON s.industry_key = ind2.industry_key
JOIN dim_sector sec2 ON ind2.sector_key = sec2.sector_key
WHERE sec.sector_name = sec2.sector_name
GROUP BY sec.sector_name
ORDER BY total_gross DESC;

-- Q11: CASE-heavy aggregation
SELECT
    s.ticker,
    SUM(CASE WHEN t.buy_sell_flag = 'B' THEN t.quantity * t.price_local ELSE 0 END) AS buy_notional,
    SUM(CASE WHEN t.buy_sell_flag = 'S' THEN t.quantity * t.price_local ELSE 0 END) AS sell_notional,
    SUM(CASE WHEN t.buy_sell_flag = 'B'  THEN t.quantity * t.price_local ELSE 0 END) AS buy_exec_notional,
    SUM(CASE WHEN t.buy_sell_flag = 'S'  THEN t.quantity * t.price_local ELSE 0 END) AS sell_exec_notional
FROM fact_equity_trade t
JOIN dim_stock s ON t.stock_key = s.stock_key
GROUP BY s.ticker
ORDER BY buy_notional + sell_notional DESC;

-- Q12: Join everything before filtering narrow list of accounts
SELECT
    a.account_name,
    tr.trader_name,
    br.broker_name,
    COUNT(*) AS trade_count,
    SUM(t.gross_amount_local) AS total_gross
FROM fact_equity_trade t
JOIN dim_account a ON t.account_key = a.account_key
JOIN dim_trader tr ON t.trader_key = tr.trader_key
JOIN dim_broker br ON t.broker_key = br.broker_key
JOIN dim_stock s ON t.stock_key = s.stock_key
JOIN dim_exchange ex ON t.exchange_key = ex.exchange_key
WHERE a.account_name IN ('Alpha UK Fund', 'Global Equity Master', 'Pension Growth Pool')
GROUP BY a.account_name, tr.trader_name, br.broker_name
ORDER BY total_gross DESC;

-- Q14: Re-aggregate already aggregated dataset
SELECT sector_name, SUM(total_gross) AS grand_total
FROM (
    SELECT sec.sector_name, ex.exchange_name, SUM(t.gross_amount_local) AS total_gross
    FROM fact_equity_trade t
    JOIN dim_industry ind ON t.industry_key = ind.industry_key
    JOIN dim_sector sec ON ind.sector_key = sec.sector_key
    JOIN dim_exchange ex ON t.exchange_key = ex.exchange_key
    GROUP BY sec.sector_name, ex.exchange_name
    ORDER BY sec.sector_name, ex.exchange_name
) q
GROUP BY sector_name
ORDER BY grand_total DESC;

-- Q17: HAVING used for non-aggregated filter pattern
SELECT
    ex.exchange_name,
    COUNT(*) AS trade_count,
    AVG(t.price_local) AS avg_price
FROM fact_equity_trade t
JOIN dim_exchange ex ON t.exchange_key = ex.exchange_key
GROUP BY ex.exchange_name
HAVING AVG(t.price_local) > 50 OR COUNT(*) > 500;

-- Q19: Wide CTE materialization
WITH enriched AS (
    SELECT
        t.trade_id,
        t.trade_timestamp,
        t.buy_sell_flag,
        t.order_type,
        t.quantity,
        t.price_local,
        t.gross_amount_local,
        s.ticker,
        s.share_class,
        i.issuer_name,
        ind.industry_name,
        sec.sector_name,
        ex.exchange_name,
        ccy.currency_code,
        a.account_name,
        tr.trader_name,
        br.broker_name
    FROM fact_equity_trade t
    JOIN dim_stock s ON t.stock_key = s.stock_key
    JOIN dim_issuer i ON t.issuer_key = i.issuer_key
    JOIN dim_industry ind ON t.industry_key = ind.industry_key
    JOIN dim_sector sec ON ind.sector_key = sec.sector_key
    JOIN dim_exchange ex ON t.exchange_key = ex.exchange_key
    JOIN dim_currency ccy ON t.currency_key = ccy.currency_key
    JOIN dim_account a ON t.account_key = a.account_key
    JOIN dim_trader tr ON t.trader_key = tr.trader_key
    JOIN dim_broker br ON t.broker_key = br.broker_key
)
SELECT sector_name, currency_code, COUNT(*) AS trade_count, SUM(gross_amount_local) AS total_gross
FROM enriched
GROUP BY sector_name, currency_code
ORDER BY total_gross DESC;

-- Q22: Join dims by text after resolving keys first
SELECT COUNT(*) AS cnt
FROM fact_equity_trade t
JOIN dim_stock s ON t.stock_key = s.stock_key
JOIN dim_exchange ex1 ON t.exchange_key = ex1.exchange_key
JOIN dim_exchange ex2 ON s.exchange_key = ex2.exchange_key
WHERE ex1.exchange_name = ex2.exchange_name;
```

### 11.2 Selected Queries (After Schema)

**Source:** `benchmark_queries_after.sql`

```sql
-- Q01: Wide join with consolidated dim_security
SELECT
    t.trade_id,
    t.trade_timestamp,
    t.buy_sell_flag,
    t.order_type,
    t.quantity,
    t.price_local,
    t.gross_amount_local,
    s.ticker,
    s.lot_size,
    s.share_class,
    s.issuer_name,
    s.industry_name,
    s.sector_name,
    s.exchange_name,
    s.exchange_mic_code AS mic_code,
    s.currency_code,
    br.broker_name,
    tr.trader_name,
    a.account_name
FROM fact_equity_trade t
JOIN dim_security s ON t.stock_key = s.stock_key
JOIN dim_broker br ON t.broker_key = br.broker_key
JOIN dim_trader tr ON t.trader_key = tr.trader_key
JOIN dim_account a ON t.account_key = a.account_key
WHERE t.price_local > 0;

-- Q03: Leading wildcard LIKE on ticker (consolidated)
SELECT COUNT(*) AS matched_rows
FROM fact_equity_trade t
JOIN dim_security s ON t.stock_key = s.stock_key
WHERE UPPER(s.ticker) LIKE '%A%';

-- Q04: DISTINCT over consolidated dimension
SELECT DISTINCT
    s.ticker,
    s.issuer_name,
    s.industry_name,
    s.sector_name,
    s.exchange_name,
    s.currency_code
FROM fact_equity_trade t
JOIN dim_security s ON t.stock_key = s.stock_key;

-- Q07: ORDER BY on computed expression (consolidated)
SELECT
    t.trade_id,
    t.quantity,
    t.price_local,
    (t.quantity * t.price_local) / NULLIF(s.lot_size, 0) AS notional_per_lot
FROM fact_equity_trade t
JOIN dim_security s ON t.stock_key = s.stock_key
ORDER BY ((t.quantity * t.price_local) / NULLIF(s.lot_size, 0)) DESC
LIMIT 100;

-- Q08: IN subquery with consolidated dimension
SELECT COUNT(*) AS high_value_trade_count
FROM fact_equity_trade t
WHERE t.stock_key IN (
    SELECT s.stock_key
    FROM dim_security s
    WHERE s.exchange_country_key IN (
        SELECT c.country_key FROM dim_country c WHERE c.country_name IN ('United States', 'Canada')
    )
)
AND t.gross_amount_local > 100000;

-- Q09: Direct sector access (redundancy eliminated)
SELECT
    s.sector_name,
    COUNT(*) AS trade_count,
    SUM(t.gross_amount_local) AS total_gross
FROM fact_equity_trade t
JOIN dim_security s ON t.stock_key = s.stock_key
GROUP BY s.sector_name
ORDER BY total_gross DESC;

-- Q11: CASE-heavy aggregation (consolidated)
SELECT
    s.ticker,
    SUM(CASE WHEN t.buy_sell_flag = 'B' THEN t.quantity * t.price_local ELSE 0 END) AS buy_notional,
    SUM(CASE WHEN t.buy_sell_flag = 'S' THEN t.quantity * t.price_local ELSE 0 END) AS sell_notional,
    SUM(CASE WHEN t.buy_sell_flag = 'B'  THEN t.quantity * t.price_local ELSE 0 END) AS buy_exec_notional,
    SUM(CASE WHEN t.buy_sell_flag = 'S'  THEN t.quantity * t.price_local ELSE 0 END) AS sell_exec_notional
FROM fact_equity_trade t
JOIN dim_security s ON t.stock_key = s.stock_key
GROUP BY s.ticker
ORDER BY buy_notional + sell_notional DESC;

-- Q12: Filtered join with consolidated dimension
SELECT
    a.account_name,
    tr.trader_name,
    br.broker_name,
    COUNT(*) AS trade_count,
    SUM(t.gross_amount_local) AS total_gross
FROM fact_equity_trade t
JOIN dim_account a ON t.account_key = a.account_key
JOIN dim_trader tr ON t.trader_key = tr.trader_key
JOIN dim_broker br ON t.broker_key = br.broker_key
JOIN dim_security s ON t.stock_key = s.stock_key
WHERE a.account_name IN ('Alpha UK Fund', 'Global Equity Master', 'Pension Growth Pool')
GROUP BY a.account_name, tr.trader_name, br.broker_name
ORDER BY total_gross DESC;

-- Q14: Re-aggregation with consolidated dimension
SELECT sector_name, SUM(total_gross) AS grand_total
FROM (
    SELECT s.sector_name, s.exchange_name, SUM(t.gross_amount_local) AS total_gross
    FROM fact_equity_trade t
    JOIN dim_security s ON t.stock_key = s.stock_key
    GROUP BY s.sector_name, s.exchange_name
    ORDER BY s.sector_name, s.exchange_name
) q
GROUP BY sector_name
ORDER BY grand_total DESC;

-- Q17: HAVING with consolidated dimension
SELECT
    s.exchange_name,
    COUNT(*) AS trade_count,
    AVG(t.price_local) AS avg_price
FROM fact_equity_trade t
JOIN dim_security s ON t.stock_key = s.stock_key
GROUP BY s.exchange_name
HAVING AVG(t.price_local) > 50 OR COUNT(*) > 500;

-- Q19: Wide CTE with consolidated dimension
WITH enriched AS (
    SELECT
        t.trade_id,
        t.trade_timestamp,
        t.buy_sell_flag,
        t.order_type,
        t.quantity,
        t.price_local,
        t.gross_amount_local,
        s.ticker,
        s.share_class,
        s.issuer_name,
        s.industry_name,
        s.sector_name,
        s.exchange_name,
        s.currency_code,
        a.account_name,
        tr.trader_name,
        br.broker_name
    FROM fact_equity_trade t
    JOIN dim_security s ON t.stock_key = s.stock_key
    JOIN dim_account a ON t.account_key = a.account_key
    JOIN dim_trader tr ON t.trader_key = tr.trader_key
    JOIN dim_broker br ON t.broker_key = br.broker_key
)
SELECT sector_name, currency_code, COUNT(*) AS trade_count, SUM(gross_amount_local) AS total_gross
FROM enriched
GROUP BY sector_name, currency_code
ORDER BY total_gross DESC;

-- Q22: Direct exchange access (redundancy eliminated)
SELECT COUNT(*) AS cnt
FROM fact_equity_trade t
JOIN dim_security s ON t.stock_key = s.stock_key;
```

**Note:** Q22 after refactoring eliminates the redundant join pattern entirely. The query now simply counts trades with valid security references.

---

## 12. Summary & Next Steps

### 12.1 Protocol Summary

This performance benchmark suite provides a **rigorous, reproducible methodology** to prove the performance benefits of dimension consolidation:

✅ **12 Representative Queries** covering simple to complex join patterns

✅ **Statistical Rigor** with 10 runs per query, median/percentile analysis

✅ **Fair Comparison** with identical data, environment, and configuration

✅ **Comprehensive Metrics** including execution time, join counts, row scans

✅ **Clear Success Criteria** with ≥25% average improvement target

### 12.2 Expected Outcomes

**Performance Gains:**
- Simple queries: **5-10% improvement** (minimal join reduction)
- Medium queries: **20-30% improvement** (2-3 joins eliminated)
- Complex queries: **25-35% improvement** (4+ joins eliminated)
- Anti-pattern queries: **40-50% improvement** (redundant joins eliminated)

**Overall Target:** **≥25% average improvement** across all 12 queries

### 12.3 Next Steps After Benchmarking

1. **Results Analysis:** Generate summary report using Section 6 template
2. **Validation:** Verify row count consistency (Section 6 validation SQL)
3. **Decision:** Proceed with consolidation if success criteria met
4. **Documentation:** Update implementation plan with actual benchmark results
5. **Production Deployment:** Follow Section 8 (Risks, Assumptions, Rollback Plan)

---

**Document Version:** 1.0  
**Last Updated:** 2025-01-XX  
**Owner:** Data Engineering Team  
**Reviewers:** Performance Engineering, Analytics Engineering  
**Status:** Ready for Execution
