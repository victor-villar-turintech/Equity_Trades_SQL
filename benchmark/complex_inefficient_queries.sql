-- Deliberately pathological SQL workload for the Equity_Trades_SQL repository.
--
-- PURPOSE
--   These queries are intentionally long, redundant, broad, and inefficient.
--   They are designed as optimisation targets for Artemis agents, not as examples
--   of good production SQL.
--
-- WARNING
--   Run with --repeats 1 first. Several queries deliberately perform repeated
--   full scans, text-based joins, correlated subqueries, Cartesian products,
--   wide DISTINCT operations, self-joins, and multiple window passes.
--
-- COMPATIBILITY
--   Written for the repository's DuckDB benchmark runner and the current schema.
--   Query labels must remain in the form "-- QNN:" for the runner to discover them.

-- Q01: Pathological trade-level 360-degree enrichment with redundant dimension paths, scalar lookups, repeated calculations and broad windows
WITH direct_enrichment AS (
    SELECT
        t.trade_id,
        t.trade_timestamp,
        t.trade_date,
        t.settlement_date,
        t.stock_key,
        t.issuer_key,
        t.industry_key,
        t.sector_key,
        t.exchange_key,
        t.currency_key,
        t.account_key,
        t.trader_key,
        t.broker_key,
        t.buy_sell_flag,
        t.execution_venue,
        t.order_type,
        t.quantity,
        t.price_local,
        t.gross_amount_local,
        t.commission_local,
        t.net_amount_local,
        t.fx_to_usd,
        t.gross_amount_usd,
        t.commission_usd,
        t.net_amount_usd,
        s.ticker,
        s.share_class,
        s.lot_size,
        s.market_cap_bucket,
        s.reference_price,
        i.issuer_name,
        ind.industry_name,
        sec.sector_name,
        ex.mic_code,
        ex.exchange_name,
        ex_country.country_code AS exchange_country_code,
        ex_country.country_name AS exchange_country_name,
        issuer_country.country_code AS issuer_country_code,
        issuer_country.country_name AS issuer_country_name,
        ccy.currency_code AS trade_currency_code,
        ccy.currency_name AS trade_currency_name,
        a.account_code,
        a.account_name,
        a.account_type,
        base_ccy.currency_code AS account_base_currency_code,
        base_ccy.currency_name AS account_base_currency_name,
        tr.trader_code,
        tr.trader_name,
        tr.trading_desk,
        br.broker_name,
        s2.ticker AS redundant_ticker,
        i2.issuer_name AS redundant_issuer_name,
        ind2.industry_name AS redundant_industry_name,
        sec2.sector_name AS redundant_sector_name,
        ex2.exchange_name AS redundant_exchange_name,
        ccy2.currency_code AS redundant_currency_code
    FROM fact_equity_trade t
    JOIN dim_stock s ON t.stock_key = s.stock_key
    JOIN dim_issuer i ON t.issuer_key = i.issuer_key
    JOIN dim_industry ind ON t.industry_key = ind.industry_key
    JOIN dim_sector sec ON t.sector_key = sec.sector_key
    JOIN dim_exchange ex ON t.exchange_key = ex.exchange_key
    JOIN dim_country ex_country ON ex.country_key = ex_country.country_key
    JOIN dim_country issuer_country ON i.country_key = issuer_country.country_key
    JOIN dim_currency ccy ON t.currency_key = ccy.currency_key
    JOIN dim_account a ON t.account_key = a.account_key
    JOIN dim_currency base_ccy ON a.base_currency_key = base_ccy.currency_key
    JOIN dim_trader tr ON t.trader_key = tr.trader_key
    JOIN dim_broker br ON t.broker_key = br.broker_key
    JOIN dim_stock s2 ON t.stock_key = s2.stock_key
    JOIN dim_issuer i2 ON s2.issuer_key = i2.issuer_key
    JOIN dim_industry ind2 ON s2.industry_key = ind2.industry_key
    JOIN dim_sector sec2 ON ind2.sector_key = sec2.sector_key
    JOIN dim_exchange ex2 ON s2.exchange_key = ex2.exchange_key
    JOIN dim_currency ccy2 ON s2.currency_key = ccy2.currency_key
),
scalar_lookup_enrichment AS (
    SELECT
        d.*,
        (SELECT MAX(ds.ticker) FROM dim_stock ds WHERE ds.stock_key = d.stock_key) AS scalar_ticker,
        (SELECT MAX(di.issuer_name) FROM dim_issuer di WHERE di.issuer_key = d.issuer_key) AS scalar_issuer_name,
        (SELECT MAX(dind.industry_name) FROM dim_industry dind WHERE dind.industry_key = d.industry_key) AS scalar_industry_name,
        (SELECT MAX(dsec.sector_name) FROM dim_sector dsec WHERE dsec.sector_key = d.sector_key) AS scalar_sector_name,
        (SELECT MAX(dex.exchange_name) FROM dim_exchange dex WHERE dex.exchange_key = d.exchange_key) AS scalar_exchange_name,
        (SELECT MAX(dc.currency_code) FROM dim_currency dc WHERE dc.currency_key = d.currency_key) AS scalar_currency_code,
        (SELECT MAX(da.account_name) FROM dim_account da WHERE da.account_key = d.account_key) AS scalar_account_name,
        (SELECT MAX(dt.trader_name) FROM dim_trader dt WHERE dt.trader_key = d.trader_key) AS scalar_trader_name,
        (SELECT MAX(db.broker_name) FROM dim_broker db WHERE db.broker_key = d.broker_key) AS scalar_broker_name,
        (SELECT AVG(f2.gross_amount_usd) FROM fact_equity_trade f2 WHERE f2.account_key = d.account_key) AS account_avg_gross_usd,
        (SELECT AVG(f3.commission_usd) FROM fact_equity_trade f3 WHERE f3.broker_key = d.broker_key) AS broker_avg_commission_usd,
        (SELECT AVG(f4.price_local) FROM fact_equity_trade f4 WHERE f4.stock_key = d.stock_key) AS stock_avg_execution_price,
        (SELECT COUNT(*) FROM fact_equity_trade f5 WHERE f5.trader_key = d.trader_key) AS trader_total_trade_count,
        (SELECT SUM(f6.gross_amount_usd) FROM fact_equity_trade f6 WHERE f6.sector_key = d.sector_key) AS sector_total_gross_usd
    FROM direct_enrichment d
),
wide_windows AS (
    SELECT
        s.*,
        (s.quantity * s.price_local) AS recomputed_gross_local_1,
        (s.quantity * s.price_local) AS recomputed_gross_local_2,
        ((s.quantity * s.price_local) * s.fx_to_usd) AS recomputed_gross_usd_1,
        ((s.quantity * s.price_local) * s.fx_to_usd) AS recomputed_gross_usd_2,
        ABS(s.gross_amount_local - (s.quantity * s.price_local)) AS local_gross_difference,
        ABS(s.gross_amount_usd - ((s.quantity * s.price_local) * s.fx_to_usd)) AS usd_gross_difference,
        SUM(s.gross_amount_usd) OVER (
            PARTITION BY s.account_name
            ORDER BY s.trade_timestamp, s.trade_id
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS account_running_gross_usd,
        AVG(s.gross_amount_usd) OVER (
            PARTITION BY s.account_name, s.sector_name
        ) AS account_sector_avg_gross_usd,
        SUM(s.commission_usd) OVER (
            PARTITION BY s.broker_name, s.trade_currency_code
        ) AS broker_currency_total_commission_usd,
        ROW_NUMBER() OVER (
            PARTITION BY s.account_name, s.ticker
            ORDER BY s.gross_amount_usd DESC, s.trade_id
        ) AS account_stock_gross_rank,
        DENSE_RANK() OVER (
            PARTITION BY s.sector_name
            ORDER BY s.gross_amount_usd DESC
        ) AS sector_trade_dense_rank,
        PERCENT_RANK() OVER (
            PARTITION BY s.trading_desk
            ORDER BY s.commission_usd
        ) AS desk_commission_percent_rank,
        LAG(s.gross_amount_usd) OVER (
            PARTITION BY s.account_name, s.ticker
            ORDER BY s.trade_timestamp, s.trade_id
        ) AS previous_account_stock_gross_usd,
        LEAD(s.gross_amount_usd) OVER (
            PARTITION BY s.account_name, s.ticker
            ORDER BY s.trade_timestamp, s.trade_id
        ) AS next_account_stock_gross_usd
    FROM scalar_lookup_enrichment s
)
SELECT DISTINCT
    w.*,
    CASE
        WHEN w.gross_amount_usd > w.account_avg_gross_usd THEN 'ABOVE_ACCOUNT_AVERAGE'
        ELSE 'AT_OR_BELOW_ACCOUNT_AVERAGE'
    END AS account_relative_size_flag,
    CASE
        WHEN w.commission_usd > w.broker_avg_commission_usd THEN 'ABOVE_BROKER_AVERAGE'
        ELSE 'AT_OR_BELOW_BROKER_AVERAGE'
    END AS broker_relative_commission_flag,
    CASE
        WHEN UPPER(w.ticker) = UPPER(w.scalar_ticker)
         AND UPPER(w.issuer_name) = UPPER(w.scalar_issuer_name)
         AND UPPER(w.industry_name) = UPPER(w.scalar_industry_name)
         AND UPPER(w.sector_name) = UPPER(w.scalar_sector_name)
         AND UPPER(w.exchange_name) = UPPER(w.scalar_exchange_name)
         AND UPPER(w.trade_currency_code) = UPPER(w.scalar_currency_code)
        THEN 'REDUNDANT_LOOKUPS_AGREE'
        ELSE 'REDUNDANT_LOOKUPS_DISAGREE'
    END AS redundant_lookup_reconciliation,
    (SELECT COUNT(*)
     FROM fact_equity_trade fx
     WHERE CAST(fx.trade_timestamp AS DATE) = CAST(w.trade_timestamp AS DATE)
       AND fx.stock_key = w.stock_key) AS same_stock_same_day_trade_count
FROM wide_windows w
WHERE UPPER(COALESCE(w.ticker, '')) LIKE '%' || UPPER(SUBSTRING(COALESCE(w.ticker, '') FROM 1 FOR 1)) || '%'
  AND CAST(w.trade_timestamp AS DATE) BETWEEN
      (SELECT MIN(CAST(fmin.trade_timestamp AS DATE)) FROM fact_equity_trade fmin)
      AND
      (SELECT MAX(CAST(fmax.trade_timestamp AS DATE)) FROM fact_equity_trade fmax)
  AND w.gross_amount_usd >= (
      SELECT AVG(favg.gross_amount_usd) * 0.10
      FROM fact_equity_trade favg
      WHERE favg.currency_key = w.currency_key
  )
ORDER BY
    w.account_name,
    w.sector_name,
    w.ticker,
    (w.quantity * w.price_local * w.fx_to_usd) DESC,
    w.trade_timestamp,
    w.trade_id
LIMIT 1000;

-- Q02: Repeated full-scan account, trader and broker scorecard joined back together on descriptive text rather than keys
WITH account_trade_metrics AS (
    SELECT
        a.account_name,
        a.account_type,
        base_ccy.currency_code AS account_base_currency,
        COUNT(DISTINCT t.trade_id) AS account_trade_count,
        SUM(t.quantity) AS account_quantity,
        SUM(t.gross_amount_local) AS account_gross_local,
        SUM(t.gross_amount_usd) AS account_gross_usd,
        SUM(t.commission_usd) AS account_commission_usd,
        SUM(t.net_amount_usd) AS account_net_usd,
        COUNT(DISTINCT s.ticker) AS account_distinct_tickers,
        COUNT(DISTINCT i.issuer_name) AS account_distinct_issuers,
        COUNT(DISTINCT ind.industry_name) AS account_distinct_industries,
        COUNT(DISTINCT sec.sector_name) AS account_distinct_sectors,
        COUNT(DISTINCT ex.exchange_name) AS account_distinct_exchanges,
        COUNT(DISTINCT ex_country.country_name) AS account_distinct_exchange_countries,
        COUNT(DISTINCT issuer_country.country_name) AS account_distinct_issuer_countries,
        COUNT(DISTINCT ccy.currency_code) AS account_distinct_trade_currencies,
        COUNT(DISTINCT br.broker_name) AS account_distinct_brokers,
        COUNT(DISTINCT tr.trader_name) AS account_distinct_traders
    FROM fact_equity_trade t
    JOIN dim_account a ON t.account_key = a.account_key
    JOIN dim_currency base_ccy ON a.base_currency_key = base_ccy.currency_key
    JOIN dim_stock s ON t.stock_key = s.stock_key
    JOIN dim_issuer i ON t.issuer_key = i.issuer_key
    JOIN dim_country issuer_country ON i.country_key = issuer_country.country_key
    JOIN dim_industry ind ON t.industry_key = ind.industry_key
    JOIN dim_sector sec ON t.sector_key = sec.sector_key
    JOIN dim_exchange ex ON t.exchange_key = ex.exchange_key
    JOIN dim_country ex_country ON ex.country_key = ex_country.country_key
    JOIN dim_currency ccy ON t.currency_key = ccy.currency_key
    JOIN dim_broker br ON t.broker_key = br.broker_key
    JOIN dim_trader tr ON t.trader_key = tr.trader_key
    GROUP BY a.account_name, a.account_type, base_ccy.currency_code
),
account_buy_metrics AS (
    SELECT
        a.account_name,
        SUM(CASE WHEN t.buy_sell_flag = 'B' THEN t.gross_amount_usd ELSE 0 END) AS account_buy_gross_usd,
        SUM(CASE WHEN t.buy_sell_flag = 'B' THEN t.commission_usd ELSE 0 END) AS account_buy_commission_usd,
        COUNT(DISTINCT CASE WHEN t.buy_sell_flag = 'B' THEN s.ticker ELSE NULL END) AS account_buy_tickers
    FROM fact_equity_trade t
    JOIN dim_account a ON t.account_key = a.account_key
    JOIN dim_stock s ON t.stock_key = s.stock_key
    JOIN dim_issuer i ON s.issuer_key = i.issuer_key
    JOIN dim_industry ind ON i.industry_key = ind.industry_key
    JOIN dim_sector sec ON ind.sector_key = sec.sector_key
    JOIN dim_exchange ex ON s.exchange_key = ex.exchange_key
    JOIN dim_country c ON ex.country_key = c.country_key
    JOIN dim_currency ccy ON s.currency_key = ccy.currency_key
    JOIN dim_broker br ON t.broker_key = br.broker_key
    JOIN dim_trader tr ON t.trader_key = tr.trader_key
    GROUP BY a.account_name
),
account_sell_metrics AS (
    SELECT
        a.account_name,
        SUM(CASE WHEN t.buy_sell_flag = 'S' THEN t.gross_amount_usd ELSE 0 END) AS account_sell_gross_usd,
        SUM(CASE WHEN t.buy_sell_flag = 'S' THEN t.commission_usd ELSE 0 END) AS account_sell_commission_usd,
        COUNT(DISTINCT CASE WHEN t.buy_sell_flag = 'S' THEN s.ticker ELSE NULL END) AS account_sell_tickers
    FROM fact_equity_trade t
    JOIN dim_account a ON t.account_key = a.account_key
    JOIN dim_stock s ON t.stock_key = s.stock_key
    JOIN dim_issuer i ON t.issuer_key = i.issuer_key
    JOIN dim_industry ind ON t.industry_key = ind.industry_key
    JOIN dim_sector sec ON t.sector_key = sec.sector_key
    JOIN dim_exchange ex ON t.exchange_key = ex.exchange_key
    JOIN dim_country c ON ex.country_key = c.country_key
    JOIN dim_currency ccy ON t.currency_key = ccy.currency_key
    JOIN dim_broker br ON t.broker_key = br.broker_key
    JOIN dim_trader tr ON t.trader_key = tr.trader_key
    GROUP BY a.account_name
),
trader_metrics AS (
    SELECT
        tr.trader_name,
        tr.trading_desk,
        a.account_name,
        COUNT(*) AS trader_account_trade_count,
        SUM(t.gross_amount_usd) AS trader_account_gross_usd,
        SUM(t.commission_usd) AS trader_account_commission_usd,
        AVG(t.price_local) AS trader_account_avg_price,
        COUNT(DISTINCT br.broker_name) AS trader_account_broker_count,
        COUNT(DISTINCT s.ticker) AS trader_account_ticker_count,
        COUNT(DISTINCT sec.sector_name) AS trader_account_sector_count
    FROM fact_equity_trade t
    JOIN dim_trader tr ON t.trader_key = tr.trader_key
    JOIN dim_account a ON t.account_key = a.account_key
    JOIN dim_broker br ON t.broker_key = br.broker_key
    JOIN dim_stock s ON t.stock_key = s.stock_key
    JOIN dim_issuer i ON t.issuer_key = i.issuer_key
    JOIN dim_industry ind ON t.industry_key = ind.industry_key
    JOIN dim_sector sec ON t.sector_key = sec.sector_key
    JOIN dim_exchange ex ON t.exchange_key = ex.exchange_key
    JOIN dim_country c ON ex.country_key = c.country_key
    JOIN dim_currency ccy ON t.currency_key = ccy.currency_key
    GROUP BY tr.trader_name, tr.trading_desk, a.account_name
),
broker_metrics AS (
    SELECT
        br.broker_name,
        a.account_name,
        COUNT(*) AS broker_account_trade_count,
        SUM(t.gross_amount_usd) AS broker_account_gross_usd,
        SUM(t.commission_usd) AS broker_account_commission_usd,
        AVG(t.commission_usd / NULLIF(t.gross_amount_usd, 0)) AS broker_account_avg_commission_rate,
        COUNT(DISTINCT tr.trader_name) AS broker_account_trader_count,
        COUNT(DISTINCT ex.exchange_name) AS broker_account_exchange_count,
        COUNT(DISTINCT ccy.currency_code) AS broker_account_currency_count
    FROM fact_equity_trade t
    JOIN dim_broker br ON t.broker_key = br.broker_key
    JOIN dim_account a ON t.account_key = a.account_key
    JOIN dim_trader tr ON t.trader_key = tr.trader_key
    JOIN dim_stock s ON t.stock_key = s.stock_key
    JOIN dim_issuer i ON s.issuer_key = i.issuer_key
    JOIN dim_industry ind ON s.industry_key = ind.industry_key
    JOIN dim_sector sec ON s.sector_key = sec.sector_key
    JOIN dim_exchange ex ON s.exchange_key = ex.exchange_key
    JOIN dim_country c ON ex.country_key = c.country_key
    JOIN dim_currency ccy ON s.currency_key = ccy.currency_key
    GROUP BY br.broker_name, a.account_name
),
account_global_rank AS (
    SELECT
        atm.*,
        DENSE_RANK() OVER (ORDER BY atm.account_gross_usd DESC) AS account_gross_rank,
        PERCENT_RANK() OVER (ORDER BY atm.account_commission_usd) AS account_commission_percent_rank,
        SUM(atm.account_gross_usd) OVER () AS all_accounts_gross_usd,
        AVG(atm.account_gross_usd) OVER () AS all_accounts_avg_gross_usd
    FROM account_trade_metrics atm
)
SELECT DISTINCT
    agr.account_name,
    agr.account_type,
    agr.account_base_currency,
    tm.trader_name,
    tm.trading_desk,
    bm.broker_name,
    agr.account_trade_count,
    agr.account_quantity,
    agr.account_gross_local,
    agr.account_gross_usd,
    agr.account_commission_usd,
    agr.account_net_usd,
    abm.account_buy_gross_usd,
    asm.account_sell_gross_usd,
    abm.account_buy_commission_usd,
    asm.account_sell_commission_usd,
    abm.account_buy_tickers,
    asm.account_sell_tickers,
    agr.account_distinct_tickers,
    agr.account_distinct_issuers,
    agr.account_distinct_industries,
    agr.account_distinct_sectors,
    agr.account_distinct_exchanges,
    agr.account_distinct_exchange_countries,
    agr.account_distinct_issuer_countries,
    agr.account_distinct_trade_currencies,
    agr.account_distinct_brokers,
    agr.account_distinct_traders,
    tm.trader_account_trade_count,
    tm.trader_account_gross_usd,
    tm.trader_account_commission_usd,
    tm.trader_account_avg_price,
    bm.broker_account_trade_count,
    bm.broker_account_gross_usd,
    bm.broker_account_commission_usd,
    bm.broker_account_avg_commission_rate,
    agr.account_gross_rank,
    agr.account_commission_percent_rank,
    agr.account_gross_usd / NULLIF(agr.all_accounts_gross_usd, 0) AS account_share_of_all_gross,
    agr.account_gross_usd - agr.all_accounts_avg_gross_usd AS account_gross_minus_global_average,
    (SELECT AVG(f.gross_amount_usd) FROM fact_equity_trade f WHERE f.account_key IN (
        SELECT a2.account_key FROM dim_account a2 WHERE UPPER(a2.account_name) = UPPER(agr.account_name)
    )) AS repeated_account_average,
    (SELECT COUNT(*) FROM fact_equity_trade f2 WHERE f2.account_key IN (
        SELECT a3.account_key FROM dim_account a3 WHERE UPPER(a3.account_name) = UPPER(agr.account_name)
    ) AND f2.trader_key IN (
        SELECT tr2.trader_key FROM dim_trader tr2 WHERE UPPER(tr2.trader_name) = UPPER(tm.trader_name)
    )) AS repeated_account_trader_count
FROM account_global_rank agr
JOIN account_buy_metrics abm ON UPPER(agr.account_name) = UPPER(abm.account_name)
JOIN account_sell_metrics asm ON UPPER(agr.account_name) = UPPER(asm.account_name)
JOIN trader_metrics tm ON UPPER(agr.account_name) = UPPER(tm.account_name)
JOIN broker_metrics bm ON UPPER(agr.account_name) = UPPER(bm.account_name)
WHERE agr.account_trade_count >= (
    SELECT AVG(x.account_trade_count)
    FROM account_trade_metrics x
)
ORDER BY
    agr.account_gross_usd DESC,
    tm.trader_account_gross_usd DESC,
    bm.broker_account_gross_usd DESC,
    agr.account_name,
    tm.trader_name,
    bm.broker_name
LIMIT 1000;

-- Q03: Sparse multidimensional cube built through a large Cartesian product and left joined to repeatedly enriched aggregate facts
WITH sector_values AS (
    SELECT DISTINCT sec.sector_name
    FROM fact_equity_trade t
    JOIN dim_sector sec ON t.sector_key = sec.sector_key
    JOIN dim_industry ind ON t.industry_key = ind.industry_key
    WHERE UPPER(sec.sector_name) LIKE '%' || UPPER(SUBSTRING(sec.sector_name FROM 1 FOR 1)) || '%'
),
exchange_country_values AS (
    SELECT DISTINCT c.country_name AS exchange_country_name
    FROM fact_equity_trade t
    JOIN dim_exchange ex ON t.exchange_key = ex.exchange_key
    JOIN dim_country c ON ex.country_key = c.country_key
    JOIN dim_stock s ON t.stock_key = s.stock_key
    JOIN dim_exchange ex2 ON s.exchange_key = ex2.exchange_key
    WHERE UPPER(ex.exchange_name) = UPPER(ex2.exchange_name)
),
currency_values AS (
    SELECT DISTINCT ccy.currency_code
    FROM fact_equity_trade t
    JOIN dim_currency ccy ON t.currency_key = ccy.currency_key
    JOIN dim_account a ON t.account_key = a.account_key
    JOIN dim_currency base_ccy ON a.base_currency_key = base_ccy.currency_key
    WHERE LENGTH(ccy.currency_code) > 0 OR LENGTH(base_ccy.currency_code) > 0
),
account_type_values AS (
    SELECT DISTINCT a.account_type
    FROM fact_equity_trade t
    JOIN dim_account a ON t.account_key = a.account_key
    JOIN dim_currency ccy ON a.base_currency_key = ccy.currency_key
),
trading_desk_values AS (
    SELECT DISTINCT tr.trading_desk
    FROM fact_equity_trade t
    JOIN dim_trader tr ON t.trader_key = tr.trader_key
    JOIN dim_broker br ON t.broker_key = br.broker_key
),
broker_values AS (
    SELECT DISTINCT br.broker_name
    FROM fact_equity_trade t
    JOIN dim_broker br ON t.broker_key = br.broker_key
    JOIN dim_trader tr ON t.trader_key = tr.trader_key
),
side_values AS (
    SELECT DISTINCT buy_sell_flag
    FROM fact_equity_trade
),
market_cap_values AS (
    SELECT DISTINCT s.market_cap_bucket
    FROM fact_equity_trade t
    JOIN dim_stock s ON t.stock_key = s.stock_key
    JOIN dim_issuer i ON s.issuer_key = i.issuer_key
),
cartesian_cube AS (
    SELECT
        sv.sector_name,
        ecv.exchange_country_name,
        cv.currency_code,
        atv.account_type,
        tdv.trading_desk,
        bv.broker_name,
        side.buy_sell_flag,
        mcv.market_cap_bucket
    FROM sector_values sv
    CROSS JOIN exchange_country_values ecv
    CROSS JOIN currency_values cv
    CROSS JOIN account_type_values atv
    CROSS JOIN trading_desk_values tdv
    CROSS JOIN broker_values bv
    CROSS JOIN side_values side
    CROSS JOIN market_cap_values mcv
),
actual_facts AS (
    SELECT
        sec.sector_name,
        ex_country.country_name AS exchange_country_name,
        ccy.currency_code,
        a.account_type,
        tr.trading_desk,
        br.broker_name,
        t.buy_sell_flag,
        s.market_cap_bucket,
        COUNT(*) AS trade_count,
        SUM(t.quantity) AS total_quantity,
        SUM(t.gross_amount_local) AS total_gross_local,
        SUM(t.commission_local) AS total_commission_local,
        SUM(t.net_amount_local) AS total_net_local,
        SUM(t.gross_amount_usd) AS total_gross_usd,
        SUM(t.commission_usd) AS total_commission_usd,
        SUM(t.net_amount_usd) AS total_net_usd,
        AVG(t.price_local) AS average_price_local,
        AVG(t.fx_to_usd) AS average_fx_to_usd,
        COUNT(DISTINCT st.ticker) AS distinct_tickers,
        COUNT(DISTINCT i.issuer_name) AS distinct_issuers,
        COUNT(DISTINCT ind.industry_name) AS distinct_industries,
        COUNT(DISTINCT ex.exchange_name) AS distinct_exchanges,
        COUNT(DISTINCT issuer_country.country_name) AS distinct_issuer_countries,
        COUNT(DISTINCT a.account_name) AS distinct_accounts,
        COUNT(DISTINCT tr.trader_name) AS distinct_traders
    FROM fact_equity_trade t
    JOIN dim_stock s ON t.stock_key = s.stock_key
    JOIN dim_stock st ON t.stock_key = st.stock_key
    JOIN dim_issuer i ON t.issuer_key = i.issuer_key
    JOIN dim_country issuer_country ON i.country_key = issuer_country.country_key
    JOIN dim_industry ind ON t.industry_key = ind.industry_key
    JOIN dim_sector sec ON t.sector_key = sec.sector_key
    JOIN dim_exchange ex ON t.exchange_key = ex.exchange_key
    JOIN dim_country ex_country ON ex.country_key = ex_country.country_key
    JOIN dim_currency ccy ON t.currency_key = ccy.currency_key
    JOIN dim_account a ON t.account_key = a.account_key
    JOIN dim_currency base_ccy ON a.base_currency_key = base_ccy.currency_key
    JOIN dim_trader tr ON t.trader_key = tr.trader_key
    JOIN dim_broker br ON t.broker_key = br.broker_key
    GROUP BY
        sec.sector_name,
        ex_country.country_name,
        ccy.currency_code,
        a.account_type,
        tr.trading_desk,
        br.broker_name,
        t.buy_sell_flag,
        s.market_cap_bucket
),
filled_cube AS (
    SELECT
        c.*,
        COALESCE(a.trade_count, 0) AS trade_count,
        COALESCE(a.total_quantity, 0) AS total_quantity,
        COALESCE(a.total_gross_local, 0) AS total_gross_local,
        COALESCE(a.total_commission_local, 0) AS total_commission_local,
        COALESCE(a.total_net_local, 0) AS total_net_local,
        COALESCE(a.total_gross_usd, 0) AS total_gross_usd,
        COALESCE(a.total_commission_usd, 0) AS total_commission_usd,
        COALESCE(a.total_net_usd, 0) AS total_net_usd,
        COALESCE(a.average_price_local, 0) AS average_price_local,
        COALESCE(a.average_fx_to_usd, 0) AS average_fx_to_usd,
        COALESCE(a.distinct_tickers, 0) AS distinct_tickers,
        COALESCE(a.distinct_issuers, 0) AS distinct_issuers,
        COALESCE(a.distinct_industries, 0) AS distinct_industries,
        COALESCE(a.distinct_exchanges, 0) AS distinct_exchanges,
        COALESCE(a.distinct_issuer_countries, 0) AS distinct_issuer_countries,
        COALESCE(a.distinct_accounts, 0) AS distinct_accounts,
        COALESCE(a.distinct_traders, 0) AS distinct_traders
    FROM cartesian_cube c
    LEFT JOIN actual_facts a
      ON UPPER(c.sector_name) = UPPER(a.sector_name)
     AND UPPER(c.exchange_country_name) = UPPER(a.exchange_country_name)
     AND UPPER(c.currency_code) = UPPER(a.currency_code)
     AND UPPER(c.account_type) = UPPER(a.account_type)
     AND UPPER(c.trading_desk) = UPPER(a.trading_desk)
     AND UPPER(c.broker_name) = UPPER(a.broker_name)
     AND UPPER(c.buy_sell_flag) = UPPER(a.buy_sell_flag)
     AND UPPER(c.market_cap_bucket) = UPPER(a.market_cap_bucket)
)
SELECT
    f.*,
    SUM(f.total_gross_usd) OVER (
        PARTITION BY f.sector_name
    ) AS sector_cube_gross_usd,
    SUM(f.total_gross_usd) OVER (
        PARTITION BY f.exchange_country_name
    ) AS country_cube_gross_usd,
    SUM(f.total_gross_usd) OVER (
        PARTITION BY f.currency_code
    ) AS currency_cube_gross_usd,
    DENSE_RANK() OVER (
        PARTITION BY f.sector_name, f.exchange_country_name
        ORDER BY f.total_gross_usd DESC
    ) AS sector_country_cell_rank,
    CASE WHEN f.trade_count = 0 THEN 'EMPTY_CARTESIAN_CELL' ELSE 'OBSERVED_CELL' END AS cell_status,
    (SELECT AVG(af.total_gross_usd) FROM actual_facts af) AS average_observed_cell_gross_usd
FROM filled_cube f
ORDER BY
    f.trade_count DESC,
    f.total_gross_usd DESC,
    f.sector_name,
    f.exchange_country_name,
    f.currency_code,
    f.account_type,
    f.trading_desk,
    f.broker_name,
    f.buy_sell_flag,
    f.market_cap_bucket
LIMIT 2000;

-- Q04: Potential internal-crossing and opposite-side trade-pair search using a broad fact self-join and duplicate enrichment on both legs
WITH candidate_pairs AS (
    SELECT
        b.trade_id AS buy_trade_id,
        s.trade_id AS sell_trade_id,
        b.trade_timestamp AS buy_timestamp,
        s.trade_timestamp AS sell_timestamp,
        b.trade_date AS buy_trade_date,
        s.trade_date AS sell_trade_date,
        b.settlement_date AS buy_settlement_date,
        s.settlement_date AS sell_settlement_date,
        b.stock_key,
        b.account_key AS buy_account_key,
        s.account_key AS sell_account_key,
        b.trader_key AS buy_trader_key,
        s.trader_key AS sell_trader_key,
        b.broker_key AS buy_broker_key,
        s.broker_key AS sell_broker_key,
        b.exchange_key AS buy_exchange_key,
        s.exchange_key AS sell_exchange_key,
        b.currency_key AS buy_currency_key,
        s.currency_key AS sell_currency_key,
        b.quantity AS buy_quantity,
        s.quantity AS sell_quantity,
        b.price_local AS buy_price_local,
        s.price_local AS sell_price_local,
        b.gross_amount_usd AS buy_gross_usd,
        s.gross_amount_usd AS sell_gross_usd,
        b.commission_usd AS buy_commission_usd,
        s.commission_usd AS sell_commission_usd,
        b.net_amount_usd AS buy_net_usd,
        s.net_amount_usd AS sell_net_usd,
        b.execution_venue AS buy_execution_venue,
        s.execution_venue AS sell_execution_venue,
        b.order_type AS buy_order_type,
        s.order_type AS sell_order_type
    FROM fact_equity_trade b
    JOIN fact_equity_trade s
      ON b.stock_key = s.stock_key
     AND CAST(b.trade_timestamp AS DATE) = CAST(s.trade_timestamp AS DATE)
     AND b.buy_sell_flag = 'B'
     AND s.buy_sell_flag = 'S'
     AND b.trade_id < s.trade_id
     AND b.account_key <> s.account_key
     AND ABS(b.price_local - s.price_local) <= ((ABS(b.price_local) + ABS(s.price_local)) / 2.0) * 0.05
),
enriched_pairs AS (
    SELECT
        cp.*,
        st.ticker,
        st.share_class,
        st.lot_size,
        st.market_cap_bucket,
        st.reference_price,
        issuer.issuer_name,
        issuer_country.country_name AS issuer_country_name,
        industry.industry_name,
        sector.sector_name,
        buy_exchange.exchange_name AS buy_exchange_name,
        buy_exchange_country.country_name AS buy_exchange_country_name,
        sell_exchange.exchange_name AS sell_exchange_name,
        sell_exchange_country.country_name AS sell_exchange_country_name,
        buy_currency.currency_code AS buy_currency_code,
        sell_currency.currency_code AS sell_currency_code,
        buy_account.account_name AS buy_account_name,
        buy_account.account_type AS buy_account_type,
        buy_base_currency.currency_code AS buy_account_base_currency,
        sell_account.account_name AS sell_account_name,
        sell_account.account_type AS sell_account_type,
        sell_base_currency.currency_code AS sell_account_base_currency,
        buy_trader.trader_name AS buy_trader_name,
        buy_trader.trading_desk AS buy_trading_desk,
        sell_trader.trader_name AS sell_trader_name,
        sell_trader.trading_desk AS sell_trading_desk,
        buy_broker.broker_name AS buy_broker_name,
        sell_broker.broker_name AS sell_broker_name,
        ABS(cp.buy_quantity - cp.sell_quantity) AS absolute_quantity_difference,
        ABS(cp.buy_price_local - cp.sell_price_local) AS absolute_price_difference,
        ABS(cp.buy_gross_usd - cp.sell_gross_usd) AS absolute_gross_difference,
        (cp.buy_quantity + cp.sell_quantity) AS combined_quantity,
        (cp.buy_gross_usd + cp.sell_gross_usd) AS combined_gross_usd,
        (cp.buy_commission_usd + cp.sell_commission_usd) AS combined_commission_usd
    FROM candidate_pairs cp
    JOIN dim_stock st ON cp.stock_key = st.stock_key
    JOIN dim_issuer issuer ON st.issuer_key = issuer.issuer_key
    JOIN dim_country issuer_country ON issuer.country_key = issuer_country.country_key
    JOIN dim_industry industry ON st.industry_key = industry.industry_key
    JOIN dim_sector sector ON st.sector_key = sector.sector_key
    JOIN dim_exchange buy_exchange ON cp.buy_exchange_key = buy_exchange.exchange_key
    JOIN dim_country buy_exchange_country ON buy_exchange.country_key = buy_exchange_country.country_key
    JOIN dim_exchange sell_exchange ON cp.sell_exchange_key = sell_exchange.exchange_key
    JOIN dim_country sell_exchange_country ON sell_exchange.country_key = sell_exchange_country.country_key
    JOIN dim_currency buy_currency ON cp.buy_currency_key = buy_currency.currency_key
    JOIN dim_currency sell_currency ON cp.sell_currency_key = sell_currency.currency_key
    JOIN dim_account buy_account ON cp.buy_account_key = buy_account.account_key
    JOIN dim_currency buy_base_currency ON buy_account.base_currency_key = buy_base_currency.currency_key
    JOIN dim_account sell_account ON cp.sell_account_key = sell_account.account_key
    JOIN dim_currency sell_base_currency ON sell_account.base_currency_key = sell_base_currency.currency_key
    JOIN dim_trader buy_trader ON cp.buy_trader_key = buy_trader.trader_key
    JOIN dim_trader sell_trader ON cp.sell_trader_key = sell_trader.trader_key
    JOIN dim_broker buy_broker ON cp.buy_broker_key = buy_broker.broker_key
    JOIN dim_broker sell_broker ON cp.sell_broker_key = sell_broker.broker_key
),
scored_pairs AS (
    SELECT
        ep.*,
        CASE WHEN UPPER(ep.buy_exchange_name) = UPPER(ep.sell_exchange_name) THEN 1 ELSE 0 END AS same_exchange_flag,
        CASE WHEN UPPER(ep.buy_currency_code) = UPPER(ep.sell_currency_code) THEN 1 ELSE 0 END AS same_currency_flag,
        CASE WHEN UPPER(ep.buy_broker_name) = UPPER(ep.sell_broker_name) THEN 1 ELSE 0 END AS same_broker_flag,
        CASE WHEN UPPER(ep.buy_trading_desk) = UPPER(ep.sell_trading_desk) THEN 1 ELSE 0 END AS same_desk_flag,
        CASE WHEN UPPER(ep.buy_execution_venue) = UPPER(ep.sell_execution_venue) THEN 1 ELSE 0 END AS same_execution_venue_flag,
        CASE WHEN UPPER(ep.buy_order_type) = UPPER(ep.sell_order_type) THEN 1 ELSE 0 END AS same_order_type_flag,
        ep.absolute_price_difference / NULLIF((ABS(ep.buy_price_local) + ABS(ep.sell_price_local)) / 2.0, 0) AS relative_price_difference,
        ep.absolute_quantity_difference / NULLIF((ABS(ep.buy_quantity) + ABS(ep.sell_quantity)) / 2.0, 0) AS relative_quantity_difference,
        ROW_NUMBER() OVER (
            PARTITION BY ep.ticker, ep.buy_trade_date
            ORDER BY ep.absolute_price_difference, ep.absolute_quantity_difference, ep.buy_trade_id, ep.sell_trade_id
        ) AS daily_stock_pair_rank,
        COUNT(*) OVER (
            PARTITION BY ep.ticker, ep.buy_trade_date
        ) AS daily_stock_pair_count,
        SUM(ep.combined_gross_usd) OVER (
            PARTITION BY ep.sector_name, ep.buy_trade_date
        ) AS sector_day_candidate_gross_usd
    FROM enriched_pairs ep
)
SELECT DISTINCT
    sp.*,
    (
        sp.same_exchange_flag
        + sp.same_currency_flag
        + sp.same_broker_flag
        + sp.same_desk_flag
        + sp.same_execution_venue_flag
        + sp.same_order_type_flag
    ) AS simple_similarity_score,
    (SELECT COUNT(*)
     FROM fact_equity_trade tx
     WHERE tx.stock_key = sp.stock_key
       AND CAST(tx.trade_timestamp AS DATE) = sp.buy_trade_date) AS repeated_stock_day_trade_count,
    (SELECT AVG(ty.price_local)
     FROM fact_equity_trade ty
     WHERE ty.stock_key = sp.stock_key
       AND CAST(ty.trade_timestamp AS DATE) = sp.buy_trade_date) AS repeated_stock_day_average_price,
    (SELECT AVG(tz.gross_amount_usd)
     FROM fact_equity_trade tz
     WHERE tz.account_key IN (sp.buy_account_key, sp.sell_account_key)) AS repeated_pair_account_average_gross
FROM scored_pairs sp
WHERE sp.relative_price_difference <= 0.05
  AND sp.combined_gross_usd >= (
      SELECT AVG(f.gross_amount_usd) * 2
      FROM fact_equity_trade f
      WHERE f.stock_key = sp.stock_key
  )
ORDER BY
    simple_similarity_score DESC,
    sp.combined_gross_usd DESC,
    sp.relative_price_difference,
    sp.relative_quantity_difference,
    sp.buy_trade_id,
    sp.sell_trade_id
LIMIT 1000;

-- Q05: Redundant foreign-key and descriptive-attribute reconciliation audit using multiple paths to the same dimensions
WITH reconciliation_rows AS (
    SELECT
        t.trade_id,
        t.trade_timestamp,
        t.trade_date,
        t.settlement_date,
        t.stock_key AS fact_stock_key,
        t.issuer_key AS fact_issuer_key,
        t.industry_key AS fact_industry_key,
        t.sector_key AS fact_sector_key,
        t.exchange_key AS fact_exchange_key,
        t.currency_key AS fact_currency_key,
        t.account_key,
        t.trader_key,
        t.broker_key,
        t.buy_sell_flag,
        t.execution_venue,
        t.order_type,
        t.quantity,
        t.price_local,
        t.gross_amount_local,
        t.commission_local,
        t.net_amount_local,
        t.fx_to_usd,
        t.gross_amount_usd,
        t.commission_usd,
        t.net_amount_usd,
        stock_direct.ticker,
        stock_direct.issuer_key AS stock_issuer_key,
        stock_direct.industry_key AS stock_industry_key,
        stock_direct.sector_key AS stock_sector_key,
        stock_direct.exchange_key AS stock_exchange_key,
        stock_direct.currency_key AS stock_currency_key,
        stock_direct.share_class,
        stock_direct.lot_size,
        stock_direct.market_cap_bucket,
        stock_direct.reference_price,
        issuer_fact.issuer_name AS issuer_name_from_fact_key,
        issuer_stock.issuer_name AS issuer_name_from_stock_key,
        issuer_fact.country_key AS issuer_fact_country_key,
        issuer_stock.country_key AS issuer_stock_country_key,
        issuer_fact.industry_key AS issuer_fact_industry_key,
        issuer_stock.industry_key AS issuer_stock_industry_key,
        industry_fact.industry_name AS industry_name_from_fact_key,
        industry_stock.industry_name AS industry_name_from_stock_key,
        industry_issuer_fact.industry_name AS industry_name_from_fact_issuer,
        industry_issuer_stock.industry_name AS industry_name_from_stock_issuer,
        industry_fact.sector_key AS industry_fact_sector_key,
        industry_stock.sector_key AS industry_stock_sector_key,
        sector_fact.sector_name AS sector_name_from_fact_key,
        sector_stock.sector_name AS sector_name_from_stock_key,
        sector_industry_fact.sector_name AS sector_name_from_fact_industry,
        sector_industry_stock.sector_name AS sector_name_from_stock_industry,
        exchange_fact.exchange_name AS exchange_name_from_fact_key,
        exchange_stock.exchange_name AS exchange_name_from_stock_key,
        exchange_fact.mic_code AS exchange_mic_from_fact_key,
        exchange_stock.mic_code AS exchange_mic_from_stock_key,
        exchange_country_fact.country_name AS exchange_country_from_fact_key,
        exchange_country_stock.country_name AS exchange_country_from_stock_key,
        issuer_country_fact.country_name AS issuer_country_from_fact_key,
        issuer_country_stock.country_name AS issuer_country_from_stock_key,
        currency_fact.currency_code AS currency_from_fact_key,
        currency_stock.currency_code AS currency_from_stock_key,
        account.account_code,
        account.account_name,
        account.account_type,
        account_base_currency.currency_code AS account_base_currency,
        trader.trader_code,
        trader.trader_name,
        trader.trading_desk,
        broker.broker_name
    FROM fact_equity_trade t
    JOIN dim_stock stock_direct ON t.stock_key = stock_direct.stock_key
    JOIN dim_issuer issuer_fact ON t.issuer_key = issuer_fact.issuer_key
    JOIN dim_issuer issuer_stock ON stock_direct.issuer_key = issuer_stock.issuer_key
    JOIN dim_industry industry_fact ON t.industry_key = industry_fact.industry_key
    JOIN dim_industry industry_stock ON stock_direct.industry_key = industry_stock.industry_key
    JOIN dim_industry industry_issuer_fact ON issuer_fact.industry_key = industry_issuer_fact.industry_key
    JOIN dim_industry industry_issuer_stock ON issuer_stock.industry_key = industry_issuer_stock.industry_key
    JOIN dim_sector sector_fact ON t.sector_key = sector_fact.sector_key
    JOIN dim_sector sector_stock ON stock_direct.sector_key = sector_stock.sector_key
    JOIN dim_sector sector_industry_fact ON industry_fact.sector_key = sector_industry_fact.sector_key
    JOIN dim_sector sector_industry_stock ON industry_stock.sector_key = sector_industry_stock.sector_key
    JOIN dim_exchange exchange_fact ON t.exchange_key = exchange_fact.exchange_key
    JOIN dim_exchange exchange_stock ON stock_direct.exchange_key = exchange_stock.exchange_key
    JOIN dim_country exchange_country_fact ON exchange_fact.country_key = exchange_country_fact.country_key
    JOIN dim_country exchange_country_stock ON exchange_stock.country_key = exchange_country_stock.country_key
    JOIN dim_country issuer_country_fact ON issuer_fact.country_key = issuer_country_fact.country_key
    JOIN dim_country issuer_country_stock ON issuer_stock.country_key = issuer_country_stock.country_key
    JOIN dim_currency currency_fact ON t.currency_key = currency_fact.currency_key
    JOIN dim_currency currency_stock ON stock_direct.currency_key = currency_stock.currency_key
    JOIN dim_account account ON t.account_key = account.account_key
    JOIN dim_currency account_base_currency ON account.base_currency_key = account_base_currency.currency_key
    JOIN dim_trader trader ON t.trader_key = trader.trader_key
    JOIN dim_broker broker ON t.broker_key = broker.broker_key
),
flagged_rows AS (
    SELECT
        r.*,
        CASE WHEN r.fact_issuer_key = r.stock_issuer_key THEN 0 ELSE 1 END AS issuer_key_mismatch,
        CASE WHEN r.fact_industry_key = r.stock_industry_key THEN 0 ELSE 1 END AS industry_key_mismatch,
        CASE WHEN r.fact_sector_key = r.stock_sector_key THEN 0 ELSE 1 END AS sector_key_mismatch,
        CASE WHEN r.fact_exchange_key = r.stock_exchange_key THEN 0 ELSE 1 END AS exchange_key_mismatch,
        CASE WHEN r.fact_currency_key = r.stock_currency_key THEN 0 ELSE 1 END AS currency_key_mismatch,
        CASE WHEN UPPER(r.issuer_name_from_fact_key) = UPPER(r.issuer_name_from_stock_key) THEN 0 ELSE 1 END AS issuer_name_mismatch,
        CASE WHEN UPPER(r.industry_name_from_fact_key) = UPPER(r.industry_name_from_stock_key) THEN 0 ELSE 1 END AS industry_name_mismatch,
        CASE WHEN UPPER(r.industry_name_from_fact_key) = UPPER(r.industry_name_from_fact_issuer) THEN 0 ELSE 1 END AS fact_issuer_industry_name_mismatch,
        CASE WHEN UPPER(r.sector_name_from_fact_key) = UPPER(r.sector_name_from_stock_key) THEN 0 ELSE 1 END AS sector_name_mismatch,
        CASE WHEN UPPER(r.sector_name_from_fact_key) = UPPER(r.sector_name_from_fact_industry) THEN 0 ELSE 1 END AS fact_industry_sector_name_mismatch,
        CASE WHEN UPPER(r.exchange_name_from_fact_key) = UPPER(r.exchange_name_from_stock_key) THEN 0 ELSE 1 END AS exchange_name_mismatch,
        CASE WHEN UPPER(r.exchange_country_from_fact_key) = UPPER(r.exchange_country_from_stock_key) THEN 0 ELSE 1 END AS exchange_country_mismatch,
        CASE WHEN UPPER(r.issuer_country_from_fact_key) = UPPER(r.issuer_country_from_stock_key) THEN 0 ELSE 1 END AS issuer_country_mismatch,
        CASE WHEN UPPER(r.currency_from_fact_key) = UPPER(r.currency_from_stock_key) THEN 0 ELSE 1 END AS currency_code_mismatch,
        ABS(r.gross_amount_local - (r.quantity * r.price_local)) AS local_gross_recalculation_difference,
        ABS(r.gross_amount_usd - ((r.quantity * r.price_local) * r.fx_to_usd)) AS usd_gross_recalculation_difference,
        ABS(r.net_amount_local - CASE WHEN r.buy_sell_flag = 'B' THEN r.gross_amount_local + r.commission_local ELSE r.gross_amount_local - r.commission_local END) AS local_net_formula_difference,
        ABS(r.net_amount_usd - CASE WHEN r.buy_sell_flag = 'B' THEN r.gross_amount_usd + r.commission_usd ELSE r.gross_amount_usd - r.commission_usd END) AS usd_net_formula_difference
    FROM reconciliation_rows r
),
scored_rows AS (
    SELECT
        f.*,
        (
            f.issuer_key_mismatch
            + f.industry_key_mismatch
            + f.sector_key_mismatch
            + f.exchange_key_mismatch
            + f.currency_key_mismatch
            + f.issuer_name_mismatch
            + f.industry_name_mismatch
            + f.fact_issuer_industry_name_mismatch
            + f.sector_name_mismatch
            + f.fact_industry_sector_name_mismatch
            + f.exchange_name_mismatch
            + f.exchange_country_mismatch
            + f.issuer_country_mismatch
            + f.currency_code_mismatch
        ) AS dimension_mismatch_score,
        ROW_NUMBER() OVER (
            PARTITION BY f.ticker
            ORDER BY (
                f.issuer_key_mismatch
                + f.industry_key_mismatch
                + f.sector_key_mismatch
                + f.exchange_key_mismatch
                + f.currency_key_mismatch
            ) DESC,
            f.usd_gross_recalculation_difference DESC,
            f.trade_id
        ) AS ticker_reconciliation_rank,
        SUM(f.gross_amount_usd) OVER (
            PARTITION BY f.sector_name_from_fact_key
        ) AS sector_fact_path_gross_usd,
        SUM(f.gross_amount_usd) OVER (
            PARTITION BY f.sector_name_from_stock_key
        ) AS sector_stock_path_gross_usd
    FROM flagged_rows f
)
SELECT DISTINCT
    s.*,
    (SELECT COUNT(*) FROM fact_equity_trade f WHERE f.stock_key = s.fact_stock_key) AS repeated_stock_trade_count,
    (SELECT COUNT(*) FROM fact_equity_trade f WHERE f.issuer_key = s.fact_issuer_key) AS repeated_issuer_trade_count,
    (SELECT AVG(f.gross_amount_usd) FROM fact_equity_trade f WHERE f.account_key = s.account_key) AS repeated_account_avg_gross,
    CASE
        WHEN s.dimension_mismatch_score = 0
         AND s.local_gross_recalculation_difference = 0
         AND s.usd_gross_recalculation_difference = 0
        THEN 'FULLY_RECONCILED'
        WHEN s.dimension_mismatch_score = 0
        THEN 'DIMENSIONS_RECONCILED_AMOUNTS_DIFFER'
        ELSE 'DIMENSION_PATH_MISMATCH'
    END AS reconciliation_status
FROM scored_rows s
ORDER BY
    s.dimension_mismatch_score DESC,
    s.usd_gross_recalculation_difference DESC,
    s.local_gross_recalculation_difference DESC,
    s.gross_amount_usd DESC,
    s.trade_id
LIMIT 2000;

-- Q06: Commission, FX, price, settlement and amount anomaly engine with repeated peer statistics and multiple window layers
WITH enriched AS (
    SELECT
        t.*,
        s.ticker,
        s.share_class,
        s.lot_size,
        s.market_cap_bucket,
        s.reference_price,
        i.issuer_name,
        issuer_country.country_name AS issuer_country_name,
        ind.industry_name,
        sec.sector_name,
        ex.mic_code,
        ex.exchange_name,
        exchange_country.country_name AS exchange_country_name,
        ccy.currency_code,
        ccy.currency_name,
        a.account_code,
        a.account_name,
        a.account_type,
        base_ccy.currency_code AS account_base_currency,
        tr.trader_code,
        tr.trader_name,
        tr.trading_desk,
        br.broker_name,
        (t.commission_usd / NULLIF(t.gross_amount_usd, 0)) AS commission_rate_usd,
        (t.commission_local / NULLIF(t.gross_amount_local, 0)) AS commission_rate_local,
        ((t.price_local - s.reference_price) / NULLIF(s.reference_price, 0)) AS reference_price_deviation,
        ABS(t.gross_amount_local - (t.quantity * t.price_local)) AS gross_local_recalculation_error,
        ABS(t.gross_amount_usd - (t.gross_amount_local * t.fx_to_usd)) AS gross_usd_recalculation_error,
        DATE_DIFF('day', t.trade_date, t.settlement_date) AS settlement_days
    FROM fact_equity_trade t
    JOIN dim_stock s ON t.stock_key = s.stock_key
    JOIN dim_issuer i ON t.issuer_key = i.issuer_key
    JOIN dim_country issuer_country ON i.country_key = issuer_country.country_key
    JOIN dim_industry ind ON t.industry_key = ind.industry_key
    JOIN dim_sector sec ON t.sector_key = sec.sector_key
    JOIN dim_exchange ex ON t.exchange_key = ex.exchange_key
    JOIN dim_country exchange_country ON ex.country_key = exchange_country.country_key
    JOIN dim_currency ccy ON t.currency_key = ccy.currency_key
    JOIN dim_account a ON t.account_key = a.account_key
    JOIN dim_currency base_ccy ON a.base_currency_key = base_ccy.currency_key
    JOIN dim_trader tr ON t.trader_key = tr.trader_key
    JOIN dim_broker br ON t.broker_key = br.broker_key
),
peer_statistics AS (
    SELECT
        e.*,
        AVG(e.commission_rate_usd) OVER (PARTITION BY e.broker_name) AS broker_avg_commission_rate,
        STDDEV_POP(e.commission_rate_usd) OVER (PARTITION BY e.broker_name) AS broker_stddev_commission_rate,
        AVG(e.commission_rate_usd) OVER (PARTITION BY e.broker_name, e.exchange_name, e.currency_code) AS broker_venue_currency_avg_commission_rate,
        STDDEV_POP(e.commission_rate_usd) OVER (PARTITION BY e.broker_name, e.exchange_name, e.currency_code) AS broker_venue_currency_stddev_commission_rate,
        AVG(e.fx_to_usd) OVER (PARTITION BY e.currency_code, e.trade_date) AS currency_day_avg_fx,
        STDDEV_POP(e.fx_to_usd) OVER (PARTITION BY e.currency_code, e.trade_date) AS currency_day_stddev_fx,
        AVG(e.price_local) OVER (PARTITION BY e.ticker, e.trade_date) AS stock_day_avg_price,
        STDDEV_POP(e.price_local) OVER (PARTITION BY e.ticker, e.trade_date) AS stock_day_stddev_price,
        AVG(e.gross_amount_usd) OVER (PARTITION BY e.account_name, e.sector_name) AS account_sector_avg_gross,
        STDDEV_POP(e.gross_amount_usd) OVER (PARTITION BY e.account_name, e.sector_name) AS account_sector_stddev_gross,
        AVG(e.settlement_days) OVER (PARTITION BY e.exchange_country_name, e.currency_code) AS country_currency_avg_settlement_days,
        STDDEV_POP(e.settlement_days) OVER (PARTITION BY e.exchange_country_name, e.currency_code) AS country_currency_stddev_settlement_days,
        PERCENT_RANK() OVER (PARTITION BY e.broker_name ORDER BY e.commission_rate_usd) AS broker_commission_percentile,
        PERCENT_RANK() OVER (PARTITION BY e.ticker ORDER BY ABS(e.reference_price_deviation)) AS ticker_reference_deviation_percentile,
        PERCENT_RANK() OVER (PARTITION BY e.account_name ORDER BY e.gross_amount_usd) AS account_gross_percentile
    FROM enriched e
),
z_scores AS (
    SELECT
        p.*,
        (p.commission_rate_usd - p.broker_avg_commission_rate) / NULLIF(p.broker_stddev_commission_rate, 0) AS broker_commission_zscore,
        (p.commission_rate_usd - p.broker_venue_currency_avg_commission_rate) / NULLIF(p.broker_venue_currency_stddev_commission_rate, 0) AS broker_venue_currency_commission_zscore,
        (p.fx_to_usd - p.currency_day_avg_fx) / NULLIF(p.currency_day_stddev_fx, 0) AS currency_day_fx_zscore,
        (p.price_local - p.stock_day_avg_price) / NULLIF(p.stock_day_stddev_price, 0) AS stock_day_price_zscore,
        (p.gross_amount_usd - p.account_sector_avg_gross) / NULLIF(p.account_sector_stddev_gross, 0) AS account_sector_gross_zscore,
        (p.settlement_days - p.country_currency_avg_settlement_days) / NULLIF(p.country_currency_stddev_settlement_days, 0) AS settlement_days_zscore,
        (SELECT AVG(f.commission_usd / NULLIF(f.gross_amount_usd, 0)) FROM fact_equity_trade f WHERE f.broker_key = p.broker_key) AS repeated_broker_avg_commission_rate,
        (SELECT AVG(f.fx_to_usd) FROM fact_equity_trade f WHERE f.currency_key = p.currency_key AND f.trade_date = p.trade_date) AS repeated_currency_day_avg_fx,
        (SELECT AVG(f.price_local) FROM fact_equity_trade f WHERE f.stock_key = p.stock_key AND f.trade_date = p.trade_date) AS repeated_stock_day_avg_price,
        (SELECT AVG(f.gross_amount_usd) FROM fact_equity_trade f WHERE f.account_key = p.account_key AND f.sector_key = p.sector_key) AS repeated_account_sector_avg_gross
    FROM peer_statistics p
),
scored AS (
    SELECT
        z.*,
        (
            CASE WHEN ABS(COALESCE(z.broker_commission_zscore, 0)) >= 2 THEN 2 ELSE 0 END
            + CASE WHEN ABS(COALESCE(z.broker_venue_currency_commission_zscore, 0)) >= 2 THEN 2 ELSE 0 END
            + CASE WHEN ABS(COALESCE(z.currency_day_fx_zscore, 0)) >= 2 THEN 2 ELSE 0 END
            + CASE WHEN ABS(COALESCE(z.stock_day_price_zscore, 0)) >= 2 THEN 2 ELSE 0 END
            + CASE WHEN ABS(COALESCE(z.account_sector_gross_zscore, 0)) >= 2 THEN 2 ELSE 0 END
            + CASE WHEN ABS(COALESCE(z.settlement_days_zscore, 0)) >= 2 THEN 2 ELSE 0 END
            + CASE WHEN z.gross_local_recalculation_error > 0.01 THEN 1 ELSE 0 END
            + CASE WHEN z.gross_usd_recalculation_error > 0.01 THEN 1 ELSE 0 END
            + CASE WHEN z.broker_commission_percentile >= 0.99 THEN 1 ELSE 0 END
            + CASE WHEN z.ticker_reference_deviation_percentile >= 0.99 THEN 1 ELSE 0 END
            + CASE WHEN z.account_gross_percentile >= 0.99 THEN 1 ELSE 0 END
        ) AS anomaly_score
    FROM z_scores z
)
SELECT DISTINCT
    s.*,
    DENSE_RANK() OVER (ORDER BY s.anomaly_score DESC, s.gross_amount_usd DESC) AS global_anomaly_rank,
    ROW_NUMBER() OVER (PARTITION BY s.account_name ORDER BY s.anomaly_score DESC, s.gross_amount_usd DESC, s.trade_id) AS account_anomaly_rank,
    ROW_NUMBER() OVER (PARTITION BY s.broker_name ORDER BY s.anomaly_score DESC, s.commission_rate_usd DESC, s.trade_id) AS broker_anomaly_rank,
    SUM(s.anomaly_score) OVER (PARTITION BY s.trading_desk) AS desk_total_anomaly_score,
    SUM(s.gross_amount_usd) OVER (PARTITION BY s.sector_name, s.issuer_country_name) AS sector_country_total_gross_usd
FROM scored s
WHERE s.anomaly_score > 0
   OR s.gross_amount_usd > (SELECT AVG(f.gross_amount_usd) + STDDEV_POP(f.gross_amount_usd) FROM fact_equity_trade f)
ORDER BY
    s.anomaly_score DESC,
    ABS(COALESCE(s.broker_commission_zscore, 0)) DESC,
    ABS(COALESCE(s.stock_day_price_zscore, 0)) DESC,
    s.gross_amount_usd DESC,
    s.trade_id
LIMIT 2000;

-- Q07: Multi-pass market-share, concentration and contribution report built from repeated dimension-specific scans and text-key joins
WITH stock_metrics AS (
    SELECT
        s.ticker,
        s.share_class,
        s.market_cap_bucket,
        i.issuer_name,
        ind.industry_name,
        sec.sector_name,
        ex.exchange_name,
        ex_country.country_name AS exchange_country_name,
        issuer_country.country_name AS issuer_country_name,
        ccy.currency_code,
        COUNT(*) AS stock_trade_count,
        SUM(t.gross_amount_usd) AS stock_gross_usd,
        SUM(t.commission_usd) AS stock_commission_usd,
        SUM(t.net_amount_usd) AS stock_net_usd,
        SUM(t.quantity) AS stock_quantity,
        AVG(t.price_local) AS stock_average_price,
        AVG(s.reference_price) AS repeated_reference_price
    FROM fact_equity_trade t
    JOIN dim_stock s ON t.stock_key = s.stock_key
    JOIN dim_issuer i ON s.issuer_key = i.issuer_key
    JOIN dim_country issuer_country ON i.country_key = issuer_country.country_key
    JOIN dim_industry ind ON s.industry_key = ind.industry_key
    JOIN dim_sector sec ON s.sector_key = sec.sector_key
    JOIN dim_exchange ex ON s.exchange_key = ex.exchange_key
    JOIN dim_country ex_country ON ex.country_key = ex_country.country_key
    JOIN dim_currency ccy ON s.currency_key = ccy.currency_key
    JOIN dim_account a ON t.account_key = a.account_key
    JOIN dim_trader tr ON t.trader_key = tr.trader_key
    JOIN dim_broker br ON t.broker_key = br.broker_key
    GROUP BY
        s.ticker,
        s.share_class,
        s.market_cap_bucket,
        i.issuer_name,
        ind.industry_name,
        sec.sector_name,
        ex.exchange_name,
        ex_country.country_name,
        issuer_country.country_name,
        ccy.currency_code
),
issuer_metrics AS (
    SELECT
        i.issuer_name,
        SUM(t.gross_amount_usd) AS issuer_gross_usd,
        SUM(t.commission_usd) AS issuer_commission_usd,
        COUNT(*) AS issuer_trade_count,
        COUNT(DISTINCT s.ticker) AS issuer_ticker_count
    FROM fact_equity_trade t
    JOIN dim_issuer i ON t.issuer_key = i.issuer_key
    JOIN dim_stock s ON t.stock_key = s.stock_key
    JOIN dim_industry ind ON t.industry_key = ind.industry_key
    JOIN dim_sector sec ON t.sector_key = sec.sector_key
    JOIN dim_exchange ex ON t.exchange_key = ex.exchange_key
    JOIN dim_country c ON ex.country_key = c.country_key
    JOIN dim_currency ccy ON t.currency_key = ccy.currency_key
    JOIN dim_account a ON t.account_key = a.account_key
    JOIN dim_trader tr ON t.trader_key = tr.trader_key
    JOIN dim_broker br ON t.broker_key = br.broker_key
    GROUP BY i.issuer_name
),
industry_metrics AS (
    SELECT
        ind.industry_name,
        SUM(t.gross_amount_usd) AS industry_gross_usd,
        SUM(t.commission_usd) AS industry_commission_usd,
        COUNT(*) AS industry_trade_count
    FROM fact_equity_trade t
    JOIN dim_industry ind ON t.industry_key = ind.industry_key
    JOIN dim_sector sec ON ind.sector_key = sec.sector_key
    JOIN dim_stock s ON t.stock_key = s.stock_key
    JOIN dim_issuer i ON t.issuer_key = i.issuer_key
    JOIN dim_exchange ex ON t.exchange_key = ex.exchange_key
    JOIN dim_country c ON ex.country_key = c.country_key
    JOIN dim_currency ccy ON t.currency_key = ccy.currency_key
    JOIN dim_account a ON t.account_key = a.account_key
    JOIN dim_trader tr ON t.trader_key = tr.trader_key
    JOIN dim_broker br ON t.broker_key = br.broker_key
    GROUP BY ind.industry_name
),
sector_metrics AS (
    SELECT
        sec.sector_name,
        SUM(t.gross_amount_usd) AS sector_gross_usd,
        SUM(t.commission_usd) AS sector_commission_usd,
        COUNT(*) AS sector_trade_count
    FROM fact_equity_trade t
    JOIN dim_sector sec ON t.sector_key = sec.sector_key
    JOIN dim_industry ind ON t.industry_key = ind.industry_key
    JOIN dim_stock s ON t.stock_key = s.stock_key
    JOIN dim_issuer i ON t.issuer_key = i.issuer_key
    JOIN dim_exchange ex ON t.exchange_key = ex.exchange_key
    JOIN dim_country c ON ex.country_key = c.country_key
    JOIN dim_currency ccy ON t.currency_key = ccy.currency_key
    JOIN dim_account a ON t.account_key = a.account_key
    JOIN dim_trader tr ON t.trader_key = tr.trader_key
    JOIN dim_broker br ON t.broker_key = br.broker_key
    GROUP BY sec.sector_name
),
exchange_metrics AS (
    SELECT
        ex.exchange_name,
        SUM(t.gross_amount_usd) AS exchange_gross_usd,
        SUM(t.commission_usd) AS exchange_commission_usd,
        COUNT(*) AS exchange_trade_count
    FROM fact_equity_trade t
    JOIN dim_exchange ex ON t.exchange_key = ex.exchange_key
    JOIN dim_country c ON ex.country_key = c.country_key
    JOIN dim_stock s ON t.stock_key = s.stock_key
    JOIN dim_issuer i ON t.issuer_key = i.issuer_key
    JOIN dim_industry ind ON t.industry_key = ind.industry_key
    JOIN dim_sector sec ON t.sector_key = sec.sector_key
    JOIN dim_currency ccy ON t.currency_key = ccy.currency_key
    JOIN dim_account a ON t.account_key = a.account_key
    JOIN dim_trader tr ON t.trader_key = tr.trader_key
    JOIN dim_broker br ON t.broker_key = br.broker_key
    GROUP BY ex.exchange_name
),
currency_metrics AS (
    SELECT
        ccy.currency_code,
        SUM(t.gross_amount_usd) AS currency_gross_usd,
        SUM(t.commission_usd) AS currency_commission_usd,
        COUNT(*) AS currency_trade_count
    FROM fact_equity_trade t
    JOIN dim_currency ccy ON t.currency_key = ccy.currency_key
    JOIN dim_stock s ON t.stock_key = s.stock_key
    JOIN dim_issuer i ON t.issuer_key = i.issuer_key
    JOIN dim_industry ind ON t.industry_key = ind.industry_key
    JOIN dim_sector sec ON t.sector_key = sec.sector_key
    JOIN dim_exchange ex ON t.exchange_key = ex.exchange_key
    JOIN dim_country c ON ex.country_key = c.country_key
    JOIN dim_account a ON t.account_key = a.account_key
    JOIN dim_trader tr ON t.trader_key = tr.trader_key
    JOIN dim_broker br ON t.broker_key = br.broker_key
    GROUP BY ccy.currency_code
),
account_stock_metrics AS (
    SELECT
        a.account_name,
        a.account_type,
        base_ccy.currency_code AS account_base_currency,
        s.ticker,
        tr.trader_name,
        tr.trading_desk,
        br.broker_name,
        SUM(t.gross_amount_usd) AS account_stock_trader_broker_gross_usd,
        SUM(t.commission_usd) AS account_stock_trader_broker_commission_usd,
        COUNT(*) AS account_stock_trader_broker_trade_count
    FROM fact_equity_trade t
    JOIN dim_account a ON t.account_key = a.account_key
    JOIN dim_currency base_ccy ON a.base_currency_key = base_ccy.currency_key
    JOIN dim_stock s ON t.stock_key = s.stock_key
    JOIN dim_issuer i ON t.issuer_key = i.issuer_key
    JOIN dim_industry ind ON t.industry_key = ind.industry_key
    JOIN dim_sector sec ON t.sector_key = sec.sector_key
    JOIN dim_exchange ex ON t.exchange_key = ex.exchange_key
    JOIN dim_country c ON ex.country_key = c.country_key
    JOIN dim_currency ccy ON t.currency_key = ccy.currency_key
    JOIN dim_trader tr ON t.trader_key = tr.trader_key
    JOIN dim_broker br ON t.broker_key = br.broker_key
    GROUP BY a.account_name, a.account_type, base_ccy.currency_code, s.ticker, tr.trader_name, tr.trading_desk, br.broker_name
),
combined AS (
    SELECT
        asm.*,
        sm.* EXCLUDE (ticker),
        im.issuer_gross_usd,
        im.issuer_commission_usd,
        im.issuer_trade_count,
        im.issuer_ticker_count,
        inm.industry_gross_usd,
        inm.industry_commission_usd,
        inm.industry_trade_count,
        sem.sector_gross_usd,
        sem.sector_commission_usd,
        sem.sector_trade_count,
        em.exchange_gross_usd,
        em.exchange_commission_usd,
        em.exchange_trade_count,
        cm.currency_gross_usd,
        cm.currency_commission_usd,
        cm.currency_trade_count
    FROM account_stock_metrics asm
    JOIN stock_metrics sm ON UPPER(asm.ticker) = UPPER(sm.ticker)
    JOIN issuer_metrics im ON UPPER(sm.issuer_name) = UPPER(im.issuer_name)
    JOIN industry_metrics inm ON UPPER(sm.industry_name) = UPPER(inm.industry_name)
    JOIN sector_metrics sem ON UPPER(sm.sector_name) = UPPER(sem.sector_name)
    JOIN exchange_metrics em ON UPPER(sm.exchange_name) = UPPER(em.exchange_name)
    JOIN currency_metrics cm ON UPPER(sm.currency_code) = UPPER(cm.currency_code)
)
SELECT DISTINCT
    c.*,
    c.account_stock_trader_broker_gross_usd / NULLIF(c.stock_gross_usd, 0) AS account_trader_broker_share_of_stock,
    c.stock_gross_usd / NULLIF(c.issuer_gross_usd, 0) AS stock_share_of_issuer,
    c.issuer_gross_usd / NULLIF(c.industry_gross_usd, 0) AS issuer_share_of_industry,
    c.industry_gross_usd / NULLIF(c.sector_gross_usd, 0) AS industry_share_of_sector,
    c.stock_gross_usd / NULLIF(c.exchange_gross_usd, 0) AS stock_share_of_exchange,
    c.stock_gross_usd / NULLIF(c.currency_gross_usd, 0) AS stock_share_of_currency,
    POWER(c.stock_gross_usd / NULLIF(c.sector_gross_usd, 0), 2) AS stock_sector_hhi_contribution,
    SUM(POWER(c.stock_gross_usd / NULLIF(c.sector_gross_usd, 0), 2)) OVER (PARTITION BY c.sector_name) AS repeated_sector_hhi,
    DENSE_RANK() OVER (PARTITION BY c.sector_name ORDER BY c.stock_gross_usd DESC) AS stock_rank_in_sector,
    DENSE_RANK() OVER (PARTITION BY c.exchange_name ORDER BY c.stock_gross_usd DESC) AS stock_rank_on_exchange,
    DENSE_RANK() OVER (PARTITION BY c.account_name ORDER BY c.account_stock_trader_broker_gross_usd DESC) AS account_combination_rank,
    (SELECT SUM(f.gross_amount_usd) FROM fact_equity_trade f WHERE f.stock_key IN (
        SELECT s2.stock_key FROM dim_stock s2 WHERE UPPER(s2.ticker) = UPPER(c.ticker)
    )) AS repeated_stock_gross_usd,
    (SELECT SUM(f.commission_usd) FROM fact_equity_trade f WHERE f.broker_key IN (
        SELECT b2.broker_key FROM dim_broker b2 WHERE UPPER(b2.broker_name) = UPPER(c.broker_name)
    )) AS repeated_broker_commission_usd
FROM combined c
WHERE c.stock_gross_usd >= (SELECT AVG(x.stock_gross_usd) FROM stock_metrics x)
ORDER BY
    c.sector_gross_usd DESC,
    c.industry_gross_usd DESC,
    c.issuer_gross_usd DESC,
    c.stock_gross_usd DESC,
    c.account_stock_trader_broker_gross_usd DESC,
    c.account_name,
    c.trader_name,
    c.broker_name
LIMIT 2000;

-- Q08: Dense date-by-dimension time-series scaffold with repeated daily enrichment and many rolling windows
WITH dates AS (
    SELECT DISTINCT CAST(t.trade_timestamp AS DATE) AS calendar_date
    FROM fact_equity_trade t
),
top_stocks AS (
    SELECT ticker
    FROM (
        SELECT
            s.ticker,
            SUM(t.gross_amount_usd) AS gross_usd,
            ROW_NUMBER() OVER (ORDER BY SUM(t.gross_amount_usd) DESC, s.ticker) AS rn
        FROM fact_equity_trade t
        JOIN dim_stock s ON t.stock_key = s.stock_key
        JOIN dim_issuer i ON t.issuer_key = i.issuer_key
        JOIN dim_industry ind ON t.industry_key = ind.industry_key
        JOIN dim_sector sec ON t.sector_key = sec.sector_key
        JOIN dim_exchange ex ON t.exchange_key = ex.exchange_key
        JOIN dim_country c ON ex.country_key = c.country_key
        JOIN dim_currency ccy ON t.currency_key = ccy.currency_key
        JOIN dim_account a ON t.account_key = a.account_key
        JOIN dim_trader tr ON t.trader_key = tr.trader_key
        JOIN dim_broker br ON t.broker_key = br.broker_key
        GROUP BY s.ticker
    ) ranked_stocks
    WHERE rn <= 25
),
account_types AS (
    SELECT DISTINCT a.account_type
    FROM fact_equity_trade t
    JOIN dim_account a ON t.account_key = a.account_key
),
trading_desks AS (
    SELECT DISTINCT tr.trading_desk
    FROM fact_equity_trade t
    JOIN dim_trader tr ON t.trader_key = tr.trader_key
),
calendar_scaffold AS (
    SELECT
        d.calendar_date,
        s.ticker,
        a.account_type,
        td.trading_desk
    FROM dates d
    CROSS JOIN top_stocks s
    CROSS JOIN account_types a
    CROSS JOIN trading_desks td
),
daily_actual AS (
    SELECT
        CAST(t.trade_timestamp AS DATE) AS calendar_date,
        s.ticker,
        a.account_type,
        tr.trading_desk,
        i.issuer_name,
        issuer_country.country_name AS issuer_country_name,
        ind.industry_name,
        sec.sector_name,
        ex.exchange_name,
        exchange_country.country_name AS exchange_country_name,
        ccy.currency_code,
        br.broker_name,
        COUNT(*) AS trade_count,
        SUM(t.quantity) AS total_quantity,
        SUM(CASE WHEN t.buy_sell_flag = 'B' THEN t.gross_amount_usd ELSE 0 END) AS buy_gross_usd,
        SUM(CASE WHEN t.buy_sell_flag = 'S' THEN t.gross_amount_usd ELSE 0 END) AS sell_gross_usd,
        SUM(t.gross_amount_usd) AS gross_usd,
        SUM(t.commission_usd) AS commission_usd,
        SUM(t.net_amount_usd) AS net_usd,
        AVG(t.price_local) AS average_price_local,
        AVG(t.fx_to_usd) AS average_fx_to_usd,
        MIN(t.price_local) AS minimum_price_local,
        MAX(t.price_local) AS maximum_price_local,
        COUNT(DISTINCT t.account_key) AS distinct_accounts,
        COUNT(DISTINCT t.trader_key) AS distinct_traders,
        COUNT(DISTINCT t.broker_key) AS distinct_brokers
    FROM fact_equity_trade t
    JOIN dim_stock s ON t.stock_key = s.stock_key
    JOIN dim_issuer i ON t.issuer_key = i.issuer_key
    JOIN dim_country issuer_country ON i.country_key = issuer_country.country_key
    JOIN dim_industry ind ON t.industry_key = ind.industry_key
    JOIN dim_sector sec ON t.sector_key = sec.sector_key
    JOIN dim_exchange ex ON t.exchange_key = ex.exchange_key
    JOIN dim_country exchange_country ON ex.country_key = exchange_country.country_key
    JOIN dim_currency ccy ON t.currency_key = ccy.currency_key
    JOIN dim_account a ON t.account_key = a.account_key
    JOIN dim_currency base_ccy ON a.base_currency_key = base_ccy.currency_key
    JOIN dim_trader tr ON t.trader_key = tr.trader_key
    JOIN dim_broker br ON t.broker_key = br.broker_key
    GROUP BY
        CAST(t.trade_timestamp AS DATE),
        s.ticker,
        a.account_type,
        tr.trading_desk,
        i.issuer_name,
        issuer_country.country_name,
        ind.industry_name,
        sec.sector_name,
        ex.exchange_name,
        exchange_country.country_name,
        ccy.currency_code,
        br.broker_name
),
collapsed_daily_actual AS (
    SELECT
        calendar_date,
        ticker,
        account_type,
        trading_desk,
        MAX(issuer_name) AS issuer_name,
        MAX(issuer_country_name) AS issuer_country_name,
        MAX(industry_name) AS industry_name,
        MAX(sector_name) AS sector_name,
        MAX(exchange_name) AS exchange_name,
        MAX(exchange_country_name) AS exchange_country_name,
        MAX(currency_code) AS currency_code,
        COUNT(DISTINCT broker_name) AS daily_broker_name_count,
        SUM(trade_count) AS trade_count,
        SUM(total_quantity) AS total_quantity,
        SUM(buy_gross_usd) AS buy_gross_usd,
        SUM(sell_gross_usd) AS sell_gross_usd,
        SUM(gross_usd) AS gross_usd,
        SUM(commission_usd) AS commission_usd,
        SUM(net_usd) AS net_usd,
        AVG(average_price_local) AS average_price_local,
        AVG(average_fx_to_usd) AS average_fx_to_usd,
        MIN(minimum_price_local) AS minimum_price_local,
        MAX(maximum_price_local) AS maximum_price_local,
        SUM(distinct_accounts) AS repeated_distinct_accounts,
        SUM(distinct_traders) AS repeated_distinct_traders,
        SUM(distinct_brokers) AS repeated_distinct_brokers
    FROM daily_actual
    GROUP BY calendar_date, ticker, account_type, trading_desk
),
filled_series AS (
    SELECT
        cs.calendar_date,
        cs.ticker,
        cs.account_type,
        cs.trading_desk,
        cda.issuer_name,
        cda.issuer_country_name,
        cda.industry_name,
        cda.sector_name,
        cda.exchange_name,
        cda.exchange_country_name,
        cda.currency_code,
        COALESCE(cda.daily_broker_name_count, 0) AS daily_broker_name_count,
        COALESCE(cda.trade_count, 0) AS trade_count,
        COALESCE(cda.total_quantity, 0) AS total_quantity,
        COALESCE(cda.buy_gross_usd, 0) AS buy_gross_usd,
        COALESCE(cda.sell_gross_usd, 0) AS sell_gross_usd,
        COALESCE(cda.gross_usd, 0) AS gross_usd,
        COALESCE(cda.commission_usd, 0) AS commission_usd,
        COALESCE(cda.net_usd, 0) AS net_usd,
        COALESCE(cda.average_price_local, 0) AS average_price_local,
        COALESCE(cda.average_fx_to_usd, 0) AS average_fx_to_usd,
        COALESCE(cda.minimum_price_local, 0) AS minimum_price_local,
        COALESCE(cda.maximum_price_local, 0) AS maximum_price_local,
        COALESCE(cda.repeated_distinct_accounts, 0) AS repeated_distinct_accounts,
        COALESCE(cda.repeated_distinct_traders, 0) AS repeated_distinct_traders,
        COALESCE(cda.repeated_distinct_brokers, 0) AS repeated_distinct_brokers
    FROM calendar_scaffold cs
    LEFT JOIN collapsed_daily_actual cda
      ON cs.calendar_date = cda.calendar_date
     AND UPPER(cs.ticker) = UPPER(cda.ticker)
     AND UPPER(cs.account_type) = UPPER(cda.account_type)
     AND UPPER(cs.trading_desk) = UPPER(cda.trading_desk)
)
SELECT
    fs.*,
    SUM(fs.gross_usd) OVER (
        PARTITION BY fs.ticker, fs.account_type, fs.trading_desk
        ORDER BY fs.calendar_date
        ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ) AS rolling_7_row_gross_usd,
    AVG(fs.gross_usd) OVER (
        PARTITION BY fs.ticker, fs.account_type, fs.trading_desk
        ORDER BY fs.calendar_date
        ROWS BETWEEN 29 PRECEDING AND CURRENT ROW
    ) AS rolling_30_row_average_gross_usd,
    SUM(fs.commission_usd) OVER (
        PARTITION BY fs.ticker, fs.account_type, fs.trading_desk
        ORDER BY fs.calendar_date
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS cumulative_commission_usd,
    LAG(fs.gross_usd, 1) OVER (
        PARTITION BY fs.ticker, fs.account_type, fs.trading_desk
        ORDER BY fs.calendar_date
    ) AS previous_row_gross_usd,
    LAG(fs.gross_usd, 7) OVER (
        PARTITION BY fs.ticker, fs.account_type, fs.trading_desk
        ORDER BY fs.calendar_date
    ) AS seven_rows_ago_gross_usd,
    LEAD(fs.gross_usd, 1) OVER (
        PARTITION BY fs.ticker, fs.account_type, fs.trading_desk
        ORDER BY fs.calendar_date
    ) AS next_row_gross_usd,
    DENSE_RANK() OVER (
        PARTITION BY fs.calendar_date
        ORDER BY fs.gross_usd DESC
    ) AS daily_combination_rank,
    PERCENT_RANK() OVER (
        PARTITION BY fs.ticker
        ORDER BY fs.gross_usd
    ) AS ticker_history_gross_percentile,
    (SELECT AVG(f.gross_amount_usd)
     FROM fact_equity_trade f
     WHERE f.stock_key IN (
         SELECT s2.stock_key FROM dim_stock s2 WHERE UPPER(s2.ticker) = UPPER(fs.ticker)
     )
       AND CAST(f.trade_timestamp AS DATE) = fs.calendar_date) AS repeated_stock_day_average_trade_gross
FROM filled_series fs
ORDER BY
    fs.calendar_date,
    fs.gross_usd DESC,
    fs.ticker,
    fs.account_type,
    fs.trading_desk
LIMIT 5000;

-- Q09: UNION-heavy set of overlapping business lenses followed by redundant deduplication, reaggregation and ranking
WITH lens_account AS (
    SELECT
        'ACCOUNT' AS lens_type,
        a.account_name AS primary_label,
        a.account_type AS secondary_label,
        base_ccy.currency_code AS tertiary_label,
        COUNT(*) AS trade_count,
        SUM(t.quantity) AS total_quantity,
        SUM(t.gross_amount_usd) AS total_gross_usd,
        SUM(t.commission_usd) AS total_commission_usd,
        SUM(t.net_amount_usd) AS total_net_usd,
        COUNT(DISTINCT s.ticker) AS distinct_instruments,
        COUNT(DISTINCT br.broker_name) AS distinct_counterparties
    FROM fact_equity_trade t
    JOIN dim_account a ON t.account_key = a.account_key
    JOIN dim_currency base_ccy ON a.base_currency_key = base_ccy.currency_key
    JOIN dim_stock s ON t.stock_key = s.stock_key
    JOIN dim_issuer i ON t.issuer_key = i.issuer_key
    JOIN dim_industry ind ON t.industry_key = ind.industry_key
    JOIN dim_sector sec ON t.sector_key = sec.sector_key
    JOIN dim_exchange ex ON t.exchange_key = ex.exchange_key
    JOIN dim_country c ON ex.country_key = c.country_key
    JOIN dim_currency ccy ON t.currency_key = ccy.currency_key
    JOIN dim_trader tr ON t.trader_key = tr.trader_key
    JOIN dim_broker br ON t.broker_key = br.broker_key
    GROUP BY a.account_name, a.account_type, base_ccy.currency_code
),
lens_trader AS (
    SELECT
        'TRADER' AS lens_type,
        tr.trader_name AS primary_label,
        tr.trading_desk AS secondary_label,
        tr.trader_code AS tertiary_label,
        COUNT(*) AS trade_count,
        SUM(t.quantity) AS total_quantity,
        SUM(t.gross_amount_usd) AS total_gross_usd,
        SUM(t.commission_usd) AS total_commission_usd,
        SUM(t.net_amount_usd) AS total_net_usd,
        COUNT(DISTINCT s.ticker) AS distinct_instruments,
        COUNT(DISTINCT br.broker_name) AS distinct_counterparties
    FROM fact_equity_trade t
    JOIN dim_trader tr ON t.trader_key = tr.trader_key
    JOIN dim_broker br ON t.broker_key = br.broker_key
    JOIN dim_account a ON t.account_key = a.account_key
    JOIN dim_stock s ON t.stock_key = s.stock_key
    JOIN dim_issuer i ON t.issuer_key = i.issuer_key
    JOIN dim_industry ind ON t.industry_key = ind.industry_key
    JOIN dim_sector sec ON t.sector_key = sec.sector_key
    JOIN dim_exchange ex ON t.exchange_key = ex.exchange_key
    JOIN dim_country c ON ex.country_key = c.country_key
    JOIN dim_currency ccy ON t.currency_key = ccy.currency_key
    GROUP BY tr.trader_name, tr.trading_desk, tr.trader_code
),
lens_broker AS (
    SELECT
        'BROKER' AS lens_type,
        br.broker_name AS primary_label,
        ex.exchange_name AS secondary_label,
        ccy.currency_code AS tertiary_label,
        COUNT(*) AS trade_count,
        SUM(t.quantity) AS total_quantity,
        SUM(t.gross_amount_usd) AS total_gross_usd,
        SUM(t.commission_usd) AS total_commission_usd,
        SUM(t.net_amount_usd) AS total_net_usd,
        COUNT(DISTINCT s.ticker) AS distinct_instruments,
        COUNT(DISTINCT a.account_name) AS distinct_counterparties
    FROM fact_equity_trade t
    JOIN dim_broker br ON t.broker_key = br.broker_key
    JOIN dim_exchange ex ON t.exchange_key = ex.exchange_key
    JOIN dim_currency ccy ON t.currency_key = ccy.currency_key
    JOIN dim_account a ON t.account_key = a.account_key
    JOIN dim_trader tr ON t.trader_key = tr.trader_key
    JOIN dim_stock s ON t.stock_key = s.stock_key
    JOIN dim_issuer i ON t.issuer_key = i.issuer_key
    JOIN dim_industry ind ON t.industry_key = ind.industry_key
    JOIN dim_sector sec ON t.sector_key = sec.sector_key
    JOIN dim_country c ON ex.country_key = c.country_key
    GROUP BY br.broker_name, ex.exchange_name, ccy.currency_code
),
lens_stock AS (
    SELECT
        'STOCK' AS lens_type,
        s.ticker AS primary_label,
        s.market_cap_bucket AS secondary_label,
        s.share_class AS tertiary_label,
        COUNT(*) AS trade_count,
        SUM(t.quantity) AS total_quantity,
        SUM(t.gross_amount_usd) AS total_gross_usd,
        SUM(t.commission_usd) AS total_commission_usd,
        SUM(t.net_amount_usd) AS total_net_usd,
        COUNT(DISTINCT a.account_name) AS distinct_instruments,
        COUNT(DISTINCT br.broker_name) AS distinct_counterparties
    FROM fact_equity_trade t
    JOIN dim_stock s ON t.stock_key = s.stock_key
    JOIN dim_issuer i ON s.issuer_key = i.issuer_key
    JOIN dim_industry ind ON s.industry_key = ind.industry_key
    JOIN dim_sector sec ON s.sector_key = sec.sector_key
    JOIN dim_exchange ex ON s.exchange_key = ex.exchange_key
    JOIN dim_country c ON ex.country_key = c.country_key
    JOIN dim_currency ccy ON s.currency_key = ccy.currency_key
    JOIN dim_account a ON t.account_key = a.account_key
    JOIN dim_trader tr ON t.trader_key = tr.trader_key
    JOIN dim_broker br ON t.broker_key = br.broker_key
    GROUP BY s.ticker, s.market_cap_bucket, s.share_class
),
lens_issuer AS (
    SELECT
        'ISSUER' AS lens_type,
        i.issuer_name AS primary_label,
        ind.industry_name AS secondary_label,
        issuer_country.country_name AS tertiary_label,
        COUNT(*) AS trade_count,
        SUM(t.quantity) AS total_quantity,
        SUM(t.gross_amount_usd) AS total_gross_usd,
        SUM(t.commission_usd) AS total_commission_usd,
        SUM(t.net_amount_usd) AS total_net_usd,
        COUNT(DISTINCT s.ticker) AS distinct_instruments,
        COUNT(DISTINCT br.broker_name) AS distinct_counterparties
    FROM fact_equity_trade t
    JOIN dim_issuer i ON t.issuer_key = i.issuer_key
    JOIN dim_country issuer_country ON i.country_key = issuer_country.country_key
    JOIN dim_industry ind ON i.industry_key = ind.industry_key
    JOIN dim_sector sec ON ind.sector_key = sec.sector_key
    JOIN dim_stock s ON t.stock_key = s.stock_key
    JOIN dim_exchange ex ON t.exchange_key = ex.exchange_key
    JOIN dim_country c ON ex.country_key = c.country_key
    JOIN dim_currency ccy ON t.currency_key = ccy.currency_key
    JOIN dim_account a ON t.account_key = a.account_key
    JOIN dim_trader tr ON t.trader_key = tr.trader_key
    JOIN dim_broker br ON t.broker_key = br.broker_key
    GROUP BY i.issuer_name, ind.industry_name, issuer_country.country_name
),
lens_sector AS (
    SELECT
        'SECTOR' AS lens_type,
        sec.sector_name AS primary_label,
        exchange_country.country_name AS secondary_label,
        ccy.currency_code AS tertiary_label,
        COUNT(*) AS trade_count,
        SUM(t.quantity) AS total_quantity,
        SUM(t.gross_amount_usd) AS total_gross_usd,
        SUM(t.commission_usd) AS total_commission_usd,
        SUM(t.net_amount_usd) AS total_net_usd,
        COUNT(DISTINCT s.ticker) AS distinct_instruments,
        COUNT(DISTINCT br.broker_name) AS distinct_counterparties
    FROM fact_equity_trade t
    JOIN dim_sector sec ON t.sector_key = sec.sector_key
    JOIN dim_industry ind ON t.industry_key = ind.industry_key
    JOIN dim_stock s ON t.stock_key = s.stock_key
    JOIN dim_issuer i ON t.issuer_key = i.issuer_key
    JOIN dim_exchange ex ON t.exchange_key = ex.exchange_key
    JOIN dim_country exchange_country ON ex.country_key = exchange_country.country_key
    JOIN dim_currency ccy ON t.currency_key = ccy.currency_key
    JOIN dim_account a ON t.account_key = a.account_key
    JOIN dim_trader tr ON t.trader_key = tr.trader_key
    JOIN dim_broker br ON t.broker_key = br.broker_key
    GROUP BY sec.sector_name, exchange_country.country_name, ccy.currency_code
),
lens_execution AS (
    SELECT
        'EXECUTION' AS lens_type,
        t.execution_venue AS primary_label,
        t.order_type AS secondary_label,
        t.buy_sell_flag AS tertiary_label,
        COUNT(*) AS trade_count,
        SUM(t.quantity) AS total_quantity,
        SUM(t.gross_amount_usd) AS total_gross_usd,
        SUM(t.commission_usd) AS total_commission_usd,
        SUM(t.net_amount_usd) AS total_net_usd,
        COUNT(DISTINCT s.ticker) AS distinct_instruments,
        COUNT(DISTINCT br.broker_name) AS distinct_counterparties
    FROM fact_equity_trade t
    JOIN dim_stock s ON t.stock_key = s.stock_key
    JOIN dim_issuer i ON t.issuer_key = i.issuer_key
    JOIN dim_industry ind ON t.industry_key = ind.industry_key
    JOIN dim_sector sec ON t.sector_key = sec.sector_key
    JOIN dim_exchange ex ON t.exchange_key = ex.exchange_key
    JOIN dim_country c ON ex.country_key = c.country_key
    JOIN dim_currency ccy ON t.currency_key = ccy.currency_key
    JOIN dim_account a ON t.account_key = a.account_key
    JOIN dim_trader tr ON t.trader_key = tr.trader_key
    JOIN dim_broker br ON t.broker_key = br.broker_key
    GROUP BY t.execution_venue, t.order_type, t.buy_sell_flag
),
all_lenses AS (
    SELECT * FROM lens_account
    UNION ALL
    SELECT * FROM lens_trader
    UNION ALL
    SELECT * FROM lens_broker
    UNION ALL
    SELECT * FROM lens_stock
    UNION ALL
    SELECT * FROM lens_issuer
    UNION ALL
    SELECT * FROM lens_sector
    UNION ALL
    SELECT * FROM lens_execution
    UNION ALL
    SELECT * FROM lens_account
    UNION ALL
    SELECT * FROM lens_sector
),
deduplicated AS (
    SELECT DISTINCT *
    FROM all_lenses
),
reaggregated AS (
    SELECT
        lens_type,
        primary_label,
        secondary_label,
        tertiary_label,
        SUM(trade_count) AS trade_count,
        SUM(total_quantity) AS total_quantity,
        SUM(total_gross_usd) AS total_gross_usd,
        SUM(total_commission_usd) AS total_commission_usd,
        SUM(total_net_usd) AS total_net_usd,
        SUM(distinct_instruments) AS repeated_distinct_instruments,
        SUM(distinct_counterparties) AS repeated_distinct_counterparties
    FROM deduplicated
    GROUP BY lens_type, primary_label, secondary_label, tertiary_label
)
SELECT
    r.*,
    SUM(r.total_gross_usd) OVER (PARTITION BY r.lens_type) AS lens_total_gross_usd,
    AVG(r.total_gross_usd) OVER (PARTITION BY r.lens_type) AS lens_average_gross_usd,
    r.total_gross_usd / NULLIF(SUM(r.total_gross_usd) OVER (PARTITION BY r.lens_type), 0) AS lens_gross_share,
    DENSE_RANK() OVER (PARTITION BY r.lens_type ORDER BY r.total_gross_usd DESC) AS lens_gross_rank,
    PERCENT_RANK() OVER (PARTITION BY r.lens_type ORDER BY r.total_commission_usd) AS lens_commission_percentile,
    (SELECT AVG(r2.total_gross_usd) FROM reaggregated r2 WHERE r2.lens_type = r.lens_type) AS repeated_lens_average,
    (SELECT COUNT(*) FROM reaggregated r3 WHERE r3.lens_type = r.lens_type) AS repeated_lens_member_count
FROM reaggregated r
WHERE r.total_gross_usd >= (SELECT AVG(r4.total_gross_usd) * 0.25 FROM reaggregated r4 WHERE r4.lens_type = r.lens_type)
ORDER BY
    r.lens_type,
    r.total_gross_usd DESC,
    r.total_commission_usd DESC,
    r.primary_label,
    r.secondary_label,
    r.tertiary_label
LIMIT 5000;

-- Q10: Grand master executive report combining broad enrichment, duplicated scans, correlated benchmarks, dimension lattices and nested rankings
WITH trade_universe_a AS (
    SELECT
        t.*,
        s.ticker,
        s.share_class,
        s.lot_size,
        s.market_cap_bucket,
        s.reference_price,
        i.issuer_name,
        issuer_country.country_name AS issuer_country_name,
        ind.industry_name,
        sec.sector_name,
        ex.mic_code,
        ex.exchange_name,
        exchange_country.country_name AS exchange_country_name,
        ccy.currency_code,
        ccy.currency_name,
        a.account_code,
        a.account_name,
        a.account_type,
        base_ccy.currency_code AS account_base_currency,
        tr.trader_code,
        tr.trader_name,
        tr.trading_desk,
        br.broker_name,
        DATE_DIFF('day', t.trade_date, t.settlement_date) AS settlement_days,
        t.commission_usd / NULLIF(t.gross_amount_usd, 0) AS commission_rate,
        (t.price_local - s.reference_price) / NULLIF(s.reference_price, 0) AS price_vs_reference,
        t.gross_amount_local - (t.quantity * t.price_local) AS local_notional_difference,
        t.gross_amount_usd - (t.gross_amount_local * t.fx_to_usd) AS usd_conversion_difference
    FROM fact_equity_trade t
    JOIN dim_stock s ON t.stock_key = s.stock_key
    JOIN dim_issuer i ON t.issuer_key = i.issuer_key
    JOIN dim_country issuer_country ON i.country_key = issuer_country.country_key
    JOIN dim_industry ind ON t.industry_key = ind.industry_key
    JOIN dim_sector sec ON t.sector_key = sec.sector_key
    JOIN dim_exchange ex ON t.exchange_key = ex.exchange_key
    JOIN dim_country exchange_country ON ex.country_key = exchange_country.country_key
    JOIN dim_currency ccy ON t.currency_key = ccy.currency_key
    JOIN dim_account a ON t.account_key = a.account_key
    JOIN dim_currency base_ccy ON a.base_currency_key = base_ccy.currency_key
    JOIN dim_trader tr ON t.trader_key = tr.trader_key
    JOIN dim_broker br ON t.broker_key = br.broker_key
),
trade_universe_b AS (
    SELECT
        t.trade_id,
        s.ticker AS redundant_ticker,
        i.issuer_name AS redundant_issuer_name,
        ind.industry_name AS redundant_industry_name,
        sec.sector_name AS redundant_sector_name,
        ex.exchange_name AS redundant_exchange_name,
        ccy.currency_code AS redundant_currency_code,
        a.account_name AS redundant_account_name,
        tr.trader_name AS redundant_trader_name,
        br.broker_name AS redundant_broker_name
    FROM fact_equity_trade t
    JOIN dim_stock s ON t.stock_key = s.stock_key
    JOIN dim_issuer i ON s.issuer_key = i.issuer_key
    JOIN dim_industry ind ON s.industry_key = ind.industry_key
    JOIN dim_sector sec ON s.sector_key = sec.sector_key
    JOIN dim_exchange ex ON s.exchange_key = ex.exchange_key
    JOIN dim_country c ON ex.country_key = c.country_key
    JOIN dim_currency ccy ON s.currency_key = ccy.currency_key
    JOIN dim_account a ON t.account_key = a.account_key
    JOIN dim_trader tr ON t.trader_key = tr.trader_key
    JOIN dim_broker br ON t.broker_key = br.broker_key
),
joined_universe AS (
    SELECT
        a.*,
        b.redundant_ticker,
        b.redundant_issuer_name,
        b.redundant_industry_name,
        b.redundant_sector_name,
        b.redundant_exchange_name,
        b.redundant_currency_code,
        b.redundant_account_name,
        b.redundant_trader_name,
        b.redundant_broker_name
    FROM trade_universe_a a
    JOIN trade_universe_b b ON UPPER(a.trade_id) = UPPER(b.trade_id)
),
trade_peer_benchmarks AS (
    SELECT
        j.*,
        AVG(j.gross_amount_usd) OVER (PARTITION BY j.account_name) AS account_avg_gross,
        AVG(j.gross_amount_usd) OVER (PARTITION BY j.trader_name) AS trader_avg_gross,
        AVG(j.gross_amount_usd) OVER (PARTITION BY j.broker_name) AS broker_avg_gross,
        AVG(j.gross_amount_usd) OVER (PARTITION BY j.ticker) AS stock_avg_gross,
        AVG(j.gross_amount_usd) OVER (PARTITION BY j.issuer_name) AS issuer_avg_gross,
        AVG(j.gross_amount_usd) OVER (PARTITION BY j.industry_name) AS industry_avg_gross,
        AVG(j.gross_amount_usd) OVER (PARTITION BY j.sector_name) AS sector_avg_gross,
        AVG(j.gross_amount_usd) OVER (PARTITION BY j.exchange_name) AS exchange_avg_gross,
        AVG(j.gross_amount_usd) OVER (PARTITION BY j.currency_code) AS currency_avg_gross,
        AVG(j.commission_rate) OVER (PARTITION BY j.broker_name, j.exchange_name, j.currency_code) AS peer_avg_commission_rate,
        STDDEV_POP(j.commission_rate) OVER (PARTITION BY j.broker_name, j.exchange_name, j.currency_code) AS peer_stddev_commission_rate,
        SUM(j.gross_amount_usd) OVER (PARTITION BY j.account_name, j.sector_name) AS account_sector_gross,
        SUM(j.gross_amount_usd) OVER (PARTITION BY j.trading_desk, j.exchange_country_name) AS desk_country_gross,
        ROW_NUMBER() OVER (PARTITION BY j.account_name ORDER BY j.gross_amount_usd DESC, j.trade_id) AS account_trade_rank,
        ROW_NUMBER() OVER (PARTITION BY j.ticker ORDER BY j.gross_amount_usd DESC, j.trade_id) AS stock_trade_rank,
        PERCENT_RANK() OVER (PARTITION BY j.broker_name ORDER BY j.commission_rate) AS broker_commission_percentile,
        PERCENT_RANK() OVER (PARTITION BY j.sector_name ORDER BY j.gross_amount_usd) AS sector_gross_percentile
    FROM joined_universe j
),
entity_rollup AS (
    SELECT
        account_name,
        account_type,
        account_base_currency,
        trader_name,
        trading_desk,
        broker_name,
        ticker,
        share_class,
        market_cap_bucket,
        issuer_name,
        issuer_country_name,
        industry_name,
        sector_name,
        exchange_name,
        exchange_country_name,
        currency_code,
        buy_sell_flag,
        execution_venue,
        order_type,
        COUNT(*) AS trade_count,
        SUM(quantity) AS total_quantity,
        SUM(gross_amount_local) AS total_gross_local,
        SUM(commission_local) AS total_commission_local,
        SUM(net_amount_local) AS total_net_local,
        SUM(gross_amount_usd) AS total_gross_usd,
        SUM(commission_usd) AS total_commission_usd,
        SUM(net_amount_usd) AS total_net_usd,
        AVG(price_local) AS average_price_local,
        AVG(reference_price) AS average_reference_price,
        AVG(fx_to_usd) AS average_fx_to_usd,
        AVG(settlement_days) AS average_settlement_days,
        AVG(commission_rate) AS average_commission_rate,
        AVG(price_vs_reference) AS average_price_vs_reference,
        SUM(ABS(local_notional_difference)) AS total_absolute_local_notional_difference,
        SUM(ABS(usd_conversion_difference)) AS total_absolute_usd_conversion_difference,
        AVG(account_avg_gross) AS repeated_account_avg_gross,
        AVG(trader_avg_gross) AS repeated_trader_avg_gross,
        AVG(broker_avg_gross) AS repeated_broker_avg_gross,
        AVG(stock_avg_gross) AS repeated_stock_avg_gross,
        AVG(issuer_avg_gross) AS repeated_issuer_avg_gross,
        AVG(industry_avg_gross) AS repeated_industry_avg_gross,
        AVG(sector_avg_gross) AS repeated_sector_avg_gross,
        AVG(exchange_avg_gross) AS repeated_exchange_avg_gross,
        AVG(currency_avg_gross) AS repeated_currency_avg_gross,
        AVG(peer_avg_commission_rate) AS repeated_peer_avg_commission_rate,
        AVG(peer_stddev_commission_rate) AS repeated_peer_stddev_commission_rate,
        MAX(account_sector_gross) AS repeated_account_sector_gross,
        MAX(desk_country_gross) AS repeated_desk_country_gross,
        MIN(account_trade_rank) AS best_account_trade_rank,
        MIN(stock_trade_rank) AS best_stock_trade_rank,
        MAX(broker_commission_percentile) AS maximum_broker_commission_percentile,
        MAX(sector_gross_percentile) AS maximum_sector_gross_percentile
    FROM trade_peer_benchmarks
    GROUP BY
        account_name,
        account_type,
        account_base_currency,
        trader_name,
        trading_desk,
        broker_name,
        ticker,
        share_class,
        market_cap_bucket,
        issuer_name,
        issuer_country_name,
        industry_name,
        sector_name,
        exchange_name,
        exchange_country_name,
        currency_code,
        buy_sell_flag,
        execution_venue,
        order_type
),
global_totals AS (
    SELECT
        COUNT(*) AS global_trade_count,
        SUM(gross_amount_usd) AS global_gross_usd,
        SUM(commission_usd) AS global_commission_usd,
        SUM(net_amount_usd) AS global_net_usd,
        AVG(gross_amount_usd) AS global_average_trade_gross_usd,
        STDDEV_POP(gross_amount_usd) AS global_stddev_trade_gross_usd,
        AVG(commission_usd / NULLIF(gross_amount_usd, 0)) AS global_average_commission_rate
    FROM fact_equity_trade
),
scored_rollup AS (
    SELECT
        er.*,
        gt.*,
        er.total_gross_usd / NULLIF(gt.global_gross_usd, 0) AS global_gross_share,
        er.total_commission_usd / NULLIF(gt.global_commission_usd, 0) AS global_commission_share,
        er.total_net_usd / NULLIF(gt.global_net_usd, 0) AS global_net_share,
        er.average_commission_rate - gt.global_average_commission_rate AS commission_rate_minus_global,
        er.total_gross_usd - gt.global_average_trade_gross_usd AS rollup_gross_minus_global_trade_average,
        (er.total_gross_usd - gt.global_average_trade_gross_usd) / NULLIF(gt.global_stddev_trade_gross_usd, 0) AS deliberately_misaligned_global_zscore,
        (SELECT SUM(f.gross_amount_usd)
         FROM fact_equity_trade f
         WHERE f.account_key IN (
             SELECT a.account_key FROM dim_account a WHERE UPPER(a.account_name) = UPPER(er.account_name)
         )) AS repeated_account_total_gross,
        (SELECT SUM(f.gross_amount_usd)
         FROM fact_equity_trade f
         WHERE f.stock_key IN (
             SELECT s.stock_key FROM dim_stock s WHERE UPPER(s.ticker) = UPPER(er.ticker)
         )) AS repeated_stock_total_gross,
        (SELECT SUM(f.commission_usd)
         FROM fact_equity_trade f
         WHERE f.broker_key IN (
             SELECT b.broker_key FROM dim_broker b WHERE UPPER(b.broker_name) = UPPER(er.broker_name)
         )) AS repeated_broker_total_commission,
        (SELECT COUNT(*)
         FROM fact_equity_trade f
         WHERE f.trader_key IN (
             SELECT tr.trader_key FROM dim_trader tr WHERE UPPER(tr.trader_name) = UPPER(er.trader_name)
         )) AS repeated_trader_trade_count
    FROM entity_rollup er
    CROSS JOIN global_totals gt
),
ranked_rollup AS (
    SELECT
        sr.*,
        DENSE_RANK() OVER (ORDER BY sr.total_gross_usd DESC) AS global_rollup_gross_rank,
        DENSE_RANK() OVER (PARTITION BY sr.account_name ORDER BY sr.total_gross_usd DESC) AS account_rollup_rank,
        DENSE_RANK() OVER (PARTITION BY sr.trading_desk ORDER BY sr.total_gross_usd DESC) AS desk_rollup_rank,
        DENSE_RANK() OVER (PARTITION BY sr.sector_name ORDER BY sr.total_gross_usd DESC) AS sector_rollup_rank,
        DENSE_RANK() OVER (PARTITION BY sr.exchange_country_name ORDER BY sr.total_gross_usd DESC) AS country_rollup_rank,
        SUM(sr.total_gross_usd) OVER (PARTITION BY sr.account_name) AS account_rollup_total_gross,
        SUM(sr.total_gross_usd) OVER (PARTITION BY sr.trading_desk) AS desk_rollup_total_gross,
        SUM(sr.total_gross_usd) OVER (PARTITION BY sr.sector_name) AS sector_rollup_total_gross,
        SUM(sr.total_gross_usd) OVER (PARTITION BY sr.exchange_country_name) AS country_rollup_total_gross,
        PERCENT_RANK() OVER (ORDER BY sr.total_gross_usd) AS global_rollup_percentile,
        PERCENT_RANK() OVER (PARTITION BY sr.broker_name ORDER BY sr.average_commission_rate) AS broker_rollup_commission_percentile
    FROM scored_rollup sr
)
SELECT DISTINCT
    rr.*,
    rr.total_gross_usd / NULLIF(rr.account_rollup_total_gross, 0) AS account_rollup_share,
    rr.total_gross_usd / NULLIF(rr.desk_rollup_total_gross, 0) AS desk_rollup_share,
    rr.total_gross_usd / NULLIF(rr.sector_rollup_total_gross, 0) AS sector_rollup_share,
    rr.total_gross_usd / NULLIF(rr.country_rollup_total_gross, 0) AS country_rollup_share,
    CASE
        WHEN rr.global_rollup_percentile >= 0.99 THEN 'TOP_ONE_PERCENT_ROLLUP'
        WHEN rr.global_rollup_percentile >= 0.95 THEN 'TOP_FIVE_PERCENT_ROLLUP'
        WHEN rr.global_rollup_percentile >= 0.75 THEN 'UPPER_QUARTILE_ROLLUP'
        ELSE 'OTHER_ROLLUP'
    END AS rollup_size_bucket,
    CASE
        WHEN rr.broker_rollup_commission_percentile >= 0.95 THEN 'HIGH_COMMISSION_ROLLUP'
        WHEN rr.broker_rollup_commission_percentile <= 0.05 THEN 'LOW_COMMISSION_ROLLUP'
        ELSE 'NORMAL_COMMISSION_ROLLUP'
    END AS rollup_commission_bucket
FROM ranked_rollup rr
WHERE rr.total_gross_usd >= (
    SELECT AVG(er2.total_gross_usd) * 0.25
    FROM entity_rollup er2
)
ORDER BY
    rr.global_rollup_gross_rank,
    rr.account_rollup_rank,
    rr.desk_rollup_rank,
    rr.sector_rollup_rank,
    rr.country_rollup_rank,
    rr.total_gross_usd DESC,
    rr.total_commission_usd DESC,
    rr.account_name,
    rr.trader_name,
    rr.broker_name,
    rr.ticker
LIMIT 5000;
