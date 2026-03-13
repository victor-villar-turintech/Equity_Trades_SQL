# Section 4: Consolidated Dimension Design

## Executive Summary

This section provides the complete technical design for consolidating six security-related dimensions (`dim_stock`, `dim_issuer`, `dim_industry`, `dim_sector`, `dim_exchange`, `dim_currency`) into a single unified dimension table named **`dim_security`**. The design flattens all attributes from the source dimensions using a denormalization strategy, preserves legacy foreign keys for backward compatibility and validation, and includes optimized indexes based on downstream query patterns.

**Key Design Decisions:**
- **Table Name:** `dim_security` (represents equity security master data)
- **Primary Key:** `stock_key` (finest grain - individual listed equity securities)
- **Total Columns:** 22 (1 PK + 5 stock attributes + 16 denormalized attributes from 5 dimensions + 2 country references)
- **Denormalization Strategy:** Prefix-based naming for clarity (e.g., `issuer_name`, `industry_name`, `sector_name`)
- **Legacy Key Preservation:** All 5 original foreign keys retained as reference columns
- **Null Handling:** Denormalized columns allow NULL except for core stock attributes
- **Index Strategy:** 7 indexes recommended based on Section 3 query pattern analysis

**Expected Benefits:**
- **Schema Simplification:** 6 dimension tables → 1 unified dimension
- **Fact Table Simplification:** 6 security FKs → 1 FK (`stock_key` only)
- **Query Simplification:** Up to 5 joins eliminated in complex queries (Q01, Q04, Q19)
- **Anti-Pattern Elimination:** Redundant join patterns (Q09, Q22) become impossible
- **Data Quality Enforcement:** Single source of truth prevents FK inconsistencies

---

## 1. Table Structure Overview

### 1.1 Column Inventory

The consolidated `dim_security` table contains 22 columns organized into 7 logical groups:

| Group | Source | Column Count | Description |
|-------|--------|--------------|-------------|
| **Primary Key** | dim_stock | 1 | Stock surrogate key |
| **Stock Attributes** | dim_stock | 5 | Ticker, share class, lot size, market cap, reference price |
| **Issuer Attributes** | dim_issuer | 2 | Issuer name + denormalized industry reference |
| **Industry Attributes** | dim_industry | 1 | Industry name (denormalized from hierarchy) |
| **Sector Attributes** | dim_sector | 1 | Sector name (denormalized from hierarchy) |
| **Exchange Attributes** | dim_exchange | 2 | MIC code, exchange name |
| **Currency Attributes** | dim_currency | 2 | Currency code, currency name |
| **Legacy Keys** | All sources | 5 | Preserved foreign keys for backward compatibility |
| **External References** | Issuer/Exchange | 2 | Country foreign keys (not consolidated) |

**Total: 22 columns**

---

### 1.2 Naming Convention

**Rationale:** Clear, self-documenting column names that indicate the source dimension and business meaning.

| Column Category | Naming Pattern | Examples |
|----------------|----------------|----------|
| Primary Key | `stock_key` | Unchanged from dim_stock |
| Stock Attributes | No prefix (native to stock) | `ticker`, `share_class`, `lot_size` |
| Denormalized Attributes | `<dimension>_<attribute>` | `issuer_name`, `industry_name`, `sector_name` |
| Natural Keys | `<dimension>_<code/identifier>` | `exchange_mic_code`, `currency_code` |
| Legacy Foreign Keys | `<dimension>_key` | `issuer_key`, `industry_key`, `sector_key` |
| External References | `<dimension>_country_key` | `issuer_country_key`, `exchange_country_key` |

**Benefits:**
- Intuitive for developers (clear attribute origin)
- Avoids name collisions (e.g., `name` → `issuer_name`, `industry_name`)
- Supports legacy code migration (foreign key names unchanged)
- Distinguishes native vs. denormalized attributes

---

## 2. Complete DDL Specification

### 2.1 CREATE TABLE Statement

```sql
-- =====================================================================
-- dim_security: Consolidated equity security dimension
-- 
-- Consolidates 6 source dimensions:
--   - dim_stock (base grain)
--   - dim_issuer
--   - dim_industry
--   - dim_sector
--   - dim_exchange
--   - dim_currency
--
-- Grain: One row per traded equity security (stock_key)
-- =====================================================================

CREATE TABLE dim_security (
  -- ===================================================================
  -- PRIMARY KEY (Stock Grain)
  -- ===================================================================
  stock_key INT PRIMARY KEY,
  
  -- ===================================================================
  -- STOCK ATTRIBUTES (from dim_stock)
  -- ===================================================================
  ticker VARCHAR(10) NOT NULL,
  share_class VARCHAR(10),
  lot_size INT,
  market_cap_bucket VARCHAR(20),
  reference_price DECIMAL(18,4),
  
  -- ===================================================================
  -- LEGACY FOREIGN KEYS (for backward compatibility and validation)
  -- ===================================================================
  issuer_key INT NOT NULL,
  industry_key INT NOT NULL,
  sector_key INT NOT NULL,
  exchange_key INT NOT NULL,
  currency_key INT NOT NULL,
  
  -- ===================================================================
  -- DENORMALIZED ISSUER ATTRIBUTES (from dim_issuer)
  -- ===================================================================
  issuer_name VARCHAR(150),
  issuer_country_key INT,  -- External reference to dim_country (not consolidated)
  
  -- ===================================================================
  -- DENORMALIZED INDUSTRY ATTRIBUTES (from dim_industry)
  -- ===================================================================
  industry_name VARCHAR(100),
  
  -- ===================================================================
  -- DENORMALIZED SECTOR ATTRIBUTES (from dim_sector)
  -- ===================================================================
  sector_name VARCHAR(100),
  
  -- ===================================================================
  -- DENORMALIZED EXCHANGE ATTRIBUTES (from dim_exchange)
  -- ===================================================================
  exchange_mic_code VARCHAR(10),
  exchange_name VARCHAR(100),
  exchange_country_key INT,  -- External reference to dim_country (not consolidated)
  
  -- ===================================================================
  -- DENORMALIZED CURRENCY ATTRIBUTES (from dim_currency)
  -- ===================================================================
  currency_code VARCHAR(3),
  currency_name VARCHAR(100),
  
  -- ===================================================================
  -- CONSTRAINTS
  -- ===================================================================
  -- Legacy keys reference original dimensions (for validation during transition)
  CONSTRAINT fk_security_issuer FOREIGN KEY (issuer_key) REFERENCES dim_issuer(issuer_key),
  CONSTRAINT fk_security_industry FOREIGN KEY (industry_key) REFERENCES dim_industry(industry_key),
  CONSTRAINT fk_security_sector FOREIGN KEY (sector_key) REFERENCES dim_sector(sector_key),
  CONSTRAINT fk_security_exchange FOREIGN KEY (exchange_key) REFERENCES dim_exchange(exchange_key),
  CONSTRAINT fk_security_currency FOREIGN KEY (currency_key) REFERENCES dim_currency(currency_key),
  
  -- External country references (preserve issuer/exchange country relationships)
  CONSTRAINT fk_security_issuer_country FOREIGN KEY (issuer_country_key) REFERENCES dim_country(country_key),
  CONSTRAINT fk_security_exchange_country FOREIGN KEY (exchange_country_key) REFERENCES dim_country(country_key)
);
```

