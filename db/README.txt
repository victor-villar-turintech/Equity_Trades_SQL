Synthetic Equity Trade Dataset — Original Source Layout

Package contents:
- 10 dimension tables
- 1 fact table with 100,000 trades
- SQL DDL for the original schema

Purpose:
This dataset is designed to let Artemis identify multiple stock-related dimensions used downstream and later consolidate them into a single richer stock/security dimension.

Important design choice for transformation testing:
The fact table intentionally contains these stock-descriptor foreign keys in parallel:
- stock_key
- issuer_key
- industry_key
- sector_key
- exchange_key
- currency_key

This makes it suitable for:
1. detecting overlapping dimensional dependencies,
2. replacing multiple joins with one consolidated stock dimension,
3. validating no-result-change before/after the dimensional rewrite,
4. benchmarking ETL/query simplification and speed.

Row counts:
- fact_equity_trade: 100,000
- dim_stock: 400
- dim_issuer: 320
- dim_industry: 39
- dim_sector: 11
- dim_exchange: 11
- dim_country: 10
- dim_currency: 8
- dim_broker: 12
- dim_trader: 60
- dim_account: 40

Generation notes:
- Random seed used: 20260312
- Trade IDs are unique.
- Prices, quantities, desks, venues, and order types are randomized with weighted distributions.
- Stocks are sampled with unequal popularity so the dataset looks more realistic.
- The data is synthetic and intended for schema/transformation/performance testing, not market-accurate analytics.