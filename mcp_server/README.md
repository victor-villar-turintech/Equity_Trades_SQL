# Equity Trades SQL MCP Server

This document explains the `mcp_server` folder, the MCP server code, the database connection, local testing, Render deployment, MCP Inspector testing, Artemis configuration, security controls, maintenance, and troubleshooting.

It is intentionally written as a complete end-to-end guide. Do not skip a step because it appears obvious. Many deployment failures happen because one small value was copied into the wrong field, a command was run in the wrong Terminal window, or a trailing slash was omitted.

> **This file belongs at:** `mcp_server/README.md`

---

## 1. What this server does

The repository contains a synthetic equity-trading PostgreSQL dataset. The MCP server provides controlled, read-only access to that database so an MCP client such as Artemis or MCP Inspector can:

- inspect the available tables;
- inspect a table's columns and data types;
- retrieve small samples;
- search enriched trade records;
- calculate summary statistics by ticker;
- execute a restricted read-only SQL query;
- receive results as JSON-compatible data.

The MCP server does **not** modify the database. It is designed to read data only.

The deployed architecture is:

```text
Artemis or MCP Inspector
          |
          | HTTPS request
          | Authorization: Bearer <MCP_API_KEY>
          v
Render Web Service
          |
          | Runs Uvicorn + Starlette + FastMCP
          | Validates the bearer token
          | Applies host/origin security checks
          v
Python MCP server: mcp_server/app.py
          |
          | Opens a short-lived PostgreSQL connection
          | Uses the read-only mcp_reader role
          | Applies a 10-second statement timeout
          v
Neon pooled PostgreSQL connection
          |
          v
Synthetic equity-trading tables
```

The important separation is:

- **Artemis receives the MCP URL and MCP bearer token.**
- **Render receives the database URL and MCP bearer token.**
- **Neon stores the database.**
- **Artemis never needs the Neon database password.**

---

## 2. What MCP means

**MCP** stands for **Model Context Protocol**.

MCP is a standard way for an AI application to discover and call tools exposed by another program.

In this project:

- **MCP client:** Artemis or MCP Inspector.
- **MCP server:** the Python application in `mcp_server/app.py`.
- **MCP tool:** a Python function decorated with `@mcp.tool()`.
- **Tool call:** a request from Artemis asking the server to run one of those functions.
- **Tool result:** the JSON-compatible data returned by that function.

A simplified example is:

```text
Artemis asks:
"List all database tables."

Artemis calls:
list_tables

The MCP server runs:
A read-only query against PostgreSQL.

The MCP server returns:
A JSON list of table names.
```

---

## 3. Important terminology

### PostgreSQL

PostgreSQL is the database engine. It stores the tables and executes SQL.

### Neon

Neon is the hosted PostgreSQL provider used by this project.

### Render

Render hosts the Python web service and gives it a public HTTPS URL.

### Uvicorn

Uvicorn is the web server process that starts the Python ASGI application.

### Starlette

Starlette provides the HTTP routes, application lifecycle, and middleware structure.

### FastMCP

FastMCP registers the Python functions as MCP tools and provides the Streamable HTTP MCP application.

### Streamable HTTP

Streamable HTTP is the network transport used by the remote MCP server.

The deployed MCP endpoint is:

```text
https://equity-trades-mcp.onrender.com/mcp/
```

The trailing slash is intentional.

### Endpoint

An endpoint is a URL path handled by the server.

This application exposes:

| Endpoint | Authentication | Purpose |
|---|---|---|
| `/` | Public | Basic service information |
| `/health` | Public | Health check |
| `/mcp/` | Bearer token required | MCP protocol endpoint |

### Bearer token

A bearer token is a secret value sent in an HTTP header:

```http
Authorization: Bearer <secret-value>
```

Anyone who possesses this value can authenticate to this MCP server. Treat it as a password.

### Environment variable

An environment variable is a named value supplied to a process without hard-coding it in source code.

This application uses:

- `DATABASE_URL`
- `MCP_API_KEY`
- `PUBLIC_MCP_HOST`

### Database role

A PostgreSQL role is a database user with permissions.

The application must use:

```text
mcp_reader
```

It must not use:

```text
neondb_owner
```

### Direct connection string

A direct Neon connection string connects directly to a Neon PostgreSQL endpoint. It is appropriate for schema creation and data import.

Its hostname normally does **not** contain `-pooler`.

### Pooled connection string

A pooled Neon connection string goes through Neon's connection pooler. It is appropriate for the deployed web application, which opens short-lived connections.

Its hostname contains:

```text
-pooler
```

Example shape:

```text
postgresql://mcp_reader:PASSWORD@ep-example-pooler.eu-west-2.aws.neon.tech/neondb?sslmode=require
```

Never paste a real connection string into source code, GitHub, screenshots, tickets, or documentation.

---

## 4. Folder contents

The MCP folder contains:

```text
mcp_server/
├── __init__.py
├── app.py
└── README.md
```

### `__init__.py`

This marks `mcp_server` as a Python package.

It can be empty.

### `app.py`

This is the complete MCP server implementation.

It contains:

- environment-variable loading;
- FastMCP configuration;
- DNS-rebinding protection;
- database query helpers;
- read-only validation;
- MCP tool definitions;
- public health and status routes;
- bearer-token middleware;
- the final ASGI `app` object used by Uvicorn.

### `README.md`

This document.

The Python package dependencies are stored at repository root in:

```text
requirements.txt
```

Current dependency ranges:

```text
mcp>=1.28,<2
psycopg[binary]>=3.2,<4
uvicorn>=0.34,<1
```

---

## 5. Existing repository purpose

The root repository is a synthetic equity-trading benchmark designed for schema simplification, ETL validation, SQL rewriting, and before/after performance comparison.

The database includes:

- 100,000 synthetic equity trades;
- stock reference data;
- issuer reference data;
- industry and sector reference data;
- exchange and country reference data;
- currency reference data;
- broker reference data;
- trader reference data;
- account reference data.

The data is synthetic. It is suitable for database, SQL, MCP, and performance-testing workflows. It must not be treated as genuine market data or used for real trading decisions.

---

## 6. Database tables exposed by the server

The current allow-list in `app.py` contains:

```text
dim_account
dim_broker
dim_country
dim_currency
dim_exchange
dim_industry
dim_issuer
dim_sector
dim_stock
dim_trader
fact_equity_trade
```

The allow-list is deliberate.

Functions such as `describe_table` and `sample_table` reject any table name that is not in this list.

This prevents a client from inventing arbitrary table names and asking the server to inspect tables outside the intended dataset.

---

## 7. Environment variables

The application reads three environment variables.

### 7.1 `DATABASE_URL`

Purpose:

```text
Connect the Python server to Neon PostgreSQL.
```

Required:

```text
Yes
```

Expected content:

```text
A pooled Neon PostgreSQL connection string for the mcp_reader role.
```

Correct shape:

```text
postgresql://mcp_reader:PASSWORD@ep-example-pooler.eu-west-2.aws.neon.tech/neondb?sslmode=require&channel_binding=require
```

Incorrect examples:

```text
postgresql://neondb_owner:...
```

```text
https://ep-example...
```

```text
"postgresql://mcp_reader:..."
```

Do not include surrounding quotation marks when entering the value in Render.

### 7.2 `MCP_API_KEY`

Purpose:

```text
Authenticate requests to /mcp/.
```

Required:

```text
Yes
```

Expected content:

```text
A random 64-character hexadecimal value.
```

Generate it with:

```bash
openssl rand -hex 32
```

The Render environment variable contains the raw token only:

```text
a1b2c3d4...
```

It must not contain:

```text
Bearer a1b2c3d4...
```

The `Bearer ` prefix is added by the HTTP client when it builds the `Authorization` header.

### 7.3 `PUBLIC_MCP_HOST`

Purpose:

```text
Allow the deployed public hostname through the MCP transport's
DNS-rebinding protection.
```

Required on Render:

```text
Recommended
```

Current value:

```text
equity-trades-mcp.onrender.com
```

Correct:

```text
equity-trades-mcp.onrender.com
```

Incorrect:

```text
https://equity-trades-mcp.onrender.com
```

Incorrect:

```text
equity-trades-mcp.onrender.com/mcp/
```

Incorrect:

```text
https://equity-trades-mcp.onrender.com/mcp/
```

This value is a hostname only. It does not include a protocol or path.

---

## 8. What happens when the application starts

When Python imports `mcp_server.app`, the following occurs:

1. Python imports the required libraries.
2. The program reads `DATABASE_URL`.
3. The program reads `MCP_API_KEY`.
4. The program reads `PUBLIC_MCP_HOST`.
5. The program stops immediately if `DATABASE_URL` is empty.
6. The program stops immediately if `MCP_API_KEY` is empty.
7. FastMCP is configured.
8. The MCP tools are registered.
9. Starlette routes are created.
10. Bearer authentication middleware wraps the Starlette application.
11. The final ASGI application is exposed as `app`.

This is why the Uvicorn start command references:

```text
mcp_server.app:app
```

That syntax means:

```text
Python module: mcp_server.app
Object inside that module: app
```

---

## 9. Code walkthrough

### 9.1 Imports

The application imports:

- `contextlib` for the asynchronous application lifespan;
- `os` for environment variables;
- `re` for SQL validation;
- `secrets` for constant-time bearer-token comparison;
- date, datetime, Decimal, and bytes conversion helpers;
- `psycopg` for PostgreSQL access;
- `FastMCP` for MCP tool registration;
- `TransportSecuritySettings` for host and origin validation;
- Starlette for HTTP routing;
- ASGI types for the custom middleware.

### 9.2 Required configuration

The application reads:

```python
DATABASE_URL = os.getenv("DATABASE_URL", "").strip()
MCP_API_KEY = os.getenv("MCP_API_KEY", "").strip()
```

The `.strip()` removes accidental whitespace at the beginning or end.

The application deliberately fails early if either required value is absent. This is better than starting a broken service and failing later on the first request.

### 9.3 Limits

The code defines:

```python
MAX_RESULT_ROWS = 500
MAX_SQL_LENGTH = 20_000
```

These limits reduce the chance of a client requesting an unbounded amount of data or sending an excessively large SQL statement.

Different tools use smaller limits:

- `sample_table`: maximum 100 rows;
- `search_equity_trades`: maximum 200 rows;
- `trade_summary_by_ticker`: maximum 100 rows;
- `execute_read_only_sql`: maximum 500 rows.

### 9.4 FastMCP configuration

The server uses:

```python
stateless_http=True
json_response=True
streamable_http_path="/"
```

The FastMCP application itself is mounted under Starlette at `/mcp`.

Because it is mounted as a sub-application, the canonical deployed path is:

```text
/mcp/
```

### 9.5 DNS-rebinding protection

The MCP transport validates the incoming host and origin.

Allowed hosts include:

- the configured public Render hostname;
- the same hostname with an arbitrary port;
- `localhost`;
- `127.0.0.1`.

This protects the local or deployed service from requests carrying an unexpected `Host` header.

A missing public hostname causes:

```text
421 Invalid Host header
```

The fix is not to disable security. The fix is to supply the correct `PUBLIC_MCP_HOST`.

### 9.6 JSON conversion

PostgreSQL can return values that cannot be serialized directly to JSON.

The `_jsonable` helper converts:

- `Decimal` to text;
- `date` and `datetime` to ISO-formatted text;
- `bytes` to UTF-8 text;
- dictionaries recursively;
- lists and tuples recursively.

Decimal values are returned as strings to avoid silently losing precision.

### 9.7 Result limits

The `_bounded_limit` helper forces a requested limit into an allowed range.

For example:

```text
Requested limit: -5
Actual limit: 1
```

```text
Requested limit: 100000
Maximum: 500
Actual limit: 500
```

### 9.8 Query execution

The `_run_query` helper:

1. opens a new PostgreSQL connection;
2. uses dictionary-style rows;
3. sets a 10-second connection timeout;
4. starts a read-only transaction;
5. sets a 10-second SQL statement timeout;
6. executes the query;
7. fetches one more row than requested;
8. uses the extra row to determine whether results were truncated;
9. converts values to JSON-compatible types;
10. returns a consistent result object.

The usual result shape is:

```json
{
  "columns": [
    "ticker",
    "trade_count"
  ],
  "rows": [
    {
      "ticker": "EXAMPLE",
      "trade_count": 123
    }
  ],
  "row_count": 1,
  "truncated": false
}
```

If `truncated` is `true`, more rows existed than the tool was allowed to return.

### 9.9 Table-name validation

`_validate_table` normalizes a requested table name to lowercase and checks it against `ALLOWED_TABLES`.

This is important because SQL identifiers cannot be safely handled in the same way as ordinary query values.

The code uses Psycopg's `sql.Identifier` when dynamically inserting an approved table name.

### 9.10 Read-only SQL validation

`_validate_read_only_sql` performs application-level checks:

- the query cannot be empty;
- the query cannot exceed 20,000 characters;
- SQL comments are removed before validation;
- only one statement is allowed;
- only `SELECT`, `WITH`, and `EXPLAIN` are accepted.

The server also uses a read-only database role and read-only transaction.

The application-level validator is one security layer. It must never be treated as a replacement for the database-level read-only role.

---

## 10. MCP tools

The server currently exposes seven tools.

### 10.1 `database_overview`

Purpose:

```text
Return high-level statistics for the fact table.
```

Inputs:

```text
None
```

Returns:

- trade count;
- earliest trade date;
- latest trade date;
- distinct stock count;
- distinct account count;
- distinct trader count;
- total gross amount in USD;
- total commission amount in USD.

Example Artemis request:

```text
Use the equity-trades MCP server to give me a database overview.
```

### 10.2 `list_tables`

Purpose:

```text
List base tables in the public PostgreSQL schema.
```

Inputs:

```text
None
```

Example Artemis request:

```text
List every table available through the equity-trades MCP server.
```

### 10.3 `describe_table`

Purpose:

```text
Describe the columns and row count of one approved table.
```

Inputs:

| Input | Type | Required | Example |
|---|---|---:|---|
| `table_name` | string | Yes | `fact_equity_trade` |

Returns:

- table name;
- column order;
- column names;
- PostgreSQL data types;
- nullability;
- character length where relevant;
- numeric precision and scale where relevant;
- row count.

Inspector input:

```json
{
  "table_name": "fact_equity_trade"
}
```

Example Artemis request:

```text
Describe fact_equity_trade, including every column and data type.
```

### 10.4 `sample_table`

Purpose:

```text
Return a small sample from one approved table.
```

Inputs:

| Input | Type | Required | Default | Maximum |
|---|---|---:|---:|---:|
| `table_name` | string | Yes | N/A | N/A |
| `limit` | integer | No | 10 | 100 |

Inspector input:

```json
{
  "table_name": "dim_stock",
  "limit": 5
}
```

Example Artemis request:

```text
Show five sample rows from dim_stock.
```

### 10.5 `search_equity_trades`

Purpose:

```text
Search enriched trade records joined to descriptive dimension tables.
```

Inputs:

| Input | Type | Required | Meaning |
|---|---|---:|---|
| `ticker` | string | No | Exact ticker match, case-insensitive |
| `date_from` | string | No | Inclusive lower date, `YYYY-MM-DD` |
| `date_to` | string | No | Inclusive upper date, `YYYY-MM-DD` |
| `side` | string | No | `B` for buy or `S` for sell |
| `account_code` | string | No | Exact account code |
| `trader_code` | string | No | Exact trader code |
| `minimum_gross_usd` | number | No | Minimum gross USD amount |
| `limit` | integer | No | Default 50, maximum 200 |

Example Inspector input:

```json
{
  "side": "B",
  "minimum_gross_usd": 1000000,
  "limit": 10
}
```

Returned records include:

- trade identifiers and dates;
- ticker;
- issuer;
- industry;
- sector;
- exchange;
- currency;
- account;
- trader;
- broker;
- buy/sell side;
- venue;
- order type;
- quantity;
- local price;
- local gross;
- USD gross;
- USD commission;
- USD net amount.

Example Artemis request:

```text
Find the ten largest buy trades with gross amount above one million USD.
```

### 10.6 `trade_summary_by_ticker`

Purpose:

```text
Aggregate trading activity by ticker.
```

Inputs:

| Input | Type | Required | Default | Maximum |
|---|---|---:|---:|---:|
| `date_from` | string | No | None | N/A |
| `date_to` | string | No | None | N/A |
| `limit` | integer | No | 25 | 100 |

Returns:

- ticker;
- trade count;
- total quantity;
- buy gross USD;
- sell gross USD;
- total gross USD;
- total commission USD;
- total net USD;
- average local price.

Example Inspector input:

```json
{
  "limit": 20
}
```

Example Artemis request:

```text
Return the twenty tickers with the largest total gross traded amount.
```

### 10.7 `execute_read_only_sql`

Purpose:

```text
Run one restricted read-only SQL statement.
```

Inputs:

| Input | Type | Required | Default | Maximum |
|---|---|---:|---:|---:|
| `query` | string | Yes | N/A | 20,000 characters |
| `max_rows` | integer | No | 100 | 500 |

Accepted leading commands:

```text
SELECT
WITH
EXPLAIN
```

Rejected:

```text
INSERT
UPDATE
DELETE
DROP
ALTER
CREATE
TRUNCATE
GRANT
REVOKE
```

Multiple statements are rejected.

Valid example:

```json
{
  "query": "SELECT buy_sell_flag, COUNT(*) AS trade_count FROM fact_equity_trade GROUP BY buy_sell_flag ORDER BY buy_sell_flag",
  "max_rows": 10
}
```

Example Artemis request:

```text
Use read-only SQL to count trades by buy/sell flag.
```

---

## 11. HTTP routes

### 11.1 `/`

Request:

```bash
curl -s https://equity-trades-mcp.onrender.com/
```

Expected shape:

```json
{
  "service": "Equity Trades SQL MCP",
  "status": "running",
  "transport": "streamable-http",
  "mcp_endpoint": "/mcp/",
  "authentication": "Bearer token required"
}
```

This route is public and contains no database credentials.

### 11.2 `/health`

Request:

```bash
curl -i https://equity-trades-mcp.onrender.com/health
```

Expected:

```text
HTTP/2 200
```

Body:

```json
{"status":"ok"}
```

This confirms the Python web service is running. It does not prove the database query path is working.

### 11.3 `/mcp/`

This is the protected MCP endpoint.

Without a valid bearer token:

```text
401 Unauthorized
```

With the correct bearer token and valid MCP request:

```text
200 OK
```

Using `/mcp` without the trailing slash can cause:

```text
307 Temporary Redirect
```

Use `/mcp/` consistently.

---

## 12. Bearer authentication middleware

The custom `BearerAuthMiddleware` protects:

```text
/mcp
/mcp/
anything beginning with /mcp/
```

It expects the complete header value:

```text
Bearer <MCP_API_KEY>
```

The comparison uses `secrets.compare_digest`.

The public `/` and `/health` routes are not protected.

The middleware returns:

```json
{"error":"unauthorized"}
```

with HTTP status:

```text
401
```

and header:

```text
WWW-Authenticate: Bearer
```

---

## 13. Security model

The server uses several independent controls.

### Layer 1: Bearer token

A caller must possess `MCP_API_KEY`.

### Layer 2: DNS-rebinding protection

The MCP transport accepts only configured hosts and origins.

### Layer 3: Approved-table allow-list

Table inspection and sampling are limited to known tables.

### Layer 4: SQL command validation

Only a single `SELECT`, `WITH`, or `EXPLAIN` statement is accepted by the generic SQL tool.

### Layer 5: Parameterized values

Tool inputs are passed as SQL parameters rather than concatenated into SQL values.

### Layer 6: Read-only transaction

Every database query begins with:

```sql
SET TRANSACTION READ ONLY;
```

### Layer 7: Read-only PostgreSQL role

The deployed application uses `mcp_reader`, not the owner role.

### Layer 8: Result limits

Rows are capped.

### Layer 9: Query timeout

Queries are limited to ten seconds.

No single layer should be removed merely because another layer exists.

---

# Part II — Complete setup from a new Mac

## 14. Assumed local path

This guide assumes the repository is stored at:

```text
/Users/vvillar/Software/Equity_Trades_SQL
```

The shell shortcut for that path is:

```text
~/Software/Equity_Trades_SQL
```

Before running project commands:

```bash
cd ~/Software/Equity_Trades_SQL
```

Confirm:

```bash
pwd
```

Expected:

```text
/Users/vvillar/Software/Equity_Trades_SQL
```

---

## 15. Install Homebrew

Check:

```bash
brew --version
```

If Homebrew is not installed, install it from the official Homebrew website and follow the displayed command that adds Homebrew to the shell path.

On Apple Silicon, Homebrew normally uses:

```text
/opt/homebrew
```

---

## 16. Install required command-line tools

Install Python, PostgreSQL client tools, GitHub CLI, and Node:

```bash
brew install python@3.11 libpq gh fnm
```

