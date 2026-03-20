"""
Prime number generation using the Segmented Sieve of Eratosthenes.

Why segmented?
--------------
A classic sieve allocates a boolean array of size `end`, which becomes
impractical for large upper bounds (e.g., 10 million entries). The segmented
variant splits the range into fixed-size segments and sieves each one using
only the "small" primes found up to sqrt(end). This keeps peak memory usage
proportional to sqrt(end) rather than end itself, while maintaining the same
O(n log log n) time complexity.

Algorithm outline
-----------------
1. Find all small primes up to floor(sqrt(end)) using a standard sieve.
2. Divide [max(start, 2) .. end] into segments of size SEGMENT_SIZE.
3. For each segment [lo .. hi]:
   a. Initialise a boolean array `is_prime[0..hi-lo]` to True.
   b. For each small prime p, mark its multiples that fall in [lo..hi].
   c. Collect indices still marked True — they are prime.
4. Handle edge case: if start <= 2, prepend 2 (the only even prime).
"""

import math

SEGMENT_SIZE = 32_768  # ~L1 cache-friendly (32 KiB of bools)


def _simple_sieve(limit: int) -> list[int]:
    """Return all primes up to `limit` using the classic sieve."""
    if limit < 2:
        return []
    is_prime = bytearray([1]) * (limit + 1)
    is_prime[0] = is_prime[1] = 0
    for i in range(2, math.isqrt(limit) + 1):
        if is_prime[i]:
            is_prime[i * i :: i] = bytearray(len(is_prime[i * i :: i]))
    return [i for i, v in enumerate(is_prime) if v]


def segmented_sieve(start: int, end: int) -> list[int]:
    """
    Return a sorted list of all primes in the closed interval [start, end].

    Parameters
    ----------
    start : int  Lower bound (>= 0).
    end   : int  Upper bound (<= 10_000_000 as enforced by the API layer).
    """
    if end < 2 or start > end:
        return []

    # --- Phase 1: small primes up to sqrt(end) ---
    sqrt_end = math.isqrt(end)
    small_primes = _simple_sieve(sqrt_end)

    results: list[int] = []

    # Include 2 if the range covers it (handled separately to let the inner
    # loop focus on odd numbers only — a simple but effective optimisation).
    if start <= 2:
        results.append(2)

    # Clamp the effective lower bound to the first odd number >= max(start, 3)
    lo = max(start, 3)
    if lo % 2 == 0:
        lo += 1  # bump to next odd

    # --- Phase 2: sieve each segment ---
    for seg_lo in range(lo, end + 1, SEGMENT_SIZE * 2):
        seg_hi = min(seg_lo + SEGMENT_SIZE * 2 - 2, end)
        size = (seg_hi - seg_lo) // 2 + 1  # number of odd candidates

        # is_prime[k] represents the number  seg_lo + 2*k
        is_prime = bytearray([1]) * size

        for p in small_primes:
            if p < 3:
                continue  # skip 2; we only track odd numbers in this array

            # Find the smallest multiple of p that is >= seg_lo and odd.
            # Start from p*p when possible (earlier multiples already sieved).
            first = max(p * p, seg_lo + ((p - seg_lo % p) % p))
            if first % 2 == 0:
                first += p  # ensure it's odd

            # Walk through multiples of p with step 2p (skipping even ones)
            for composite in range(first, seg_hi + 1, 2 * p):
                idx = (composite - seg_lo) // 2
                if 0 <= idx < size:
                    is_prime[idx] = 0

        for k, flag in enumerate(is_prime):
            if flag:
                results.append(seg_lo + 2 * k)

    return results
