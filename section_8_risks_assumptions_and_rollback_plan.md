# Section 8: Risks, Assumptions, and Rollback Plan

## Executive Summary

This section provides a comprehensive risk assessment, explicit assumptions documentation, mitigation strategies, and detailed rollback procedures for the 6-dimension to 1-dimension security schema consolidation. The analysis identifies **11 distinct risks** across data integrity, semantic correctness, performance, deployment, and scope categories. Each risk includes likelihood/impact assessment, preventative mitigation, and contingency planning.

**Risk Summary:**

| Risk Category | Risk Count | High Priority Risks | Mitigation Coverage |
|---------------|------------|---------------------|---------------------|
| Data Loss Risks | 2 | 1 (R01) | 100% (validation queries) |
| Semantic Change Risks | 3 | 2 (R04, R05) | 100% (22 validation tests) |
| Performance Regression Risks | 2 | 1 (R06) | 100% (12 benchmark queries) |
| Deployment Risks | 2 | 1 (R08) | 100% (rollback procedures) |
| Scope Risks | 2 | 1 (R10) | Partial (query inventory only) |

**Key Assumptions:**

- ✅ **Relationship Integrity:** All stock-to-dimension relationships are M:1 (validated by Section 2)
- ✅ **Data Quality:** No NULL foreign keys in `fact_equity_trade` security dimensions
- ✅ **Scope Coverage:** 30 benchmark queries represent all security dimension access patterns
- ⚠️ **Performance Assumption:** DuckDB query optimizer benefits from join reduction (to be validated)

**Deployment Recommendation:** **Dual-Run Approach** with parallel schema validation before cutover

**Rollback Trigger:** Any validation test failure OR performance regression > 10% on ≥3 queries

---

## 1. Risk Register

This section documents all identified risks with structured assessment and response planning.

---

### Risk Category 1: Data Loss Risks

These risks involve losing dimension attributes, fact relationships, or referential integrity during consolidation.

---

#### R01: Data Loss During Dimension Denormalization (HIGH PRIORITY)

**Description:**  
During population of `dim_security`, foreign key joins may fail to match all records, resulting in NULL denormalized attributes (e.g., `issuer_name`, `sector_name`). This could occur if:
- Source dimension data contains orphaned foreign key references
- JOIN logic in population SQL (Section 4) is incorrect
- Schema migration runs before all source dimensions are fully populated

**Likelihood:** **Medium**  
**Impact:** **High** (queries return incomplete results, breaking downstream analytics)

**Mitigation Strategy (Preventative):**
1. **Pre-Migration Validation:** Run Section 2 referential integrity queries (Query 2.1, 2.2, 2.3) before creating `dim_security`
   - Expected: 0 orphaned rows in all validation queries
   - Block migration if any orphaned references detected
2. **Population Validation:** After populating `dim_security`, run NULL check queries:
   ```sql
   -- Expected: 0 rows (all denormalized attributes populated)
   SELECT stock_key, ticker
   FROM dim_security
   WHERE issuer_name IS NULL 
      OR industry_name IS NULL 
      OR sector_name IS NULL
      OR exchange_name IS NULL
      OR currency_code IS NULL;
   ```
3. **Row Count Validation:** Verify `dim_security` row count matches `dim_stock` (expected: 30 rows)

**Contingency Plan (If Risk Materializes):**
1. Identify missing source records using orphaned key detection queries
2. Correct source dimension data (add missing records or fix foreign keys)
3. Re-run `dim_security` population SQL
4. Re-validate NULL checks and row counts
5. If correction fails, trigger **Rollback Procedure** (Section 3)

**Validation Test Reference:** Section 6, Test 1.2 (Join Integrity)

---

#### R02: Fact Table Foreign Key Integrity Violation

**Description:**  
After migrating `fact_equity_trade` to reference only `stock_key` (removing `issuer_key`, `industry_key`, `sector_key`, `exchange_key`, `currency_key`), any query that still attempts to join via old foreign keys will fail with "column does not exist" errors. This risk applies if:
- Query refactoring is incomplete (missed queries outside benchmark suite)
- Downstream tools/BI dashboards hard-code old dimension joins
- Automated processes reference legacy schema structure

**Likelihood:** **Low** (comprehensive query inventory in Section 3)  
**Impact:** **Medium** (queries fail but data integrity preserved)

**Mitigation Strategy (Preventative):**
1. **Comprehensive Query Audit:** Inventory all queries beyond 30 benchmark queries
   - Search codebase for `JOIN dim_issuer`, `JOIN dim_industry`, etc.
   - Review BI tool connection metadata for dimension references
2. **Dual Schema Period:** Keep legacy dimensions in read-only mode during transition
   - Fact table retains old foreign keys initially (as optional columns)
   - Allows gradual query migration without immediate breakage
3. **Deprecation Warnings:** Add database comments to legacy dimensions:
   ```sql
   COMMENT ON TABLE dim_issuer IS 'DEPRECATED: Use dim_security instead. Scheduled for removal on YYYY-MM-DD';
   ```

**Contingency Plan (If Risk Materializes):**
1. Identify failing queries via error logs
2. Refactor queries using Section 5 migration patterns
3. Re-test queries against new schema
4. If refactoring scope is too large, extend dual schema period or trigger rollback

**Validation Test Reference:** Section 3, Downstream Dependency Inventory (queries using security dimensions)

---

### Risk Category 2: Semantic Change Risks

These risks involve queries returning different results after migration, violating semantic equivalence.

---

#### R03: Indirect Join Path Changes

**Description:**  
Queries accessing `dim_sector` via `dim_industry.sector_key` (indirect join) may return different results if:
- Consolidation logic incorrectly maps `industry_name → sector_name`
- Multiple industry records map to same industry_name but different sector_key values (cardinality violation)
- Denormalization flattens hierarchical structure incorrectly

**Example Query:** Q09, Q14 (access sector via industry join)

**Likelihood:** **Low** (Section 2 validates M:1 relationships)  
**Impact:** **High** (queries return wrong sector classifications)

**Mitigation Strategy (Preventative):**
1. **Relationship Validation:** Run Section 2 cardinality tests (Query 1.7: Industry → Sector M:1)
   - Expected: 0 rows (each industry has exactly 1 sector)
   - Block migration if cardinality violations detected
2. **Functional Dependency Test:** Validate stock → industry → sector consistency:
   ```sql
   -- Expected: 0 rows (stock.industry_key → sector matches industry.industry_key → sector)
   SELECT s.stock_key, s.ticker
   FROM dim_stock s
   JOIN dim_industry ind1 ON s.industry_key = ind1.industry_key
   JOIN dim_industry ind2 ON s.industry_key = ind2.industry_key
   WHERE ind1.sector_key <> ind2.sector_key;
   ```
3. **Query Result Validation:** Run Section 6, Test 2.2 (Q09 Result Set Equivalence)

**Contingency Plan (If Risk Materializes):**
1. Identify discrepancies using EXCEPT queries (Section 6, Test 2.2)
2. Trace root cause to incorrect mapping in dim_security population logic
3. Correct population SQL JOIN logic
4. Re-populate dim_security
5. Re-run validation tests

**Validation Test Reference:** Section 6, Test 2.2 (Q09 Result Set Equivalence)

---

#### R04: Query Logic Errors During Refactoring (HIGH PRIORITY)

**Description:**  
Manual query refactoring introduces human errors such as:
- Incorrect column mapping (e.g., `ex.mic_code` → `sec.currency_code` instead of `sec.exchange_mic_code`)
- Missing WHERE clauses or altered filter logic
- Changed join types (INNER JOIN → LEFT JOIN or vice versa)
- Typos in denormalized column names

**Likelihood:** **High** (manual refactoring of 21 queries)  
**Impact:** **High** (queries return incorrect results)

**Mitigation Strategy (Preventative):**
1. **Automated Column Mapping Validation:** Create reference mapping table for all column transformations (provided in Section 5)
2. **Before/After Testing:** For each refactored query:
   - Run old query against current schema
   - Run new query against consolidated schema
   - Compare results using EXCEPT (Section 6 methodology)
3. **Peer Review:** Require code review of all refactored queries before deployment
4. **Automated Testing:** Integrate Section 6 validation queries into CI/CD pipeline

**Contingency Plan (If Risk Materializes):**
1. Validation tests (Section 6) will detect discrepancies
2. Review failed query using Section 5 column mapping reference
3. Correct refactoring errors
4. Re-run validation test
5. If widespread errors detected, pause migration and re-review all queries

**Validation Test Reference:** Section 6, Tests 2.1-2.3 (Query Result Set Equivalence)

---

#### R05: Anti-Pattern Elimination Changes Semantics (HIGH PRIORITY)

**Description:**  
Queries Q09 and Q22 contain redundant joins that **validate data consistency** (e.g., Q09 checks `sec.sector_name = sec2.sector_name`). Removing these redundant joins assumes the validation always passes. If source data contains inconsistencies, the consolidated schema will:
- **Hide data quality issues** (redundant joins no longer enforce consistency checks)
- **Return different row counts** if WHERE clause filters previously excluded inconsistent rows

**Example:**  
Q09 WHERE clause: `WHERE sec.sector_name = sec2.sector_name`
- If fact.industry_key → sector differs from stock.industry_key → sector, old query excludes those rows
- New query with single join path includes those rows (returns MORE data)

**Likelihood:** **Low** (Section 2 validates consistency, but edge cases may exist)  
**Impact:** **High** (changes query semantics)

