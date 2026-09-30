#!/bin/bash
# probe_one.sh <name==version> — replicate uv's isolated sdist build for one
# pin, inside the devenv env (CFLAGS/CPATH/LIBRARY_PATH/UV_BUILD_CONSTRAINT).
# MUST run inside `devenv shell`.
set -u
spec="$1"
safe=$(echo "$spec" | tr -c 'A-Za-z0-9._-' '_')
py="$(python -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
venv="/tmp/probe-$py-$safe"
logd="${2:-./probe-logs}"
mkdir -p "$logd"
rm -rf "$venv"
uv venv --python "$py" "$venv" >/dev/null 2>&1 || { echo "VENVFAIL $spec"; exit 0; }
if uv pip install --python "$venv/bin/python" --no-deps "$spec" >"$logd/$safe.log" 2>&1; then
  echo "OK   $spec"
else
  echo "FAIL $spec"
fi
rm -rf "$venv"
