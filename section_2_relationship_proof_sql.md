# Section 2: Relationship Proof SQL

## Executive Summary

This section provides executable SQL queries that validate the feasibility of consolidating six security-related dimensions (`dim_stock`, `dim_issuer`, `dim_industry`, `dim_sector`, `dim_exchange`, `dim_currency`) into a single unified dimension. All queries are written in DuckDB syntax and are designed to run against CSV files loaded into DuckDB.

**Validation Strategy:**
- **Cardinality Tests:** Prove Many-to-One relationships exist between dimensions
- **Referential Integrity Tests:** Prove no orphaned foreign key references exist
- **Functional Dependency Tests:** Prove deterministic mappings and consistency
- **Join Path Tests:** Prove semantic equivalence between direct and indirect joins

**Success Criteria:** All queries must return **zero rows** (indicating no violations) to prove consolidation can be performed without data loss.

---

## 1. Cardinality Validation Queries

These queries validate that all dimension relationships are Many-to-One (M:1) or One-to-One (1:1), which is required for lossless consolidation.

### Query 1.1: Stock → Issuer Cardinality (M:1 Expected)

**Purpose:** Verify that each stock maps to exactly one issuer (many stocks can belong to the same issuer, but each stock has only one issuer).

**SQL:**
```sql
-- Expected: 0 rows (no violations)
SELECT 
  stock_key, 
  COUNT(DISTINCT issuer_key) as issuer_count
FROM dim_stock
GROUP BY stock_key
HAVING COUNT(DISTINCT issuer_key) > 1;
```

**Expected Result:** 0 rows

**Pass/Fail Criteria:**
- ✅ **PASS:** 0 rows returned (each stock has exactly 1 issuer)
- ❌ **FAIL:** 1+ rows returned (indicates a stock with multiple issuers, violates M:1 assumption)

**Interpretation:** If this query returns any rows, it means a single stock_key is associated with multiple issuer_key values, which would prevent lossless consolidation using stock as the grain.

---

### Query 1.2: Stock → Industry Cardinality (M:1 Expected)

**Purpose:** Verify that each stock maps to exactly one industry classification.

**SQL:**
```sql
-- Expected: 0 rows (no violations)
SELECT 
  stock_key, 
  COUNT(DISTINCT industry_key) as industry_count
FROM dim_stock
GROUP BY stock_key
HAVING COUNT(DISTINCT industry_key) > 1;
```

**Expected Result:** 0 rows

**Pass/Fail Criteria:**
- ✅ **PASS:** 0 rows returned (each stock has exactly 1 industry)
- ❌ **FAIL:** 1+ rows returned (indicates a stock with multiple industries)

**Interpretation:** This query validates that the dim_stock table has a deterministic stock → industry mapping.

---

### Query 1.3: Stock → Sector Cardinality (M:1 Expected)

**Purpose:** Verify that each stock maps to exactly one sector classification.

**SQL:**
```sql
-- Expected: 0 rows (no violations)
SELECT 
  stock_key, 
  COUNT(DISTINCT sector_key) as sector_count
FROM dim_stock
GROUP BY stock_key
HAVING COUNT(DISTINCT sector_key) > 1;
```

**Expected Result:** 0 rows

**Pass/Fail Criteria:**
- ✅ **PASS:** 0 rows returned (each stock has exactly 1 sector)
- ❌ **FAIL:** 1+ rows returned (indicates a stock with multiple sectors)

**Interpretation:** This query validates that sector assignment is deterministic at the stock level.

---

### Query 1.4: Stock → Exchange Cardinality (M:1 Expected)

**Purpose:** Verify that each stock is traded on exactly one primary exchange (not multi-listed).

**SQL:**
```sql
-- Expected: 0 rows (no violations)
SELECT 
  stock_key, 
  COUNT(DISTINCT exchange_key) as exchange_count
FROM dim_stock
GROUP BY stock_key
HAVING COUNT(DISTINCT exchange_key) > 1;
```

**Expected Result:** 0 rows

**Pass/Fail Criteria:**
- ✅ **PASS:** 0 rows returned (each stock has exactly 1 exchange)
- ❌ **FAIL:** 1+ rows returned (indicates a stock listed on multiple exchanges)

**Interpretation:** If any rows are returned, it means the business model allows multi-listing, and the consolidation grain would need to be adjusted to (stock_key, exchange_key).