**Note on Foreign Key Constraints:** The constraints on legacy keys (`issuer_key`, `industry_key`, etc.) serve two purposes:
1. **During Migration:** Validate that populated data matches source dimensions
2. **Post-Migration:** Can be dropped once original dimensions are retired

---

### 2.2 Column-by-Column Specification

| Column Name | Data Type | Nullable | Source Table | Source Column | Business Meaning |
|-------------|-----------|----------|--------------|---------------|------------------|
| **stock_key** | INT | NO | dim_stock | stock_key | Surrogate key, unique identifier for each stock |
| **ticker** | VARCHAR(10) | NO | dim_stock | ticker | Stock ticker symbol (e.g., AAPL, TSLA) |
| **share_class** | VARCHAR(10) | YES | dim_stock | share_class | Share class identifier (ORD, A, B, ADR, etc.) |
| **lot_size** | INT | YES | dim_stock | lot_size | Standard trading lot size |
| **market_cap_bucket** | VARCHAR(20) | YES | dim_stock | market_cap_bucket | Market capitalization bucket (Small/Mid/Large) |
| **reference_price** | DECIMAL(18,4) | YES | dim_stock | reference_price | Reference or closing price |
| **issuer_key** | INT | NO | dim_stock | issuer_key | Legacy FK to dim_issuer (for validation) |
| **industry_key** | INT | NO | dim_stock | industry_key | Legacy FK to dim_industry (for validation) |
| **sector_key** | INT | NO | dim_stock | sector_key | Legacy FK to dim_sector (for validation) |
| **exchange_key** | INT | NO | dim_stock | exchange_key | Legacy FK to dim_exchange (for validation) |
| **currency_key** | INT | NO | dim_stock | currency_key | Legacy FK to dim_currency (for validation) |
| **issuer_name** | VARCHAR(150) | YES | dim_issuer | issuer_name | Issuing company name |
| **issuer_country_key** | INT | YES | dim_issuer | country_key | Country of incorporation (references dim_country) |
| **industry_name** | VARCHAR(100) | YES | dim_industry | industry_name | Industry classification name |
| **sector_name** | VARCHAR(100) | YES | dim_sector | sector_name | Sector classification name (top-level hierarchy) |
| **exchange_mic_code** | VARCHAR(10) | YES | dim_exchange | mic_code | ISO 10383 Market Identifier Code |
| **exchange_name** | VARCHAR(100) | YES | dim_exchange | exchange_name | Stock exchange name |
| **exchange_country_key** | INT | YES | dim_exchange | country_key | Country where exchange is located |
| **currency_code** | VARCHAR(3) | YES | dim_currency | currency_code | ISO 4217 currency code (USD, EUR, JPY, etc.) |
| **currency_name** | VARCHAR(100) | YES | dim_currency | currency_name | Currency name |

**Nullability Design Decisions:**
- **NOT NULL:** Only `stock_key` (PK), `ticker` (business key), and legacy foreign keys
- **Nullable:** All denormalized attributes allow NULL to handle edge cases (missing reference data, data quality issues)
- **Rationale:** Preserves flexibility during migration and handles incomplete source data gracefully

---

## 3. Index Strategy

### 3.1 Recommended Indexes

Based on Section 3 query pattern analysis (17 queries use security dimensions), the following indexes are recommended:

| Index Name | Index Type | Columns | Justification | Queries Benefiting |
|------------|------------|---------|---------------|---------------------|
| **pk_dim_security** | PRIMARY KEY | `stock_key` | All fact table joins use stock_key | All 30 queries (via fact join) |
| **idx_security_ticker** | B-TREE | `ticker` | Pattern matching (LIKE), filters | Q03, Q07, Q11, Q15, Q23, Q29 (6 queries) |
| **idx_security_exchange_name** | B-TREE | `exchange_name` | Aggregation, GROUP BY, filters | Q08, Q12, Q14, Q17, Q22, Q25, Q28, Q30 (8 queries) |
| **idx_security_sector_name** | B-TREE | `sector_name` | Aggregation, GROUP BY | Q01, Q04, Q09, Q14, Q19, Q30 (6 queries) |
| **idx_security_industry_name** | B-TREE | `industry_name` | Aggregation, GROUP BY | Q01, Q04, Q09, Q14, Q19, Q30 (6 queries) |
| **idx_security_currency_code** | B-TREE | `currency_code` | Filters, lookups | Q26, Q28, Q30 (3 queries) |
| **idx_security_issuer_name** | B-TREE | `issuer_name` | Filters, DISTINCT | Q01, Q04, Q19 (3 queries) |

