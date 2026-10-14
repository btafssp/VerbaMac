"""Train per-language zstd dictionaries and compress article HTML."""

from __future__ import annotations

from typing import Iterable, Optional

import zstandard as zstd


DEFAULT_DICT_SIZE = 32 * 1024  # 32 KiB — good for lexicon HTML
LEVEL = 3


def train_dictionary(samples: Iterable[bytes], dict_size: int = DEFAULT_DICT_SIZE) -> bytes:
    samples = [s for s in samples if s]
    if not samples:
        # Empty dict placeholder (zstd still accepts compress without dict)
        return b""
    # Need enough samples; duplicate if tiny seed set
    while len(samples) < 8:
        samples = list(samples) + list(samples)
    # zstd requires total sample size >= dict size roughly; pad if needed
    total = sum(len(s) for s in samples)
    if total < dict_size:
        # repeat samples to reach dict_size
        padded = list(samples)
        i = 0
        while sum(len(s) for s in padded) < dict_size * 2:
            padded.append(samples[i % len(samples)])
            i += 1
        samples = padded
    try:
        raw = zstd.train_dictionary(dict_size, samples, level=LEVEL)
        return raw.as_bytes()
    except Exception:
        # Fall back: smaller dict
        try:
            raw = zstd.train_dictionary(min(dict_size, 4096), samples[:64], level=LEVEL)
            return raw.as_bytes()
        except Exception:
            return b""


def compress(html: str, dict_bytes: Optional[bytes]) -> bytes:
    data = html.encode("utf-8")
    if dict_bytes:
        d = zstd.ZstdCompressionDict(dict_bytes)
        cctx = zstd.ZstdCompressor(level=LEVEL, dict_data=d)
    else:
        cctx = zstd.ZstdCompressor(level=LEVEL)
    return cctx.compress(data)


def decompress(blob: bytes, dict_bytes: Optional[bytes]) -> str:
    if dict_bytes:
        d = zstd.ZstdCompressionDict(dict_bytes)
        dctx = zstd.ZstdDecompressor(dict_data=d)
    else:
        dctx = zstd.ZstdDecompressor()
    return dctx.decompress(blob).decode("utf-8")