---

### Query 1.5: Stock → Currency Cardinality (M:1 Expected)

**Purpose:** Verify that each stock trades in exactly one primary currency.

**SQL:**
```sql
-- Expected: 0 rows (no violations)
SELECT 
  stock_key, 
  COUNT(DISTINCT currency_key) as currency_count
FROM dim_stock
GROUP BY stock_key
HAVING COUNT(DISTINCT currency_key) > 1;
```

**Expected Result:** 0 rows

**Pass/Fail Criteria:**
- ✅ **PASS:** 0 rows returned (each stock has exactly 1 currency)
- ❌ **FAIL:** 1+ rows returned (indicates a stock trading in multiple currencies)

**Interpretation:** If any rows are returned, it means dual-currency trading exists, which would require grain adjustment.

---

### Query 1.6: Issuer → Industry Cardinality (M:1 Expected)

**Purpose:** Verify that each issuer (company) is classified into exactly one industry.

**SQL:**
```sql
-- Expected: 0 rows (no violations)
SELECT 
  issuer_key, 
  COUNT(DISTINCT industry_key) as industry_count
FROM dim_issuer
GROUP BY issuer_key
HAVING COUNT(DISTINCT industry_key) > 1;
```

**Expected Result:** 0 rows

**Pass/Fail Criteria:**
- ✅ **PASS:** 0 rows returned (each issuer has exactly 1 industry)
- ❌ **FAIL:** 1+ rows returned (indicates a conglomerate with multiple industry classifications)

**Interpretation:** This validates the issuer → industry relationship is deterministic, supporting hierarchical consolidation.

---

### Query 1.7: Industry → Sector Cardinality (M:1 Expected)

**Purpose:** Verify that each industry belongs to exactly one sector (no cross-sector industries).

**SQL:**
```sql
-- Expected: 0 rows (no violations)
SELECT 
  industry_key, 
  COUNT(DISTINCT sector_key) as sector_count
FROM dim_industry
GROUP BY industry_key
HAVING COUNT(DISTINCT sector_key) > 1;
```

**Expected Result:** 0 rows

**Pass/Fail Criteria:**
- ✅ **PASS:** 0 rows returned (each industry belongs to exactly 1 sector)
- ❌ **FAIL:** 1+ rows returned (indicates industry spanning multiple sectors)

**Interpretation:** This validates the industry → sector hierarchy is clean and supports consolidation.

---

## 2. Referential Integrity Validation Queries

These queries check for orphaned foreign key references (rows that reference non-existent parent records).

### Query 2.1: Orphaned Foreign Keys in dim_stock

**Purpose:** Verify that all foreign keys in dim_stock reference valid records in parent dimensions.

**SQL:**
```sql
-- Expected: 0 rows (no orphaned references)
SELECT 
  s.stock_key,
  s.ticker,
  CASE 
    WHEN i.issuer_key IS NULL THEN 'Missing Issuer: ' || s.issuer_key
    WHEN ind.industry_key IS NULL THEN 'Missing Industry: ' || s.industry_key
    WHEN sec.sector_key IS NULL THEN 'Missing Sector: ' || s.sector_key
    WHEN ex.exchange_key IS NULL THEN 'Missing Exchange: ' || s.exchange_key
    WHEN cur.currency_key IS NULL THEN 'Missing Currency: ' || s.currency_key
  END as orphan_type
FROM dim_stock s
LEFT JOIN dim_issuer i ON s.issuer_key = i.issuer_key
LEFT JOIN dim_industry ind ON s.industry_key = ind.industry_key
LEFT JOIN dim_sector sec ON s.sector_key = sec.sector_key
LEFT JOIN dim_exchange ex ON s.exchange_key = ex.exchange_key
LEFT JOIN dim_currency cur ON s.currency_key = cur.currency_key
WHERE i.issuer_key IS NULL
   OR ind.industry_key IS NULL
   OR sec.sector_key IS NULL
   OR ex.exchange_key IS NULL
   OR cur.currency_key IS NULL;
```

**Expected Result:** 0 rows

**Pass/Fail Criteria:**
- ✅ **PASS:** 0 rows returned (all foreign keys are valid)
- ❌ **FAIL:** 1+ rows returned (indicates orphaned foreign key references)