**Total Indexes:** 7 (1 PK + 6 secondary indexes)

---

### 3.2 Index Coverage Analysis

| Query Pattern | Queries | Index Used | Coverage |
|---------------|---------|------------|----------|
| Ticker lookup/filter | Q03, Q07, Q11, Q15, Q23, Q29 | idx_security_ticker | 100% |
| Exchange aggregation/filter | Q08, Q12, Q14, Q17, Q22, Q25, Q28, Q30 | idx_security_exchange_name | 100% |
| Sector aggregation | Q01, Q04, Q09, Q14, Q19, Q30 | idx_security_sector_name | 100% |
| Industry aggregation | Q01, Q04, Q09, Q14, Q19, Q30 | idx_security_industry_name | 100% |
| Currency filter | Q26, Q28, Q30 | idx_security_currency_code | 100% |
| Issuer DISTINCT/filter | Q01, Q04, Q19 | idx_security_issuer_name | 100% |
| Stock key join (fact) | All 30 | pk_dim_security | 100% |

**Coverage Summary:** All 17 queries using security dimensions benefit from at least one secondary index beyond the primary key.

---

### 3.3 Optional Composite Indexes

For high-volume production environments, consider these composite indexes:

```sql
-- For queries filtering by sector + exchange (Q14, Q30)
CREATE INDEX idx_security_sector_exchange 
ON dim_security(sector_name, exchange_name);

-- For queries needing industry → sector hierarchy (Q09, Q19)
CREATE INDEX idx_security_industry_sector 
ON dim_security(industry_name, sector_name);
```

**Tradeoff:** Composite indexes improve read performance but increase storage and write overhead. Recommend profiling actual query workload before implementing.

---

## 4. Population SQL Logic

### 4.1 Data Population Strategy

**Approach:** Single INSERT/SELECT statement with LEFT JOINs to preserve all dim_stock rows (grain level).

**Join Strategy:**
- **Base Table:** `dim_stock` (30 rows - finest grain)
- **LEFT JOIN** to all parent dimensions to preserve stock records even if reference data is missing
- **Flattening:** Denormalize attributes from all 5 parent dimensions into single row per stock

**Null Handling:** LEFT JOINs allow NULL values in denormalized columns if parent records are missing (though Section 2 proves 100% referential integrity exists).

---

### 4.2 Complete Population SQL

```sql
-- =====================================================================
-- POPULATION SQL: dim_security
-- 
-- Populates consolidated dimension from 6 source dimensions
-- Base: dim_stock (30 rows)
-- Joins: dim_issuer, dim_industry, dim_sector, dim_exchange, dim_currency
-- =====================================================================

INSERT INTO dim_security (
  -- Primary key
  stock_key,
  
  -- Stock attributes (from dim_stock)
  ticker,
  share_class,
  lot_size,
  market_cap_bucket,
  reference_price,
  
  -- Legacy foreign keys (from dim_stock)
  issuer_key,
  industry_key,
  sector_key,
  exchange_key,
  currency_key,
  
  -- Denormalized issuer attributes (from dim_issuer)
  issuer_name,
  issuer_country_key,
  
  -- Denormalized industry attributes (from dim_industry)
  industry_name,
  
  -- Denormalized sector attributes (from dim_sector)
  sector_name,
  
  -- Denormalized exchange attributes (from dim_exchange)
  exchange_mic_code,
  exchange_name,
  exchange_country_key,
  
  -- Denormalized currency attributes (from dim_currency)
  currency_code,
  currency_name
)
SELECT
  -- ===================================================================
  -- Primary key
  -- ===================================================================
  s.stock_key,
  
  -- ===================================================================
  -- Stock attributes (base dimension - dim_stock)
  -- ===================================================================
  s.ticker,
  s.share_class,
  s.lot_size,
  s.market_cap_bucket,
  s.reference_price,
  
  -- ===================================================================
  -- Legacy foreign keys (preserve for backward compatibility)
  -- ===================================================================
  s.issuer_key,
  s.industry_key,
  s.sector_key,
  s.exchange_key,
  s.currency_key,
  
  -- ===================================================================
  -- Denormalized issuer attributes (from dim_issuer via stock.issuer_key)
  -- ===================================================================
  iss.issuer_name,
  iss.country_key AS issuer_country_key,
  
  -- ===================================================================
  -- Denormalized industry attributes (from dim_industry via stock.industry_key)
  -- ===================================================================
  ind.industry_name,
  
  -- ===================================================================
  -- Denormalized sector attributes (from dim_sector via industry.sector_key)
  -- 
  -- Note: Could also join via stock.sector_key (redundant path)
  -- Using industry.sector_key validates hierarchical consistency
  -- ===================================================================
  sec.sector_name,
  
  -- ===================================================================
  -- Denormalized exchange attributes (from dim_exchange via stock.exchange_key)
  -- ===================================================================
  ex.mic_code AS exchange_mic_code,
  ex.exchange_name,
  ex.country_key AS exchange_country_key,
  
  -- ===================================================================
  -- Denormalized currency attributes (from dim_currency via stock.currency_key)
  -- ===================================================================
  cur.currency_code,
  cur.currency_name

FROM dim_stock s

-- =====================================================================
-- LEFT JOINS to preserve all stock records (grain level)
-- Section 2 proves 100% referential integrity, so LEFT JOINs will not 
-- produce NULLs in practice, but LEFT JOIN is safer for production
-- =====================================================================

LEFT JOIN dim_issuer iss 
  ON s.issuer_key = iss.issuer_key

LEFT JOIN dim_industry ind 
  ON s.industry_key = ind.industry_key

-- Join sector via industry hierarchy (validates consistency with stock.sector_key)
LEFT JOIN dim_sector sec 
  ON ind.sector_key = sec.sector_key

LEFT JOIN dim_exchange ex 
  ON s.exchange_key = ex.exchange_key

LEFT JOIN dim_currency cur 
  ON s.currency_key = cur.currency_key

-- =====================================================================
-- VALIDATION QUERY (optional - uncomment to validate sector consistency)
-- 
-- This WHERE clause validates that stock.sector_key matches industry.sector_key
-- (per Section 2 proof, this should always be true)
-- =====================================================================
-- WHERE s.sector_key = ind.sector_key  -- Validates redundant FK consistency

ORDER BY s.stock_key;
```