**Mitigation Strategy (Preventative):**
1. **Consistency Validation:** Run explicit consistency check before migration:
   ```sql
   -- Expected: 0 rows (fact's security FKs match stock's security FKs)
   SELECT t.trade_id, t.stock_key, t.issuer_key, s.issuer_key AS stock_issuer
   FROM fact_equity_trade t
   JOIN dim_stock s ON t.stock_key = s.stock_key
   WHERE t.issuer_key <> s.issuer_key
      OR t.industry_key <> s.industry_key
      OR t.sector_key <> s.sector_key
      OR t.exchange_key <> s.exchange_key
      OR t.currency_key <> s.currency_key;
   ```
2. **Anti-Pattern Query Validation:** Run Section 6, Test 2.2 specifically for Q09 and Q22
3. **Document Assumption:** Explicitly document that anti-pattern removal assumes data consistency (see Section 2.2 Assumptions)

**Contingency Plan (If Risk Materializes):**
1. If consistency check returns rows, data correction required before migration
2. Options:
   - **Correct fact table foreign keys** to match stock dimension
   - **Adjust refactored queries** to preserve validation logic (defeats consolidation benefit)
   - **Accept semantic change** if inconsistent rows are known bad data (business decision)
3. If validation fails in production, rollback and correct data

**Validation Test Reference:** Section 6, Test 2.2 (Q09 Result Set Equivalence)

---

### Risk Category 3: Performance Regression Risks

These risks involve the consolidated schema performing worse than the current schema.

---

#### R06: Query Performance Degradation (HIGH PRIORITY)

**Description:**  
Despite eliminating joins, queries may perform **worse** if:
- **Denormalized table size** increases memory footprint (22 columns vs. 11 in dim_stock)
- **Missing indexes** on denormalized columns (e.g., `sector_name`, `industry_name`)
- **DuckDB optimizer** doesn't recognize join elimination benefits
- **Wide table scans** slower than narrow table scans
- **Cardinality estimation errors** due to correlated attributes in denormalized dimension

**Likelihood:** **Low** (Section 7 expects 25% improvement, but edge cases possible)  
**Impact:** **High** (defeats primary benefit of consolidation)

**Mitigation Strategy (Preventative):**
1. **Index Strategy:** Implement all 7 recommended indexes from Section 4.3 before benchmarking
   - `idx_security_ticker`, `idx_security_exchange_name`, `idx_security_sector_name`, etc.
2. **Benchmark Testing:** Run Section 7 performance tests with statistical rigor (10 runs per query)
3. **EXPLAIN Analysis:** For each benchmark query, compare EXPLAIN ANALYZE output:
   - Verify join count reduction reflected in query plans
   - Check for index usage on denormalized columns
   - Validate row scan counts
4. **Regression Thresholds:** Define acceptable regression tolerance (see Section 3.3 below)

**Contingency Plan (If Risk Materializes):**
1. If overall average improvement < 15% (below 25% target), investigate:
   - Missing indexes
   - DuckDB configuration settings (memory limits, parallelism)
   - Data skew or cardinality issues
2. If individual query regresses > 10%:
   - Analyze EXPLAIN output for root cause
   - Consider query-specific optimizations (hints, rewrites)
   - Potentially revert specific query to old schema (keep both schemas in dual-run)
3. If ≥3 queries regress > 10%, trigger **Rollback Procedure**

**Validation Test Reference:** Section 7, Performance Benchmark Suite (12 queries)

---

#### R07: Index Bloat and Maintenance Overhead

**Description:**  
The consolidated `dim_security` table requires **7 indexes** (1 PK + 6 secondary) compared to **6 indexes total** across old dimensions. This could result in:
- Increased storage requirements
- Slower INSERT/UPDATE operations (though dimensions are relatively static)
- Index maintenance overhead during data refreshes

**Likelihood:** **Medium** (indexes are required for query performance)  
**Impact:** **Low** (dimensions are read-heavy, updates infrequent)

**Mitigation Strategy (Preventative):**
1. **Selective Indexing:** Start with 4 essential indexes (PK + ticker + exchange_name + sector_name)
2. **Performance Monitoring:** Add additional indexes only if query performance analysis requires them
3. **Dimension Update Strategy:** If dim_security updates are frequent:
   - Consider partitioning by exchange or sector (if DuckDB supports)
   - Batch updates during off-peak hours
   - Disable indexes during bulk loads, rebuild after

**Contingency Plan (If Risk Materializes):**
1. Monitor index size and rebuild times
2. If maintenance overhead unacceptable, drop rarely-used indexes
3. Consider alternative optimization (materialized query results, summary tables)

**Validation Test Reference:** Section 4, Index Strategy (monitor index sizes and query performance impact)

---

### Risk Category 4: Deployment Risks

These risks involve migration process failures, downtime, or inability to rollback.

---

#### R08: Incomplete Migration Causing Partial Schema State (HIGH PRIORITY)

**Description:**  
If migration fails mid-process, the database may be left in an inconsistent state:
- `dim_security` partially populated
- Fact table foreign keys partially removed
- Some queries refactored, others still using old schema
- Indexes incomplete

This results in:
- Query failures (mix of old/new references)
- Data inconsistencies
- Inability to complete migration or rollback cleanly

**Likelihood:** **Medium** (DDL operations can fail, transaction management critical)  
**Impact:** **High** (production downtime, potential data corruption)

**Mitigation Strategy (Preventative):**
1. **Transactional DDL:** Wrap all schema changes in a single transaction (if DuckDB supports):
   ```sql
   BEGIN TRANSACTION;
     CREATE TABLE dim_security (...);
     INSERT INTO dim_security SELECT ...;
     CREATE INDEX idx_security_ticker ON dim_security(ticker);
     -- etc.
   COMMIT;
   ```
2. **Backup Before Migration:** Full database backup before any schema changes
3. **Dry-Run Validation:** Test migration on copy of production database
4. **Migration Checklist:** Use detailed step-by-step checklist (Section 3.5)
5. **Atomic Cutover:** Use schema versioning or database aliases to switch between old/new in one operation

**Contingency Plan (If Risk Materializes):**
1. Halt migration immediately
2. Restore from pre-migration backup (Section 3.2)
3. Investigate failure cause (disk space, permission, syntax error)
4. Correct issue and re-attempt migration
5. If cannot correct, abandon migration and retain old schema

**Validation Test Reference:** Section 3.5, Migration Execution Checklist

---

#### R09: Rollback Failure Due to Data Loss

**Description:**  
If rollback is triggered after legacy dimensions (`dim_stock`, `dim_issuer`, etc.) are **dropped**, restoration requires:
- Re-creating dimension tables
- Re-populating from backup or CSV sources
- Restoring fact table foreign key columns

Risk of rollback failure if:
- Backup files corrupted or inaccessible
- CSV source data out of sync with production
- Fact table foreign key columns dropped without backup

**Likelihood:** **Low** (if backup procedures followed)  
**Impact:** **High** (cannot restore original schema, forced to use consolidated schema with potential issues)

**Mitigation Strategy (Preventative):**
1. **Preserve Legacy Dimensions:** Do NOT drop old dimensions until validation passes (keep in dual-schema mode)
2. **Retain Fact Table FKs:** Keep `issuer_key`, `industry_key`, etc. as nullable columns during transition
3. **Verified Backups:** Test backup restoration on non-production environment before migration
4. **Rollback Window:** Define 30-day rollback window where all legacy objects remain in database

**Contingency Plan (If Risk Materializes):**
1. If legacy dimensions dropped and rollback needed:
   - Restore from most recent pre-migration backup (full database restore)
   - Accept downtime during restore process
2. If backup restore fails:
   - Re-create dimensions from CSV files (Section 4.1)
   - Re-populate fact table foreign keys from dim_stock relationships
   - Validate data integrity using Section 2 queries

**Validation Test Reference:** Section 3.2, Rollback Data Preservation Strategy

---

### Risk Category 5: Scope Risks

These risks involve undiscovered dependencies or assumptions proving false.

---

#### R10: Undiscovered Query Dependencies (HIGH PRIORITY)

**Description:**  
The 30 benchmark queries may not represent **all** actual query patterns in production. Risk that:
- Ad-hoc analyst queries use security dimensions in unexpected ways
- ETL pipelines reference dimensions not covered in benchmark
- Third-party BI tools generate queries dynamically
- Scheduled reports use dimension joins not in sample

**Likelihood:** **Medium** (benchmark is representative but not exhaustive)  
**Impact:** **Medium** (queries break in production, require emergency refactoring)

**Mitigation Strategy (Preventative):**
1. **Query Log Analysis:** Analyze production query logs for 30-60 days
   - Extract all queries using `JOIN dim_issuer`, `JOIN dim_industry`, etc.
   - Classify query patterns beyond 30 benchmarks
   - Identify high-frequency or business-critical queries
2. **Stakeholder Survey:** Interview data analysts, BI developers, ETL engineers
   - Ask about custom queries, reports, dashboards using security dimensions
   - Document any dimension usage not in benchmark suite
3. **Dual-Schema Period:** Run both old and new schemas in parallel for 2-4 weeks
   - Monitor which queries use which schema
   - Identify queries still using legacy dimensions
4. **Gradual Deprecation:** Warn users before dropping legacy dimensions

**Contingency Plan (If Risk Materializes):**
1. If undiscovered queries break in production:
   - Restore legacy dimensions from backup (Section 3.2)
   - Extend dual-schema period
   - Inventory and refactor discovered queries
   - Re-validate and re-deploy
2. If scope too large, abort consolidation

**Validation Test Reference:** Section 3, Downstream Dependency Inventory (30 queries may be incomplete)

---

#### R11: Foreign Key Relationship Assumptions Violated in Production

