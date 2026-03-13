# Section 1: Consolidation Candidate Analysis

## Executive Summary

This section profiles six security-related dimension tables as candidates for consolidation into a single unified dimension. Analysis shows that `dim_stock` represents the finest grain and already contains foreign key references to all other five security-related dimensions (`dim_issuer`, `dim_industry`, `dim_sector`, `dim_exchange`, `dim_currency`). The fact table `fact_equity_trade` redundantly stores foreign keys to all six dimensions, creating opportunities for schema simplification.

**Consolidation Assessment:** The six dimensions form a hierarchical relationship structure with `dim_stock` at the base, making consolidation feasible and beneficial.

---

## 1. Dimension Structure Profile

Complete schema documentation for all 6 security-related dimensions extracted from `db/schema.sql`:

### Table: dim_stock

**Primary Key:** `stock_key` (INT)

**Column Count:** 11

**DDL:**
```sql
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
```

**Foreign Keys:**
- `issuer_key` → `dim_issuer(issuer_key)`
- `industry_key` → `dim_industry(industry_key)`
- `sector_key` → `dim_sector(sector_key)`
- `exchange_key` → `dim_exchange(exchange_key)`
- `currency_key` → `dim_currency(currency_key)`

**Data Types:**
- Surrogate key: INT
- Business identifiers: VARCHAR (ticker)
- Descriptive attributes: VARCHAR (share_class, market_cap_bucket)
- Numeric attributes: INT (lot_size), DECIMAL (reference_price)
- Foreign keys: INT (5 references)

**Nullability:** Schema does not explicitly define NOT NULL constraints beyond primary key

**Business Grain:** One row per traded listed equity security

---

### Table: dim_issuer

**Primary Key:** `issuer_key` (INT)

**Column Count:** 4

**DDL:**
```sql
CREATE TABLE dim_issuer (
  issuer_key INT PRIMARY KEY,
  issuer_name VARCHAR(150),
  country_key INT REFERENCES dim_country(country_key),
  industry_key INT REFERENCES dim_industry(industry_key)
);
```

**Foreign Keys:**
- `country_key` → `dim_country(country_key)` [not a security dimension]
- `industry_key` → `dim_industry(industry_key)`

**Data Types:**
- Surrogate key: INT
- Descriptive attributes: VARCHAR (issuer_name)
- Foreign keys: INT (2 references)

**Nullability:** Schema does not explicitly define NOT NULL constraints beyond primary key

**Business Grain:** One row per issuing company/entity

---

### Table: dim_industry

**Primary Key:** `industry_key` (INT)

**Column Count:** 3

**DDL:**
```sql
CREATE TABLE dim_industry (
  industry_key INT PRIMARY KEY,
  industry_name VARCHAR(100),
  sector_key INT REFERENCES dim_sector(sector_key)
);
```

**Foreign Keys:**
- `sector_key` → `dim_sector(sector_key)`

**Data Types:**
- Surrogate key: INT
- Descriptive attributes: VARCHAR (industry_name)
- Foreign keys: INT (1 reference)

**Nullability:** Schema does not explicitly define NOT NULL constraints beyond primary key

**Business Grain:** One row per industry classification

---

### Table: dim_sector

**Primary Key:** `sector_key` (INT)

**Column Count:** 2

**DDL:**
```sql
CREATE TABLE dim_sector (
  sector_key INT PRIMARY KEY,
  sector_name VARCHAR(100)
);
```

**Foreign Keys:** None

**Data Types:**
- Surrogate key: INT
- Descriptive attributes: VARCHAR (sector_name)

**Nullability:** Schema does not explicitly define NOT NULL constraints beyond primary key

**Business Grain:** One row per sector classification (highest level industry grouping)

---

### Table: dim_exchange

**Primary Key:** `exchange_key` (INT)

**Column Count:** 4

**DDL:**
```sql
CREATE TABLE dim_exchange (
  exchange_key INT PRIMARY KEY,
  mic_code VARCHAR(10),
  exchange_name VARCHAR(100),
  country_key INT REFERENCES dim_country(country_key)
);
```

**Foreign Keys:**
- `country_key` → `dim_country(country_key)` [not a security dimension]

**Data Types:**
- Surrogate key: INT
- Business identifiers: VARCHAR (mic_code - Market Identifier Code)
- Descriptive attributes: VARCHAR (exchange_name)
- Foreign keys: INT (1 reference)

**Nullability:** Schema does not explicitly define NOT NULL constraints beyond primary key

