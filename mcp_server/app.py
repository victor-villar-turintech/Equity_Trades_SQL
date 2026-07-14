from __future__ import annotations

import contextlib
import os
import re
import secrets
from datetime import date, datetime
from decimal import Decimal
from typing import Any, Sequence

import psycopg
from mcp.server.fastmcp import FastMCP
from mcp.server.transport_security import TransportSecuritySettings
from psycopg import sql
from psycopg.rows import dict_row
from starlette.applications import Starlette
from starlette.responses import JSONResponse
from starlette.routing import Mount, Route
from starlette.types import ASGIApp, Receive, Scope, Send


DATABASE_URL = os.getenv("DATABASE_URL", "").strip()
MCP_API_KEY = os.getenv("MCP_API_KEY", "").strip()

PUBLIC_MCP_HOST = os.getenv(
    "PUBLIC_MCP_HOST",
    "equity-trades-mcp.onrender.com",
).strip()

if not DATABASE_URL:
    raise RuntimeError("DATABASE_URL environment variable is required.")

if not MCP_API_KEY:
    raise RuntimeError("MCP_API_KEY environment variable is required.")


MAX_RESULT_ROWS = 500
MAX_SQL_LENGTH = 20_000

ALLOWED_TABLES = {
    "dim_account",
    "dim_broker",
    "dim_country",
    "dim_currency",
    "dim_exchange",
    "dim_industry",
    "dim_issuer",
    "dim_sector",
    "dim_stock",
    "dim_trader",
    "fact_equity_trade",
}


mcp = FastMCP(
    name="Equity Trades SQL",
    instructions=(
        "Read-only access to a synthetic equity-trading PostgreSQL database. "
        "The database contains dimension tables and a 100,000-row "
        "fact_equity_trade table. Never attempt to modify database data."
    ),
    stateless_http=True,
    json_response=True,
    streamable_http_path="/",
    transport_security=TransportSecuritySettings(
        enable_dns_rebinding_protection=True,
        allowed_hosts=[
            PUBLIC_MCP_HOST,
            f"{PUBLIC_MCP_HOST}:*",
            "localhost:*",
            "127.0.0.1:*",
        ],
        allowed_origins=[
            f"https://{PUBLIC_MCP_HOST}",
            "http://localhost:*",
            "http://127.0.0.1:*",
        ],
    ),
)


def _jsonable(value: Any) -> Any:
    """Convert PostgreSQL/Python values into JSON-compatible values."""
    if isinstance(value, Decimal):
        return str(value)

    if isinstance(value, (date, datetime)):
        return value.isoformat()

    if isinstance(value, bytes):
        return value.decode("utf-8", errors="replace")

    if isinstance(value, dict):
        return {str(key): _jsonable(item) for key, item in value.items()}

    if isinstance(value, (list, tuple)):
        return [_jsonable(item) for item in value]

    return value


def _bounded_limit(limit: int, maximum: int = MAX_RESULT_ROWS) -> int:
    """Constrain caller-controlled result limits."""
    return max(1, min(int(limit), maximum))


def _run_query(
    statement: Any,
    params: Sequence[Any] | None = None,
    max_rows: int = 100,
) -> dict[str, Any]:
    """
    Execute one read-only query with a statement timeout and row limit.

    A new short-lived connection is used for each tool invocation. Neon
    performs the external connection pooling.
    """
    row_limit = _bounded_limit(max_rows)

    try:
        with psycopg.connect(
            DATABASE_URL,
            row_factory=dict_row,
            prepare_threshold=None,
            connect_timeout=10,
        ) as connection:
            with connection.cursor() as cursor:
                cursor.execute("SET TRANSACTION READ ONLY")
                cursor.execute("SET LOCAL statement_timeout = '10s'")

                if params is None:
                    cursor.execute(statement)
                else:
                    cursor.execute(statement, params)

                if cursor.description is None:
                    return {
                        "columns": [],
                        "rows": [],
                        "row_count": 0,
                        "truncated": False,
                    }

                rows = cursor.fetchmany(row_limit + 1)
                truncated = len(rows) > row_limit
                rows = rows[:row_limit]

                columns = [column.name for column in cursor.description]

                return {
                    "columns": columns,
                    "rows": _jsonable(rows),
                    "row_count": len(rows),
                    "truncated": truncated,
                }

    except psycopg.Error as exc:
        raise RuntimeError(
            f"Database query failed: {exc.__class__.__name__}: {exc}"
        ) from exc


