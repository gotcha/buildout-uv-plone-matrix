#!/usr/bin/env bash
# Map a Plone release to its Python (devenv CLI override, mirroring
# buildout's own versions:x=y CLI overrides), enter the devenv with it,
# run the cell action. Usage: cell.sh <build|fg|check> <plone> <buildout> [python]
set -euo pipefail
mode="$1"; plone="$2"; buildout="$3"; py="${4:-}"
if [ -z "$py" ]; then
  case "$plone" in
    5.2.*) py=3.9 ;;
    6.0.*) py=3.10 ;;
    6.1.*) py=3.12 ;;
    6.2.*) py=3.13 ;;
    *) echo "no Python mapping for Plone $plone; pass one explicitly" >&2; exit 2 ;;
  esac
fi
cd "$(dirname "$0")/.."
exec devenv shell --option languages.python.version:string "$py" -- \
  bash tools/cell-inner.sh "$mode" "$plone" "$buildout" "$py"
