"""
Unit tests for the segmented sieve implementation.
Run with:  python -m pytest tests/ -v
"""

import pytest
from app.primes import segmented_sieve


# ── Correctness tests ──────────────────────────────────────────────────────────

def test_primes_1_to_10():
    assert segmented_sieve(1, 10) == [2, 3, 5, 7]

def test_primes_0_to_0():
    assert segmented_sieve(0, 0) == []

def test_primes_0_to_1():
    assert segmented_sieve(0, 1) == []

def test_primes_0_to_2():
    assert segmented_sieve(0, 2) == [2]

def test_primes_2_to_2():
    assert segmented_sieve(2, 2) == [2]

def test_primes_3_to_3():
    assert segmented_sieve(3, 3) == [3]

def test_primes_4_to_6():
    assert segmented_sieve(4, 6) == [5]

def test_primes_14_to_16():
    """Range with no primes."""
    assert segmented_sieve(14, 16) == []

def test_primes_1_to_50():
    expected = [2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47]
    assert segmented_sieve(1, 50) == expected

def test_start_equals_end_prime():
    assert segmented_sieve(97, 97) == [97]

def test_start_equals_end_composite():
    assert segmented_sieve(100, 100) == []

def test_start_greater_than_end():
    assert segmented_sieve(10, 1) == []

def test_large_start():
    """Primes in a mid-range window (validated against known values)."""
    result = segmented_sieve(1_000_000, 1_000_100)
    assert result == [1_000_003, 1_000_033, 1_000_037, 1_000_039, 1_000_081, 1_000_099]

def test_count_primes_up_to_1000():
    """There are 168 primes up to 1000 (prime-counting function π(1000)=168)."""
    assert len(segmented_sieve(0, 1000)) == 168

def test_count_primes_up_to_100000():
    """π(100000) = 9592"""
    assert len(segmented_sieve(0, 100_000)) == 9592


# ── Edge-case / boundary tests ─────────────────────────────────────────────────

def test_start_zero():
    result = segmented_sieve(0, 10)
    assert result[0] == 2

def test_only_even_range():
    assert segmented_sieve(8, 10) == []

def test_two_is_only_even_prime():
    evens = set(range(4, 200, 2))
    primes = set(segmented_sieve(2, 200))
    assert not (evens & primes)  # no even number > 2 should be in the result
    assert 2 in primes

def test_results_are_sorted():
    result = segmented_sieve(0, 10_000)
    assert result == sorted(result)

def test_no_duplicates():
    result = segmented_sieve(0, 10_000)
    assert len(result) == len(set(result))