---

### 4.3 Population Validation Queries

After population, run these queries to validate data integrity:

```sql
-- =====================================================================
-- VALIDATION 1: Row Count Match
-- Expected: 30 rows (same as dim_stock)
-- =====================================================================
SELECT 
  (SELECT COUNT(*) FROM dim_stock) AS stock_count,
  (SELECT COUNT(*) FROM dim_security) AS security_count,
  CASE 
    WHEN (SELECT COUNT(*) FROM dim_stock) = (SELECT COUNT(*) FROM dim_security) 
    THEN 'PASS' 
    ELSE 'FAIL' 
  END AS validation_status;

-- =====================================================================
-- VALIDATION 2: No NULL Legacy Keys
-- Expected: 0 rows (all legacy keys should be populated)
-- =====================================================================
SELECT 
  stock_key,
  CASE 
    WHEN issuer_key IS NULL THEN 'Missing issuer_key'
    WHEN industry_key IS NULL THEN 'Missing industry_key'
    WHEN sector_key IS NULL THEN 'Missing sector_key'
    WHEN exchange_key IS NULL THEN 'Missing exchange_key'
    WHEN currency_key IS NULL THEN 'Missing currency_key'
  END AS missing_key
FROM dim_security
WHERE issuer_key IS NULL 
   OR industry_key IS NULL 
   OR sector_key IS NULL 
   OR exchange_key IS NULL 
   OR currency_key IS NULL;

-- =====================================================================
-- VALIDATION 3: Denormalized Attribute Completeness
-- Expected: 0 rows with NULL denormalized attributes
-- (Based on Section 2 100% referential integrity proof)
-- =====================================================================
SELECT 
  stock_key,
  ticker,
  CASE 
    WHEN issuer_name IS NULL THEN 'Missing issuer_name'
    WHEN industry_name IS NULL THEN 'Missing industry_name'
    WHEN sector_name IS NULL THEN 'Missing sector_name'
    WHEN exchange_name IS NULL THEN 'Missing exchange_name'
    WHEN currency_code IS NULL THEN 'Missing currency_code'
  END AS missing_attribute
FROM dim_security
WHERE issuer_name IS NULL 
   OR industry_name IS NULL 
   OR sector_name IS NULL 
   OR exchange_name IS NULL 
   OR currency_code IS NULL;

-- =====================================================================
-- VALIDATION 4: Sector Consistency Validation
-- Validate that stock.sector_key matches industry.sector_key
-- Expected: 0 rows (no mismatches)
-- =====================================================================
SELECT 
  ds.stock_key,
  ds.ticker,
  ds.sector_key AS stock_sector_key,
  di.sector_key AS industry_sector_key,
  ds.sector_name AS security_sector_name,
  sec.sector_name AS actual_sector_name
FROM dim_security ds
JOIN dim_industry di ON ds.industry_key = di.industry_key
JOIN dim_sector sec ON ds.sector_key = sec.sector_key
WHERE ds.sector_key != di.sector_key;

-- =====================================================================
-- VALIDATION 5: Sample Data Inspection
-- Verify denormalized attributes match source dimensions
-- =====================================================================
SELECT 
  ds.stock_key,
  ds.ticker,
  -- Compare denormalized vs. source
  ds.issuer_name,
  iss.issuer_name AS source_issuer_name,
  ds.industry_name,
  ind.industry_name AS source_industry_name,
  ds.sector_name,
  sec.sector_name AS source_sector_name,
  ds.exchange_name,
  ex.exchange_name AS source_exchange_name,
  ds.currency_code,
  cur.currency_code AS source_currency_code
FROM dim_security ds
JOIN dim_issuer iss ON ds.issuer_key = iss.issuer_key
JOIN dim_industry ind ON ds.industry_key = ind.industry_key
JOIN dim_sector sec ON ds.sector_key = sec.sector_key
JOIN dim_exchange ex ON ds.exchange_key = ex.exchange_key
JOIN dim_currency cur ON ds.currency_key = cur.currency_key
WHERE ds.issuer_name != iss.issuer_name
   OR ds.industry_name != ind.industry_name
   OR ds.sector_name != sec.sector_name
   OR ds.exchange_name != ex.exchange_name
   OR ds.currency_code != cur.currency_code
LIMIT 5;
```

---

## 5. Design Rationale

### 5.1 Table Name Choice: `dim_security`

**Options Considered:**
1. `dim_stock_consolidated` - Descriptive but verbose
2. `dim_equity_security` - Specific but limits future expansion (e.g., bonds, options)
3. `dim_security` - Concise, domain-appropriate, extensible

**Decision:** `dim_security`