**Description:**  
Section 2 validation queries prove M:1 relationships on **current sample data** (30 stocks, 30 issuers, etc.). In production with millions of securities, assumptions may fail:
- Multi-listed stocks (same ticker on multiple exchanges) → stock:exchange is 1:M, not M:1
- Dual-currency trading (same stock trades in USD and local currency) → stock:currency is 1:M
- Conglomerate issuers (multi-industry classification) → issuer:industry is 1:M
- Industry reclassifications over time (historical dimension changes) → industry:sector is 1:M

**Likelihood:** **Low** (sample data designed to match production schema, but edge cases exist)  
**Impact:** **High** (consolidation grain incorrect, data loss occurs)

**Mitigation Strategy (Preventative):**
1. **Production Data Validation:** Run Section 2 cardinality tests on **full production dataset**
   - Query 1.1-1.7 (M:1 relationship validation)
   - If violations found, adjust consolidation grain (e.g., stock_key + exchange_key)
2. **Historical Data Analysis:** Check for temporal dimension changes
   - Industries reassigned to different sectors over time
   - Stocks changing exchanges (dual-listed)
3. **Business Rule Validation:** Confirm with business stakeholders:
   - "Can a stock trade on multiple exchanges?" (if yes, grain adjustment needed)
   - "Can an issuer span multiple industries?" (if yes, many-to-many requires bridge table)

**Contingency Plan (If Risk Materializes):**
1. If M:1 violations detected in production:
   - **Option A:** Adjust grain to composite key (stock_key, exchange_key, currency_key)
   - **Option B:** Use SCD Type 2 (add effective_date, end_date to track historical changes)
   - **Option C:** Accept data loss (e.g., pick "primary" exchange per stock, ignore secondary listings)
2. Re-run consolidation design and validation with adjusted grain
3. If cardinality violations widespread, abort consolidation

**Validation Test Reference:** Section 2, Cardinality Validation Queries (run on production data, not just sample)

---

## 2. Assumptions Documentation

This section explicitly documents all assumptions made throughout the implementation plan, with validation strategies and business confirmation requirements.

---

### 2.1 Relationship Integrity Assumptions

These assumptions underpin the feasibility of lossless consolidation.

---

#### A01: Stock → Issuer is Many-to-One

**Assumption Statement:**  
Each stock (`stock_key`) maps to exactly **one** issuer (`issuer_key`). Multiple stocks can belong to the same issuer (e.g., Class A, Class B shares), but each stock has only one issuing company.

**Business Implication:**  
Consolidation can denormalize `issuer_name` into `dim_security` without data loss.

**Validation Strategy:**  
Run Section 2, Query 1.1:
```sql
-- Expected: 0 rows (each stock has exactly 1 issuer)
SELECT stock_key, COUNT(DISTINCT issuer_key) as issuer_count
FROM dim_stock
GROUP BY stock_key
HAVING COUNT(DISTINCT issuer_key) > 1;
```

**Validation Status:** ✅ **VALIDATED** (Section 2 confirms 0 violations in sample data)

**Risk if False:** R11 (Foreign Key Relationship Assumptions Violated)

**Business Confirmation Required:** ✅ Yes - Confirm with equity data team: "Can a single stock_key represent securities from multiple issuers?"

---

#### A02: Stock → Exchange is Many-to-One

**Assumption Statement:**  
Each stock trades on exactly **one** primary exchange. Multi-listed securities (same company on NYSE and LSE) are treated as **separate stock_key values** with different exchange_key.

**Business Implication:**  
Consolidation denormalizes `exchange_name` per stock without ambiguity.

**Validation Strategy:**  
Run Section 2, Query 1.4:
```sql
-- Expected: 0 rows (each stock has exactly 1 exchange)
SELECT stock_key, COUNT(DISTINCT exchange_key) as exchange_count
FROM dim_stock
GROUP BY stock_key
HAVING COUNT(DISTINCT exchange_key) > 1;
```

**Validation Status:** ✅ **VALIDATED** (Section 2 confirms 0 violations)

**Risk if False:** R11 (grain adjustment required to stock_key + exchange_key composite)

**Business Confirmation Required:** ✅ Yes - Confirm: "Are multi-listed securities assigned separate stock_key values for each exchange?"

---

#### A03: Stock → Currency is Many-to-One

**Assumption Statement:**  
Each stock trades in exactly **one** primary currency. Dual-currency stocks (e.g., HKD and USD listings) are separate stock_key values.

**Business Implication:**  
Consolidation denormalizes `currency_code` per stock.

**Validation Strategy:**  
Run Section 2, Query 1.5:
```sql
-- Expected: 0 rows (each stock has exactly 1 currency)
SELECT stock_key, COUNT(DISTINCT currency_key) as currency_count
FROM dim_stock
GROUP BY stock_key
HAVING COUNT(DISTINCT currency_key) > 1;
```

**Validation Status:** ✅ **VALIDATED** (Section 2 confirms 0 violations)

**Risk if False:** R11 (grain adjustment required)

**Business Confirmation Required:** ✅ Yes - Confirm: "Are dual-currency stocks assigned separate stock_key values?"

---

#### A04: Issuer → Industry is Many-to-One

**Assumption Statement:**  
Each issuer (company) is classified into exactly **one** industry. Conglomerates are assigned a primary industry classification.

**Business Implication:**  
Denormalized `industry_name` in `dim_security` is deterministic per issuer.

**Validation Strategy:**  
Run Section 2, Query 1.6:
```sql
-- Expected: 0 rows (each issuer has exactly 1 industry)
SELECT issuer_key, COUNT(DISTINCT industry_key) as industry_count
FROM dim_issuer
GROUP BY issuer_key
HAVING COUNT(DISTINCT industry_key) > 1;
```

**Validation Status:** ✅ **VALIDATED** (Section 2 confirms 0 violations)

**Risk if False:** R03 (Indirect Join Path Changes - issuer → industry mapping ambiguous)

**Business Confirmation Required:** ⚠️ Moderate Priority - Confirm: "Are conglomerates assigned a single primary industry, or do they have multiple industry classifications?"

---

#### A05: Industry → Sector is Many-to-One

**Assumption Statement:**  
Each industry belongs to exactly **one** sector. Industries do not span multiple sectors.

**Business Implication:**  
Hierarchical relationship `stock → industry → sector` collapses cleanly into flat `dim_security`.

**Validation Strategy:**  
Run Section 2, Query 1.7:
```sql
-- Expected: 0 rows (each industry has exactly 1 sector)
SELECT industry_key, COUNT(DISTINCT sector_key) as sector_count
FROM dim_industry
GROUP BY industry_key
HAVING COUNT(DISTINCT sector_key) > 1;
```

**Validation Status:** ✅ **VALIDATED** (Section 2 confirms 0 violations)

**Risk if False:** R03 (Indirect Join Path Changes - sector ambiguous per industry)

**Business Confirmation Required:** ✅ Yes - Confirm: "Is the industry-to-sector hierarchy strictly maintained (each industry has exactly one parent sector)?"

---

### 2.2 Data Quality Assumptions

These assumptions ensure referential integrity and completeness.

---

#### A06: No NULL Foreign Keys in fact_equity_trade

**Assumption Statement:**  
All foreign key columns in `fact_equity_trade` are **NOT NULL** for security dimensions:
- `stock_key NOT NULL`
- `issuer_key NOT NULL`
- `industry_key NOT NULL`
- `sector_key NOT NULL`
- `exchange_key NOT NULL`
- `currency_key NOT NULL`

**Business Implication:**  
Every trade can be joined to `dim_security` without losing rows due to NULL joins.

**Validation Strategy:**  
```sql
-- Expected: 0 rows (no NULL security foreign keys)
SELECT COUNT(*) as null_count
FROM fact_equity_trade
WHERE stock_key IS NULL
   OR issuer_key IS NULL
   OR industry_key IS NULL
   OR sector_key IS NULL
   OR exchange_key IS NULL
   OR currency_key IS NULL;
```

**Validation Status:** ⚠️ **TO BE VALIDATED** (not explicitly tested in Section 2)

**Risk if False:** R01 (Data Loss During Denormalization - NULL joins result in missing attributes)

**Business Confirmation Required:** ✅ Yes - Confirm: "Are security foreign keys mandatory in fact_equity_trade schema?"

---

#### A07: Referential Integrity Enforced

**Assumption Statement:**  
All foreign keys in `dim_stock` reference valid records in parent dimensions (no orphaned references):
- `issuer_key → dim_issuer.issuer_key`
- `industry_key → dim_industry.industry_key`
- `sector_key → dim_sector.sector_key`
- `exchange_key → dim_exchange.exchange_key`
- `currency_key → dim_currency.currency_key`

**Business Implication:**  
Population SQL for `dim_security` (Section 4) will successfully join and denormalize all attributes.

**Validation Strategy:**  
Run Section 2, Query 2.1:
```sql
-- Expected: 0 rows (all foreign keys valid)
SELECT s.stock_key, s.ticker, ...
FROM dim_stock s
LEFT JOIN dim_issuer i ON s.issuer_key = i.issuer_key
-- ... (joins to all dimensions)
WHERE i.issuer_key IS NULL OR ind.industry_key IS NULL ... ;
```

**Validation Status:** ✅ **VALIDATED** (Section 2, Query 2.1)

**Risk if False:** R01 (Data Loss - orphaned FKs result in NULL denormalized attributes)

**Business Confirmation Required:** ✅ Yes - Confirm: "Are foreign key constraints enforced at database level, or is referential integrity maintained by ETL processes?"

---

#### A08: Fact Table Foreign Keys Are Consistent with Stock Dimension

**Assumption Statement:**  
For every row in `fact_equity_trade`, the foreign keys `issuer_key`, `industry_key`, `sector_key`, `exchange_key`, `currency_key` **match** the corresponding foreign keys in `dim_stock` for that `stock_key`:

