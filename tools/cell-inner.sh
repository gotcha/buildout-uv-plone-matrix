#!/usr/bin/env bash
# The actual cell work. Runs INSIDE the devenv (cell.sh wraps the entry).
# mode: build | fg | check
set -euo pipefail
mode="$1"; plone="$2"; buildout="$3"; py="$4"
python --version
rm -rf bin/ eggs/ develop/ parts/ var/ .installed.cfg
# buildout.cfg's find-links points at local-wheels/. A container upload
# may prune that directory (dagger matrix_src excludes it), and uv
# errors on a missing --find-links directory even when the run needs
# nothing from it.
mkdir -p local-wheels
# Mode A (default, release): buildout from PyPI via uvx; the pin set
# — including versions:setuptools=81.0.0 — is what the status matrix
# was validated against and must stay verbatim.
# Mode B (buildout=installed, CI): the ambient interpreter already has
# the buildout under test (a source checkout). versions:zc.buildout
# pins to the ambient version: Plone's versions.cfg pins the release
# (zc.buildout = 4.2.0), and without the override the self-upgrade
# check would fetch 4.2.0 from PyPI and restart under it, silently
# not testing the checkout. No versions:setuptools pin: the branch
# under test removes setuptools from the installer=uv path and this
# mode proves it.
if [ "$buildout" = "installed" ]; then
  buildout_display="$(python -c 'from importlib.metadata import version; print(version("zc.buildout"))')"
  buildout \
    extends="https://dist.plone.org/release/$plone/versions.cfg" \
    versions:zc.buildout="$buildout_display" \
    versions:packaging=24.0 \
    allow-unknown-extras=true installer=uv install instance
else
  buildout_display="$buildout"
  uvx --from "zc.buildout==$buildout" buildout \
    extends="https://dist.plone.org/release/$plone/versions.cfg" \
    versions:zc.buildout="$buildout" \
    versions:packaging=24.0 versions:setuptools=81.0.0 \
    allow-unknown-extras=true installer=uv install instance
fi
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
    echo "OK $plone (zc.buildout $buildout_display, Python $py): HTTP 200 after ~$((i * 5))s"
    exit 0
  fi
done
echo "FAIL $plone/py$py: no HTTP 200 within 300s; tail of $LOG:" >&2
tail -20 "$LOG" >&2
exit 1