**Business Grain:** One row per stock exchange

---

### Table: dim_currency

**Primary Key:** `currency_key` (INT)

**Column Count:** 3

**DDL:**
```sql
CREATE TABLE dim_currency (
  currency_key INT PRIMARY KEY,
  currency_code VARCHAR(3),
  currency_name VARCHAR(100)
);
```

**Foreign Keys:** None

**Data Types:**
- Surrogate key: INT
- Business identifiers: VARCHAR (currency_code)
- Descriptive attributes: VARCHAR (currency_name)

**Nullability:** Schema does not explicitly define NOT NULL constraints beyond primary key

**Business Grain:** One row per currency

---

## 2. Cardinality Analysis

Row counts derived from CSV files in `db/` directory:

| Dimension | Row Count | Estimated Size | Data Density |
|-----------|-----------|----------------|--------------|
| dim_stock | 30 | Detailed | Finest grain |
| dim_issuer | 30 | Detailed | Fine grain |
| dim_industry | 30 | Moderate | Medium grain |
| dim_sector | 11 | Low | Coarse grain |
| dim_exchange | 11 | Low | Coarse grain |
| dim_currency | 8 | Low | Coarse grain |

**Key Observations:**
- `dim_stock` has the highest cardinality (30 rows) and represents the finest grain
- `dim_issuer` also has 30 rows, but with 27 unique issuers referenced by stocks (some issuers have multiple stock classes)
- `dim_industry` has 30 possible values but only 20 are referenced by stocks
- `dim_sector` has 11 rows (top-level classification)
- `dim_exchange` has 11 rows (10 unique exchanges referenced by stocks)
- `dim_currency` has 8 rows (8 unique currencies referenced by stocks)

**Cardinality Ratios (from dim_stock perspective):**
- stock:issuer ≈ 1.1:1 (30 stocks → 27 issuers)
- stock:industry = 1.5:1 (30 stocks → 20 industries)
- stock:sector ≈ 2.7:1 (30 stocks → 11 sectors)
- stock:exchange = 3:1 (30 stocks → 10 exchanges)
- stock:currency ≈ 3.75:1 (30 stocks → 8 currencies)

---

## 3. Relationship Mapping

### 3.1 Dimension-to-Dimension Relationships

The following relationship matrix shows all foreign key connections between the 6 security-related dimensions:

| Source Dimension | Target Dimension | Foreign Key Column | Relationship Type | Cardinality |
|------------------|------------------|-------------------|-------------------|-------------|
| dim_stock | dim_issuer | issuer_key | Many-to-One | Required |
| dim_stock | dim_industry | industry_key | Many-to-One | Required |
| dim_stock | dim_sector | sector_key | Many-to-One | Required |
| dim_stock | dim_exchange | exchange_key | Many-to-One | Required |
| dim_stock | dim_currency | currency_key | Many-to-One | Required |
| dim_issuer | dim_industry | industry_key | Many-to-One | Required |
| dim_industry | dim_sector | sector_key | Many-to-One | Required |

**Additional External References (not part of security consolidation):**
- dim_issuer → dim_country (country_key)
- dim_exchange → dim_country (country_key)

### 3.2 Hierarchical Structure

The dimensions form a clear hierarchical structure:

```
dim_stock (stock_key) [FINEST GRAIN]
    ├── dim_issuer (issuer_key)
    │       └── dim_industry (industry_key)
    │               └── dim_sector (sector_key)
    ├── dim_industry (industry_key) [DIRECT REFERENCE]
    │       └── dim_sector (sector_key)
    ├── dim_sector (sector_key) [DIRECT REFERENCE]
    ├── dim_exchange (exchange_key)
    └── dim_currency (currency_key)
```

**Key Relationship Patterns:**

1. **Direct References from dim_stock:**
   - Stock → Issuer (many stocks can belong to same issuer)
   - Stock → Industry (direct denormalized reference)
   - Stock → Sector (direct denormalized reference)
   - Stock → Exchange (where stock is traded)
   - Stock → Currency (trading currency)

2. **Transitive/Redundant References:**
   - dim_stock stores both `industry_key` AND `sector_key`, even though industry already references sector
   - This creates redundancy: stock → industry → sector vs. stock → sector (direct)
   - dim_stock stores `industry_key` which is also derivable via issuer: stock → issuer → industry