Add PostgreSQL command-line tools to the shell path:

```bash
grep -qxF 'export PATH="/opt/homebrew/opt/libpq/bin:$PATH"' ~/.zshrc ||
  echo 'export PATH="/opt/homebrew/opt/libpq/bin:$PATH"' >> ~/.zshrc
```

Reload the shell:

```bash
source ~/.zshrc
```

Verify:

```bash
python3 --version
psql --version
git --version
gh --version
```

Initialize `fnm` in the current shell:

```bash
eval "$(fnm env --use-on-cd)"
```

Install and select Node 22:

```bash
fnm install 22
fnm use 22
```

Verify:

```bash
node --version
npm --version
```

---

## 17. Clone the repository

Create the parent directory:

```bash
mkdir -p ~/Software
cd ~/Software
```

Clone:

```bash
git clone https://github.com/victor-villar-turintech/Equity_Trades_SQL.git
```

Enter the repository:

```bash
cd Equity_Trades_SQL
```

If it is already cloned:

```bash
cd ~/Software/Equity_Trades_SQL
git switch main
git pull origin main
```

---

## 18. Create the Python virtual environment

From repository root:

```bash
cd ~/Software/Equity_Trades_SQL
```

Create the environment:

```bash
python3.11 -m venv .venv
```

Activate it:

```bash
source .venv/bin/activate
```

The prompt should show:

```text
(.venv)
```

If it also shows `(base)`, Conda may be active. The prompt text itself is not decisive. Check the actual Python executable:

```bash
./.venv/bin/python -c "import sys; print(sys.executable)"
```

Expected:

```text
/Users/vvillar/Software/Equity_Trades_SQL/.venv/bin/python
```

Use the explicit interpreter in this guide:

```text
./.venv/bin/python
```

This avoids accidentally running Anaconda's Python or Anaconda's Uvicorn.

---

## 19. Install Python dependencies

Run:

```bash
./.venv/bin/python -m pip install --upgrade pip
```

Install the repository requirements:

```bash
./.venv/bin/python -m pip install -r requirements.txt
```

Verify:

```bash
./.venv/bin/python - <<'PY'
import mcp
import psycopg
import uvicorn

print("mcp import: OK")
print("psycopg:", psycopg.__version__)
print("uvicorn:", uvicorn.__version__)
PY
```

---

# Part III — Database preparation

## 20. Create a Neon project

Create a Neon PostgreSQL project.

Recommended names:

```text
Project: equity-trades-mcp
Database: neondb
```

Use a region close to the Render region.

The schema and data import should be performed using the Neon owner role and a direct connection string.

The deployed MCP server must later use a separate `mcp_reader` role and a pooled connection string.

---

## 21. Store the owner connection string temporarily

In Neon:

1. open the project;
2. click **Connect**;
3. select `neondb_owner`;
4. select `neondb`;
5. disable connection pooling;
6. copy the direct connection string.

In Terminal:

```bash
read -s "NEON_OWNER_URL?Paste the direct Neon owner connection string, then press Return: "
echo
export NEON_OWNER_URL
```

What happens:

1. Terminal displays the prompt.
2. Paste with `Command + V`.
3. Nothing appears because `-s` hides the value.
4. Press `Return`.
5. `echo` moves to a clean line.
6. `export` makes the variable available to `psql`.

Confirm it is populated without printing it:

```bash
if [[ -n "$NEON_OWNER_URL" ]]; then
  echo "NEON_OWNER_URL is set."
else
  echo "NEON_OWNER_URL is empty."
fi
```

Test:

```bash
psql "$NEON_OWNER_URL" \
  -v ON_ERROR_STOP=1 \
  -c "SELECT current_database(), current_user;"
```

Expected role:

```text
neondb_owner
```

---

## 22. Create the schema

From repository root:

```bash
cd ~/Software/Equity_Trades_SQL
```

Run:

```bash
psql "$NEON_OWNER_URL" \
  -v ON_ERROR_STOP=1 \
  -f db/schema.sql
```

List tables:

```bash
psql "$NEON_OWNER_URL" -c "\dt"
```

---

## 23. Load the CSV files

Load dimensions before the fact table.

Run these commands from repository root.

```bash
psql "$NEON_OWNER_URL" -v ON_ERROR_STOP=1 \
  -c "\copy dim_country FROM 'db/dim_country.csv' WITH (FORMAT csv, HEADER true)"
```

```bash
psql "$NEON_OWNER_URL" -v ON_ERROR_STOP=1 \
  -c "\copy dim_currency FROM 'db/dim_currency.csv' WITH (FORMAT csv, HEADER true)"
```

```bash
psql "$NEON_OWNER_URL" -v ON_ERROR_STOP=1 \
  -c "\copy dim_sector FROM 'db/dim_sector.csv' WITH (FORMAT csv, HEADER true)"
```

```bash
psql "$NEON_OWNER_URL" -v ON_ERROR_STOP=1 \
  -c "\copy dim_industry FROM 'db/dim_industry.csv' WITH (FORMAT csv, HEADER true)"
```

```bash
psql "$NEON_OWNER_URL" -v ON_ERROR_STOP=1 \
  -c "\copy dim_exchange FROM 'db/dim_exchange.csv' WITH (FORMAT csv, HEADER true)"
```

```bash
psql "$NEON_OWNER_URL" -v ON_ERROR_STOP=1 \
  -c "\copy dim_broker FROM 'db/dim_broker.csv' WITH (FORMAT csv, HEADER true)"
```

```bash
psql "$NEON_OWNER_URL" -v ON_ERROR_STOP=1 \
  -c "\copy dim_trader FROM 'db/dim_trader.csv' WITH (FORMAT csv, HEADER true)"
```

```bash
psql "$NEON_OWNER_URL" -v ON_ERROR_STOP=1 \
  -c "\copy dim_account FROM 'db/dim_account.csv' WITH (FORMAT csv, HEADER true)"
```

```bash
psql "$NEON_OWNER_URL" -v ON_ERROR_STOP=1 \
  -c "\copy dim_issuer FROM 'db/dim_issuer.csv' WITH (FORMAT csv, HEADER true)"
```

```bash
psql "$NEON_OWNER_URL" -v ON_ERROR_STOP=1 \
  -c "\copy dim_stock FROM 'db/dim_stock.csv' WITH (FORMAT csv, HEADER true)"
```

```bash
psql "$NEON_OWNER_URL" -v ON_ERROR_STOP=1 \
  -c "\copy fact_equity_trade FROM 'db/fact_equity_trade.csv' WITH (FORMAT csv, HEADER true)"
```

Update PostgreSQL statistics:

```bash
psql "$NEON_OWNER_URL" -v ON_ERROR_STOP=1 -c "ANALYZE;"
```

Validate the fact table:

```bash
psql "$NEON_OWNER_URL" \
  -P pager=off \
  -c "SELECT COUNT(*) AS trade_count FROM fact_equity_trade;"
```

Expected:

```text
100000
```

---

## 24. Create the read-only database role

Generate a password:

```bash
MCP_DB_PASSWORD="$(openssl rand -hex 24)"
printf '%s' "$MCP_DB_PASSWORD" | pbcopy
echo "Database password copied to clipboard."
```

Open an owner session:

```bash
psql "$NEON_OWNER_URL"
```

Run the following SQL. Replace `PASTE_DATABASE_PASSWORD` with the generated password.

```sql
CREATE ROLE mcp_reader
WITH LOGIN
PASSWORD 'PASTE_DATABASE_PASSWORD';

GRANT CONNECT ON DATABASE neondb TO mcp_reader;

GRANT USAGE ON SCHEMA public TO mcp_reader;

GRANT SELECT
ON ALL TABLES IN SCHEMA public
TO mcp_reader;

ALTER DEFAULT PRIVILEGES
IN SCHEMA public
GRANT SELECT ON TABLES TO mcp_reader;

ALTER ROLE mcp_reader
SET default_transaction_read_only = on;

ALTER ROLE mcp_reader
SET statement_timeout = '10s';

ALTER ROLE mcp_reader
SET search_path = public;
```

Exit:

```text
\q
```

Store the generated password securely.

Do not put it in Git.

---

## 25. Obtain the pooled reader URL

In Neon:

1. click **Connect**;
2. choose role `mcp_reader`;
3. choose database `neondb`;
4. enable **Connection pooling**;
5. copy the connection string.

Confirm the hostname contains:

```text
-pooler
```

In the Terminal that will start Uvicorn:

```bash
read -s "DATABASE_URL?Paste the pooled Neon mcp_reader connection string, then press Return: "
echo
export DATABASE_URL
```

Verify without showing the password:

```bash
printf '%s\n' "$DATABASE_URL" |
  sed 's#://[^@]*@#://***:***@#'
```

Inspect the embedded role safely:

```bash
./.venv/bin/python - <<'PY'
import os
from urllib.parse import urlsplit

url = os.environ.get("DATABASE_URL", "")
if not url:
    raise SystemExit("DATABASE_URL is empty")

parsed = urlsplit(url)

print("Role:", parsed.username)
print("Host:", parsed.hostname)
print("Database:", parsed.path.lstrip("/"))
PY
```

Expected role:

```text
mcp_reader
```

Expected host contains:

```text
-pooler
```

---

## 26. Test the reader role

Read test:

```bash
psql "$DATABASE_URL" \
  -v ON_ERROR_STOP=1 \
  -P pager=off \
  -c "
SELECT
    current_database() AS database_name,
    current_user AS connected_role,
    COUNT(*) AS trade_count
FROM fact_equity_trade
GROUP BY current_database(), current_user;
"
```

Expected:

```text
neondb | mcp_reader | 100000
```

Write-rejection test:

```bash
if psql "$DATABASE_URL" \
  -v ON_ERROR_STOP=1 \
  -c "DELETE FROM fact_equity_trade WHERE FALSE;"
then
  echo "WARNING: write access was accepted."
else
  echo "PASS: write access was rejected."
fi
```

Expected:

```text
PASS: write access was rejected.
```

---

# Part IV — Local MCP authentication

## 27. Create one stable local MCP key

From repository root:

```bash
cd ~/Software/Equity_Trades_SQL
```

Ensure the key file is ignored:

```bash
grep -qxF '.mcp_api_key' .gitignore ||
  echo '.mcp_api_key' >> .gitignore
```

Generate a key:

```bash
umask 077
openssl rand -hex 32 > .mcp_api_key
chmod 600 .mcp_api_key
```

Load it:

```bash
export MCP_API_KEY="$(tr -d '\n' < .mcp_api_key)"
```

Check only its length:

```bash
printf 'MCP_API_KEY length: %s\n' "${#MCP_API_KEY}"
```

Expected:

```text
64
```

Confirm Git ignores the file:

```bash
git check-ignore -v .mcp_api_key
```

Confirm it is not tracked:

```bash
git ls-files .mcp_api_key
```

Expected:

```text
No output
```

Never print the key in chat, logs, screenshots, README files, or Git commits.

---

## 28. Validate the Python application

Syntax check:

```bash
./.venv/bin/python -m py_compile mcp_server/app.py
```

No output means the syntax is valid.

Import check:

```bash
./.venv/bin/python - <<'PY'
from mcp_server.app import app
print("MCP application import: OK")
PY
```

This command requires both `DATABASE_URL` and `MCP_API_KEY` to be set.

---

## 29. Start the local server

In Terminal 1:

```bash
cd ~/Software/Equity_Trades_SQL
```

Load the MCP key:

```bash
export MCP_API_KEY="$(tr -d '\n' < .mcp_api_key)"
```

Set `DATABASE_URL` if it is not already set:

```bash
if [[ -z "$DATABASE_URL" ]]; then
  read -s "DATABASE_URL?Paste the pooled Neon mcp_reader connection string, then press Return: "
  echo
  export DATABASE_URL
fi
```

Confirm both are set:

```bash
for variable in DATABASE_URL MCP_API_KEY; do
  if [[ -n "${(P)variable}" ]]; then
    echo "$variable is set."
  else
    echo "$variable is missing."
  fi
done
```

Start:

```bash
./.venv/bin/python -m uvicorn mcp_server.app:app \
  --host 127.0.0.1 \
  --port 8000
```

Expected:

```text
Application startup complete.
Uvicorn running on http://127.0.0.1:8000
```

Leave Terminal 1 running.

---

## 30. Test from a second Terminal

Open Terminal 2.

Enter the repository:

```bash
cd ~/Software/Equity_Trades_SQL
```

Load the same MCP key:

```bash
export MCP_API_KEY="$(tr -d '\n' < .mcp_api_key)"
```

Terminal 2 does not need `DATABASE_URL`. The server process in Terminal 1 handles database access.

### Health test

```bash
curl -i http://127.0.0.1:8000/health
```

Expected:

```text
HTTP/1.1 200 OK
```

### Homepage test

```bash
curl -s http://127.0.0.1:8000/ |
  python3 -m json.tool
```

### Unauthenticated MCP test

```bash
curl -i http://127.0.0.1:8000/mcp/
```

Expected:

```text
401 Unauthorized
```

### Authenticated initialization test

```bash
curl -i \
  -X POST \
  http://127.0.0.1:8000/mcp/ \
  -H "Authorization: Bearer $MCP_API_KEY" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  --data '{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "initialize",
    "params": {
      "protocolVersion": "2025-06-18",
      "capabilities": {},
      "clientInfo": {
        "name": "local-curl-test",
        "version": "1.0"
      }
    }
  }'
```

Expected:

```text
HTTP/1.1 200 OK
```

A `%` shown immediately after the response body in Zsh is usually the shell indicating that the response did not end with a newline. It is not part of the JSON response.

---

# Part V — MCP Inspector

## 31. Start MCP Inspector

Use a current Inspector version:

```bash
npx -y @modelcontextprotocol/inspector@latest
```

A browser window should open.

The Inspector has two separate authentication concepts.

### 31.1 Proxy Session Token

The Inspector generates this token.

Purpose:

```text
Authenticate the browser UI to the local Inspector proxy.
```

Do not replace it with `MCP_API_KEY`.

