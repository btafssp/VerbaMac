"""Lemma normalization matching MorphPreprocess / SPEC."""

from __future__ import annotations

import re
import unicodedata


_COMBINING = re.compile(r"[\u0300-\u036f]")


def strip_combining(s: str) -> str:
    nfd = unicodedata.normalize("NFD", s)
    return _COMBINING.sub("", nfd)


def latin_lemma_norm(raw: str) -> str:
    s = raw.strip().lower()
    # L&S writes y-breve as Cyrillic ў (U+045E = у + breve): key it as Latin y.
    s = unicodedata.normalize("NFD", s).replace("\u0443", "y")
    s = s.replace("v", "u").replace("j", "i")
    s = strip_combining(s)
    s = re.sub(r"[^a-z]", "", s)
    return s


def greek_lemma_norm(raw: str) -> str:
    """Accent-stripped Greek base (Unicode). Keeps final sigma ς like MorphPreprocess."""
    s = unicodedata.normalize("NFC", raw.strip()).lower()
    s = strip_combining(s)
    out = []
    for ch in s:
        if "\u0370" <= ch <= "\u03ff" or "\u1f00" <= ch <= "\u1fff":
            out.append(ch)
    return "".join(out)


def looks_greek(s: str) -> bool:
    return any(
        ("\u0370" <= c <= "\u03ff") or ("\u1f00" <= c <= "\u1fff") for c in s
    )
