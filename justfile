# Default buildout under test; override: just check 5.2.7 5.3.0a3
default_buildout := "5.3.0a2"

# Clean, run buildout for a Plone version, serve in foreground
fg plone_version buildout_version=default_buildout: (build plone_version buildout_version)
	bin/instance fg

# Clean + run buildout only
build plone_version buildout_version=default_buildout:
	rm -rf bin/ eggs/ develop/ parts/ var/ .installed.cfg
	uvx --from "zc.buildout=={{ buildout_version }}" buildout extends=https://dist.plone.org/release/{{ plone_version }}/versions.cfg versions:zc.buildout={{ buildout_version }} versions:packaging=24.0 versions:setuptools=81.0.0 allow-unknown-extras=true installer=uv install instance

# Clean, build, boot, assert HTTP 200 on :8080, tear down (CI-style proof run)
check plone_version buildout_version=default_buildout: (build plone_version buildout_version)
	#!/usr/bin/env bash
	set -euo pipefail
	LOG="${TMPDIR:-/tmp}/plone-check-{{ plone_version }}.log"
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
	    echo "FAIL {{ plone_version }}: instance exited early; tail of $LOG:" >&2
	    tail -20 "$LOG" >&2
	    exit 1
	  fi
	  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 http://localhost:8080/ || true)
	  if [ "$code" = "200" ]; then
	    echo "OK {{ plone_version }} (zc.buildout {{ buildout_version }}): HTTP 200 after ~$((i * 5))s"
	    exit 0
	  fi
	done
	echo "FAIL {{ plone_version }}: no HTTP 200 within 300s; tail of $LOG:" >&2
	tail -20 "$LOG" >&2
	exit 1