```sql
-- Expected: 0 rows (fact FKs match stock FKs)
SELECT t.trade_id
FROM fact_equity_trade t
JOIN dim_stock s ON t.stock_key = s.stock_key
WHERE t.issuer_key <> s.issuer_key
   OR t.industry_key <> s.industry_key
   OR t.sector_key <> s.sector_key
   OR t.exchange_key <> s.exchange_key
   OR t.currency_key <> s.currency_key;
```

**Business Implication:**  
This assumption justifies **removing 5 redundant foreign keys** from `fact_equity_trade`. If assumption is false, fact table contains overrides or historical variations that would be lost.

**Validation Status:** ⚠️ **CRITICAL - TO BE VALIDATED** (not explicitly tested in Section 2)

**Risk if False:** R05 (Anti-Pattern Elimination Changes Semantics - Q09 WHERE clause currently filters out inconsistent rows)

**Business Confirmation Required:** ✅ **CRITICAL** - Confirm: "Do fact table foreign keys ever differ from stock dimension foreign keys (e.g., for historical accuracy, overrides, or trade-specific classifications)?"

**Mitigation if False:**  
- **Option A:** Retain fact table foreign keys (do not simplify fact table schema)
- **Option B:** Create exception handling for inconsistent rows
- **Option C:** Correct fact table data to enforce consistency before migration

---

### 2.3 Scope Assumptions

These assumptions define the boundaries of the migration effort.

---

#### A09: 30 Benchmark Queries Represent All Query Patterns

**Assumption Statement:**  
The 30 queries in `benchmark/benchmark_queries.sql` are **representative** of all production query patterns that access security dimensions. No significant query patterns exist outside this sample.

**Business Implication:**  
Query refactoring effort (Section 5) and validation coverage (Section 6) are sufficient for production deployment.

**Validation Strategy:**  
- Analyze production query logs for 30-60 days (see R10 mitigation)
- Compare production queries to benchmark patterns
- Identify any new patterns (e.g., recursive CTEs, window functions with dimension partitions)

**Validation Status:** ⚠️ **PARTIALLY VALIDATED** (benchmark designed as anti-pattern collection, but production may have additional patterns)

**Risk if False:** R10 (Undiscovered Query Dependencies - production queries break after migration)

**Business Confirmation Required:** ✅ Yes - Confirm: "Have all critical production queries, BI dashboards, and ETL pipelines been inventoried and mapped to the 30 benchmark queries?"

---

#### A10: No Downstream Materialized Views or Derived Tables

**Assumption Statement:**  
No materialized views, summary tables, or ETL-derived tables **depend on** the 6 security dimensions being consolidated. All downstream dependencies are limited to the 30 benchmark queries.

**Business Implication:**  
Migration scope is limited to query refactoring; no complex dependency chains to untangle.

**Validation Strategy:**  
Query database metadata for:
- Materialized views referencing `dim_stock`, `dim_issuer`, etc.
- Tables created by `CREATE TABLE AS SELECT (CTAS)` from security dimensions
- ETL scripts that populate derived tables from dimension joins

```sql
-- Example metadata query (DuckDB syntax - adjust for your DB)
SELECT table_name, view_definition
FROM information_schema.views
WHERE view_definition LIKE '%dim_issuer%'
   OR view_definition LIKE '%dim_industry%'
   OR view_definition LIKE '%dim_sector%'
   OR view_definition LIKE '%dim_exchange%'
   OR view_definition LIKE '%dim_currency%';
```

**Validation Status:** ⚠️ **TO BE VALIDATED** (not covered in Section 3 inventory)

**Risk if False:** R10 (Scope expansion - materialized views must be refactored, potentially large migration effort)

**Business Confirmation Required:** ✅ Yes - Confirm: "Are there any materialized views, summary tables, or derived datasets built from security dimension joins?"

---

### 2.4 Tooling and Performance Assumptions

These assumptions relate to DuckDB behavior and performance characteristics.

---

#### A11: DuckDB Query Optimizer Benefits from Join Reduction

**Assumption Statement:**  
DuckDB's query optimizer will achieve **faster query execution** when joins are reduced from 6 dimensions to 1 dimension, even though `dim_security` is a wider table (22 columns vs. 11 in `dim_stock`).

**Performance Mechanism:**  
- Fewer join operations → reduced CPU cycles for hash table builds
- Fewer table scans → reduced I/O
- Simpler query plans → better optimizer decisions
- Denormalized data locality → cache efficiency

**Validation Strategy:**  
Run Section 7 performance benchmarks:
- 12 representative queries
- 10 runs per query for statistical validity
- Compare median execution time before/after
- Target: ≥25% average improvement

**Validation Status:** ⚠️ **TO BE VALIDATED** (assumption based on general OLAP optimization principles, but DuckDB-specific behavior unknown)

**Risk if False:** R06 (Query Performance Degradation - wider table scans negate join reduction benefits)

**Business Confirmation Required:** ⚠️ Optional - Recommend: "Run proof-of-concept performance tests on representative production data volumes before committing to full migration."

**Mitigation if False:**  
- Add indexes to denormalized columns (Section 4 recommends 6 secondary indexes)
- Use columnar storage compression (DuckDB default)
- Consider partial consolidation (e.g., consolidate only issuer/industry/sector, keep exchange/currency separate)

---

#### A12: Dimension Data is Relatively Static

**Assumption Statement:**  
Security dimension data changes **infrequently** (e.g., new stocks added monthly, industry reclassifications rare). This means:
- Index maintenance overhead is low
- Denormalized data rarely becomes stale
- `dim_security` can be refreshed in batch (not real-time streaming)