**Interpretation:** Any rows returned indicate referential integrity violations that must be corrected before consolidation.

---

### Query 2.2: Orphaned Foreign Keys in dim_issuer

**Purpose:** Verify that all foreign keys in dim_issuer reference valid records.

**SQL:**
```sql
-- Expected: 0 rows (no orphaned references)
SELECT 
  i.issuer_key,
  i.issuer_name,
  CASE 
    WHEN ind.industry_key IS NULL THEN 'Missing Industry: ' || i.industry_key
    WHEN c.country_key IS NULL THEN 'Missing Country: ' || i.country_key
  END as orphan_type
FROM dim_issuer i
LEFT JOIN dim_industry ind ON i.industry_key = ind.industry_key
LEFT JOIN dim_country c ON i.country_key = c.country_key
WHERE ind.industry_key IS NULL
   OR c.country_key IS NULL;
```

**Expected Result:** 0 rows

**Pass/Fail Criteria:**
- ✅ **PASS:** 0 rows returned (all foreign keys are valid)
- ❌ **FAIL:** 1+ rows returned (indicates orphaned references)

**Interpretation:** While country_key is not part of security consolidation, this query ensures dim_issuer has clean referential integrity overall.

---

### Query 2.3: Orphaned Foreign Keys in dim_industry

**Purpose:** Verify that all industries reference valid sectors.

**SQL:**
```sql
-- Expected: 0 rows (no orphaned references)
SELECT 
  i.industry_key,
  i.industry_name,
  i.sector_key,
  'Missing Sector: ' || i.sector_key as orphan_type
FROM dim_industry i
LEFT JOIN dim_sector s ON i.sector_key = s.sector_key
WHERE s.sector_key IS NULL;
```

**Expected Result:** 0 rows

**Pass/Fail Criteria:**
- ✅ **PASS:** 0 rows returned (all foreign keys are valid)
- ❌ **FAIL:** 1+ rows returned (indicates orphaned sector references)

**Interpretation:** This validates the industry → sector hierarchy has no broken references.

---

## 3. Functional Dependency Validation Queries

These queries validate that redundant foreign keys in dim_stock and fact_equity_trade are consistent with their derivable values.

### Query 3.1: Stock Industry vs. Issuer Industry Consistency

**Purpose:** Verify whether stock.industry_key always matches issuer.industry_key, or if stock-level overrides exist.

**SQL:**
```sql
-- Expected: 0 rows if stock industry always matches issuer industry
-- Non-zero rows indicate stock-level industry override (business exception)
SELECT 
  s.stock_key,
  s.ticker,
  s.issuer_key,
  i.issuer_name,
  s.industry_key as stock_industry_key,
  i.industry_key as issuer_industry_key,
  si.industry_name as stock_industry_name,
  ii.industry_name as issuer_industry_name
FROM dim_stock s
JOIN dim_issuer i ON s.issuer_key = i.issuer_key
LEFT JOIN dim_industry si ON s.industry_key = si.industry_key
LEFT JOIN dim_industry ii ON i.industry_key = ii.industry_key
WHERE s.industry_key <> i.industry_key
   OR s.industry_key IS NULL
   OR i.industry_key IS NULL;
```

**Expected Result:** 0 rows (industry is consistent)

**Pass/Fail Criteria:**
- ✅ **PASS:** 0 rows returned (stock.industry_key always equals issuer.industry_key)
- ⚠️ **WARNING:** 1+ rows returned (stock-level industry overrides exist)

**Interpretation:** 
- If 0 rows: stock.industry_key is redundant and can be removed (derivable from issuer)
- If >0 rows: stock.industry_key serves a business purpose (e.g., tracking security-specific industry vs. parent company industry)

---

### Query 3.2: Stock Sector vs. Industry Sector Consistency

**Purpose:** Verify whether stock.sector_key always matches industry.sector_key through the hierarchy.

**SQL:**
```sql
-- Expected: 0 rows (sector should be consistent via industry)
SELECT 
  s.stock_key,
  s.ticker,
  s.industry_key,
  ind.industry_name,
  s.sector_key as stock_sector_key,
  ind.sector_key as industry_sector_key,
  ss.sector_name as stock_sector_name,
  is2.sector_name as industry_sector_name
FROM dim_stock s
JOIN dim_industry ind ON s.industry_key = ind.industry_key
LEFT JOIN dim_sector ss ON s.sector_key = ss.sector_key
LEFT JOIN dim_sector is2 ON ind.sector_key = is2.sector_key
WHERE s.sector_key <> ind.sector_key
   OR s.sector_key IS NULL
   OR ind.sector_key IS NULL;
```

