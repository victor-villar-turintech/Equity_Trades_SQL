-- Non-optimised SQL benchmark queries for synthetic equity trade dataset
-- Assumes tables already exist:
-- fact_equity_trade, dim_stock, dim_issuer, dim_industry, dim_sector,
-- dim_exchange, dim_country, dim_currency, dim_broker, dim_trader, dim_account

-- Q01: Repeat joins and select many columns instead of projecting narrowly
SELECT
    t.trade_id,
    t.trade_ts,
    t.side,
    t.trade_status,
    t.order_type,
    t.settlement_type,
    t.quantity,
    t.price,
    t.gross_amount,
    s.ticker,
    s.isin,
    s.lot_size,
    s.instrument_type,
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
WHERE t.price > 0;

-- Q02: Function on timestamp column in filter prevents efficient pruning
SELECT COUNT(*) AS trade_count
FROM fact_equity_trade t
WHERE CAST(t.trade_ts AS DATE) BETWEEN DATE '2025-01-01' AND DATE '2025-12-31';

-- Q03: Leading wildcard LIKE on ticker description style search
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

-- Q05: Correlated subquery for per-account average gross amount
SELECT
    a.account_name,
    t.trade_id,
    t.gross_amount
FROM fact_equity_trade t
JOIN dim_account a ON t.account_key = a.account_key
WHERE t.gross_amount > (
    SELECT AVG(t2.gross_amount)
    FROM fact_equity_trade t2
    WHERE t2.account_key = t.account_key
);

-- Q06: Self-join on fact for same stock and day
SELECT COUNT(*) AS pair_count
FROM fact_equity_trade t1
JOIN fact_equity_trade t2
  ON t1.stock_key = t2.stock_key
 AND CAST(t1.trade_ts AS DATE) = CAST(t2.trade_ts AS DATE)
 AND t1.trade_id < t2.trade_id;

-- Q07: ORDER BY on computed expression across full set
SELECT
    t.trade_id,
    t.quantity,
    t.price,
    (t.quantity * t.price) / NULLIF(s.lot_size, 0) AS notional_per_lot
FROM fact_equity_trade t
JOIN dim_stock s ON t.stock_key = s.stock_key
ORDER BY ((t.quantity * t.price) / NULLIF(s.lot_size, 0)) DESC
LIMIT 100;

-- Q08: IN subquery instead of join / semijoin rewrite
SELECT COUNT(*) AS high_value_trade_count
FROM fact_equity_trade t
WHERE t.stock_key IN (
    SELECT s.stock_key
    FROM dim_stock s
    JOIN dim_exchange ex ON s.primary_exchange_key = ex.exchange_key
    WHERE ex.country_key IN (
        SELECT c.country_key FROM dim_country c WHERE c.region_name = 'North America'
    )
)
AND t.gross_amount > 100000;

-- Q09: Multiple redundant joins to reach sector even though industry already points to sector
SELECT
    sec.sector_name,
    COUNT(*) AS trade_count,
    SUM(t.gross_amount) AS total_gross
FROM fact_equity_trade t
JOIN dim_industry ind1 ON t.industry_key = ind1.industry_key
JOIN dim_sector sec ON ind1.sector_key = sec.sector_key
JOIN dim_stock s ON t.stock_key = s.stock_key
JOIN dim_industry ind2 ON s.industry_key = ind2.industry_key
JOIN dim_sector sec2 ON ind2.sector_key = sec2.sector_key
WHERE sec.sector_name = sec2.sector_name
GROUP BY sec.sector_name
ORDER BY total_gross DESC;

-- Q10: Nested aggregation with broad intermediate dataset
SELECT AVG(account_trade_count) AS avg_trades_per_account
FROM (
    SELECT t.account_key, COUNT(*) AS account_trade_count
    FROM fact_equity_trade t
    JOIN dim_account a ON t.account_key = a.account_key
    JOIN dim_broker b ON t.broker_key = b.broker_key
    GROUP BY t.account_key, a.account_name, b.broker_name
) q;

-- Q11: CASE-heavy aggregation with repeated expressions
SELECT
    s.ticker,
    SUM(CASE WHEN t.side = 'BUY' THEN t.quantity * t.price ELSE 0 END) AS buy_notional,
    SUM(CASE WHEN t.side = 'SELL' THEN t.quantity * t.price ELSE 0 END) AS sell_notional,
    SUM(CASE WHEN t.side = 'BUY' AND t.trade_status = 'EXECUTED' THEN t.quantity * t.price ELSE 0 END) AS buy_exec_notional,
    SUM(CASE WHEN t.side = 'SELL' AND t.trade_status = 'EXECUTED' THEN t.quantity * t.price ELSE 0 END) AS sell_exec_notional
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
    SUM(t.gross_amount) AS total_gross
