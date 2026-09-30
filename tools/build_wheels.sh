#!/bin/bash
# Build the 5 binary repair wheels for Plone 5.2.2-5.2.7 pin sets.
# MUST run inside `devenv shell` (needs CFLAGS waiver, python 3.9, uv).
set -euo pipefail
WORK=/tmp/wheelbuild-52x
OUT=/tmp/built-wheels-52x
rm -rf "$WORK" "$OUT"
mkdir -p "$OUT"

echo "=== envA: Zope 4.6.3-era pinned build deps (persistent 4.7.0, zope.proxy 4.3.5, zope.interface 5.4.0)"
uv venv --seed --python 3.9 "$WORK/envA" >/dev/null
uv pip install --python "$WORK/envA/bin/python" setuptools==69.0.3 wheel persistent==4.7.0 zope.proxy==4.3.5 zope.interface==5.4.0
for spec in BTrees==4.9.2 zope.container==4.4.0 zope.security==5.1.1; do
  echo "--- building $spec"
  "$WORK/envA/bin/python" -m pip wheel --no-deps --no-build-isolation -w "$OUT" "$spec"
done

echo "=== envB: Zope 4.5.x-era pinned build deps (persistent 4.6.4, zope.proxy 4.3.5, zope.interface 5.2.0)"
uv venv --seed --python 3.9 "$WORK/envB" >/dev/null
uv pip install --python "$WORK/envB/bin/python" setuptools==69.0.3 wheel persistent==4.6.4 zope.proxy==4.3.5 zope.interface==5.2.0
"$WORK/envB/bin/python" -m pip wheel --no-deps --no-build-isolation -w "$OUT" BTrees==4.7.2

echo "=== envC: cffi 1.14.0 via libffi's own FFI_LEGACY_CLOSURE_API switch"
uv venv --seed --python 3.9 "$WORK/envC" >/dev/null
uv pip install --python "$WORK/envC/bin/python" setuptools==69.0.3 wheel
CFLAGS="${CFLAGS:-} -DFFI_LEGACY_CLOSURE_API=1" "$WORK/envC/bin/python" -m pip wheel --no-deps --no-build-isolation -w "$OUT" cffi==1.14.0

echo "=== .so inventory"
cd "$OUT"
for w in *.whl; do
  echo "$w: $(unzip -l "$w" | grep -c '\.so$' || true) .so files"
done
ls -la "$OUT"