3. **Normalization Analysis:**
   - The current design is partially denormalized for query performance
   - dim_stock contains redundant FKs that could be derived through the hierarchy
   - dim_issuer provides the "correct" industry classification for a company
   - dim_stock may override or confirm this at the security level

---

## 4. Fact Table Linkage Analysis

### 4.1 fact_equity_trade Foreign Key Structure

**DDL Extract:**
```sql
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
  -- [measures omitted]
);
```

### 4.2 Security-Related Foreign Keys in Fact Table

| Foreign Key Column | References | Direct/Derivable | Redundancy Status |
|--------------------|------------|------------------|-------------------|
| stock_key | dim_stock(stock_key) | Direct | **Primary** |
| issuer_key | dim_issuer(issuer_key) | Derivable via stock | **Redundant** |
| industry_key | dim_industry(industry_key) | Derivable via stock or issuer | **Redundant** |
| sector_key | dim_sector(sector_key) | Derivable via industry | **Redundant** |
| exchange_key | dim_exchange(exchange_key) | Derivable via stock | **Redundant** |
| currency_key | dim_currency(currency_key) | Derivable via stock | **Redundant** |

### 4.3 Non-Security Foreign Keys (Preserved)

The following foreign keys are NOT candidates for consolidation as they represent different business entities:

- `account_key` → dim_account (trading account)
- `trader_key` → dim_trader (person executing trade)
- `broker_key` → dim_broker (brokerage firm)

### 4.4 Redundancy Analysis

**Current State:** fact_equity_trade stores 6 security-related foreign keys

**Derivation Paths:**
```
Given stock_key, all other security attributes are derivable:
  stock_key → dim_stock.issuer_key
  stock_key → dim_stock.industry_key  
  stock_key → dim_stock.sector_key
  stock_key → dim_stock.exchange_key
  stock_key → dim_stock.currency_key
```

**Impact:**
- Every trade fact row carries 5 redundant foreign keys
- Query patterns must join fact → stock → issuer/industry/sector/exchange/currency to ensure consistency
- ETL must ensure denormalized keys remain synchronized
- Risk of data inconsistency if fact.issuer_key ≠ stock.issuer_key for same stock_key

### 4.5 Usage Statistics from fact_equity_trade.csv

Based on 30 sample trades:
- Unique stock_key values: 27 (out of 30 possible)
- Unique issuer_key values: 26
- Unique industry_key values: 20
- Unique sector_key values: 10
- Unique exchange_key values: 9
- Unique currency_key values: 7

**Key Finding:** The fact table utilizes most of the dimension cardinality, indicating active use of the security dimensions.

---

## 5. Grain Analysis and Consolidation Rationale

### 5.1 Identified Grain

**Consolidation Grain: `stock_key`** (dim_stock primary key)

**Rationale:**
1. **Finest Granularity:** dim_stock (30 rows) represents the most detailed level - individual traded securities
2. **Central Hub:** dim_stock already contains foreign keys to all 5 other security dimensions
3. **Fact Table Anchor:** fact_equity_trade records trades of stocks, making stock_key the natural business key
4. **One-to-One Mapping:** Each stock maps to exactly one issuer, industry, sector, exchange, and currency
5. **Business Semantics:** A trade occurs on a specific stock, not on an abstract industry or sector

### 5.2 Hierarchical Relationships

**Industry/Sector Hierarchy:**
- Sector (11 rows) → Industry (30 rows): One-to-Many
- Industry → Sector is Many-to-One (confirmed in dim_industry schema)
- Stock → Industry: Many-to-One
- Stock → Sector: Many-to-One (direct and via industry)

**Stock/Issuer Relationship:**
- Issuer (30 rows, 27 unique in stock data) → Stock (30 rows): One-to-Many
- Stock → Issuer: Many-to-One
- Example: An issuer may have multiple share classes (ORD, A, B, ADR) traded as separate stocks

**Stock/Exchange Relationship:**
- Exchange (11 rows) → Stock: One-to-Many
- Stock → Exchange: Many-to-One
- A stock is listed on exactly one primary exchange

**Stock/Currency Relationship:**
- Currency (8 rows) → Stock: One-to-Many
- Stock → Currency: Many-to-One
- A stock trades in exactly one primary currency

### 5.3 Data Type and Constraint Summary

