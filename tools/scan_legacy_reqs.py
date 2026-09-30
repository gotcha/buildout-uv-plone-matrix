#!/usr/bin/env python3
"""Scan every pin of Plone 5.2.10/5.2.11 (incl. extended Zope pins) for
requires_dist entries that modern `packaging` (and thus uv) cannot parse."""
import json
import re
import sys
import time
import urllib.request

from packaging.requirements import Requirement

PIN_RE = re.compile(r"^([A-Za-z0-9_.\-]+)\s*=\s*([^\s;#]+)")


def pins(path):
    out = {}
    for line in open(path):
        m = PIN_RE.match(line.strip())
        if m and not line.lstrip().startswith("#"):
            out.setdefault(m.group(1), m.group(2))
    return out


def main():
    files = sys.argv[1:]
    all_pins = {}
    for f in files:
        for name, ver in pins(f).items():
            all_pins.setdefault(name, set()).add(ver)

    bad = []
    errors = []
    checked = 0
    for name in sorted(all_pins, key=str.lower):
        for ver in sorted(all_pins[name]):
            url = f"https://pypi.org/pypi/{name}/{ver}/json"
            try:
                with urllib.request.urlopen(url, timeout=15) as r:
                    data = json.load(r)
            except Exception as e:
                errors.append(f"{name}=={ver}: fetch failed: {e}")
                continue
            checked += 1
            for req in data["info"].get("requires_dist") or []:
                try:
                    Requirement(req)
                except Exception:
                    bad.append(f"{name}=={ver}: {req}")
            time.sleep(0.05)

    print(f"checked {checked} pinned releases")
    print(f"--- {len(bad)} unparseable requirement entries ---")
    for b in bad:
        print(b)
    if errors:
        print(f"--- {len(errors)} fetch failures (not on PyPI / network) ---")
        for e in errors:
            print(e)


if __name__ == "__main__":
    main()