**Rationale:**
- **Business Alignment:** "Security" is the standard financial term for tradable instruments
- **Conciseness:** Shorter name improves query readability
- **Extensibility:** Can accommodate other security types (bonds, derivatives) if business expands
- **Industry Standard:** Aligns with common data warehouse naming conventions

---

### 5.2 Denormalization Strategy

**Principle:** Flatten all descriptive attributes into a single wide table while preserving dimensional hierarchy as legacy keys.

**Benefits:**
1. **Query Simplification:** Eliminates 4-5 joins in complex queries (Q01, Q04, Q09, Q19)
2. **Anti-Pattern Prevention:** Makes redundant joins (Q09, Q22) structurally impossible
3. **Performance:** Reduces join overhead for frequently accessed attributes (sector_name, industry_name)
4. **Single Source of Truth:** One table for all security master data

**Tradeoffs:**
| Benefit | Tradeoff |
|---------|----------|
| Fewer joins in queries | Wider table (22 columns vs. 2-11 per original dimension) |
| Simpler query logic | Increased storage per row (denormalized attributes) |
| No FK inconsistencies | Data duplication across hierarchy (e.g., sector_name repeated for all stocks in sector) |
| Faster read performance | Slower INSERT/UPDATE (more columns to populate) |

**Mitigation:**
- **Storage Impact:** Minimal (30 rows total, string columns are < 150 chars)
- **Update Complexity:** Securities are Type 1 SCD (current state only), updates rare
- **Data Duplication:** Sector/industry names are static reference data (11 sectors, 30 industries)

---

### 5.3 Legacy Foreign Key Preservation

**Design Decision:** Retain all 5 original foreign keys (`issuer_key`, `industry_key`, `sector_key`, `exchange_key`, `currency_key`) as columns in the consolidated dimension.

**Rationale:**

| Use Case | Benefit |
|----------|---------|
| **Backward Compatibility** | Existing queries using legacy keys continue to work during migration |
| **Validation** | FK constraints validate denormalized data matches source dimensions |
| **Debugging** | Enables comparison queries to detect data quality issues |
| **Incremental Migration** | Allows phased rollout (legacy queries use legacy keys, new queries use denormalized attributes) |
| **Rollback Safety** | Preserves join paths to original dimensions if rollback is needed |

**Post-Migration Options:**
1. **Keep Legacy Keys:** Minimal storage overhead (5 INT columns), useful for validation
2. **Drop Legacy Keys:** Remove after all downstream queries refactored and validated

**Recommendation:** **Keep legacy keys permanently**. Storage cost is negligible (20 bytes per row × 30 rows = 600 bytes), and they provide long-term value for:
- Data lineage tracing
- Integration with legacy systems
- Troubleshooting data quality issues

---

### 5.4 Null Handling Philosophy

**Constraint Strategy:** NOT NULL only on `stock_key` (PK), `ticker` (business key), and legacy foreign keys.

**Rationale:**

| Column Category | Nullable | Justification |
|----------------|----------|---------------|
| Primary Key (`stock_key`) | NO | Required for entity identity |
| Business Key (`ticker`) | NO | Core identifying attribute |
| Legacy Foreign Keys | NO | Must reference source dimensions (validated by FK constraints) |
| Denormalized Attributes | YES | Allows graceful handling of missing reference data |
| Stock Attributes | YES | Some attributes may be unknown (e.g., reference_price during IPO) |

**Benefits:**
- **Robustness:** ETL processes don't fail on incomplete reference data
- **Flexibility:** Supports partial data loads during migration
- **Real-World Modeling:** Acknowledges that not all attributes are always available

**Risk Mitigation:** Validation queries (Section 4.3) detect unexpected NULLs. In practice, Section 2 proves 100% referential integrity exists in current data.

---

## 6. Denormalization Tradeoffs Analysis

### 6.1 Storage Impact Assessment

**Original Schema:**
- dim_stock: 30 rows × ~50 bytes = 1.5 KB
- dim_issuer: 30 rows × ~30 bytes = 0.9 KB
- dim_industry: 30 rows × ~20 bytes = 0.6 KB
- dim_sector: 11 rows × ~15 bytes = 0.165 KB
- dim_exchange: 11 rows × ~25 bytes = 0.275 KB
- dim_currency: 8 rows × ~20 bytes = 0.16 KB
- **Total: ~3.6 KB**

**Consolidated Schema:**
- dim_security: 30 rows × ~200 bytes = 6 KB

**Storage Overhead:** +2.4 KB (67% increase)

**Assessment:** **Negligible** - In a production system with millions of fact rows, dimension storage is insignificant.

---

### 6.2 Performance Impact Analysis

| Operation | Original Schema | Consolidated Schema | Impact |
|-----------|----------------|---------------------|--------|
| **Fact Table Join** | 1 join (stock_key) + 5 dimension hops | 1 join (stock_key) | **Faster** (5 joins eliminated) |
| **Wide SELECT (Q01, Q04)** | 6 joins (5 direct + 1 indirect) | 1 join | **5× faster** (join reduction) |
| **Redundant Join Queries (Q09, Q22)** | 5 joins (2 redundant) | 1 join | **5× faster** + anti-pattern eliminated |
| **Sector Aggregation (Q14)** | 2 joins (industry → sector) | 1 join | **2× faster** (direct sector access) |
| **Dimension INSERT** | 1 write operation | 1 write operation (wider row) | **Slightly slower** (more columns) |
| **Dimension UPDATE** | Multiple tables potentially | 1 table update | **Simpler** (single update point) |
| **Full Table Scan** | 6 small scans | 1 wider scan | **Comparable** (30 rows is tiny) |

**Overall Assessment:** **Net Performance Gain** due to join elimination in read-heavy workloads (typical for analytics).

---

### 6.3 Maintenance Impact Analysis