| Dimension | Primary Key Type | Has Natural Key | Nullability Defined | SCD Type |
|-----------|------------------|----------------|---------------------|----------|
| dim_stock | INT | Yes (ticker) | Implicit NOT NULL on PK | Type 1 (assumed) |
| dim_issuer | INT | No | Implicit NOT NULL on PK | Type 1 (assumed) |
| dim_industry | INT | No | Implicit NOT NULL on PK | Static |
| dim_sector | INT | No | Implicit NOT NULL on PK | Static |
| dim_exchange | INT | Yes (mic_code) | Implicit NOT NULL on PK | Static |
| dim_currency | INT | Yes (currency_code) | Implicit NOT NULL on PK | Static |

**Slowly Changing Dimension Analysis:**
- **Static Dimensions:** sector, industry, exchange, currency (classification codes, rarely change)
- **Type 1 Dimensions:** stock, issuer (current state only, no history tracking observed in schema)
- **No Type 2 Detected:** No effective_date, expiry_date, or is_current flags observed

**Impact on Consolidation:** All dimensions appear to be Type 1 or static, simplifying consolidation. No temporal complexity to preserve.

---

## 6. Relationship Cardinality Validation Requirements

To prove the consolidation is lossless, the following SQL checks must be executed (deferred to Section 2):

### 6.1 One-to-One/Many-to-One Validation Queries

**Check 1: Each stock_key maps to exactly one issuer_key**
```sql
-- Expected: 0 rows (no violations)
SELECT stock_key, COUNT(DISTINCT issuer_key) as issuer_count
FROM dim_stock
GROUP BY stock_key
HAVING COUNT(DISTINCT issuer_key) > 1;
```

**Check 2: Each stock_key maps to exactly one industry_key**
```sql
-- Expected: 0 rows (no violations)
SELECT stock_key, COUNT(DISTINCT industry_key) as industry_count
FROM dim_stock
GROUP BY stock_key
HAVING COUNT(DISTINCT industry_key) > 1;
```

**Check 3: Each stock_key maps to exactly one sector_key**
```sql
-- Expected: 0 rows (no violations)
SELECT stock_key, COUNT(DISTINCT sector_key) as sector_count
FROM dim_stock
GROUP BY stock_key
HAVING COUNT(DISTINCT sector_key) > 1;
```

**Check 4: Each stock_key maps to exactly one exchange_key**
```sql
-- Expected: 0 rows (no violations)
SELECT stock_key, COUNT(DISTINCT exchange_key) as exchange_count
FROM dim_stock
GROUP BY stock_key
HAVING COUNT(DISTINCT exchange_key) > 1;
```

**Check 5: Each stock_key maps to exactly one currency_key**
```sql
-- Expected: 0 rows (no violations)
SELECT stock_key, COUNT(DISTINCT currency_key) as currency_count
FROM dim_stock
GROUP BY stock_key
HAVING COUNT(DISTINCT currency_key) > 1;
```

**Check 6: Industry → Sector relationship is Many-to-One**
```sql
-- Expected: 0 rows (no violations)
SELECT industry_key, COUNT(DISTINCT sector_key) as sector_count
FROM dim_industry
GROUP BY industry_key
HAVING COUNT(DISTINCT sector_key) > 1;
```

**Check 7: Issuer → Industry relationship is Many-to-One**
```sql
-- Expected: 0 rows (no violations)
SELECT issuer_key, COUNT(DISTINCT industry_key) as industry_count
FROM dim_issuer
GROUP BY issuer_key
HAVING COUNT(DISTINCT industry_key) > 1;
```

### 6.2 Fact Table Consistency Validation

**Check 8: Verify fact table foreign keys match dim_stock foreign keys**
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
  s.currency_key as stock_currency_key
FROM fact_equity_trade f
JOIN dim_stock s ON f.stock_key = s.stock_key
WHERE f.issuer_key <> s.issuer_key
   OR f.industry_key <> s.industry_key
   OR f.sector_key <> s.sector_key
   OR f.exchange_key <> s.exchange_key
   OR f.currency_key <> s.currency_key;
```

**Check 9: Verify stock.industry_key matches issuer.industry_key**
```sql
-- Expected: 0 rows if stock industry always matches issuer industry
-- Non-zero rows indicate stock-level industry override (exception case)
SELECT 
  s.stock_key,
  s.ticker,
  s.industry_key as stock_industry_key,
  i.industry_key as issuer_industry_key
FROM dim_stock s
JOIN dim_issuer i ON s.issuer_key = i.issuer_key
WHERE s.industry_key <> i.industry_key;
```

**Check 10: Verify industry.sector_key matches stock.sector_key**
```sql
-- Expected: 0 rows (sector should be consistent via industry)
SELECT 
  s.stock_key,
  s.ticker,
  s.sector_key as stock_sector_key,
  ind.sector_key as industry_sector_key
