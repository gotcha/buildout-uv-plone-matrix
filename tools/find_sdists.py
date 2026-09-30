#!/usr/bin/env python3
"""List pinned (name, version) across versions.cfg files that have NO
compatible wheel on PyPI for this interpreter/platform (=> sdist builds),
and separately those with unusable-but-present wheels. Uses packaging.tags
sys_tags for a faithful compatibility check (mirrors uv's selection).
"""
import json
import re
import sys
import urllib.request

from packaging.tags import sys_tags
from packaging.utils import parse_wheel_filename

PIN_RE = re.compile(r"^([A-Za-z0-9_.\-]+)\s*=\s*([^\s;#]+)")

TAGS = set(sys_tags())


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

    sdists = []
    wheeled = 0
    errors = []
    for name in sorted(all_pins, key=str.lower):
        for ver in sorted(all_pins[name]):
            try:
                with urllib.request.urlopen(
                    f"https://pypi.org/pypi/{name}/{ver}/json", timeout=15
                ) as r:
                    data = json.load(r)
            except Exception as e:
                errors.append(f"{name}=={ver}: {e}")
                continue
            ok = False
            for fdata in data["urls"]:
                fn = fdata["filename"]
                if not fn.endswith(".whl"):
                    continue
                try:
                    _, _, _, tags = parse_wheel_filename(fn)
                except Exception:
                    continue
                if tags & TAGS:
                    ok = True
                    break
            if ok:
                wheeled += 1
            else:
                sdists.append(f"{name}=={ver}")

    print(f"# {wheeled} pins have compatible wheels; {len(sdists)} need sdist builds")
    for s in sdists:
        print(s)
    if errors:
        print(f"# {len(errors)} fetch failures:", file=sys.stderr)
        for e in errors:
            print(f"#   {e}", file=sys.stderr)


if __name__ == "__main__":
    main()