**Expected Result:** 0 rows (sector is consistent)

**Pass/Fail Criteria:**
- ✅ **PASS:** 0 rows returned (stock.sector_key always equals industry.sector_key)
- ❌ **FAIL:** 1+ rows returned (indicates data inconsistency or denormalization error)

**Interpretation:** 
- If 0 rows: stock.sector_key is redundant and derivable via industry
- If >0 rows: Data quality issue requiring correction before consolidation

---

## 4. Fact Table Consistency Validation Queries

These queries validate that the redundant foreign keys in fact_equity_trade are synchronized with dim_stock.

### Query 4.1: Fact Table Foreign Key Consistency Check

**Purpose:** Verify that all security-related foreign keys in fact_equity_trade match the corresponding foreign keys in dim_stock for the same stock_key.

**SQL:**
```sql
-- Expected: 0 rows (no mismatches)
SELECT 
  f.trade_id,
  f.stock_key,
  f.issuer_key as fact_issuer_key,
  s.issuer_key as stock_issuer_key,
  f.industry_key as fact_industry_key,
  s.industry_key as stock_industry_key,
  f.sector_key as fact_sector_key,
  s.sector_key as stock_sector_key,
  f.exchange_key as fact_exchange_key,
  s.exchange_key as stock_exchange_key,
  f.currency_key as fact_currency_key,
  s.currency_key as stock_currency_key,
  CASE 
    WHEN f.issuer_key <> s.issuer_key THEN 'Issuer Mismatch'
    WHEN f.industry_key <> s.industry_key THEN 'Industry Mismatch'
    WHEN f.sector_key <> s.sector_key THEN 'Sector Mismatch'
    WHEN f.exchange_key <> s.exchange_key THEN 'Exchange Mismatch'
    WHEN f.currency_key <> s.currency_key THEN 'Currency Mismatch'
  END as mismatch_type
FROM fact_equity_trade f
JOIN dim_stock s ON f.stock_key = s.stock_key
WHERE f.issuer_key <> s.issuer_key
   OR f.industry_key <> s.industry_key
   OR f.sector_key <> s.sector_key
   OR f.exchange_key <> s.exchange_key
   OR f.currency_key <> s.currency_key;
```

**Expected Result:** 0 rows

**Pass/Fail Criteria:**
- ✅ **PASS:** 0 rows returned (fact table foreign keys are synchronized with dim_stock)
- ❌ **FAIL:** 1+ rows returned (indicates data inconsistency requiring ETL correction)

**Interpretation:** Any mismatches indicate that the denormalized foreign keys in fact_equity_trade are out of sync with dim_stock. This must be corrected before consolidation to ensure no data loss.

---

### Query 4.2: Fact Table Orphaned Stock Keys

**Purpose:** Verify that all stock_key values in fact_equity_trade reference valid stocks in dim_stock.

**SQL:**
```sql
-- Expected: 0 rows (no orphaned stock references)
SELECT 
  f.trade_id,
  f.stock_key,
  'Orphaned Stock Key: ' || f.stock_key as issue
FROM fact_equity_trade f
LEFT JOIN dim_stock s ON f.stock_key = s.stock_key
WHERE s.stock_key IS NULL;
```

**Expected Result:** 0 rows

**Pass/Fail Criteria:**
- ✅ **PASS:** 0 rows returned (all trades reference valid stocks)
- ❌ **FAIL:** 1+ rows returned (indicates orphaned fact records)

**Interpretation:** Any orphaned records must be corrected or removed before consolidation.

---

## 5. Join Path Equivalence Validation Queries

These queries prove that different join paths yield identical results, validating that consolidation won't change query semantics.

### Query 5.1: Direct vs. Indirect Sector Join Equivalence

**Purpose:** Prove that querying sector via fact → stock → industry → sector yields the same result as fact → stock → sector (direct).