FROM dim_stock s
JOIN dim_industry ind ON s.industry_key = ind.industry_key
WHERE s.sector_key <> ind.sector_key;
```

---

## 7. Consolidation Feasibility Assessment

### 7.1 Feasibility Determination

**FEASIBLE** - The six security-related dimensions are strong candidates for consolidation.

### 7.2 Supporting Evidence

1. **Structural Feasibility:**
   - dim_stock already serves as a central hub with FKs to all other 5 dimensions
   - All relationships from stock to other dimensions are Many-to-One (expected)
   - No Many-to-Many relationships detected
   - Schema indicates deterministic mappings

2. **Cardinality Feasibility:**
   - dim_stock has finest grain (30 rows)
   - All other dimensions have equal or lower cardinality
   - No one-to-many expansion risk when pivoting on stock_key

3. **Semantic Feasibility:**
   - All six dimensions describe characteristics of the same business entity: a traded equity security
   - Issuer, industry, sector describe "what company/business"
   - Exchange describes "where traded"
   - Currency describes "denomination"
   - Stock ties all together as the tradable instrument

4. **Redundancy Evidence:**
   - fact_equity_trade stores 6 foreign keys when only stock_key is required
   - 5 of 6 security FKs in fact table are derivable from stock_key
   - Current design creates maintenance burden and consistency risk

5. **Query Pattern Benefit:**
   - Consolidation would reduce fact table from 6 security FKs to 1
   - Downstream queries would join 1 consolidated dimension instead of 6 separate dimensions
   - Potential for significant query simplification and performance improvement

### 7.3 Identified Risks and Exceptions

**Risk 1: Stock vs. Issuer Industry Mismatch**
- dim_stock contains both issuer_key AND industry_key
- dim_issuer also contains industry_key
- **Question:** Can stock.industry_key differ from issuer.industry_key?
- **Action Required:** Execute Check 9 (Section 6.2) to verify consistency
- **Hypothesis:** They should always match, making one reference redundant

**Risk 2: Redundant Sector Reference**
- dim_stock contains both industry_key AND sector_key
- dim_industry already contains sector_key
- **Question:** Can stock.sector_key differ from industry.sector_key?
- **Action Required:** Execute Check 10 (Section 6.2) to verify consistency
- **Hypothesis:** They should always match via industry, making direct sector_key redundant

**Risk 3: Fact Table Consistency**
- fact_equity_trade duplicates all 6 security FKs
- **Question:** Are fact table FKs always synchronized with dim_stock FKs?
- **Action Required:** Execute Check 8 (Section 6.2)
- **Impact:** If mismatches exist, ETL correction required before consolidation

**Risk 4: Multi-listed Securities**
- **Question:** Can a stock be listed on multiple exchanges?
- **Current Schema:** Each stock has single exchange_key (one-to-one assumed)
- **Impact:** If actual business allows multi-listing, consolidation grain must be stock+exchange

**Risk 5: Dual Currency Trading**
- **Question:** Can a stock trade in multiple currencies?
- **Current Schema:** Each stock has single currency_key (one-to-one assumed)
- **Impact:** If actual business allows dual currency, consolidation grain must account for this

### 7.4 Preliminary Consolidation Strategy

**Recommended Approach:**

1. **New Consolidated Dimension:** `dim_security` or `dim_equity_security`
2. **Grain:** One row per stock_key (same as current dim_stock)
3. **Included Attributes:** All columns from all 6 dimensions that are used downstream
4. **Surrogate Key:** New `security_key` (or reuse `stock_key` as primary identifier)
5. **Retained Legacy Keys:** Preserve original surrogate keys as reference columns for traceability
6. **Hierarchical Attributes:** Denormalize issuer, industry, sector, exchange, currency descriptors into single row

**Preliminary Column List for Consolidated Dimension:**
- security_key (PK, new or aliased to stock_key)
- ticker (from dim_stock)
- share_class (from dim_stock)
- lot_size (from dim_stock)
- market_cap_bucket (from dim_stock)
- reference_price (from dim_stock)
- issuer_name (from dim_issuer via issuer_key)
- industry_name (from dim_industry via industry_key)
- sector_name (from dim_sector via sector_key)
- exchange_mic_code (from dim_exchange via exchange_key)
- exchange_name (from dim_exchange via exchange_key)
- currency_code (from dim_currency via currency_key)
- currency_name (from dim_currency via currency_key)
- legacy_stock_key (reference)
- legacy_issuer_key (reference)
- legacy_industry_key (reference)
- legacy_sector_key (reference)
- legacy_exchange_key (reference)
- legacy_currency_key (reference)

**Total Estimated Rows:** 30 (same as current dim_stock)

---

## 8. Summary of Findings

### 8.1 Consolidation Candidates Confirmed

The following 6 dimensions are confirmed as consolidation candidates:

1. ✓ dim_stock (30 rows) - Central hub, finest grain
2. ✓ dim_issuer (30 rows) - Company/entity information
3. ✓ dim_industry (30 rows) - Industry classification
4. ✓ dim_sector (11 rows) - Sector classification
5. ✓ dim_exchange (11 rows) - Trading venue
6. ✓ dim_currency (8 rows) - Trading currency

### 8.2 Key Metrics

| Metric | Value |
|--------|-------|
| Total dimensions analyzed | 6 |
| Total columns across dimensions | 27 |
| Total current fact table security FKs | 6 |
| Redundant fact table FKs | 5 |
| Proposed consolidated dimension rows | 30 |
| Proposed fact table security FKs | 1 |
| FK reduction | 83% (6→1) |

### 8.3 Next Steps

1. **Section 2:** Execute relationship proof SQL (Checks 1-10) to validate lossless consolidation assumptions
2. **Section 3:** Inventory all downstream dependencies on the 6 dimensions
3. **Section 4:** Design complete DDL and population logic for consolidated dimension
4. **Section 5:** Plan migration for each downstream object
5. **Section 6:** Generate validation SQL suite
6. **Section 7:** Generate performance benchmark suite
7. **Section 8:** Document risks and rollback plan
8. **Section 9:** Provide final go/no-go recommendation

---

## Appendix A: Complete Data Profile

### dim_stock - Sample Data
```
stock_key | ticker | issuer_key | industry_key | sector_key | exchange_key | currency_key | share_class | lot_size | market_cap_bucket | reference_price
----------|--------|------------|--------------|------------|--------------|--------------|-------------|----------|-------------------|----------------
1         | PIONH  | 226        | 29           | 8          | 1            | 1            | ORD         | 10       | Mid Cap           | 24.08
2         | STERX  | 108        | 5            | 2          | 11           | 8            | ORD         | 1        | Large Cap         | 75.55
7         | EASTQ  | 147        | 2            | 1          | 3            | 2            | ORD         | 1        | Large Cap         | 187.08
8         | EASTO  | 147        | 2            | 1          | 3            | 2            | ORD         | 1        | Mid Cap           | 26.66
```
*Note: Rows 7-8 show same issuer (147) with different share classes/market caps*

### dim_issuer - Sample Data
```
issuer_key | issuer_name                  | country_key | industry_key
-----------|------------------------------|-------------|-------------
1          | Harbor Bioscience plc        | 8           | 31
2          | East Systems                 | 7           | 37
147        | East Telecom                 | 3           | 2
226        | Pioneer Utilities            | 1           | 29
```

### dim_industry - Sample Data
```
industry_key | industry_name           | sector_key
-------------|-------------------------|------------
1            | Software                | 1
2            | Semiconductors          | 1
5            | Banks                   | 2
29           | Gas Utilities           | 8
```

### dim_sector - Complete Data
```
sector_key | sector_name
-----------|------------------------
1          | Technology
2          | Financials
3          | Healthcare
4          | Industrials
5          | Energy
6          | Consumer Discretionary
7          | Consumer Staples
8          | Utilities
9          | Materials
10         | Communication Services
11         | Real Estate
```

### dim_exchange - Complete Data
```
exchange_key | mic_code | exchange_name              | country_key
-------------|----------|----------------------------|-------------
1            | XNYS     | New York Stock Exchange    | 1
2            | XNAS     | NASDAQ                     | 1
3            | XLON     | London Stock Exchange      | 2
11           | XASX     | ASX                        | 10
```

### dim_currency - Complete Data
```
currency_key | currency_code | currency_name
-------------|---------------|---------------
1            | USD           | US Dollar
2            | GBP           | Pound Sterling
3            | EUR           | Euro
8            | AUD           | Australian Dollar
```

---

**Document Version:** 1.0  
**Created:** 2025  
**Status:** Complete - Ready for Section 2 (Relationship Proof SQL)