FROM fact_equity_trade t
JOIN dim_account a ON t.account_key = a.account_key
JOIN dim_trader tr ON t.trader_key = tr.trader_key
JOIN dim_broker br ON t.broker_key = br.broker_key
JOIN dim_stock s ON t.stock_key = s.stock_key
JOIN dim_exchange ex ON t.exchange_key = ex.exchange_key
WHERE a.account_name IN ('Alpha UK Fund', 'Global Equity Master', 'Pension Growth Pool')
GROUP BY a.account_name, tr.trader_name, br.broker_name
ORDER BY total_gross DESC;

-- Q13: Union instead of simpler grouped predicate
SELECT COUNT(*) AS cnt
FROM (
    SELECT trade_id FROM fact_equity_trade WHERE side = 'BUY'
    UNION
    SELECT trade_id FROM fact_equity_trade WHERE trade_status = 'EXECUTED'
) q;

-- Q14: Re-aggregate already aggregated dataset with unnecessary sort
SELECT sector_name, SUM(total_gross) AS grand_total
FROM (
    SELECT sec.sector_name, ex.exchange_name, SUM(t.gross_amount) AS total_gross
    FROM fact_equity_trade t
    JOIN dim_industry ind ON t.industry_key = ind.industry_key
    JOIN dim_sector sec ON ind.sector_key = sec.sector_key
    JOIN dim_exchange ex ON t.exchange_key = ex.exchange_key
    GROUP BY sec.sector_name, ex.exchange_name
    ORDER BY sec.sector_name, ex.exchange_name
) q
GROUP BY sector_name
ORDER BY grand_total DESC;

-- Q15: Window over full fact table for running totals without partition reduction
SELECT
    t.trade_id,
    t.trade_ts,
    s.ticker,
    t.gross_amount,
    SUM(t.gross_amount) OVER (PARTITION BY s.ticker ORDER BY t.trade_ts, t.trade_id) AS running_notional
FROM fact_equity_trade t
JOIN dim_stock s ON t.stock_key = s.stock_key;

-- Q16: Scalar subqueries in select list
SELECT
    t.trade_id,
    (SELECT s.ticker FROM dim_stock s WHERE s.stock_key = t.stock_key) AS ticker,
    (SELECT a.account_name FROM dim_account a WHERE a.account_key = t.account_key) AS account_name,
    (SELECT br.broker_name FROM dim_broker br WHERE br.broker_key = t.broker_key) AS broker_name,
    t.gross_amount
FROM fact_equity_trade t;

-- Q17: HAVING used for non-aggregated filter pattern
SELECT
    ex.exchange_name,
    COUNT(*) AS trade_count,
    AVG(t.price) AS avg_price
FROM fact_equity_trade t
JOIN dim_exchange ex ON t.exchange_key = ex.exchange_key
GROUP BY ex.exchange_name
HAVING AVG(t.price) > 50 OR COUNT(*) > 500;

-- Q18: Cross-date comparison via self-join and extracted dates
SELECT COUNT(*) AS matched_pairs
FROM fact_equity_trade t1
JOIN fact_equity_trade t2
  ON t1.account_key = t2.account_key
 AND t1.stock_key = t2.stock_key
 AND CAST(t1.trade_ts AS DATE) <> CAST(t2.trade_ts AS DATE);