### 31.2 Bearer Token

This is the project's `MCP_API_KEY`.

Purpose:

```text
Authenticate the Inspector proxy to the equity-trades MCP server.
```

These two tokens are not interchangeable.

## 32. Configure local Inspector

Use:

```text
Transport Type:
Streamable HTTP
```

```text
URL:
http://127.0.0.1:8000/mcp/
```

Expand **Authentication**.

Set:

```text
Header Name:
Authorization
```

Copy the raw MCP key:

```bash
cd ~/Software/Equity_Trades_SQL
printf '%s' "$(tr -d '\n' < .mcp_api_key)" | pbcopy
```

Paste into:

```text
Bearer Token
```

Paste only the raw 64-character value.

Do not paste:

```text
Bearer <value>
```

Do not paste the Proxy Session Token.

Click **Connect**.

Test:

1. `list_tables`
2. `database_overview`
3. `describe_table`
4. `sample_table`
5. `search_equity_trades`
6. `trade_summary_by_ticker`
7. `execute_read_only_sql`

---

# Part VI — Render deployment

## 33. Create the Render Web Service

In Render:

1. sign in;
2. choose **New**;
3. choose **Web Service**;
4. connect GitHub;
5. select `victor-villar-turintech/Equity_Trades_SQL`;
6. select branch `main`.

Settings:

```text
Name:
equity-trades-mcp
```

```text
Runtime:
Python 3
```

```text
Build Command:
pip install -r requirements.txt
```

```text
Start Command:
uvicorn mcp_server.app:app --host 0.0.0.0 --port $PORT
```

```text
Health Check Path:
/health
```

Use a region close to the Neon database region.

## 34. Set Render environment variables

### `DATABASE_URL`

Value:

```text
The pooled Neon URL for mcp_reader.
```

### `MCP_API_KEY`

Copy locally:

```bash
cd ~/Software/Equity_Trades_SQL
printf '%s' "$(tr -d '\n' < .mcp_api_key)" | pbcopy
```

Paste the raw value into Render.

Do not include `Bearer `.

### `PUBLIC_MCP_HOST`

Value:

```text
equity-trades-mcp.onrender.com
```

Save the environment variables.

Deploy the latest `main` commit.

---

## 35. Understand the Render URL

Base URL:

```text
https://equity-trades-mcp.onrender.com
```

Health:

```text
https://equity-trades-mcp.onrender.com/health
```

MCP:

```text
https://equity-trades-mcp.onrender.com/mcp/
```

The MCP URL includes the trailing slash.

---

## 36. Test the deployed service

In Terminal:

```bash
cd ~/Software/Equity_Trades_SQL
export MCP_API_KEY="$(tr -d '\n' < .mcp_api_key)"
export MCP_BASE_URL="https://equity-trades-mcp.onrender.com"
```

### Health

```bash
curl -i "$MCP_BASE_URL/health"
```

Expected:

```text
HTTP/2 200
```

### Homepage

```bash
curl -s "$MCP_BASE_URL/" |
  python3 -m json.tool
```

### Authentication enforcement

```bash
curl -i "$MCP_BASE_URL/mcp/"
```

Expected:

```text
HTTP/2 401
```

### Authenticated initialization

```bash
curl -i \
  -X POST \
  "$MCP_BASE_URL/mcp/" \
  -H "Authorization: Bearer $MCP_API_KEY" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  --data '{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "initialize",
    "params": {
      "protocolVersion": "2025-06-18",
      "capabilities": {},
      "clientInfo": {
        "name": "render-curl-test",
        "version": "1.0"
      }
    }
  }'
```

Expected:

```text
HTTP/2 200
```

---

## 37. Configure deployed Inspector

Start:

```bash
npx -y @modelcontextprotocol/inspector@latest
```

Use:

```text
Transport Type:
Streamable HTTP
```

```text
URL:
https://equity-trades-mcp.onrender.com/mcp/
```

Authentication:

```text
Header Name:
Authorization
```

```text
Bearer Token:
Raw MCP_API_KEY value
```

Leave the Inspector's Proxy Session Token unchanged.

---

# Part VII — Artemis configuration

## 38. Add the MCP server to Artemis

Open:

```text
Platform Settings
→ MCP Servers
→ Your MCP Configuration
```

Use:

```json
{
  "mcpServers": {
    "equity-trades-sql": {
      "url": "https://equity-trades-mcp.onrender.com/mcp/",
      "headers": {
        "Authorization": "Bearer YOUR_64_CHARACTER_MCP_API_KEY"
      }
    }
  }
}
```

Replace:

```text
YOUR_64_CHARACTER_MCP_API_KEY
```

with the raw key.

The final header value must contain:

```text
Bearer 
```

followed by the key.

Artemis needs:

- public MCP URL;
- bearer token.

Artemis does not need:

- Neon hostname;
- Neon role;
- Neon database password;
- `DATABASE_URL`;
- `PUBLIC_MCP_HOST`.

---

## 39. Artemis test prompts

```text
Use equity-trades-sql to list all database tables.
```

```text
Describe fact_equity_trade and explain every column.
```

```text
Show five sample rows from dim_stock.
```

```text
Give me a high-level overview of the equity-trades database.
```

```text
Return the twenty tickers with the largest total gross traded amount.
```

```text
Compare total buy gross and sell gross by ticker.
```

```text
Use read-only SQL to count trades by sector.
```

```text
Find the ten largest trades by gross amount in USD and include ticker,
issuer, sector, broker, trader, and account.
```

---

# Part VIII — Safe maintenance

## 40. Start the server after opening a new Terminal

Environment variables do not automatically carry into a new Terminal.

Use:

```bash
cd ~/Software/Equity_Trades_SQL
source .venv/bin/activate
export MCP_API_KEY="$(tr -d '\n' < .mcp_api_key)"
```

Set the database URL:

```bash
read -s "DATABASE_URL?Paste the pooled Neon mcp_reader connection string, then press Return: "
echo
export DATABASE_URL
```

Start:

```bash
./.venv/bin/python -m uvicorn mcp_server.app:app \
  --host 127.0.0.1 \
  --port 8000
```

---

## 41. Rotate the MCP API key

Rotate immediately if the key appears in:

- a screenshot;
- chat;
- Terminal output copied to another person;
- Git history;
- logs;
- documentation;
- a support ticket.

Generate a replacement:

```bash
cd ~/Software/Equity_Trades_SQL
umask 077
openssl rand -hex 32 > .mcp_api_key
chmod 600 .mcp_api_key
export MCP_API_KEY="$(tr -d '\n' < .mcp_api_key)"
```

Copy:

```bash
printf '%s' "$MCP_API_KEY" | pbcopy
```

Then:

1. update `MCP_API_KEY` in Render;
2. redeploy Render;
3. update the Artemis `Authorization` header;
4. update Inspector when testing;
5. retest with authenticated `curl`;
6. discard the old key.

---

## 42. Rotate the database password

If the `mcp_reader` password is exposed:

1. connect as `neondb_owner`;
2. assign a new password to `mcp_reader`;
3. copy a new pooled connection string;
4. update `DATABASE_URL` in Render;
5. redeploy;
6. update the local `DATABASE_URL`;
7. test the health and MCP tools.