**SQL:**
```sql
-- Expected: 0 rows (both paths yield identical results)
WITH direct_path AS (
  SELECT 
    f.trade_id,
    f.stock_key,
    s.sector_key as sector_via_stock,
    sec.sector_name as sector_name_direct
  FROM fact_equity_trade f
  JOIN dim_stock s ON f.stock_key = s.stock_key
  JOIN dim_sector sec ON s.sector_key = sec.sector_key
),
indirect_path AS (
  SELECT 
    f.trade_id,
    f.stock_key,
    ind.sector_key as sector_via_industry,
    sec.sector_name as sector_name_indirect
  FROM fact_equity_trade f
  JOIN dim_stock s ON f.stock_key = s.stock_key
  JOIN dim_industry ind ON s.industry_key = ind.industry_key
  JOIN dim_sector sec ON ind.sector_key = sec.sector_key
)
SELECT 
  d.trade_id,
  d.stock_key,
  d.sector_via_stock,
  i.sector_via_industry,
  d.sector_name_direct,
  i.sector_name_indirect
FROM direct_path d
FULL OUTER JOIN indirect_path i ON d.trade_id = i.trade_id
WHERE d.sector_via_stock <> i.sector_via_industry
   OR d.sector_via_stock IS NULL
   OR i.sector_via_industry IS NULL;
```

**Expected Result:** 0 rows

**Pass/Fail Criteria:**
- ✅ **PASS:** 0 rows returned (both join paths produce identical sector values)
- ❌ **FAIL:** 1+ rows returned (indicates data inconsistency in hierarchy)

**Interpretation:** This validates that the redundant stock.sector_key is truly redundant and can be safely removed.

---

### Query 5.2: Direct vs. Indirect Industry Join Equivalence

**Purpose:** Prove that querying industry via fact → stock → issuer → industry yields the same result as fact → stock → industry (direct).

**SQL:**
```sql
-- Expected: 0 rows (both paths yield identical results)
WITH direct_path AS (
  SELECT 
    f.trade_id,
    f.stock_key,
    s.industry_key as industry_via_stock,
    ind.industry_name as industry_name_direct
  FROM fact_equity_trade f
  JOIN dim_stock s ON f.stock_key = s.stock_key
  JOIN dim_industry ind ON s.industry_key = ind.industry_key
),
indirect_path AS (
  SELECT 
    f.trade_id,
    f.stock_key,
    iss.industry_key as industry_via_issuer,
    ind.industry_name as industry_name_indirect
  FROM fact_equity_trade f
  JOIN dim_stock s ON f.stock_key = s.stock_key
  JOIN dim_issuer iss ON s.issuer_key = iss.issuer_key
  JOIN dim_industry ind ON iss.industry_key = ind.industry_key
)
SELECT 
  d.trade_id,
  d.stock_key,
  d.industry_via_stock,
  i.industry_via_issuer,
  d.industry_name_direct,
  i.industry_name_indirect
FROM direct_path d
FULL OUTER JOIN indirect_path i ON d.trade_id = i.trade_id
WHERE d.industry_via_stock <> i.industry_via_issuer
   OR d.industry_via_stock IS NULL
   OR i.industry_via_issuer IS NULL;
```

**Expected Result:** 0 rows (or may return rows if stock-level industry overrides exist)

**Pass/Fail Criteria:**
- ✅ **PASS:** 0 rows returned (stock.industry_key always equals issuer.industry_key)
- ⚠️ **WARNING:** 1+ rows returned (stock-level industry overrides exist; see Query 3.1)

**Interpretation:** 
- If 0 rows: stock.industry_key is redundant and derivable from issuer
- If >0 rows: stock.industry_key has business meaning and must be preserved in consolidated dimension

---

## 6. Completeness Validation Query

This query validates that all dimension attributes remain accessible through the proposed consolidation grain.

### Query 6.1: Attribute Accessibility After Consolidation

**Purpose:** Prove that joining fact_equity_trade to all 6 dimensions via stock_key provides access to all necessary attributes.