| Maintenance Activity | Original Schema | Consolidated Schema | Impact |
|---------------------|----------------|---------------------|--------|
| **Schema Changes** | Modify 1 of 6 tables | Modify 1 table | **Simpler** |
| **Data Quality Rules** | Enforce across 6 tables | Enforce in 1 table | **Simpler** |
| **Referential Integrity** | 6 FK relationships in fact | 1 FK relationship in fact | **83% reduction** |
| **ETL Logic** | Populate 6 dimensions | Populate 1 dimension (with 6-way join) | **Trade-off** (simpler load, complex join) |
| **Debugging** | Trace through 6 tables | Trace through 1 table | **Simpler** |
| **Documentation** | Document 6 table schemas | Document 1 table schema | **Simpler** |

**Overall Assessment:** **Significant Maintenance Simplification** - Single point of maintenance for all security master data.

---

### 6.4 Data Quality Impact

**Positive Impacts:**
1. **Eliminates FK Inconsistencies:** Impossible for `fact.industry_key ≠ stock.industry_key` (no redundant FKs)
2. **Single Source of Truth:** One authoritative record per security
3. **Enforced Hierarchy Consistency:** Sector is always derived from industry (no divergence)
4. **Simplified Validation:** One table to validate vs. six

**Risk Factors:**
1. **Denormalization Stale Data:** If source dimensions update, consolidated dimension must be refreshed
2. **Update Complexity:** Changing issuer_name requires updating dim_security (not just dim_issuer)

**Mitigation:**
- **Type 1 SCD Strategy:** Securities are current-state only (no history), simplifying updates
- **Refresh Strategy:** Rebuild dim_security nightly from source dimensions (low cost with 30 rows)
- **Validation Queries:** Section 4.3 queries detect denormalization drift

---

## 7. Migration Considerations

### 7.1 Phased Migration Approach

**Phase 1: Build Consolidated Dimension**
1. Create `dim_security` table (Section 2.1 DDL)
2. Populate from source dimensions (Section 4.2 SQL)
3. Validate data integrity (Section 4.3 queries)
4. Create indexes (Section 3.1)

**Phase 2: Parallel Operation**
1. Keep both old and new schemas active
2. ETL updates both `dim_stock` (+ 5 parent dimensions) AND `dim_security`
3. New queries use `dim_security`
4. Legacy queries continue using old schema

**Phase 3: Fact Table Migration**
1. Add `stock_key` FK to `fact_equity_trade` (if not already present)
2. Validate `fact.stock_key` matches source data
3. Test queries with new FK join path
4. Drop 5 redundant FKs from fact table (issuer_key, industry_key, sector_key, exchange_key, currency_key)

**Phase 4: Deprecation**
1. Migrate remaining legacy queries to use `dim_security`
2. Drop FK constraints from `dim_security` to source dimensions
3. Retire original 6 dimension tables (or keep as archived reference)

---

### 7.2 Rollback Strategy

**Rollback Triggers:**
- Unexpected NULL values in denormalized columns
- Performance degradation in critical queries
- Data quality issues detected in validation queries

**Rollback Process:**
1. Revert fact table FKs (restore 5 redundant keys)
2. Point queries back to original 6 dimensions
3. Retain `dim_security` for analysis
4. Investigate root cause before re-attempting migration

**Rollback Safety:** Legacy foreign keys in `dim_security` enable instant rollback without data loss.

---

## 8. Expected Benefits Summary

### 8.1 Quantitative Benefits

| Metric | Before | After | Improvement |
|--------|--------|-------|-------------|
| **Security Dimension Tables** | 6 | 1 | **83% reduction** |
| **Fact Table Security FKs** | 6 | 1 | **83% reduction** |
| **Joins in Wide SELECT (Q01)** | 6 | 1 | **83% reduction** |
| **Joins in Redundant Pattern (Q09)** | 5 | 1 | **80% reduction** |
| **Queries Requiring Refactoring** | 17 | 17 | Migration effort |
| **Queries with No Changes** | 13 | 13 | 43% unaffected |

---

### 8.2 Qualitative Benefits

**Developer Experience:**
- **Simpler Mental Model:** One security dimension instead of navigating 6-table hierarchy
- **Reduced Join Complexity:** Sector/industry attributes accessible without intermediate joins
- **Self-Documenting Schema:** Prefixed column names (issuer_name, industry_name) clarify attribute source
- **Impossible Anti-Patterns:** Redundant joins (Q09, Q22) structurally prevented

**Data Quality:**
- **No FK Inconsistencies:** Single FK in fact table eliminates `stock.industry_key ≠ fact.industry_key` errors
- **Enforced Hierarchy:** Industry-sector relationship always consistent
- **Single Source of Truth:** One authoritative record per security

**Query Performance:**
- **Join Elimination:** 5 joins removed in complex queries (Q01, Q04, Q19)
- **Direct Attribute Access:** Sector accessible without joining through industry
- **Reduced Optimizer Complexity:** Fewer join paths to evaluate

**Operational:**
- **Simplified ETL:** One dimension to load (though with multi-way source join)
- **Easier Troubleshooting:** One table to inspect for data quality issues
- **Reduced Schema Maintenance:** Changes to security attributes managed in single table

---

## 9. Query Refactoring Examples

### 9.1 Before/After: Q01 (Wide SELECT with All Dimensions)

