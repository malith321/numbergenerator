from fastapi import FastAPI, HTTPException, Query
from fastapi.responses import JSONResponse
from contextlib import asynccontextmanager
from datetime import datetime, timezone
import time

from .database import init_db, save_execution, get_executions
from .primes import segmented_sieve

@asynccontextmanager
async def lifespan(app: FastAPI):
    await init_db()
    yield

app = FastAPI(
    title="Prime Number Generator Service",
    description="Generates prime numbers in a given range using the Segmented Sieve of Eratosthenes.",
    version="1.0.0",
    lifespan=lifespan,
)


@app.get("/primes", summary="Get prime numbers in a range")
async def get_primes(
    start: int = Query(..., ge=0, description="Start of the range (inclusive)"),
    end: int = Query(..., ge=0, description="End of the range (inclusive)"),
):
    """
    Returns all prime numbers between `start` and `end` (inclusive).
    Records the execution in the database.
    """
    if start > end:
        raise HTTPException(
            status_code=400,
            detail=f"'start' ({start}) must be less than or equal to 'end' ({end}).",
        )

    if end > 10_000_000:
        raise HTTPException(
            status_code=400,
            detail="Range ceiling is capped at 10,000,000 for this service.",
        )

    t0 = time.perf_counter()
    primes = segmented_sieve(start, end)
    elapsed_ms = round((time.perf_counter() - t0) * 1000, 3)

    await save_execution(
        range_start=start,
        range_end=end,
        prime_count=len(primes),
        elapsed_ms=elapsed_ms,
        executed_at=datetime.now(timezone.utc),
    )

    return {
        "range": {"start": start, "end": end},
        "prime_count": len(primes),
        "primes": primes,
        "elapsed_ms": elapsed_ms,
    }


@app.get("/executions", summary="List past executions")
async def list_executions(
    limit: int = Query(20, ge=1, le=100, description="Number of records to return"),
    offset: int = Query(0, ge=0, description="Offset for pagination"),
):
    """
    Returns a paginated list of all past prime-generation executions.
    """
    rows = await get_executions(limit=limit, offset=offset)
    return {"executions": rows, "limit": limit, "offset": offset}


@app.get("/health", summary="Health check")
async def health():
    return {"status": "ok"}