**SQL:**
```sql
-- Expected: 30 rows (one per stock), all with non-null attributes
SELECT 
  s.stock_key,
  s.ticker,
  s.share_class,
  s.lot_size,
  s.market_cap_bucket,
  s.reference_price,
  i.issuer_name,
  i.country_key as issuer_country_key,
  ind.industry_name,
  sec.sector_name,
  ex.mic_code,
  ex.exchange_name,
  ex.country_key as exchange_country_key,
  cur.currency_code,
  cur.currency_name
FROM dim_stock s
LEFT JOIN dim_issuer i ON s.issuer_key = i.issuer_key
LEFT JOIN dim_industry ind ON s.industry_key = ind.industry_key
LEFT JOIN dim_sector sec ON s.sector_key = sec.sector_key
LEFT JOIN dim_exchange ex ON s.exchange_key = ex.exchange_key
LEFT JOIN dim_currency cur ON s.currency_key = cur.currency_key
WHERE i.issuer_key IS NULL
   OR ind.industry_key IS NULL
   OR sec.sector_key IS NULL
   OR ex.exchange_key IS NULL
   OR cur.currency_key IS NULL;
```

**Expected Result:** 0 rows (all stocks can be fully denormalized)

**Pass/Fail Criteria:**
- ✅ **PASS:** 0 rows returned (all attributes are accessible via stock_key)
- ❌ **FAIL:** 1+ rows returned (indicates incomplete join paths)

**Interpretation:** This query simulates the consolidated dimension creation. Zero rows proves that all dimension attributes can be successfully denormalized into a single consolidated table using stock_key as the grain.

---

## 7. Execution Instructions

### 7.1 DuckDB Setup

All queries are designed to run in DuckDB against CSV files. Execute the following setup commands:

```sql
-- Load CSV files into DuckDB tables
CREATE TABLE dim_country AS SELECT * FROM read_csv_auto('db/dim_country.csv');
CREATE TABLE dim_currency AS SELECT * FROM read_csv_auto('db/dim_currency.csv');
CREATE TABLE dim_sector AS SELECT * FROM read_csv_auto('db/dim_sector.csv');
CREATE TABLE dim_industry AS SELECT * FROM read_csv_auto('db/dim_industry.csv');
CREATE TABLE dim_exchange AS SELECT * FROM read_csv_auto('db/dim_exchange.csv');
CREATE TABLE dim_issuer AS SELECT * FROM read_csv_auto('db/dim_issuer.csv');
CREATE TABLE dim_stock AS SELECT * FROM read_csv_auto('db/dim_stock.csv');
CREATE TABLE fact_equity_trade AS SELECT * FROM read_csv_auto('db/fact_equity_trade.csv');
```

### 7.2 Query Execution Order

Execute queries in the following order:

1. **Cardinality Validation (1.1 - 1.7):** Validates M:1 relationships
2. **Referential Integrity (2.1 - 2.3):** Validates no orphaned foreign keys
3. **Functional Dependency (3.1 - 3.2):** Validates redundancy and consistency
4. **Fact Table Consistency (4.1 - 4.2):** Validates fact table data quality
5. **Join Path Equivalence (5.1 - 5.2):** Validates semantic equivalence
6. **Completeness (6.1):** Validates attribute accessibility

### 7.3 Result Interpretation

**All Tests Pass (All queries return 0 rows):**
- ✅ Consolidation is **SAFE** and **LOSSLESS**
- ✅ All relationships are M:1 or 1:1
- ✅ No data quality issues exist
- ✅ Redundant foreign keys can be safely removed
- ✅ Proceed to Section 3 (Downstream Dependency Inventory)

**Any Test Fails (Any query returns 1+ rows):**
- ❌ Data quality issues must be corrected before consolidation
- ❌ Review failed queries to understand specific violations
- ❌ Implement data correction ETL as needed
- ❌ Re-run validation suite after corrections

---

## 8. Summary of Validation Coverage

### 8.1 Validation Query Matrix

