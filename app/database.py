"""
Database layer — PostgreSQL via asyncpg.

Table: executions
-----------------
id           SERIAL PRIMARY KEY
range_start  INTEGER NOT NULL        -- user-supplied lower bound
range_end    INTEGER NOT NULL        -- user-supplied upper bound
prime_count  INTEGER NOT NULL        -- number of primes found
elapsed_ms   NUMERIC(10,3) NOT NULL  -- wall-clock time for computation
executed_at  TIMESTAMPTZ NOT NULL    -- UTC timestamp of the request
"""

import os
from datetime import datetime

import asyncpg

_pool: asyncpg.Pool | None = None

DATABASE_URL = os.environ.get(
    "DATABASE_URL",
    "postgresql://prime_user:prime_pass@db:5432/prime_db",
)

CREATE_TABLE_SQL = """
CREATE TABLE IF NOT EXISTS executions (
    id           SERIAL PRIMARY KEY,
    range_start  INTEGER        NOT NULL,
    range_end    INTEGER        NOT NULL,
    prime_count  INTEGER        NOT NULL,
    elapsed_ms   NUMERIC(10, 3) NOT NULL,
    executed_at  TIMESTAMPTZ    NOT NULL
);
"""


async def _get_pool() -> asyncpg.Pool:
    global _pool
    if _pool is None:
        _pool = await asyncpg.create_pool(DATABASE_URL, min_size=2, max_size=10)
    return _pool


async def init_db() -> None:
    """Create tables if they do not exist yet."""
    pool = await _get_pool()
    async with pool.acquire() as conn:
        await conn.execute(CREATE_TABLE_SQL)


async def save_execution(
    *,
    range_start: int,
    range_end: int,
    prime_count: int,
    elapsed_ms: float,
    executed_at: datetime,
) -> None:
    pool = await _get_pool()
    async with pool.acquire() as conn:
        await conn.execute(
            """
            INSERT INTO executions (range_start, range_end, prime_count, elapsed_ms, executed_at)
            VALUES ($1, $2, $3, $4, $5)
            """,
            range_start,
            range_end,
            prime_count,
            elapsed_ms,
            executed_at,
        )


async def get_executions(*, limit: int = 20, offset: int = 0) -> list[dict]:
    pool = await _get_pool()
    async with pool.acquire() as conn:
        rows = await conn.fetch(
            """
            SELECT id, range_start, range_end, prime_count, elapsed_ms, executed_at
            FROM   executions
            ORDER  BY executed_at DESC
            LIMIT  $1 OFFSET $2
            """,
            limit,
            offset,
        )
    return [dict(r) for r in rows]