**BEFORE (Current Schema):**
```sql
SELECT 
  t.trade_id,
  t.trade_date,
  s.ticker,
  s.lot_size,
  s.share_class,
  i.issuer_name,
  ind.industry_name,
  sec.sector_name,
  ex.exchange_name,
  ex.mic_code,
  ccy.currency_code,
  t.quantity,
  t.price_local,
  t.gross_amount_usd
FROM fact_equity_trade t
JOIN dim_stock s ON t.stock_key = s.stock_key                   -- Join 1
JOIN dim_issuer i ON t.issuer_key = i.issuer_key                -- Join 2
JOIN dim_industry ind ON t.industry_key = ind.industry_key      -- Join 3
JOIN dim_sector sec ON ind.sector_key = sec.sector_key          -- Join 4 (INDIRECT)
JOIN dim_exchange ex ON t.exchange_key = ex.exchange_key        -- Join 5
JOIN dim_currency ccy ON t.currency_key = ccy.currency_key      -- Join 6
WHERE t.trade_date = '2024-01-15';
```

**AFTER (Consolidated Schema):**
```sql
SELECT 
  t.trade_id,
  t.trade_date,
  sec.ticker,
  sec.lot_size,
  sec.share_class,
  sec.issuer_name,
  sec.industry_name,
  sec.sector_name,
  sec.exchange_name,
  sec.exchange_mic_code,
  sec.currency_code,
  t.quantity,
  t.price_local,
  t.gross_amount_usd
FROM fact_equity_trade t
JOIN dim_security sec ON t.stock_key = sec.stock_key            -- Single join!
WHERE t.trade_date = '2024-01-15';
```

**Impact:** **6 joins → 1 join** (83% reduction)

---

### 9.2 Before/After: Q09 (Redundant Join Anti-Pattern)

**BEFORE (Current Schema - Anti-Pattern):**
```sql
SELECT 
  sec.sector_name,
  SUM(t.gross_amount_usd) as total_amount
FROM fact_equity_trade t
JOIN dim_industry ind1 ON t.industry_key = ind1.industry_key    -- Path 1: via fact FK
JOIN dim_sector sec ON ind1.sector_key = sec.sector_key         -- Path 1: via industry
JOIN dim_stock s ON t.stock_key = s.stock_key                   -- Path 2: start
JOIN dim_industry ind2 ON s.industry_key = ind2.industry_key    -- Path 2: via stock FK
JOIN dim_sector sec2 ON ind2.sector_key = sec2.sector_key       -- Path 2: via industry (REDUNDANT!)
WHERE sec.sector_name = sec2.sector_name                        -- Validates consistency (always true)
GROUP BY sec.sector_name;
```

**AFTER (Consolidated Schema):**
```sql
SELECT 
  sec.sector_name,
  SUM(t.gross_amount_usd) as total_amount
FROM fact_equity_trade t
JOIN dim_security sec ON t.stock_key = sec.stock_key            -- Single join!
GROUP BY sec.sector_name;
```

**Impact:** 
- **5 joins → 1 join** (80% reduction)
- **Anti-pattern eliminated** (redundant validation no longer possible/necessary)

---

### 9.3 Before/After: Q14 (Indirect Sector Access)

**BEFORE (Current Schema):**
```sql
SELECT 
  sec.sector_name,
  ex.exchange_name,
  COUNT(DISTINCT t.trade_id) as trade_count
FROM fact_equity_trade t
JOIN dim_industry ind ON t.industry_key = ind.industry_key      -- Required for sector access
JOIN dim_sector sec ON ind.sector_key = sec.sector_key          -- INDIRECT sector access
JOIN dim_exchange ex ON t.exchange_key = ex.exchange_key
GROUP BY sec.sector_name, ex.exchange_name;
```

**AFTER (Consolidated Schema):**
```sql
SELECT 
  sec.sector_name,
  sec.exchange_name,
  COUNT(DISTINCT t.trade_id) as trade_count
FROM fact_equity_trade t
JOIN dim_security sec ON t.stock_key = sec.stock_key            -- DIRECT sector access
GROUP BY sec.sector_name, sec.exchange_name;
```

**Impact:** 
- **3 joins → 1 join** (67% reduction)
- **Direct sector access** (no intermediate industry join required)

---

### 9.4 Before/After: Q17 (Non-Stock Dimension Join)

**BEFORE (Current Schema):**
```sql
SELECT 
  ex.exchange_name,
  COUNT(*) as trade_count
FROM fact_equity_trade t
JOIN dim_exchange ex ON t.exchange_key = ex.exchange_key        -- Direct from fact FK
GROUP BY ex.exchange_name;
```

**AFTER (Consolidated Schema):**
```sql
SELECT 
  sec.exchange_name,
  COUNT(*) as trade_count
FROM fact_equity_trade t
JOIN dim_security sec ON t.stock_key = sec.stock_key            -- Via stock dimension
GROUP BY sec.exchange_name;
```

**Impact:** 
- **Same join count** (1 join before and after)
- **FK path changes** (fact.exchange_key → fact.stock_key → dim_security.exchange_name)
- **Requires query refactoring** but no performance degradation

---

## 10. Next Steps and Dependencies

### 10.1 Prerequisites for Implementation

| Prerequisite | Status | Reference |
|--------------|--------|-----------|
| Relationship validation (M:1 cardinality) | ✅ Complete | Section 2 |
| Referential integrity proof | ✅ Complete | Section 2 |
| Downstream query inventory | ✅ Complete | Section 3 |
| Consolidated dimension design | ✅ Complete | This section |

---

### 10.2 Next Section Preview: Section 5 (Migration Plan by Downstream Object)

Section 5 will provide:

1. **Query-by-Query Refactoring Plan:**
   - All 17 queries using security dimensions
   - Before/after SQL for each query
   - Validation queries to compare results

2. **Fact Table Migration:**
   - ALTER TABLE scripts to drop redundant FKs
   - Validation queries to ensure data consistency
   - Rollback scripts if needed

3. **ETL Process Updates:**
   - Dimension load process (populate dim_security from 6 sources)
   - Fact table load process (use stock_key only)
   - Incremental refresh strategy