def _validate_table(table_name: str) -> str:
    normalized = table_name.strip().lower()

    if normalized not in ALLOWED_TABLES:
        valid = ", ".join(sorted(ALLOWED_TABLES))
        raise ValueError(f"Unknown table '{table_name}'. Valid tables: {valid}")

    return normalized


def _validate_read_only_sql(query: str) -> str:
    if not query or not query.strip():
        raise ValueError("SQL query cannot be empty.")

    if len(query) > MAX_SQL_LENGTH:
        raise ValueError(
            f"SQL query exceeds the {MAX_SQL_LENGTH}-character limit."
        )

    # Remove SQL comments before checking the leading command and semicolons.
    normalized = re.sub(r"/\*.*?\*/", " ", query, flags=re.DOTALL)
    normalized = re.sub(r"--[^\n]*", " ", normalized)
    normalized = normalized.strip()

    if normalized.endswith(";"):
        normalized = normalized[:-1].rstrip()

    if ";" in normalized:
        raise ValueError("Only one SQL statement is allowed per invocation.")

    first_keyword = normalized.split(None, 1)[0].upper()

    if first_keyword not in {"SELECT", "WITH", "EXPLAIN"}:
        raise ValueError(
            "Only SELECT, WITH, and EXPLAIN statements are allowed."
        )

    return normalized


@mcp.tool()
def database_overview() -> dict[str, Any]:
    """
    Return overall database statistics, including trade count, date range,
    number of stocks, and total gross and commission amounts.
    """
    return _run_query(
        """
        SELECT
            COUNT(*) AS trade_count,
            MIN(trade_date) AS earliest_trade_date,
            MAX(trade_date) AS latest_trade_date,
            COUNT(DISTINCT stock_key) AS distinct_stocks,
            COUNT(DISTINCT account_key) AS distinct_accounts,
            COUNT(DISTINCT trader_key) AS distinct_traders,
            SUM(gross_amount_usd) AS total_gross_amount_usd,
            SUM(commission_usd) AS total_commission_usd
        FROM fact_equity_trade
        """,
        max_rows=1,
    )


@mcp.tool()
def list_tables() -> dict[str, Any]:
    """
    List the available public database tables.
    """
    return _run_query(
        """
        SELECT
            table_name,
            table_type
        FROM information_schema.tables
        WHERE table_schema = 'public'
          AND table_type = 'BASE TABLE'
        ORDER BY table_name
        """,
        max_rows=100,
    )


@mcp.tool()
def describe_table(table_name: str) -> dict[str, Any]:
    """
    Return the columns, PostgreSQL data types, nullability, and row count
    for one allowed table.
    """
    table = _validate_table(table_name)

    columns = _run_query(
        """
        SELECT
            ordinal_position,
            column_name,
            data_type,
            udt_name,
            is_nullable,
            character_maximum_length,
            numeric_precision,
            numeric_scale
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = %s
        ORDER BY ordinal_position
        """,
        [table],
        max_rows=100,
    )

    count_statement = sql.SQL(
        "SELECT COUNT(*) AS row_count FROM {}"
    ).format(sql.Identifier(table))

    row_count = _run_query(count_statement, max_rows=1)

    return {
        "table_name": table,
        "columns": columns,
        "row_count": row_count,
    }


