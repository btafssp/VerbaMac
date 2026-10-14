"""Minimal Perseus Greek Beta Code → Unicode (importer-side)."""

from __future__ import annotations

# Base lowercase Beta → Greek
_BASE = {
    "a": "α", "b": "β", "g": "γ", "d": "δ", "e": "ε", "z": "ζ",
    "h": "η", "q": "θ", "i": "ι", "k": "κ", "l": "λ", "m": "μ",
    "n": "ν", "c": "ξ", "o": "ο", "p": "π", "r": "ρ", "s": "σ",
    "t": "τ", "u": "υ", "f": "φ", "x": "χ", "y": "ψ", "w": "ω",
    "v": "ϝ",
}

# Common precomposed with breathing / accent (subset; fallback to base+combining)
# Diacritic chars in Beta: ) smooth ( rough / acute \ grave = circumflex | iota + diaeresis

_COMB = {
    ")": "\u0313",  # smooth
    "(": "\u0314",  # rough
    "/": "\u0301",  # acute
    "\\": "\u0300",  # grave
    "=": "\u0342",  # circumflex (perispomeni)
    "|": "\u0345",  # iota subscript
    "+": "\u0308",  # diaeresis
    "_": "\u0304",  # macron (Perseus LSJ quantity)
    "^": "\u0306",  # breve (Perseus LSJ quantity)
}

_DIAC_CHARS = set("()/=\\+|_^")
_BREATHABLE = set("aehiouwr")


def _apply_sigma(letters: list[str]) -> str:
    """Word-final σ → ς."""
    out = []
    for i, ch in enumerate(letters):
        if ch == "σ":
            nxt = letters[i + 1][:1] if i + 1 < len(letters) else None
            if nxt is None or not ("\u0370" <= nxt <= "\u03ff"):
                out.append("ς")
            else:
                out.append("σ")
        else:
            out.append(ch)
    return "".join(out)


def beta_to_unicode(beta: str) -> str:
    """Convert Perseus Beta Code to Unicode Greek. Non-beta passes through."""
    if not beta:
        return beta
    # Already Greek?
    if any("\u0370" <= c <= "\u03ff" or "\u1f00" <= c <= "\u1fff" for c in beta):
        return beta

    chars: list[str] = []
    i = 0
    n = len(beta)
    while i < n:
        c = beta[i]
        if c == "*":
            i += 1
            # Perseus capitals put breathing/accent *before* the letter: *)a/
            diacs = []
            while i < n and beta[i] in _DIAC_CHARS:
                diacs.append(beta[i])
                i += 1
            if i >= n:
                break
            base = beta[i].lower()
            i += 1
            while i < n and beta[i] in _DIAC_CHARS:
                diacs.append(beta[i])
                i += 1
            letter = _BASE.get(base, base)
            # capital
            letter = letter.upper() if letter.isalpha() else letter
            for d in diacs:
                letter += _COMB.get(d, "")
            chars.append(letter)
            continue

        low = c.lower()
        if low in _BASE:
            i += 1
            diacs = []
            while i < n and beta[i] in _DIAC_CHARS:
                # Breathings only follow vowels/rho: "(v)" in LSJ etymologies is a
                # parenthesised digamma, not ϝ + smooth breathing.
                if beta[i] in "()" and low not in _BREATHABLE:
                    break
                diacs.append(beta[i])
                i += 1
            letter = _BASE[low]
            for d in diacs:
                letter += _COMB.get(d, "")
            chars.append(letter)
            continue

        # Parentheses not attached to a vowel are literal punctuation.
        if c in "()":
            chars.append(c)
            i += 1
            continue
        # skip lone diacritic markers if orphaned
        if c in _DIAC_CHARS:
            i += 1
            continue
        chars.append(c)
        i += 1

    import unicodedata

    text = _apply_sigma(chars)
    return unicodedata.normalize("NFC", text)


def beta_key_plain(beta: str) -> str:
    """Strip Beta diacritics from a key (lo/gos → logos)."""
    return "".join(c for c in beta.lower() if c not in _DIAC_CHARS and c != "*")