-- Q19: Wide CTE materialization style pattern
WITH enriched AS (
    SELECT
        t.trade_id,
        t.trade_ts,
        t.side,
        t.trade_status,
        t.order_type,
        t.settlement_type,
        t.quantity,
        t.price,
        t.gross_amount,
        s.ticker,
        s.instrument_type,
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
SELECT sector_name, currency_code, COUNT(*) AS trade_count, SUM(gross_amount) AS total_gross
FROM enriched
GROUP BY sector_name, currency_code
ORDER BY total_gross DESC;

-- Q20: Non-sargable arithmetic in filter
SELECT COUNT(*) AS expensive_trade_count
FROM fact_equity_trade t
WHERE (t.quantity * t.price) / 1.0 > 250000;

-- Q21: Repeated date extraction in grouping and ordering
SELECT
    CAST(t.trade_ts AS DATE) AS trade_date,
    COUNT(*) AS trade_count,
    SUM(t.gross_amount) AS total_gross
FROM fact_equity_trade t
GROUP BY CAST(t.trade_ts AS DATE)
ORDER BY CAST(t.trade_ts AS DATE);

-- Q22: Join dims by text after resolving keys first
SELECT COUNT(*) AS cnt
FROM fact_equity_trade t
JOIN dim_stock s ON t.stock_key = s.stock_key
JOIN dim_exchange ex1 ON t.exchange_key = ex1.exchange_key
JOIN dim_exchange ex2 ON s.primary_exchange_key = ex2.exchange_key
WHERE ex1.exchange_name = ex2.exchange_name;

-- Q23: Excessively broad ranking query
SELECT *
FROM (
    SELECT
        t.trade_id,
        a.account_name,
        s.ticker,
        t.gross_amount,
        ROW_NUMBER() OVER (PARTITION BY a.account_name ORDER BY t.gross_amount DESC, t.trade_id) AS rn
    FROM fact_equity_trade t
    JOIN dim_account a ON t.account_key = a.account_key
    JOIN dim_stock s ON t.stock_key = s.stock_key
) q
WHERE rn <= 10;

-- Q24: Two-pass notional comparison using self-subquery
SELECT COUNT(*) AS above_global_avg_count
FROM fact_equity_trade t
WHERE t.gross_amount > (
    SELECT AVG(gross_amount) FROM fact_equity_trade
);

-- Q25: String concatenation in grouping key
SELECT
    ex.exchange_name || ' - ' || c.country_name AS venue_label,
    COUNT(*) AS trade_count,
    SUM(t.gross_amount) AS total_gross
FROM fact_equity_trade t
JOIN dim_exchange ex ON t.exchange_key = ex.exchange_key
JOIN dim_country c ON ex.country_key = c.country_key
GROUP BY ex.exchange_name || ' - ' || c.country_name
ORDER BY total_gross DESC;

-- Q26: Multiple OR branches instead of lookup/set-based simplification
SELECT COUNT(*) AS cnt
FROM fact_equity_trade t
JOIN dim_currency ccy ON t.currency_key = ccy.currency_key
WHERE (ccy.currency_code = 'USD' AND t.gross_amount > 10000)
   OR (ccy.currency_code = 'GBP' AND t.gross_amount > 9000)
   OR (ccy.currency_code = 'EUR' AND t.gross_amount > 9500)
   OR (ccy.currency_code = 'CAD' AND t.gross_amount > 8000)
   OR (ccy.currency_code = 'JPY' AND t.gross_amount > 1200000);

-- Q27: Full outer style logic via union all where simpler logic may exist
SELECT COUNT(*) AS cnt
FROM (
    SELECT stock_key, account_key FROM fact_equity_trade
    UNION ALL
    SELECT stock_key, account_key FROM fact_equity_trade WHERE trade_status = 'EXECUTED'
) q;

-- Q28: Repeated enrichment for simple top brokers output
SELECT
    br.broker_name,
    COUNT(*) AS trade_count,
    SUM(t.gross_amount) AS total_gross,
    AVG(t.price) AS avg_price,
    MIN(t.trade_ts) AS first_trade_ts,
    MAX(t.trade_ts) AS last_trade_ts
FROM fact_equity_trade t
JOIN dim_broker br ON t.broker_key = br.broker_key
JOIN dim_stock s ON t.stock_key = s.stock_key
JOIN dim_exchange ex ON t.exchange_key = ex.exchange_key
JOIN dim_currency ccy ON t.currency_key = ccy.currency_key
GROUP BY br.broker_name
ORDER BY total_gross DESC;

-- Q29: Unnecessary nested distinct and count
SELECT COUNT(*) AS unique_traded_tickers
FROM (
    SELECT DISTINCT ticker
    FROM (
        SELECT s.ticker
        FROM fact_equity_trade t
        JOIN dim_stock s ON t.stock_key = s.stock_key
    ) q1
) q2;

-- Q30: Heavy mart-like query with broad joins and many group keys
SELECT
    CAST(t.trade_ts AS DATE) AS trade_date,
    a.account_type,
    br.broker_tier,
    tr.desk_name,
    sec.sector_name,
    ex.exchange_name,
    ccy.currency_code,
    t.side,
    t.trade_status,
    COUNT(*) AS trade_count,
    SUM(t.quantity) AS total_qty,
    SUM(t.gross_amount) AS total_gross,
    AVG(t.price) AS avg_price
FROM fact_equity_trade t
JOIN dim_account a ON t.account_key = a.account_key
JOIN dim_broker br ON t.broker_key = br.broker_key
JOIN dim_trader tr ON t.trader_key = tr.trader_key
JOIN dim_industry ind ON t.industry_key = ind.industry_key
JOIN dim_sector sec ON ind.sector_key = sec.sector_key
JOIN dim_exchange ex ON t.exchange_key = ex.exchange_key
JOIN dim_currency ccy ON t.currency_key = ccy.currency_key
GROUP BY
    CAST(t.trade_ts AS DATE),
    a.account_type,
    br.broker_tier,
    tr.desk_name,
    sec.sector_name,
    ex.exchange_name,
    ccy.currency_code,
    t.side,
    t.trade_status
ORDER BY trade_date, total_gross DESC;
