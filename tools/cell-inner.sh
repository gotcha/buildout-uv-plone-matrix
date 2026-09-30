#!/usr/bin/env bash
# The actual cell work. Runs INSIDE the devenv (cell.sh wraps the entry).
# mode: build | fg | check
set -euo pipefail
mode="$1"; plone="$2"; buildout="$3"; py="$4"
python --version
rm -rf bin/ eggs/ develop/ parts/ var/ .installed.cfg
uvx --from "zc.buildout==$buildout" buildout \
  extends="https://dist.plone.org/release/$plone/versions.cfg" \
  versions:zc.buildout="$buildout" \
  versions:packaging=24.0 versions:setuptools=81.0.0 \
  allow-unknown-extras=true installer=uv install instance
[ "$mode" = "build" ] && exit 0
if [ "$mode" = "fg" ]; then
  exec bin/instance fg
fi
# check mode
LOG="${TMPDIR:-/tmp}/plone-cell-$plone-py$py.log"
bin/instance fg >"$LOG" 2>&1 &
FG=$!
cleanup() {
  kill -9 $FG 2>/dev/null || true
  kill -9 $(lsof -ti :8080) 2>/dev/null || true
}
trap cleanup EXIT
for i in $(seq 1 60); do
  sleep 5
  if ! kill -0 $FG 2>/dev/null; then
    echo "FAIL $plone/py$py: instance exited early; tail of $LOG:" >&2
    tail -20 "$LOG" >&2
    exit 1
  fi
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 http://localhost:8080/ || true)
  if [ "$code" = "200" ]; then
    echo "OK $plone (zc.buildout $buildout, Python $py): HTTP 200 after ~$((i * 5))s"
    exit 0
  fi
done
echo "FAIL $plone/py$py: no HTTP 200 within 300s; tail of $LOG:" >&2
tail -20 "$LOG" >&2
exit 1