Example SQL:

```sql
ALTER ROLE mcp_reader
PASSWORD 'NEW_RANDOM_PASSWORD';
```

The old connection string becomes invalid after the password changes.

---

## 43. Change the public hostname

When moving to a new Render service or custom domain:

1. identify the exact hostname;
2. set `PUBLIC_MCP_HOST` to that hostname;
3. do not include `https://`;
4. do not include `/mcp/`;
5. redeploy;
6. update Artemis and Inspector URLs;
7. test for `421 Invalid Host header`.

---

## 44. Add a new MCP tool

A new tool should:

1. have a clear name;
2. have a precise docstring;
3. use typed inputs;
4. validate every user-controlled value;
5. use parameterized SQL values;
6. enforce a result limit;
7. call `_run_query`;
8. remain read-only;
9. have an Inspector test;
10. have a README entry.

Skeleton:

```python
@mcp.tool()
def example_tool(limit: int = 10) -> dict[str, Any]:
    """
    Explain exactly what this tool returns.
    """
    result_limit = _bounded_limit(limit, maximum=100)

    return _run_query(
        """
        SELECT *
        FROM some_allowed_table
        LIMIT %s
        """,
        [result_limit],
        max_rows=result_limit,
    )
```

Do not interpolate arbitrary input directly into SQL.

Bad:

```python
statement = f"SELECT * FROM table WHERE value = '{user_value}'"
```

Better:

```python
statement = "SELECT * FROM table WHERE value = %s"
params = [user_value]
```

---

## 45. Add a new approved table

If a new table should be available to `describe_table` and `sample_table`:

1. create and populate the table;
2. grant `SELECT` to `mcp_reader`;
3. add its name to `ALLOWED_TABLES`;
4. validate with `describe_table`;
5. validate with `sample_table`;
6. update this README.

Grant:

```sql
GRANT SELECT ON new_table TO mcp_reader;
```

---

## 46. Validate code before committing

Syntax:

```bash
./.venv/bin/python -m py_compile mcp_server/app.py
```

Imports:

```bash
./.venv/bin/python - <<'PY'
from mcp_server.app import app
print("Import OK")
PY
```

Local health:

```bash
curl -i http://127.0.0.1:8000/health
```

Authenticated initialize:

```bash
curl -i \
  -X POST \
  http://127.0.0.1:8000/mcp/ \
  -H "Authorization: Bearer $MCP_API_KEY" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  --data '{
    "jsonrpc":"2.0",
    "id":1,
    "method":"initialize",
    "params":{
      "protocolVersion":"2025-06-18",
      "capabilities":{},
      "clientInfo":{"name":"pre-commit-test","version":"1.0"}
    }
  }'
```

---

## 47. Safe Git workflow

Update main:

```bash
git switch main
git pull origin main
```

Create a branch:

```bash
git switch -c feature/descriptive-branch-name
```

Inspect changes:

```bash
git status
git diff
```

Stage only intended files:

```bash
git add mcp_server/app.py mcp_server/README.md
```

Do not use `git add .` when secret files exist.

Inspect staged changes:

```bash
git diff --cached
```

Commit:

```bash
git commit -m "Describe the change"
```

Confirm a commit exists:

```bash
git log --oneline main..HEAD
```

Push:

```bash
git push -u origin feature/descriptive-branch-name
```

Create pull request:

```bash
gh pr create \
  --base main \
  --head feature/descriptive-branch-name \
  --title "Describe the change" \
  --body "Explain what changed and how it was tested."
```

Merge:

```bash
gh pr merge feature/descriptive-branch-name \
  --squash \
  --delete-branch
```

Return to main:

```bash
git switch main
git pull origin main
```

---

## 48. Confirm secrets are not committed

Check tracked files:

```bash
git ls-files .mcp_api_key .env
```

Expected:

```text
No output
```

Search current committed content for obvious secrets:

```bash
git grep -nE \
  'postgresql://[^[:space:]]+@|MCP_API_KEY=[0-9a-f]{64}' \
  HEAD -- ':!*.md' || true
```

If a secret was committed:

1. rotate it immediately;
2. remove it from tracked files;
3. do not assume deletion from the latest commit removes it from history;
4. assess whether repository history must be rewritten;
5. update every service that used the old secret.

---

# Part IX — Troubleshooting

## 49. `ModuleNotFoundError: No module named 'psycopg'`

Meaning:

```text
The Python process is using an environment where Psycopg is not installed.
```

Check:

```bash
command -v python
command -v uvicorn
```

If Uvicorn is:

```text
/opt/anaconda3/bin/uvicorn
```

do not run it directly.

Install requirements into `.venv`:

```bash
./.venv/bin/python -m pip install -r requirements.txt
```

Start with:

```bash
./.venv/bin/python -m uvicorn mcp_server.app:app \
  --host 127.0.0.1 \
  --port 8000
```

---

## 50. Prompt shows both `(.venv)` and `(base)`

This can be a Conda prompt issue.

The decisive check is:

```bash
./.venv/bin/python -c "import sys; print(sys.executable)"
```

Use the explicit `.venv` interpreter regardless of prompt decoration.

Optional:

```bash
conda config --set auto_activate_base false
```

Then restart the shell.

---

## 51. `DATABASE_URL environment variable is required`

Meaning:

```text
The Terminal starting Uvicorn does not have DATABASE_URL.
```

Fix:

```bash
read -s "DATABASE_URL?Paste the pooled Neon mcp_reader connection string, then press Return: "
echo
export DATABASE_URL
```

Restart Uvicorn.

---

## 52. `MCP_API_KEY environment variable is required`

Fix:

```bash
cd ~/Software/Equity_Trades_SQL
export MCP_API_KEY="$(tr -d '\n' < .mcp_api_key)"
```

Restart Uvicorn.

---

## 53. `401 Unauthorized`

Meaning:

```text
The request reached the server but the Authorization header did not
exactly match the key loaded when the server started.
```

Checklist:

1. use `/mcp/`;
2. load `.mcp_api_key` in the curl Terminal;
3. stop Uvicorn;
4. load the same `.mcp_api_key` in the server Terminal;
5. restart Uvicorn;
6. ensure Render has the same raw key;
7. ensure the header contains `Bearer ` followed by the raw key.

Compare hashes without revealing the key:

```bash
printf '%s' "$MCP_API_KEY" | shasum -a 256
```

Run in both Terminals. Hashes must match.

---

## 54. `307 Temporary Redirect`

Meaning:

```text
The request used /mcp instead of the mounted canonical path /mcp/.
```

Use:

```text
/mcp/
```

Do not rely on redirect-following for authenticated MCP clients.

---

## 55. `421 Invalid Host header`

Meaning:

```text
The MCP transport rejected the incoming Host header.
```

Check Render:

```text
PUBLIC_MCP_HOST=equity-trades-mcp.onrender.com
```

Do not include scheme or path.

Confirm the deployed code includes `TransportSecuritySettings`.

Redeploy the latest `main` commit.

---