| Query ID | Test Category | Relationship Tested | Expected Rows | Critical? |
|----------|---------------|---------------------|---------------|-----------|
| 1.1 | Cardinality | Stock → Issuer | 0 | ✓ Critical |
| 1.2 | Cardinality | Stock → Industry | 0 | ✓ Critical |
| 1.3 | Cardinality | Stock → Sector | 0 | ✓ Critical |
| 1.4 | Cardinality | Stock → Exchange | 0 | ✓ Critical |
| 1.5 | Cardinality | Stock → Currency | 0 | ✓ Critical |
| 1.6 | Cardinality | Issuer → Industry | 0 | ✓ Critical |
| 1.7 | Cardinality | Industry → Sector | 0 | ✓ Critical |
| 2.1 | Referential Integrity | dim_stock FKs | 0 | ✓ Critical |
| 2.2 | Referential Integrity | dim_issuer FKs | 0 | ✓ Critical |
| 2.3 | Referential Integrity | dim_industry FKs | 0 | ✓ Critical |
| 3.1 | Functional Dependency | Stock vs Issuer Industry | 0 | ⚠️ Warning if fails |
| 3.2 | Functional Dependency | Stock vs Industry Sector | 0 | ✓ Critical |
| 4.1 | Fact Consistency | Fact vs Stock FKs | 0 | ✓ Critical |
| 4.2 | Fact Consistency | Orphaned Stock Keys | 0 | ✓ Critical |
| 5.1 | Join Path Equivalence | Sector via Industry | 0 | ✓ Critical |
| 5.2 | Join Path Equivalence | Industry via Issuer | 0 | ⚠️ Warning if fails |
| 6.1 | Completeness | Attribute Accessibility | 0 | ✓ Critical |

**Total Queries:** 17  
**Critical Validations:** 15  
**Warning Validations:** 2 (Queries 3.1 and 5.2 - may indicate business rules for stock-level overrides)

### 8.2 What Successful Validation Proves

If all critical queries return 0 rows, the following is proven:

1. ✅ **Lossless Consolidation:** All dimension relationships are M:1 or 1:1, ensuring no data duplication when denormalizing
2. ✅ **Referential Integrity:** All foreign key references are valid, ensuring no orphaned records
3. ✅ **Functional Dependencies:** Redundant foreign keys (sector_key, industry_key in stock; issuer_key, industry_key, sector_key, exchange_key, currency_key in fact_equity_trade) are consistent and derivable
4. ✅ **Join Path Equivalence:** Direct and indirect join paths produce identical results, proving semantic equivalence
5. ✅ **Attribute Completeness:** All dimension attributes are accessible through the consolidation grain (stock_key)
6. ✅ **Schema Simplification:** fact_equity_trade can safely drop 5 of 6 security-related foreign keys (83% reduction)

### 8.3 Next Steps After Validation

**If All Tests Pass:**
- Proceed to **Section 3: Downstream Dependency Inventory** to identify all views, reports, and queries that reference the 6 dimensions
- Begin designing the consolidated dimension DDL (Section 4)

**If Any Tests Fail:**
- Document all failures and root causes
- Implement data correction ETL/scripts
- Re-run validation suite
- Obtain stakeholder approval for any business rule changes

---

## Appendix A: Query Performance Notes

**Expected Query Performance:**
- All queries are expected to run in <1 second on the sample dataset (30 stocks, 30 trades)
- Queries use LEFT/FULL OUTER JOINs to detect missing references
- GROUP BY queries (1.1-1.7) scan dimension tables only, not fact tables
- Fact table queries (4.1, 4.2, 5.1, 5.2) scan ~30 rows
- No indexes required for sample dataset; production execution may benefit from indexes on foreign keys

**DuckDB-Specific Features Used:**
- `read_csv_auto()` for automatic CSV schema detection
- Standard SQL syntax (ANSI-compliant)
- FULL OUTER JOIN for comprehensive mismatch detection
- LEFT JOIN for orphan detection

---

## Appendix B: Query Modification Guide

**To adapt queries for production environments:**

1. **Add NULL handling:** If dimensions allow NULL foreign keys, modify WHERE clauses to handle NULLs explicitly
2. **Add row limits:** For large datasets, add `LIMIT 100` to sample validation results
3. **Add performance hints:** Create indexes on foreign key columns before running validation suite
4. **Modify CSV paths:** Update `read_csv_auto()` paths to match production file locations
5. **Export results:** Use `COPY (query) TO 'results.csv'` to export validation results for documentation

**Example NULL-aware modification for Query 1.1:**
```sql
SELECT 
  stock_key, 
  COUNT(DISTINCT issuer_key) as issuer_count,
  COUNT(*) as row_count
FROM dim_stock
WHERE issuer_key IS NOT NULL  -- Exclude NULLs from cardinality check
GROUP BY stock_key
HAVING COUNT(DISTINCT issuer_key) > 1;
```

---

**End of Section 2: Relationship Proof SQL**