4. **Testing Strategy:**
   - Unit tests for each refactored query
   - Integration tests for end-to-end workflows
   - Performance benchmarking (before/after comparison)

5. **Deployment Plan:**
   - Phased rollout timeline
   - Rollback decision points
   - Communication plan for stakeholders

---

## Appendix A: Complete Column Mapping

| dim_security Column | Source Table | Source Column | Data Type | Notes |
|---------------------|--------------|---------------|-----------|-------|
| stock_key | dim_stock | stock_key | INT | Primary key |
| ticker | dim_stock | ticker | VARCHAR(10) | Business key |
| share_class | dim_stock | share_class | VARCHAR(10) | Stock attribute |
| lot_size | dim_stock | lot_size | INT | Stock attribute |
| market_cap_bucket | dim_stock | market_cap_bucket | VARCHAR(20) | Stock attribute |
| reference_price | dim_stock | reference_price | DECIMAL(18,4) | Stock attribute |
| issuer_key | dim_stock | issuer_key | INT | Legacy FK (preserved) |
| industry_key | dim_stock | industry_key | INT | Legacy FK (preserved) |
| sector_key | dim_stock | sector_key | INT | Legacy FK (preserved) |
| exchange_key | dim_stock | exchange_key | INT | Legacy FK (preserved) |
| currency_key | dim_stock | currency_key | INT | Legacy FK (preserved) |
| issuer_name | dim_issuer | issuer_name | VARCHAR(150) | Denormalized (via issuer_key) |
| issuer_country_key | dim_issuer | country_key | INT | External FK (not consolidated) |
| industry_name | dim_industry | industry_name | VARCHAR(100) | Denormalized (via industry_key) |
| sector_name | dim_sector | sector_name | VARCHAR(100) | Denormalized (via industry.sector_key) |
| exchange_mic_code | dim_exchange | mic_code | VARCHAR(10) | Denormalized (via exchange_key) |
| exchange_name | dim_exchange | exchange_name | VARCHAR(100) | Denormalized (via exchange_key) |
| exchange_country_key | dim_exchange | country_key | INT | External FK (not consolidated) |
| currency_code | dim_currency | currency_code | VARCHAR(3) | Denormalized (via currency_key) |
| currency_name | dim_currency | currency_name | VARCHAR(100) | Denormalized (via currency_key) |

**Total Columns:** 22  
**Total Storage per Row:** ~200 bytes (estimated)

---

## Appendix B: DuckDB-Specific Considerations

### B.1 Data Type Compatibility

All data types in the DDL are DuckDB-native:
- `INT` - 32-bit signed integer
- `VARCHAR(N)` - Variable-length string with max length N
- `DECIMAL(18,4)` - Fixed-precision decimal (18 digits total, 4 after decimal point)

**No modifications needed** for DuckDB execution.

---

### B.2 Index Creation Syntax

DuckDB supports standard SQL index creation:

```sql
-- Primary key index (created automatically by PRIMARY KEY constraint)

-- Secondary indexes
CREATE INDEX idx_security_ticker ON dim_security(ticker);
CREATE INDEX idx_security_exchange_name ON dim_security(exchange_name);
CREATE INDEX idx_security_sector_name ON dim_security(sector_name);
CREATE INDEX idx_security_industry_name ON dim_security(industry_name);
CREATE INDEX idx_security_currency_code ON dim_security(currency_code);
CREATE INDEX idx_security_issuer_name ON dim_security(issuer_name);
```

**Note:** DuckDB automatically creates indexes on primary keys and foreign keys.

---

### B.3 Foreign Key Constraint Behavior

DuckDB enforces foreign key constraints by default:
- INSERT/UPDATE to `dim_security` will fail if legacy keys reference non-existent parent records
- DELETE from parent dimensions (e.g., dim_issuer) will fail if referenced by `dim_security`

**Migration Impact:** Keep parent dimensions intact until `dim_security` is fully validated.

---

## Appendix C: Design Alternatives Considered

### C.1 Alternative 1: Keep Minimal Denormalization

**Approach:** Preserve foreign keys only, do not denormalize descriptive attributes.

**Pros:**
- Smaller table (11 columns vs. 22)
- No data duplication
- Easier updates to reference data

**Cons:**
- Queries still require joins to get descriptive attributes (issuer_name, sector_name, etc.)
- Does not eliminate join complexity in queries like Q01, Q04
- Does not prevent anti-patterns like Q09

**Decision:** **Rejected** - Insufficient query simplification benefit.

---

### C.2 Alternative 2: Full Denormalization (Include Country Attributes)

**Approach:** Also denormalize dim_country attributes (country_name) for issuer and exchange.

**Pros:**
- Complete elimination of all dimensional joins
- Self-contained security dimension

**Cons:**
- Scope creep (dim_country is not a security dimension)
- Additional 2 columns (issuer_country_name, exchange_country_name)
- Country data may be used by other non-security dimensions

**Decision:** **Rejected** - Out of scope. Preserve country_key foreign keys for flexibility.

---

### C.3 Alternative 3: Type 2 SCD Design (Historical Tracking)

**Approach:** Add effective_date, expiry_date, is_current columns to track security attribute changes over time.

**Pros:**
- Historical analysis capabilities (e.g., "What was the sector of AAPL on 2020-01-01?")
- Tracks ticker changes, industry reclassifications

**Cons:**
- Significantly increased complexity (SCD Type 2 logic)
- Higher storage (multiple rows per stock)
- No current business requirement for historical tracking

**Decision:** **Rejected** - Current schema uses Type 1 SCD (current state only). Recommend Type 2 as future enhancement if business needs emerge.

---

**Document Version:** 1.0  
**Created:** 2025  
**Status:** Complete - Ready for Section 5 (Migration Plan by Downstream Object)
