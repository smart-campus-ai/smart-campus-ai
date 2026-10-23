"""Minimal ULID generation, no third-party dependency.

The contract (common.json#/$defs/Id) requires a 26-character Crockford base32
string: a 48-bit millisecond timestamp followed by 80 bits of randomness. ULIDs
are lexicographically sortable by creation time, which is why they key sessions
and messages.
"""

from __future__ import annotations

import os
import time

# Crockford base32 alphabet (excludes I, L, O, U), matching the contract pattern.
_ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
_ENCODED_LEN = 26


def _encode(value: int, length: int) -> str:
    chars = []
    for _ in range(length):
        chars.append(_ALPHABET[value & 0x1F])
        value >>= 5
    return "".join(reversed(chars))


def new_ulid(timestamp_ms: int | None = None, randomness: bytes | None = None) -> str:
    """Return a new 26-character ULID.

    ``timestamp_ms`` and ``randomness`` are injectable so tests are deterministic.
    """

    if timestamp_ms is None:
        timestamp_ms = int(time.time() * 1000)
    if randomness is None:
        randomness = os.urandom(10)
    if len(randomness) != 10:
        raise ValueError("ULID randomness must be 10 bytes (80 bits)")

    time_part = _encode(timestamp_ms & ((1 << 48) - 1), 10)
    rand_int = int.from_bytes(randomness, "big")
    rand_part = _encode(rand_int, 16)
    return time_part + rand_part
