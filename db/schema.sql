CREATE TABLE dim_country (
  country_key INT PRIMARY KEY,
  country_code VARCHAR(2),
  country_name VARCHAR(100)
);

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