@mcp.tool()
def sample_table(table_name: str, limit: int = 10) -> dict[str, Any]:
    """
    Return a small sample from an allowed table. The maximum limit is 100.
    """
    table = _validate_table(table_name)
    result_limit = _bounded_limit(limit, maximum=100)

    statement = sql.SQL(
        "SELECT * FROM {} LIMIT %s"
    ).format(sql.Identifier(table))

    return _run_query(
        statement,
        [result_limit],
        max_rows=result_limit,
    )


@mcp.tool()
def search_equity_trades(
    ticker: str | None = None,
    date_from: str | None = None,
    date_to: str | None = None,
    side: str | None = None,
    account_code: str | None = None,
    trader_code: str | None = None,
    minimum_gross_usd: float | None = None,
    limit: int = 50,
) -> dict[str, Any]:
    """
    Search enriched equity trades.

    Dates must use YYYY-MM-DD. Side must be B or S. Results are ordered
    from most recent to oldest, with a maximum limit of 200.
    """
    result_limit = _bounded_limit(limit, maximum=200)

    conditions: list[str] = []
    params: list[Any] = []

    if ticker:
        conditions.append("UPPER(s.ticker) = UPPER(%s)")
        params.append(ticker.strip())

    if date_from:
        conditions.append("f.trade_date >= %s::date")
        params.append(date_from)

    if date_to:
        conditions.append("f.trade_date <= %s::date")
        params.append(date_to)

    if side:
        normalized_side = side.strip().upper()

        if normalized_side not in {"B", "S"}:
            raise ValueError("side must be either 'B' or 'S'.")

        conditions.append("f.buy_sell_flag = %s")
        params.append(normalized_side)

    if account_code:
        conditions.append("UPPER(a.account_code) = UPPER(%s)")
        params.append(account_code.strip())

    if trader_code:
        conditions.append("UPPER(t.trader_code) = UPPER(%s)")
        params.append(trader_code.strip())

    if minimum_gross_usd is not None:
        conditions.append("f.gross_amount_usd >= %s")
        params.append(minimum_gross_usd)

    where_clause = " AND ".join(conditions) if conditions else "TRUE"
    params.append(result_limit)

    statement = f"""
        SELECT
            f.trade_id,
            f.trade_timestamp,
            f.trade_date,
            f.settlement_date,
            s.ticker,
            i.issuer_name,
            ind.industry_name,
            sec.sector_name,
            e.exchange_name,
            c.currency_code,
            a.account_code,
            t.trader_code,
            t.trader_name,
            b.broker_name,
            f.buy_sell_flag,
            f.execution_venue,
            f.order_type,
            f.quantity,
            f.price_local,
            f.gross_amount_local,
            f.gross_amount_usd,
            f.commission_usd,
            f.net_amount_usd
        FROM fact_equity_trade AS f
        JOIN dim_stock AS s
          ON s.stock_key = f.stock_key
        JOIN dim_issuer AS i
          ON i.issuer_key = f.issuer_key
        JOIN dim_industry AS ind
          ON ind.industry_key = f.industry_key
        JOIN dim_sector AS sec
          ON sec.sector_key = f.sector_key
        JOIN dim_exchange AS e
          ON e.exchange_key = f.exchange_key
        JOIN dim_currency AS c
          ON c.currency_key = f.currency_key
        JOIN dim_account AS a
          ON a.account_key = f.account_key
        JOIN dim_trader AS t
          ON t.trader_key = f.trader_key
        JOIN dim_broker AS b
          ON b.broker_key = f.broker_key
        WHERE {where_clause}
        ORDER BY f.trade_timestamp DESC, f.trade_id
        LIMIT %s
    """

    return _run_query(
        statement,
        params,
        max_rows=result_limit,
    )


