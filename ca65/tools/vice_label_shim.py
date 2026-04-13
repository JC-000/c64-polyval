#!/usr/bin/env python3
"""Shim ld65's -Ln label output into the VICE/ACME format.

ld65 emits:      al 000801 .main_entry
c64-test-harness wants:  al C:0801 .main_entry

The regex in c64_test_harness.labels requires the `C:` bank prefix, so we
add it and strip leading zeros down to 4 hex digits for readability.

ld65's `-Ln` output contains duplicate entries for every symbol (each label
is emitted once per reference, not once per definition). We dedupe here so
the resulting VICE labels file has exactly one `al C:addr .name` line per
unique (address, name) pair.

Usage: vice_label_shim.py INPUT OUTPUT
"""
from __future__ import annotations

import re
import sys

_LD65_LINE = re.compile(r"^al\s+([0-9a-fA-F]+)\s+(\.\S+)\s*$")


def shim(src_path: str, dst_path: str) -> int:
    """Translate INPUT (ld65 -Ln format) to OUTPUT (VICE format).

    Returns the number of unique labels written. Duplicate (addr, name)
    pairs from ld65 are collapsed to a single line.
    """
    seen: set[tuple[int, str]] = set()
    lines: list[str] = []
    with open(src_path) as src:
        for line in src:
            m = _LD65_LINE.match(line.strip())
            if not m:
                continue
            addr = int(m.group(1), 16)
            name = m.group(2)
            key = (addr, name)
            if key in seen:
                continue
            seen.add(key)
            lines.append(f"al C:{addr:04x} {name}\n")
    with open(dst_path, "w") as dst:
        dst.writelines(lines)
    return len(lines)


def main() -> int:
    if len(sys.argv) != 3:
        print(f"usage: {sys.argv[0]} INPUT OUTPUT", file=sys.stderr)
        return 2
    n = shim(sys.argv[1], sys.argv[2])
    print(f"vice_label_shim: wrote {n} labels to {sys.argv[2]}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
