#!/usr/bin/env python3
"""Sanity-check sample_nl_output.txt shape (no Swift needed)."""
import re
import sys
from pathlib import Path

text = Path(__file__).with_name("sample_nl_output.txt").read_text()
bodies = re.findall(r"<NL>(.*?)</NL>", text, flags=re.S)
if not bodies:
    print("FAIL: no <NL> bodies", file=sys.stderr)
    sys.exit(1)
for i, body in enumerate(bodies, 1):
    body = body.strip()
    m = re.match(r"^([A-Za-z]+)\s+(\S+)\s+(.*)$", body, re.S)
    if not m:
        print(f"FAIL body {i}: {body!r}", file=sys.stderr)
        sys.exit(1)
    pos, lemma_field, rest = m.groups()
    print(f"OK {i}: pos={pos} lemma_field={lemma_field!r} morph≈{rest[:40]!r}")
print(f"Checked {len(bodies)} analyses.")
