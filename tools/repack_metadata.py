#!/usr/bin/env python3
"""Repack PyPI wheels as +local1 with unparseable Requires-Dist lines
normalized to bare requirements (name[+extras]).

Rationale: 2019-era metadata carries SVN-era specifiers (``>=1.1.6dev-r22380``,
``>=3.0.0Acquisition``, ``>dev``) that predate PEP 440. Strict parsers (uv,
packaging >= 22) reject them and abort the whole resolve; pkg_resources
tolerated them via LegacyVersion. Normalizing to the bare requirement is
exactly what upstream itself did in later releases (e.g. CMFPlone 5.2.12).

Usage: repack_metadata.py out_dir dist:version [dist:version ...]
"""
import base64
import csv
import hashlib
import io
import json
import os
import re
import shutil
import sys
import urllib.request
import zipfile

from packaging.requirements import Requirement


def fetch_wheel_url(dist, version):
    with urllib.request.urlopen(
        f"https://pypi.org/pypi/{dist}/{version}/json", timeout=30
    ) as r:
        data = json.load(r)
    for f in data["urls"]:
        if f["filename"].endswith(".whl"):
            return f["url"], f["filename"]
    raise SystemExit(f"no wheel for {dist}=={version}")


def record_line(arcname, data):
    digest = base64.urlsafe_b64encode(hashlib.sha256(data).digest()).rstrip(b"=")
    return arcname, f"sha256={digest.decode()}", str(len(data))


def repack(dist, version, out_dir, retag=False):
    url, filename = fetch_wheel_url(dist, version)
    with urllib.request.urlopen(url, timeout=60) as r:
        blob = r.read()
    transform(blob, filename, version, out_dir, retag=retag)


def repack_file(path, out_dir):
    """Version-bump an already-built local wheel to +local1 (no metadata
    fixes beyond the version; RECORD regenerated)."""
    from packaging.utils import parse_wheel_filename
    filename = os.path.basename(path)
    dist, version, _, _ = parse_wheel_filename(filename)
    version = str(version)
    with open(path, "rb") as f:
        blob = f.read()
    transform(blob, filename, version, out_dir)


def transform(blob, filename, version, out_dir, retag=False):
    local_version = f"{version}+local1"
    out_filename = filename.replace(f"-{version}-", f"-{local_version}-", 1)
    if retag:
        # e.g. py2-only wheel whose code is py3-compatible (pinned by a
        # py3-era release): py2-none-any -> py2.py3-none-any
        out_filename = out_filename.replace("-py2-none-any", "-py2.py3-none-any")
        assert out_filename != filename.replace(f"-{version}-", f"-{local_version}-", 1)
    out_path = os.path.join(out_dir, out_filename)
    if os.path.exists(out_path):
        print(f"SKIP {out_filename} (exists)")
        return

    src = zipfile.ZipFile(io.BytesIO(blob))
    # dist-info dir name uses the *canonical* name per the wheel's own layout;
    # find it rather than assuming.
    names = src.namelist()
    di_candidates = {n.split("/")[0] for n in names if n.endswith(".dist-info/METADATA")}
    assert len(di_candidates) == 1, di_candidates
    old_distinfo = di_candidates.pop()
    new_distinfo = old_distinfo.replace(f"-{version}.dist-info", f"-{local_version}.dist-info")
    assert new_distinfo != old_distinfo, old_distinfo

    entries = {}  # arcname -> bytes
    for n in names:
        if n.endswith("/"):
            continue
        data = src.read(n)
        if n.startswith(old_distinfo + "/"):
            n = new_distinfo + "/" + n[len(old_distinfo) + 1:]
        if n == new_distinfo + "/METADATA":
            text = data.decode("utf-8")
            lines = text.splitlines()
            fixed = []
            for line in lines:
                if line.startswith("Requires-Dist:"):
                    req = line[len("Requires-Dist:"):].strip()
                    try:
                        Requirement(req)
                        fixed.append(line)
                    except Exception:
                        # strip the legacy parenthesized specifier; keep
                        # name (+extras) and any env marker
                        bare = re.sub(r"\s*\([^)]*\)", "", req)
                        Requirement(bare)  # must parse now
                        fixed.append(f"Requires-Dist: {bare}")
                        print(f"  {filename}: {req!r} -> {bare!r}")
                else:
                    fixed.append(line)
            text = "\n".join(fixed) + "\n"
            text = re.sub(
                rf"^Version: {re.escape(version)}$",
                f"Version: {local_version}",
                text,
                count=1,
                flags=re.M,
            )
            data = text.encode("utf-8")
        if retag and n == new_distinfo + "/WHEEL":
            text = data.decode("utf-8").replace("Tag: py2-none-any", "Tag: py2.py3-none-any")
            data = text.encode("utf-8")
        if n == new_distinfo + "/RECORD":
            continue  # regenerated below
        entries[n] = data

    # regenerate RECORD
    rows = []
    for arcname, data in sorted(entries.items()):
        rows.append(record_line(arcname, data))
    rows.append((new_distinfo + "/RECORD", "", ""))
    buf = io.StringIO()
    csv.writer(buf, lineterminator="\n").writerows(rows)
    entries[new_distinfo + "/RECORD"] = buf.getvalue().encode("utf-8")

    with zipfile.ZipFile(out_path, "w", zipfile.ZIP_DEFLATED) as z:
        for arcname, data in sorted(entries.items()):
            z.writestr(arcname, data)
    print(f"WROTE {out_filename}")


def main():
    out_dir = sys.argv[1]
    for spec in sys.argv[2:]:
        retag = spec.endswith(":retag-py2py3")
        if retag:
            spec = spec[: -len(":retag-py2py3")]
        if spec.endswith(".whl") and os.path.exists(spec):
            repack_file(spec, out_dir)
            continue
        dist, version = spec.rsplit(":", 1)
        repack(dist, version, out_dir, retag=retag)


if __name__ == "__main__":
    main()