## 56. `403 Invalid Origin header`

Meaning:

```text
A client sent an Origin value not present in allowed_origins.
```

Identify the exact origin and add only that trusted origin to the transport-security configuration.

Do not disable DNS-rebinding protection merely to remove the error.

---

## 57. `404 Not Found`

Likely causes:

- wrong hostname;
- wrong path;
- missing trailing slash;
- Render deployed an old service;
- route was changed.

Use:

```text
https://equity-trades-mcp.onrender.com/mcp/
```

---

## 58. `500 Internal Server Error`

Check Render logs.

Common causes:

- invalid `DATABASE_URL`;
- database password changed;
- wrong database;
- missing table;
- `mcp_reader` lacks `SELECT`;
- dependency import failure;
- code syntax or import error.

Test the database URL locally with `psql`.

---

## 59. `password authentication failed`

The password embedded in `DATABASE_URL` is wrong or obsolete.

Obtain a fresh pooled connection string for `mcp_reader` and update Render.

---

## 60. `permission denied for table`

Connect as owner and grant:

```sql
GRANT USAGE ON SCHEMA public TO mcp_reader;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO mcp_reader;
```

For future tables:

```sql
ALTER DEFAULT PRIVILEGES
IN SCHEMA public
GRANT SELECT ON TABLES TO mcp_reader;
```

---

## 61. Connected role is `neondb_owner`

Stop.

The application must use `mcp_reader`.

Obtain a pooled URL for `mcp_reader` and replace `DATABASE_URL`.

---

## 62. `relation fact_equity_trade does not exist`

Possible causes:

- schema was loaded into another database;
- `DATABASE_URL` points to the wrong database;
- schema import failed;
- `search_path` is wrong.

Check:

```bash
psql "$DATABASE_URL" -c "\dt"
```

---

## 63. Query timeout

The server intentionally limits statements to ten seconds.

Reduce the requested data:

- add a date filter;
- add a ticker filter;
- aggregate before returning rows;
- reduce `max_rows`;
- inspect the query with `EXPLAIN`;
- add appropriate indexes only when consistent with benchmark goals.

Do not remove the timeout merely to make an inefficient query finish.

---

## 64. Inspector uses the wrong token

Remember:

```text
Proxy Session Token:
Generated by Inspector for its own local proxy.
```

```text
Bearer Token:
The project's MCP_API_KEY.
```

The Bearer Token field must contain `.mcp_api_key`, not the Proxy Session Token.

---

## 65. Inspector works locally but not remotely

Check in this order:

1. Render `/health` returns 200.
2. Render homepage returns service JSON.
3. unauthenticated `/mcp/` returns 401.
4. authenticated `curl` returns 200.
5. Inspector URL has `/mcp/`.
6. Bearer Token is the raw MCP key.
7. Proxy Session Token remains unchanged.
8. Render has correct `PUBLIC_MCP_HOST`.

If authenticated `curl` works, the server is working. The remaining problem is Inspector configuration.

---

## 66. Render first request is slow

A free service may need to start after being idle.

Warm it:

```bash
curl -i https://equity-trades-mcp.onrender.com/health
```

Wait for 200, then connect Artemis or Inspector.

---

## 67. `gh pr create` says `No commits between main and branch`

Meaning:

```text
The branch was pushed before a new commit was created.
```

Fix:

```bash
git status
git add <intended-files>
git commit -m "Describe the change"
git push
```

Confirm:

```bash
git log --oneline main..HEAD
```

Then run `gh pr create` again.

---

## 68. `psql: command not found`

Add Homebrew `libpq` to the path:

```bash
grep -qxF 'export PATH="/opt/homebrew/opt/libpq/bin:$PATH"' ~/.zshrc ||
  echo 'export PATH="/opt/homebrew/opt/libpq/bin:$PATH"' >> ~/.zshrc

source ~/.zshrc
```

Verify:

```bash
psql --version
```

---

# Part X — Operational checklist

## 69. Before every deployment

- [ ] `mcp_server/app.py` compiles.
- [ ] Local health returns 200.
- [ ] Local unauthenticated MCP returns 401.
- [ ] Local authenticated MCP initialization returns 200.
- [ ] `DATABASE_URL` uses `mcp_reader`.
- [ ] `DATABASE_URL` hostname contains `-pooler`.
- [ ] `MCP_API_KEY` is not printed or committed.
- [ ] `.mcp_api_key` is ignored.
- [ ] `PUBLIC_MCP_HOST` matches the deployment hostname.
- [ ] No database owner credentials are in code.
- [ ] The branch contains a real commit.
- [ ] The pull request contains only intended files.

## 70. After every deployment

- [ ] Render logs show successful startup.
- [ ] `/health` returns 200.
- [ ] `/` returns correct MCP metadata.
- [ ] `/mcp/` without auth returns 401.
- [ ] `/mcp/` with auth returns 200.
- [ ] `list_tables` works.
- [ ] `database_overview` works.
- [ ] Inspector works.
- [ ] Artemis works.
- [ ] No secrets appear in logs.

---

# Part XI — Current limitations

The current server intentionally has limitations.

- Authentication uses one shared static bearer token.
- There are no separate users or per-user permissions.
- There is no OAuth flow.
- There is no rate limiter.
- There is no persistent application-level database pool; Neon handles external pooling.
- There is no audit database for tool calls.
- There are no write tools.
- There are no MCP resources or prompts defined; the server currently exposes tools.
- SQL execution is limited but still powerful.
- The dataset is synthetic.

For a higher-security production system, consider:

- OAuth-based MCP authentication;
- per-user authorization;
- short-lived tokens;
- rate limiting;
- structured audit logging;
- network restrictions;
- secret-manager integration;
- database row-level security;
- narrower SQL tools instead of general SQL execution;
- automated tests;
- monitoring and alerts.

---

# Part XII — Reference links

Repository:

```text
https://github.com/victor-villar-turintech/Equity_Trades_SQL
```

Official MCP Python SDK:

```text
https://github.com/modelcontextprotocol/python-sdk
```

Official MCP Inspector:

```text
https://github.com/modelcontextprotocol/inspector
```

MCP documentation:

```text
https://modelcontextprotocol.io/
```

Neon connection documentation:

```text
https://neon.com/docs/connect/connect-from-any-app
```

Neon connection pooling:

```text
https://neon.com/docs/connect/connection-pooling
```

Render Python deployment documentation:

```text
https://render.com/docs/deploy-fastapi
```

Psycopg documentation:

```text
https://www.psycopg.org/psycopg3/docs/
```

Uvicorn documentation:

```text
https://www.uvicorn.org/
```

PostgreSQL documentation:

```text
https://www.postgresql.org/docs/
```

---

## Final reminder

The three values below are different:

```text
DATABASE_URL
MCP_API_KEY
Inspector Proxy Session Token
```

They are used for different connections:

```text
DATABASE_URL:
Python MCP server → Neon PostgreSQL
```

```text
MCP_API_KEY:
Artemis or Inspector → Python MCP server
```

```text
Inspector Proxy Session Token:
Inspector browser → Inspector local proxy
```

Never substitute one for another.