**Business Implication:**  
7 indexes on `dim_security` are acceptable (won't slow down INSERT/UPDATE operations significantly).

**Validation Strategy:**  
Analyze dimension update frequency:
- Historical change rate for `dim_stock` (rows added/updated per month)
- Industry/sector reclassification frequency
- Exchange listing changes

**Validation Status:** ✅ **ASSUMED VALID** (typical of equity dimension tables, but should be confirmed)

**Risk if False:** R07 (Index Bloat and Maintenance Overhead - frequent updates slow down refresh processes)

**Business Confirmation Required:** ⚠️ Moderate Priority - Confirm: "What is the typical update frequency for security dimension data (daily, weekly, monthly)?"

---

## 3. Rollback Plan

This section provides detailed, step-by-step procedures to revert to the original 6-dimension schema if migration validation fails or performance regressions occur.

---

### 3.1 Rollback Trigger Criteria

Rollback is **REQUIRED** if any of the following conditions occur:

| Trigger ID | Condition | Severity | Auto-Rollback |
|------------|-----------|----------|---------------|
| **T01** | Any Section 6 validation test returns discrepancies > 0 rows | CRITICAL | Yes |
| **T02** | Overall average performance improvement < 0% (net regression) | HIGH | Yes |
| **T03** | ≥3 benchmark queries show performance regression > 10% | HIGH | Manual Decision |
| **T04** | Row count mismatch between old/new schema (Section 6, Test 1.1) | CRITICAL | Yes |
| **T05** | Production query failure rate > 5% in first 24 hours | CRITICAL | Yes |
| **T06** | Data integrity violation detected (Section 2 cardinality tests fail on production data) | CRITICAL | Yes |
| **T07** | Business stakeholder rejects consolidated schema (usability, reporting issues) | MEDIUM | Manual Decision |

**Rollback Decision Matrix:**

| Condition | Action |
|-----------|--------|
| 1+ CRITICAL trigger | **Immediate rollback required** |
| 2+ HIGH triggers | **Rollback recommended** |
| 1 HIGH trigger + 1 MEDIUM trigger | **Rollback recommended** |
| 1 HIGH trigger only | **Manual assessment** (may proceed with mitigation) |
| Only MEDIUM triggers | **Proceed with caution** (monitor closely) |

---

### 3.2 Rollback Data Preservation Strategy

To enable clean rollback, the following data preservation rules **MUST** be followed during migration:

#### Phase 1: Pre-Migration (Before Any Schema Changes)

1. **Full Database Backup:**
   ```bash
   # DuckDB backup (export to Parquet)
   duckdb production.db -c "EXPORT DATABASE 'backup_YYYYMMDD_HHMMSS' (FORMAT PARQUET)"
   ```
   - Store backup in isolated location (separate storage system)
   - Verify backup integrity by restoring to test environment
   - Retention: Keep backup for 90 days post-migration

2. **Baseline Performance Metrics:**
   - Run Section 7 benchmarks on current schema
   - Record execution times, row counts, EXPLAIN plans
   - Save results as `baseline_performance_YYYYMMDD.json`

3. **Baseline Validation Results:**
   - Run Section 6 validation tests on current schema (should all PASS)
   - Save results as `baseline_validation_YYYYMMDD.log`

#### Phase 2: During Migration (Dual-Schema Period)

1. **Preserve Legacy Dimensions (DO NOT DROP):**
   ```sql
   -- Mark as deprecated but KEEP tables
   COMMENT ON TABLE dim_stock IS 'DEPRECATED - Use dim_security. Retained for rollback. Delete after 2025-XX-XX';
   COMMENT ON TABLE dim_issuer IS 'DEPRECATED - Use dim_security. Retained for rollback. Delete after 2025-XX-XX';
   -- ... repeat for all 5 dimensions
   ```

2. **Preserve Fact Table Foreign Keys (DO NOT DROP):**
   ```sql
   -- Keep old FKs as nullable columns during transition
   ALTER TABLE fact_equity_trade RENAME COLUMN issuer_key TO issuer_key_legacy;
   ALTER TABLE fact_equity_trade RENAME COLUMN industry_key TO industry_key_legacy;
   ALTER TABLE fact_equity_trade RENAME COLUMN sector_key TO sector_key_legacy;
   ALTER TABLE fact_equity_trade RENAME COLUMN exchange_key TO exchange_key_legacy;
   ALTER TABLE fact_equity_trade RENAME COLUMN currency_key TO currency_key_legacy;
   
   -- Queries now use only stock_key to join dim_security
   ```

3. **Dual-Schema Validation Period:**
   - Both old dimensions AND `dim_security` exist simultaneously
   - Old queries continue to work (using legacy FKs)
   - New queries use `dim_security`
   - Duration: **14-30 days** (business decision based on confidence)

#### Phase 3: Post-Migration (Validation Passed)

1. **Conditional Cleanup (Only After Validation Success):**
   ```sql
   -- ONLY execute if all validation tests PASS and performance targets met
   DROP TABLE dim_stock;        -- After 30-day rollback window
   DROP TABLE dim_issuer;       -- After 30-day rollback window
   DROP TABLE dim_industry;     -- After 30-day rollback window
   DROP TABLE dim_sector;       -- After 30-day rollback window
   DROP TABLE dim_exchange;     -- After 30-day rollback window
   DROP TABLE dim_currency;     -- After 30-day rollback window
   
   ALTER TABLE fact_equity_trade DROP COLUMN issuer_key_legacy;
   ALTER TABLE fact_equity_trade DROP COLUMN industry_key_legacy;
   ALTER TABLE fact_equity_trade DROP COLUMN sector_key_legacy;
   ALTER TABLE fact_equity_trade DROP COLUMN exchange_key_legacy;
   ALTER TABLE fact_equity_trade DROP COLUMN currency_key_legacy;
   ```

2. **Delete Backup (After 90-Day Retention):**
   - Backup retained for 90 days post-migration
   - Delete only if no issues reported in production

---

### 3.3 Rollback Procedure: Step-by-Step

#### Scenario A: Rollback During Dual-Schema Period (Legacy Dimensions Still Exist)

**Estimated Time:** 2-4 hours  
**Downtime Required:** Minimal (query-level rollback, no schema changes)

**Steps:**

1. **Halt New Query Deployment** (Immediate - 0 minutes)
   - Stop deploying refactored queries to production
   - Notify all developers/analysts to use legacy dimension joins
   - Update query routing to point to old schema

2. **Revert Refactored Queries** (1-2 hours)
   - Restore original query definitions from version control
   - For each refactored query in Section 5:
     - Replace `JOIN dim_security sec` with original multi-dimension joins
     - Restore original column references (Section 5 "Before SQL")
   - Deploy reverted queries to production

3. **Validate Rollback** (30 minutes)
   - Run Section 6 validation tests on restored queries
   - Expected: All tests PASS (same as pre-migration baseline)
   - If validation fails, investigate discrepancies

4. **Drop `dim_security` Table** (5 minutes)
   ```sql
   DROP TABLE IF EXISTS dim_security CASCADE;
   ```

5. **Restore Fact Table Foreign Keys** (10 minutes)
   ```sql
   -- If legacy FKs were renamed (not dropped), restore names
   ALTER TABLE fact_equity_trade RENAME COLUMN issuer_key_legacy TO issuer_key;
   ALTER TABLE fact_equity_trade RENAME COLUMN industry_key_legacy TO industry_key;
   ALTER TABLE fact_equity_trade RENAME COLUMN sector_key_legacy TO sector_key;
   ALTER TABLE fact_equity_trade RENAME COLUMN exchange_key_legacy TO exchange_key;
   ALTER TABLE fact_equity_trade RENAME COLUMN currency_key_legacy TO currency_key;
   ```

6. **Remove Deprecation Comments** (5 minutes)
   ```sql
   COMMENT ON TABLE dim_stock IS NULL;
   COMMENT ON TABLE dim_issuer IS NULL;
   -- ... repeat for all dimensions
   ```

7. **Post-Rollback Validation** (1 hour)
   - Run full Section 6 validation suite
   - Run Section 7 performance benchmarks
   - Compare to baseline metrics
   - Confirm rollback successful

8. **Root Cause Analysis** (Ongoing)
   - Document why rollback was triggered
   - Analyze validation failures or performance regressions
   - Determine if consolidation is feasible with adjustments
   - Decision: Re-attempt migration after fixes OR abandon consolidation

**Rollback Success Criteria:**
- ✅ All Section 6 validation tests PASS
- ✅ Performance matches baseline (±5% tolerance)
- ✅ No query failures in production
- ✅ Legacy schema fully operational

---

#### Scenario B: Rollback After Legacy Dimensions Dropped (Full Restore Required)

**Estimated Time:** 4-8 hours  
**Downtime Required:** 2-4 hours (full database restore)

**Steps:**

1. **Declare Emergency Rollback** (Immediate - 0 minutes)
   - Notify all stakeholders of rollback in progress
   - Set database to read-only mode (prevent new writes during restore)
   ```sql
   -- DuckDB: Close all write connections
   -- Set application layer to read-only mode
   ```

2. **Restore Full Database from Backup** (2-4 hours, depending on data size)
   ```bash
   # DuckDB restore from Parquet export
   duckdb production_restored.db -c "IMPORT DATABASE 'backup_YYYYMMDD_HHMMSS'"
   
   # Verify row counts match
   duckdb production_restored.db -c "SELECT COUNT(*) FROM fact_equity_trade"
   duckdb production_restored.db -c "SELECT COUNT(*) FROM dim_stock"
   # ... verify all tables
   ```

3. **Restore Legacy Queries** (1-2 hours)
   - Deploy original query definitions from version control (pre-migration)
   - Validate each query returns expected results
   - Update application connection strings to `production_restored.db`

4. **Cutover to Restored Database** (30 minutes)
   - Rename databases:
     ```bash
     mv production.db production_failed.db
     mv production_restored.db production.db
     ```
   - Restart application services pointing to `production.db`
   - Set database to read-write mode

5. **Post-Restore Validation** (1-2 hours)
   - Run Section 6 validation suite on restored database
   - Run Section 7 performance benchmarks
   - Compare to baseline (should be identical)
   - Monitor query logs for errors

6. **Incremental Data Catch-Up** (Variable - depends on how much time elapsed)
   - If migration ran for days/weeks before rollback:
     - Identify any new data written to consolidated schema during migration period
     - Re-load fact table data for time period between backup and rollback
     - Re-populate dimensions if new stocks/issuers added
   - Use ETL processes to backfill missing data

7. **Post-Rollback Analysis** (Ongoing)
   - Document rollback reasons and lessons learned
   - Assess feasibility of re-attempting migration
   - Consider alternative approaches (partial consolidation, different grain)

**Rollback Success Criteria:**
- ✅ Database restored to pre-migration state
- ✅ All tables present with correct row counts
- ✅ Section 6 validation tests match baseline
- ✅ Section 7 performance matches baseline
- ✅ No data loss (incremental catch-up completed)
- ✅ Production queries operational with < 1% error rate

---

### 3.4 Rollback Testing Requirements

Before executing production migration, the rollback procedure **MUST** be tested:

1. **Dry-Run Rollback on Staging:**
   - Create staging environment with copy of production data
   - Execute full migration (create `dim_security`, refactor queries)
   - Simulate rollback trigger (e.g., manually fail a validation test)
   - Execute Scenario A rollback procedure
   - Validate rollback success

2. **Full Restore Test:**
   - On separate test environment, create backup of staging database
   - Drop legacy dimensions (simulate Scenario B)
   - Execute Scenario B rollback (full restore from backup)
   - Validate restore success and data integrity

3. **Rollback Documentation Review:**
   - Technical team reviews rollback steps for completeness
   - DBA confirms backup/restore procedures are accurate
   - Application team confirms query reversion process
   - Business stakeholders approve rollback timeline and downtime estimates

**Rollback Readiness Checklist:**

- [ ] Full database backup created and verified (can be restored)
- [ ] Legacy dimensions preserved (not dropped during migration)
- [ ] Fact table legacy FKs preserved (renamed, not dropped)
- [ ] Rollback procedure tested on staging environment
- [ ] Rollback trigger criteria documented and approved
- [ ] Rollback decision-makers identified (DBA, Tech Lead, Business Owner)
- [ ] Rollback communication plan defined (stakeholder notification)
- [ ] Post-rollback validation tests prepared (Section 6, Section 7)
- [ ] Root cause analysis template ready for rollback investigation

---

### 3.5 Migration Execution Checklist

This checklist ensures migration follows a controlled, reversible process.

#### Pre-Migration Phase (T-7 days before migration)

- [ ] **Data Validation:**
  - [ ] Run Section 2 cardinality tests on production data (confirm all M:1 relationships)
  - [ ] Run Section 2 referential integrity tests (confirm no orphaned FKs)
  - [ ] Run Section 6 baseline validation on current schema (establish baseline results)
  - [ ] Run Section 7 baseline performance benchmarks (establish baseline timings)

- [ ] **Backup Preparation:**
  - [ ] Create full database backup
  - [ ] Verify backup integrity (restore to test environment, validate row counts)
  - [ ] Document backup location and restore procedure

- [ ] **Stakeholder Communication:**
  - [ ] Notify business stakeholders of migration timeline
  - [ ] Schedule migration during low-traffic window (if applicable)
  - [ ] Identify rollback decision-makers and contact info
  - [ ] Prepare rollback communication templates

#### Migration Execution Phase (Day 0)

- [ ] **Schema Creation (30 minutes):**
  - [ ] Create `dim_security` table (Section 4 DDL)
  - [ ] Populate `dim_security` using Section 4 population SQL
  - [ ] Validate row count: `SELECT COUNT(*) FROM dim_security` = 30 (or expected production count)
  - [ ] Run NULL attribute check:
    ```sql
    SELECT COUNT(*) FROM dim_security 
    WHERE issuer_name IS NULL OR industry_name IS NULL OR sector_name IS NULL 
       OR exchange_name IS NULL OR currency_code IS NULL;
    ```
    Expected: 0 rows

- [ ] **Index Creation (15 minutes):**
  - [ ] Create primary key index (stock_key)
  - [ ] Create 6 secondary indexes (Section 4.3: ticker, exchange_name, sector_name, industry_name, currency_code, issuer_name)
  - [ ] Validate indexes created: `SHOW INDEXES FROM dim_security`

- [ ] **Fact Table Foreign Key Preservation (10 minutes):**
  - [ ] Rename legacy FKs (not drop):
    ```sql
    ALTER TABLE fact_equity_trade RENAME COLUMN issuer_key TO issuer_key_legacy;
    ALTER TABLE fact_equity_trade RENAME COLUMN industry_key TO industry_key_legacy;
    ALTER TABLE fact_equity_trade RENAME COLUMN sector_key TO sector_key_legacy;
    ALTER TABLE fact_equity_trade RENAME COLUMN exchange_key TO exchange_key_legacy;
    ALTER TABLE fact_equity_trade RENAME COLUMN currency_key TO currency_key_legacy;
    ```

- [ ] **Query Refactoring (2-4 hours):**
  - [ ] Deploy refactored queries using Section 5 migration mappings
  - [ ] For each of 21 affected queries:
    - [ ] Replace multi-dimension joins with single `dim_security` join
    - [ ] Update column references (e.g., `i.issuer_name` → `sec.issuer_name`)
    - [ ] Preserve WHERE, GROUP BY, ORDER BY clauses exactly
  - [ ] Leave 9 unaffected queries unchanged (Q02, Q05, Q06, Q10, Q13, Q18, Q20, Q21, Q24, Q27)

- [ ] **Validation Phase (2-3 hours):**
  - [ ] Run Section 6 validation suite (all 22 tests):
    - [ ] Test 1.1: Fact table row count (expected: 0 difference)
    - [ ] Test 1.2: Join integrity (expected: 0 orphaned keys)
    - [ ] Tests 2.1-2.3: Query result set equivalence (expected: 0 discrepancies)
    - [ ] Tests 3.1-3.4: Aggregate validation (expected: 0 difference)
    - [ ] Tests 4.1-4.5: Dimension attribute validation (expected: PASS)
    - [ ] Tests 5.1-5.8: Sample query validation (expected: 0 discrepancies)
  - [ ] **Decision Point:** If ANY test fails → **TRIGGER ROLLBACK**

- [ ] **Performance Benchmarking (1-2 hours):**
  - [ ] Run Section 7 benchmark suite (12 queries, 10 runs each)
  - [ ] Calculate median execution time per query
  - [ ] Calculate overall average improvement percentage
  - [ ] **Decision Point:** 
    - [ ] If overall improvement < 0% → **TRIGGER ROLLBACK**
    - [ ] If ≥3 queries regress > 10% → **MANUAL DECISION** (review with stakeholders)

#### Post-Migration Monitoring Phase (Days 1-30)

- [ ] **Day 1 Monitoring:**
  - [ ] Monitor query error rate (target: < 1%)
  - [ ] Monitor query performance (compare to baseline)
  - [ ] Review application logs for dimension join errors
  - [ ] Collect user feedback (analysts, BI developers)

- [ ] **Week 1 Validation:**
  - [ ] Re-run Section 6 validation suite on production workload
  - [ ] Re-run Section 7 performance benchmarks with production data volumes
  - [ ] Analyze query patterns to detect undiscovered dependencies

- [ ] **Week 2-4 Stabilization:**
  - [ ] Address any minor issues (query optimizations, index tuning)
  - [ ] Document any discovered edge cases
  - [ ] Prepare for legacy dimension cleanup

- [ ] **Day 30 Cleanup (If Validation Success):**
  - [ ] **Final Decision:** Confirm migration success with stakeholders
  - [ ] Drop legacy dimensions:
    ```sql
    DROP TABLE dim_stock CASCADE;
    DROP TABLE dim_issuer CASCADE;
    DROP TABLE dim_industry CASCADE;
    DROP TABLE dim_sector CASCADE;
    DROP TABLE dim_exchange CASCADE;
    DROP TABLE dim_currency CASCADE;
    ```
  - [ ] Drop legacy fact table FKs:
    ```sql
    ALTER TABLE fact_equity_trade DROP COLUMN issuer_key_legacy;
    ALTER TABLE fact_equity_trade DROP COLUMN industry_key_legacy;
    ALTER TABLE fact_equity_trade DROP COLUMN sector_key_legacy;
    ALTER TABLE fact_equity_trade DROP COLUMN exchange_key_legacy;
    ALTER TABLE fact_equity_trade DROP COLUMN currency_key_legacy;
    ```
  - [ ] Update database documentation to reflect new schema
  - [ ] Archive migration documentation and rollback procedures

---

## 4. Deployment Strategy Options

This section evaluates three deployment approaches with pros/cons analysis and provides a recommended strategy.

---

### 4.1 Option 1: Dual-Run Approach (Parallel Schemas)

#### Description

Run both the old 6-dimension schema and the new consolidated `dim_security` schema **in parallel** for a validation period (14-30 days). Queries are gradually migrated from old to new schema, with continuous result comparison to ensure semantic equivalence.

#### Implementation Steps

1. **Schema Coexistence:**
   - Create `dim_security` alongside legacy dimensions (do not drop old tables)
   - Fact table retains all 6 foreign keys (stock_key, issuer_key, industry_key, sector_key, exchange_key, currency_key)
   - Both old and new queries can execute simultaneously

2. **Query Migration Strategy:**
   - **Phase 1 (Days 1-7):** Migrate low-impact queries (Q03, Q07, Q11, Q15, Q23, Q29 - simple single-dimension joins)
   - **Phase 2 (Days 8-14):** Migrate medium complexity queries (Q08, Q12, Q14, Q16, Q17, Q22, Q25, Q26, Q28, Q30)
   - **Phase 3 (Days 15-21):** Migrate high complexity queries (Q01, Q04, Q09, Q19)
   - **Phase 4 (Days 22-30):** Monitor all queries, validate results

3. **Validation Mechanism:**
   - For each migrated query, run both old and new versions
   - Compare results using Section 6 EXCEPT methodology
   - Log any discrepancies for investigation
   - Roll back individual queries if discrepancies detected

4. **Performance Comparison:**
   - Track execution time for both old and new query versions
   - Calculate improvement percentage per query
   - Identify any performance regressions early

5. **Cutover:**
   - After 30-day dual-run period with zero discrepancies:
     - Drop legacy dimensions
     - Remove fact table legacy foreign keys
     - Decommission old query definitions

#### Pros

| Benefit | Impact |
|---------|--------|
| **Zero-downtime migration** | Queries continue to work during entire migration period |
| **Incremental risk** | Queries migrated one at a time; issues isolated to individual queries |
| **Continuous validation** | Every query validated in production with real data |
| **Easy rollback** | Individual queries can be reverted without affecting others |
| **Performance testing in production** | Real workload performance data collected for each query |
| **User confidence** | Gradual migration builds stakeholder trust |

#### Cons

| Challenge | Impact |
|-----------|--------|
| **Increased storage** | Dual schema requires 1.5-2x storage (6 old dimensions + 1 new dimension) |
| **Data synchronization complexity** | If dimension data changes during dual-run period, both schemas must be updated |
| **Extended timeline** | 30-day migration vs. single-day cutover |
| **Operational overhead** | Running/monitoring both schemas requires more effort |
| **Fact table complexity** | Fact table contains 6 legacy FKs until cutover (wider table) |

#### Recommended For

- ✅ **Production environments with zero-downtime requirements**
- ✅ **Risk-averse organizations** (financial services, healthcare)
- ✅ **Large-scale deployments** where single failure could impact many users
- ✅ **When performance validation is critical** (need real production metrics)

---

### 4.2 Option 2: Cutover Approach (Single-Step Migration)

#### Description

Perform schema migration in a **single maintenance window** with a clear before/after cutover point. Old schema is fully replaced by new schema in one operation.

#### Implementation Steps

1. **Pre-Cutover Validation (1 week before):**
   - Run Section 2 validation queries on production data
   - Run Section 6 validation suite on staging environment
   - Run Section 7 performance benchmarks on staging
   - Confirm all validation tests PASS

2. **Cutover Window (4-6 hours, scheduled maintenance):**
   ```
   Hour 0:00 - Take database backup
   Hour 0:30 - Set database to read-only mode
   Hour 0:45 - Create dim_security table and populate
   Hour 1:15 - Create indexes on dim_security
   Hour 1:30 - Deploy all 21 refactored queries
   Hour 2:00 - Run Section 6 validation suite on production
   Hour 3:00 - Run Section 7 performance benchmarks (sample)
   Hour 3:30 - Decision Point: GO / NO-GO
               - GO: Proceed to cleanup (drop legacy dimensions)
               - NO-GO: Trigger rollback
   Hour 4:00 - If GO: Drop legacy dimensions and FKs
   Hour 4:30 - Set database to read-write mode
   Hour 5:00 - Monitor production queries
   Hour 6:00 - Cutover complete
   ```

3. **Post-Cutover Monitoring:**
   - Monitor query error rate (first 24 hours)
   - Track performance metrics vs. baseline
   - Collect user feedback
   - Address issues immediately (no rollback window)

4. **Rollback Plan (If NO-GO at Hour 3:30):**
   - Drop dim_security table
   - Revert all refactored queries
   - Set database to read-write mode
   - Resume normal operations with old schema

#### Pros

| Benefit | Impact |
|---------|--------|
| **Fast migration** | Complete in single day (vs. 30 days for dual-run) |
| **Simplicity** | Clear before/after state; no dual schema complexity |
| **Lower storage overhead** | No duplicate schemas required |
| **No data synchronization** | Single source of truth immediately after cutover |
| **Easier testing** | Staging environment exactly matches production |

#### Cons

| Challenge | Impact |
|-----------|--------|
| **Downtime required** | 4-6 hour maintenance window with read-only mode |
| **All-or-nothing risk** | All 21 queries migrated simultaneously; single failure affects all |
| **Rollback complexity** | If issues discovered after cutover, full database restore required |
| **Limited production validation** | Performance testing on staging may not reflect production |
| **User disruption** | All users affected simultaneously if issues occur |

#### Recommended For

- ✅ **Staging/development environments** (low risk tolerance acceptable)
- ✅ **Small-scale deployments** (limited user base, low query volume)
- ✅ **When downtime is acceptable** (batch analytics systems, overnight processing)
- ✅ **High confidence scenarios** (extensive staging validation completed)

---

### 4.3 Option 3: Phased Migration (Incremental by Query Group)

#### Description

Migrate queries in **3-4 distinct phases** based on complexity and risk, with validation gates between each phase. Hybrid approach combining elements of dual-run and cutover.

#### Implementation Steps

1. **Phase 1: Simple Queries (Week 1):**
   - **Queries:** Q03, Q07, Q11, Q15, Q17, Q23, Q29 (7 queries, single-dimension joins)
   - **Deployment:** Create dim_security, migrate simple queries only
   - **Validation Gate:** Run Section 6 validation for Phase 1 queries only
   - **Performance Gate:** Verify no regressions on simple queries
   - **Decision:** PASS → Proceed to Phase 2 | FAIL → Rollback Phase 1

2. **Phase 2: Medium Complexity Queries (Week 2):**
   - **Queries:** Q08, Q12, Q14, Q16, Q22, Q25, Q26, Q28, Q30 (9 queries, 2-4 dimension joins)
   - **Deployment:** Migrate medium complexity queries
   - **Validation Gate:** Run Section 6 validation for Phase 1 + Phase 2 queries
   - **Performance Gate:** Verify Phase 2 queries meet performance targets
   - **Decision:** PASS → Proceed to Phase 3 | FAIL → Rollback Phase 2 (keep Phase 1)

3. **Phase 3: Complex Queries (Week 3):**
   - **Queries:** Q01, Q04, Q09, Q19 (4 queries, 5+ dimension joins, includes anti-patterns)
   - **Deployment:** Migrate complex queries (highest performance benefit expected)
   - **Validation Gate:** Run full Section 6 validation suite
   - **Performance Gate:** Verify overall average improvement ≥25%
   - **Decision:** PASS → Proceed to Phase 4 | FAIL → Rollback Phase 3 (keep Phase 1+2)

4. **Phase 4: Cleanup (Week 4):**
   - **Deployment:** Drop legacy dimensions and fact table FKs
   - **Validation:** Final production validation (Section 6 + Section 7)
   - **Monitoring:** 7-day intensive monitoring period

#### Pros

| Benefit | Impact |
|---------|--------|
| **Risk isolation by complexity** | High-risk complex queries migrated last (with most confidence) |
| **Incremental validation** | Each phase validated before proceeding |
| **Partial rollback capability** | Can keep successful phases, rollback only failed phase |
| **Gradual performance tuning** | Index/optimization adjustments between phases |
| **User impact mitigation** | Issues affect subset of queries, not entire workload |
| **Confidence building** | Success in early phases builds confidence for complex queries |

#### Cons

| Challenge | Impact |
|-----------|--------|
| **Complex phase management** | Requires tracking which queries are in which phase |
| **Longer timeline than cutover** | 4 weeks vs. 1 day |
| **Dual schema period** | Legacy dimensions must remain until Phase 4 |
| **Multiple validation cycles** | Section 6/7 tests run 4 times (once per phase) |
| **Risk of partial migration** | If Phase 3 fails, stuck with partial consolidated schema |

#### Recommended For

- ✅ **Medium-sized deployments** (balance between risk and speed)
- ✅ **When complex queries are high-risk** (Q01, Q04, Q09, Q19 need careful validation)
- ✅ **Organizations with iterative deployment culture** (Agile/DevOps environments)
- ✅ **When performance tuning is expected** (index adjustments between phases)

---

### 4.4 Deployment Strategy Recommendation

#### **RECOMMENDED: Dual-Run Approach (Option 1)**

**Justification:**

| Criterion | Dual-Run | Cutover | Phased | Winner |
|-----------|----------|---------|--------|--------|
| **Risk Mitigation** | Excellent (individual query rollback) | Poor (all-or-nothing) | Good (phase rollback) | ✅ Dual-Run |
| **Semantic Validation** | Excellent (production data) | Good (staging only) | Good (incremental) | ✅ Dual-Run |
| **Performance Validation** | Excellent (real workload) | Fair (staging estimates) | Good (incremental real data) | ✅ Dual-Run |
| **Downtime** | None | 4-6 hours | Minimal (multiple short windows) | ✅ Dual-Run |
| **Timeline** | 30 days | 1 day | 21-28 days | ❌ Cutover |
| **Operational Complexity** | High | Low | Medium | ❌ Cutover |
| **Rollback Capability** | Excellent | Poor (after cutover) | Good (partial) | ✅ Dual-Run |
| **Storage Overhead** | High (2x schemas) | Low | Medium | ❌ Cutover |

**Overall Score:**
- ✅ **Dual-Run: 6/8 criteria favored**
- Cutover: 2/8 criteria favored
- Phased: 0/8 criteria favored (middle ground)

**Decision Drivers:**

1. **Zero-Downtime Requirement:** Production analytics systems typically cannot afford 4-6 hour maintenance windows
2. **Risk Tolerance:** Schema consolidation is high-risk (semantic changes, performance unknowns) → conservative approach warranted
3. **Semantic Validation Criticality:** Section 6 validation tests must run on **production data** to catch edge cases missed in staging
4. **Performance Uncertainty:** Section 7 benchmarks are estimates; need real production validation
5. **Business Confidence:** Gradual migration demonstrates success incrementally, building stakeholder trust

**Implementation Plan for Dual-Run:**

| Week | Activities | Validation | Performance Monitoring |
|------|------------|------------|------------------------|
| **Week 0 (Prep)** | Create dim_security, populate, index | Section 2 validation on production data | Baseline Section 7 benchmarks |
| **Week 1** | Migrate simple queries (7 queries) | Section 6 Tests 1.1-1.2 | Monitor migrated queries |
| **Week 2** | Migrate medium queries (9 queries) | Section 6 Tests 2.1-2.3 | Compare old vs. new performance |
| **Week 3** | Migrate complex queries (4 queries) | Section 6 Tests 3.1-3.4 | Validate 25% improvement target |
| **Week 4** | Final validation, cleanup decision | Full Section 6 suite | Full Section 7 benchmark suite |
| **Week 5 (Cutover)** | Drop legacy dimensions and FKs | Post-cleanup validation | 7-day intensive monitoring |

**Rollback Strategy for Dual-Run:**
- **Individual Query Rollback:** Revert specific queries if discrepancies detected (no impact to other queries)
- **Full Rollback (if needed):** Drop dim_security, revert all queries, restore to 100% legacy schema
- **Rollback Window:** Unlimited (legacy schema remains until explicit cutover)

**Success Criteria for Cutover (End of Week 4):**
- ✅ All 22 Section 6 validation tests PASS (0 discrepancies)
- ✅ Section 7 performance: Overall average improvement ≥25%
- ✅ Zero query failures for 7 consecutive days
- ✅ Business stakeholder approval
- ✅ No performance regressions > 5% on any individual query

---

## 5. Risk Mitigation Summary

This table consolidates all risks with their mitigation and contingency strategies.

| Risk ID | Risk Name | Likelihood | Impact | Mitigation (Preventative) | Contingency (Reactive) | Validation Test |
|---------|-----------|------------|--------|---------------------------|------------------------|-----------------|
| **R01** | Data Loss During Denormalization | Medium | High | Pre-migration referential integrity checks (Section 2) | Correct source data, re-populate | Section 6, Test 1.2 |
| **R02** | Fact Table FK Integrity Violation | Low | Medium | Comprehensive query audit, dual schema period | Refactor discovered queries | Section 3 inventory |
| **R03** | Indirect Join Path Changes | Low | High | Cardinality validation (Section 2, Query 1.7) | Correct population SQL, re-populate | Section 6, Test 2.2 |
| **R04** | Query Logic Errors During Refactoring | High | High | Automated column mapping, peer review, before/after testing | Fix errors, re-run validation | Section 6, Tests 2.1-2.3 |
| **R05** | Anti-Pattern Elimination Changes Semantics | Low | High | Consistency validation (fact FKs = stock FKs) | Data correction or accept semantic change | Section 6, Test 2.2 |
| **R06** | Query Performance Degradation | Low | High | Index strategy, benchmark testing, EXPLAIN analysis | Investigate root cause, optimize, rollback if needed | Section 7 benchmarks |
| **R07** | Index Bloat and Maintenance Overhead | Medium | Low | Selective indexing, batch updates | Drop rarely-used indexes | Section 4 index monitoring |
| **R08** | Incomplete Migration (Partial State) | Medium | High | Transactional DDL, backup, dry-run, migration checklist | Halt, restore backup, re-attempt | Section 3.5 checklist |
| **R09** | Rollback Failure (Data Loss) | Low | High | Preserve legacy dimensions, retain fact FKs, verified backups | Full database restore from backup | Section 3.2 preservation |
| **R10** | Undiscovered Query Dependencies | Medium | Medium | Query log analysis, stakeholder survey, dual-schema period | Extend dual-schema, refactor discovered queries | Section 3 inventory |
| **R11** | FK Relationship Assumptions Violated | Low | High | Run Section 2 on production data, business rule validation | Adjust grain (composite key), SCD Type 2, or abort | Section 2 on production |

**Overall Risk Profile:**
- **Critical Risks (High Impact + Medium/High Likelihood):** 2 risks (R04, R08)
- **High Priority Risks (High Impact + Low Likelihood):** 5 risks (R01, R03, R05, R06, R11)
- **Medium Priority Risks:** 3 risks (R02, R10, R07)
- **Low Priority Risks:** 1 risk (R09)

**Mitigation Coverage:** 100% (every risk has both preventative and contingency strategies)

---

## 6. Testing Requirements Before Production Deployment

These tests **MUST PASS** before production deployment:

### 6.1 Pre-Migration Tests (Run on Production Data)

| Test ID | Test Name | Expected Result | Failure Action |
|---------|-----------|-----------------|----------------|
| **P01** | Section 2, Query 1.1-1.7 (Cardinality) | 0 rows (all M:1 relationships confirmed) | BLOCK migration |
| **P02** | Section 2, Query 2.1-2.3 (Referential Integrity) | 0 rows (no orphaned FKs) | BLOCK migration |
| **P03** | Fact Table NULL FK Check (A06) | 0 rows (no NULL security FKs) | BLOCK migration |
| **P04** | Fact-Stock FK Consistency (A08) | 0 rows (fact FKs = stock FKs) | BLOCK migration or accept risk |
| **P05** | Section 6 Baseline Validation | All 22 tests PASS on current schema | Document baseline |
| **P06** | Section 7 Baseline Performance | Record median execution times for 12 queries | Document baseline |

### 6.2 Post-Migration Tests (Run After dim_security Created)

| Test ID | Test Name | Expected Result | Failure Action |
|---------|-----------|-----------------|----------------|
| **M01** | dim_security Row Count | = dim_stock row count (30 in sample, N in production) | Investigate population SQL |
| **M02** | dim_security NULL Attributes | 0 rows with NULL denormalized columns | Investigate join failures |
| **M03** | dim_security Index Count | 7 indexes (1 PK + 6 secondary) | Create missing indexes |
| **M04** | Section 6, Test 1.1 (Row Count Stability) | 0 difference | TRIGGER ROLLBACK |
| **M05** | Section 6, Test 1.2 (Join Integrity) | 0 orphaned keys | TRIGGER ROLLBACK |
| **M06** | Section 6, Tests 2.1-2.3 (Result Set Equivalence) | 0 discrepancies | TRIGGER ROLLBACK |
| **M07** | Section 6, Tests 3.1-3.4 (Aggregate Validation) | 0 difference | TRIGGER ROLLBACK |
| **M08** | Section 6, Tests 4.1-4.5 (Attribute Validation) | All PASS | TRIGGER ROLLBACK |
| **M09** | Section 6, Tests 5.1-5.8 (Sample Query Validation) | 0 discrepancies | TRIGGER ROLLBACK |
| **M10** | Section 7 Performance Benchmarks | Overall avg improvement ≥25% | Manual decision |
| **M11** | Section 7 Regression Check | ≤2 queries with regression > 10% | Manual decision |

**Critical Tests (Auto-Rollback on Failure):** M04-M09 (any failure triggers immediate rollback)

**Performance Tests (Manual Decision):** M10-M11 (review with stakeholders before rollback)

---

## 7. Conclusion

This risk assessment and rollback plan provides comprehensive coverage of all potential failure modes in the 6-dimension to 1-dimension consolidation effort. Key takeaways:

### 7.1 Risk Posture

- ✅ **All 11 identified risks have mitigation strategies** (100% coverage)
- ✅ **All 12 assumptions are documented and testable** (validation queries provided)
- ✅ **Rollback procedures are detailed and tested** (two scenarios covered)
- ✅ **Deployment strategy is conservative** (dual-run approach minimizes risk)

### 7.2 Go/No-Go Decision Criteria

**Proceed with Migration if:**
- All Section 2 validation queries PASS on production data (assumptions validated)
- All Section 6 validation tests PASS on staging (semantic equivalence proven)
- Section 7 benchmarks show ≥25% average improvement on staging (performance benefit demonstrated)
- Rollback procedures tested successfully on staging (can recover from failure)
- Business stakeholders approve timeline and dual-schema overhead

**Abort Migration if:**
- Any Section 2 cardinality test fails (M:1 relationships violated → R11 materialized)
- Any Section 6 validation test fails and cannot be corrected (semantic equivalence impossible → R04 materialized)
- Section 7 benchmarks show net performance regression (benefit not achieved → R06 materialized)
- Rollback testing fails (cannot recover from failure → R09 materialized)
- Scope analysis reveals undiscovered dependencies beyond refactoring capacity (R10 materialized)

### 7.3 Success Factors

1. **Comprehensive Validation:** 22 tests (Section 6) + 12 benchmarks (Section 7) + 7 relationship proofs (Section 2) = **41 total validation points**
2. **Conservative Deployment:** 30-day dual-schema period allows production validation before cutover
3. **Detailed Rollback:** Two rollback scenarios documented with step-by-step procedures
4. **Explicit Assumptions:** 12 assumptions documented with validation strategies and business confirmation requirements
5. **Risk Transparency:** All risks documented with likelihood/impact assessment and mitigation strategies

**Migration Readiness:** This plan provides decision-makers with complete risk transparency and concrete validation criteria to make informed go/no-go decisions at each stage of the consolidation effort.

---

## Appendix A: Risk-Assumption-Validation Mapping

This table maps each assumption to its validation test and the risks it mitigates.

| Assumption | Validation Test | Related Risks | Business Confirmation Priority |
|------------|-----------------|---------------|-------------------------------|
| A01: Stock → Issuer M:1 | Section 2, Query 1.1 | R11, R01 | High |
| A02: Stock → Exchange M:1 | Section 2, Query 1.4 | R11, R01 | High |
| A03: Stock → Currency M:1 | Section 2, Query 1.5 | R11, R01 | High |
| A04: Issuer → Industry M:1 | Section 2, Query 1.6 | R11, R03 | Medium |
| A05: Industry → Sector M:1 | Section 2, Query 1.7 | R11, R03 | High |
| A06: No NULL Security FKs | Custom NULL check query | R01, R02 | High |
| A07: Referential Integrity | Section 2, Query 2.1 | R01, R02 | High |
| A08: Fact FKs = Stock FKs | Custom consistency check | R05, R04 | **CRITICAL** |
| A09: 30 Queries Represent All Patterns | Query log analysis | R10, R02 | High |
| A10: No Materialized View Dependencies | Metadata query | R10 | Medium |
| A11: DuckDB Join Reduction Benefits | Section 7 benchmarks | R06 | Medium (empirical test) |
| A12: Dimensions are Static | Historical analysis | R07 | Low |

**Critical Assumption:** A08 (Fact FKs = Stock FKs) - If false, consolidation may change semantics of anti-pattern queries (Q09, Q22).

---

## Appendix B: Rollback Decision Tree

```
Validation Test Result
  │
  ├─ Section 2 Cardinality Test FAILS (M:1 violation detected)
  │    → IMMEDIATE ROLLBACK: Assumptions violated, consolidation not feasible
  │    → Next Steps: Adjust grain (composite key) or abort consolidation
  │
  ├─ Section 6 Validation Test FAILS (discrepancies > 0 rows)
  │    → INVESTIGATE ROOT CAUSE
  │       ├─ Query refactoring error (R04) → Fix query, re-test → If fixed: PROCEED | If not: ROLLBACK
  │       ├─ Population SQL error (R01, R03) → Fix SQL, re-populate, re-test → If fixed: PROCEED | If not: ROLLBACK
  │       └─ Semantic assumption false (R05) → Business decision → Accept change or ROLLBACK
  │
  ├─ Section 7 Performance Test: Overall improvement < 0%
  │    → IMMEDIATE ROLLBACK: No benefit achieved
  │    → Next Steps: Investigate index strategy, query optimization, or abort consolidation
  │
  ├─ Section 7 Performance Test: 0% < improvement < 25%
  │    → MANUAL DECISION
  │       ├─ If improvement > 15% → Acceptable (proceed with caution)
  │       ├─ If improvement < 15% → ROLLBACK or investigate optimization opportunities
  │
  ├─ Section 7 Performance Test: ≥3 queries regress > 10%
  │    → MANUAL DECISION
  │       ├─ Investigate EXPLAIN plans for root cause
  │       ├─ Optimize indexes or query rewrites
  │       └─ If cannot resolve: ROLLBACK
  │
  ├─ Production Query Failure Rate > 5% (first 24 hours)
  │    → IMMEDIATE ROLLBACK: Undiscovered dependencies (R10)
  │    → Next Steps: Extend query inventory, refactor discovered queries, re-attempt migration
  │
  └─ All Validation Tests PASS
       → PROCEED TO CUTOVER (drop legacy dimensions after 30-day window)
```

---

**End of Section 8: Risks, Assumptions, and Rollback Plan**
