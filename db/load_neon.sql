\set ON_ERROR_STOP on

\echo 'Loading dim_country'
\copy dim_country FROM 'db/dim_country.csv' WITH (FORMAT csv, HEADER true)

\echo 'Loading dim_currency'
\copy dim_currency FROM 'db/dim_currency.csv' WITH (FORMAT csv, HEADER true)

\echo 'Loading dim_sector'
\copy dim_sector FROM 'db/dim_sector.csv' WITH (FORMAT csv, HEADER true)

\echo 'Loading dim_industry'
\copy dim_industry FROM 'db/dim_industry.csv' WITH (FORMAT csv, HEADER true)

\echo 'Loading dim_exchange'
\copy dim_exchange FROM 'db/dim_exchange.csv' WITH (FORMAT csv, HEADER true)

\echo 'Loading dim_broker'
\copy dim_broker FROM 'db/dim_broker.csv' WITH (FORMAT csv, HEADER true)

\echo 'Loading dim_trader'
\copy dim_trader FROM 'db/dim_trader.csv' WITH (FORMAT csv, HEADER true)

\echo 'Loading dim_account'
\copy dim_account FROM 'db/dim_account.csv' WITH (FORMAT csv, HEADER true)

\echo 'Loading dim_issuer'
\copy dim_issuer FROM 'db/dim_issuer.csv' WITH (FORMAT csv, HEADER true)

\echo 'Loading dim_stock'
\copy dim_stock FROM 'db/dim_stock.csv' WITH (FORMAT csv, HEADER true)

\echo 'Loading fact_equity_trade'
\copy fact_equity_trade FROM 'db/fact_equity_trade.csv' WITH (FORMAT csv, HEADER true)

\echo 'Updating PostgreSQL statistics'
ANALYZE;

\echo 'Import complete'