@mcp.tool()
def trade_summary_by_ticker(
    date_from: str | None = None,
    date_to: str | None = None,
    limit: int = 25,
) -> dict[str, Any]:
    """
    Aggregate trades by ticker, including counts, quantities, buy/sell gross
    values, commissions, and net amounts. Dates use YYYY-MM-DD.
    """
    result_limit = _bounded_limit(limit, maximum=100)

    conditions: list[str] = []
    params: list[Any] = []

    if date_from:
        conditions.append("f.trade_date >= %s::date")
        params.append(date_from)

    if date_to:
        conditions.append("f.trade_date <= %s::date")
        params.append(date_to)

    where_clause = " AND ".join(conditions) if conditions else "TRUE"
    params.append(result_limit)

    statement = f"""
        SELECT
            s.ticker,
            COUNT(*) AS trade_count,
            SUM(f.quantity) AS total_quantity,
            SUM(
                CASE
                    WHEN f.buy_sell_flag = 'B'
                    THEN f.gross_amount_usd
                    ELSE 0
                END
            ) AS buy_gross_usd,
            SUM(
                CASE
                    WHEN f.buy_sell_flag = 'S'
                    THEN f.gross_amount_usd
                    ELSE 0
                END
            ) AS sell_gross_usd,
            SUM(f.gross_amount_usd) AS total_gross_usd,
            SUM(f.commission_usd) AS total_commission_usd,
            SUM(f.net_amount_usd) AS total_net_usd,
            AVG(f.price_local) AS average_local_price
        FROM fact_equity_trade AS f
        JOIN dim_stock AS s
          ON s.stock_key = f.stock_key
        WHERE {where_clause}
        GROUP BY s.ticker
        ORDER BY total_gross_usd DESC
        LIMIT %s
    """

    return _run_query(
        statement,
        params,
        max_rows=result_limit,
    )


@mcp.tool()
def execute_read_only_sql(
    query: str,
    max_rows: int = 100,
) -> dict[str, Any]:
    """
    Execute one read-only SELECT, WITH, or EXPLAIN query.

    Multiple SQL statements and modification commands are rejected.
    Results are limited to a maximum of 500 rows and execution is subject
    to a 10-second database timeout.
    """
    validated_query = _validate_read_only_sql(query)
    result_limit = _bounded_limit(max_rows)

    return _run_query(
        validated_query,
        max_rows=result_limit,
    )


async def homepage(_: Any) -> JSONResponse:
    return JSONResponse(
        {
            "service": "Equity Trades SQL MCP",
            "status": "running",
            "transport": "streamable-http",
            "mcp_endpoint": "/mcp/",
            "authentication": "Bearer token required",
        }
    )


async def health(_: Any) -> JSONResponse:
    return JSONResponse({"status": "ok"})


@contextlib.asynccontextmanager
async def lifespan(_: Starlette):
    async with mcp.session_manager.run():
        yield


starlette_app = Starlette(
    routes=[
        Route("/", homepage, methods=["GET"]),
        Route("/health", health, methods=["GET"]),
        Mount("/mcp", app=mcp.streamable_http_app()),
    ],
    lifespan=lifespan,
)


class BearerAuthMiddleware:
    """Protect only the MCP endpoint with a static bearer token."""

    def __init__(self, app: ASGIApp, api_key: str) -> None:
        self.app = app
        self.expected_header = f"Bearer {api_key}"

    async def __call__(
        self,
        scope: Scope,
        receive: Receive,
        send: Send,
    ) -> None:
        if scope["type"] == "http":
            path = scope.get("path", "")

            if path == "/mcp" or path.startswith("/mcp/"):
                headers = dict(scope.get("headers", []))
                supplied = headers.get(b"authorization", b"").decode(
                    "utf-8",
                    errors="replace",
                )

                if not secrets.compare_digest(
                    supplied,
                    self.expected_header,
                ):
                    response = JSONResponse(
                        {"error": "unauthorized"},
                        status_code=401,
                        headers={"WWW-Authenticate": "Bearer"},
                    )
                    await response(scope, receive, send)
                    return

        await self.app(scope, receive, send)


app: ASGIApp = BearerAuthMiddleware(
    starlette_app,
    MCP_API_KEY,
)
