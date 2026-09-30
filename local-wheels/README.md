# local-wheels — version-preserving repair wheels

Wired into the build via `find-links = ${buildout:directory}/local-wheels`
in `../buildout.cfg`. No Plone/Zope pin is changed: every wheel is the
*same version* as the PyPI artifact, labeled `+local1` (a PEP 440 local
label — it sorts above the public release for the resolver and still
satisfies the release's `==X.Y` pins, so selection is deterministic).

Binary wheels are `cp39 macosx_14_0_arm64` — they match this machine's
devenv interpreter. On another platform, rebuild (procedures below).

## Repair classes

| Class | Problem | Repair |
|---|---|---|
| **M** — legacy metadata | pre-PEP-440 requirement specifiers (`>=1.1.6dev-r22380`, `>=3.0.0Acquisition`, `>dev`) abort uv's whole resolve; `pkg_resources` tolerated them via `LegacyVersion` | repack the PyPI wheel with the offending `Requires-Dist` reduced to the bare name(+extras) — exactly what upstream did in later releases (e.g. CMFPlone 5.2.12) |
| **B** — build-time sibling lookup | sdist's setup.py does `pkg_resources.require()` / unbounded `setup_requires` on sibling dists to locate C headers (`persistent`, `zope.proxy`); uv's isolated build env only has setuptools+wheel, so it fails — or worse, fetches *today's* sibling (persistent 6.x no longer defines `PY3K`, sending 2019 C down its dead py2 branch) | build a binary wheel in a non-isolated venv with the *pinned* build deps of the consuming Zope set; metadata untouched |
| **C** — toolchain drift | cffi 1.14.0 calls the legacy `ffi_prep_closure`, which libffi 4.0 (nixpkgs) no longer even compiles in (`FFI_LEGACY_CLOSURE_API 0` in ffitarget.h; symbol absent from the dylib) | build with `-DCFFI_TRUST_LIBFFI`: cffi's own opt-in switches to `ffi_prep_closure_loc()` + `ffi_closure_alloc()` — the modern API (what cffi 1.14.3+ autodetects; runtime callback test passes) |
| **D** — `use_2to3` | feedparser 5.2.1's setup.py uses `use_2to3`, removed in setuptools 58; on py3 the code only ever worked via build-time 2to3 conversion | build the wheel in a venv with `setuptools==57.5.0` (last era with 2to3 on Python 3.9's `lib2to3`); the wheel ships the converted py3 code |

## Contents (31 wheels)

| Wheel | Class | Serves |
|---|---|---|
| Products.CMFPlone 5.2.0–5.2.11 `+local1` (12 wheels) | M | 5.2.0–5.2.11 (5.2.12+ is clean upstream) |
| plone.app.dexterity 2.6.3/2.6.4/2.6.5/2.6.8/2.6.9 `+local1` | M (`plone.namedfile[scales] (>=1.0b5dev-r36016)`) | 5.2.0–5.2.6 (5.2.7 pins clean 2.6.10) |
| Products.MimetypesRegistry 2.1.5/2.1.7/2.1.8 `+local1` | M (`AccessControl (>=3.0.0Acquisition)`); 2.1.5 also retagged py2→py2.py3 (its PyPI wheel is py2-only, invisible to a py3.9 resolver; the code is py3-compatible as used by Plone 5.2.x py3) | 5.2.0–5.2.6 (5.2.7 pins clean 2.1.9) |
| zope.testbrowser 5.5.1 `+local1` | M (`pytz (>dev)`) | 5.2.2–5.2.7 |
| BTrees 4.7.2 / 4.9.2 / 4.10.0 `+local1` | B | Zope 4.5.x / 4.6.3 / 4.8.x sets |
| zope.container 4.4.0 / 4.5.0 `+local1` | B | Zope 4.5.x–4.8.x sets |
| zope.security 5.1.1 / 5.2 / 5.3 `+local1` | B | Zope 4.5.x–4.8.x sets |
| cffi 1.14.0 `+local1` | C | 5.2.2 (Zope 4.5.1 pin) |
| feedparser 5.2.1 `+local1` | D | 5.2.2–5.2.4 (5.2.5+ pin 6.0.8) |

Per-release coverage:

- **5.2.15–5.2.12**: none needed (devenv env fixes suffice).
- **5.2.11**: CMFPlone.
- **5.2.10 / 5.2.9 / 5.2.8**: CMFPlone, BTrees 4.10.0, zope.container 4.5.0,
  zope.security (5.3 / 5.2).
- **5.2.7**: CMFPlone, zope.testbrowser 5.5.1, BTrees 4.9.2,
  zope.container 4.4.0, zope.security 5.1.1.
- **5.2.6 / 5.2.5**: same as 5.2.7 plus plone.app.dexterity 2.6.9,
  Products.MimetypesRegistry 2.1.8.
- **5.2.4 / 5.2.3** (ditched — boot, see ../README.md): CMFPlone,
  dexterity, MTR 2.1.8, testbrowser, feedparser, BTrees 4.7.2,
  zope.container 4.4.0, zope.security 5.1.1.
- **5.2.2** (ditched): same as 5.2.3 but MTR 2.1.7, plus cffi 1.14.0.
- **5.2.1 / 5.2.0** (ditched — build era): only the class-M metadata wheels
  are provided; the build-era failures are documented in ../README.md and
  deliberately not repaired.

## Rebuild procedures

All inside `devenv shell` (Python 3.9, CFLAGS/CPATH/LIBRARY_PATH/
UV_BUILD_CONSTRAINT already set). Scripts live in `../tools/`.

### M — metadata repacks

```sh
python3 tools/repack_metadata.py local-wheels Products.CMFPlone:5.2.7
# py2-only wheel that is py3-compatible (pinned by a py3-era release):
python3 tools/repack_metadata.py local-wheels Products.MimetypesRegistry:2.1.5:retag-py2py3
```

The script downloads the PyPI wheel, normalizes every unparseable
`Requires-Dist` to the bare name(+extras), bumps `Version:` to `+local1`,
regenerates `RECORD`, rezips. With a local wheel path instead of
`dist:version` it does the version bump only (used for class B/C/D below).

### B — sibling-lookup binary wheels

```sh
uv venv --seed --python 3.9 /tmp/wheelbuild
uv pip install --python /tmp/wheelbuild/bin/python \
    setuptools==69.0.3 wheel \
    persistent==<pinned> zope.proxy==<pinned> zope.interface==<pinned>
/tmp/wheelbuild/bin/python -m pip wheel --no-deps --no-build-isolation \
    -w /tmp/built-wheels <dist>==<version>
python3 tools/repack_metadata.py local-wheels /tmp/built-wheels/<wheel>.whl
```

Build-dep pins used here: for the Zope 4.6.3 set persistent 4.7.0 +
zope.proxy 4.3.5 + zope.interface 5.4.0; for the 4.5.x set persistent 4.6.4
+ zope.proxy 4.3.5 + zope.interface 5.2.0; for the 4.8.x set persistent
4.9.0 + zope.proxy 4.5.0 + zope.interface 5.4.0.

**Verify the wheel actually contains its `.so`s before trusting it** —
BTrees' setup.py silently falls back to pure Python when the C build fails
(`optional_build_ext`). Expect ~22 `.so` for BTrees, 1 for zope.container,
2 for zope.security:

```sh
unzip -l local-wheels/BTrees-4.9.2+local1-*.whl | grep -c '\.so$'
```

### C — cffi 1.14.0

```sh
uv venv --seed --python 3.9 /tmp/wheelbuild-cffi
uv pip install --python /tmp/wheelbuild-cffi/bin/python setuptools==69.0.3 wheel
CFLAGS="$CFLAGS -DCFFI_TRUST_LIBFFI" \
  /tmp/wheelbuild-cffi/bin/python -m pip wheel --no-deps --no-build-isolation \
  -w /tmp/built-wheels cffi==1.14.0
```

Sanity-check closures at runtime (`@ffi.callback` roundtrip) before
trusting the wheel.

### D — feedparser 5.2.1 (use_2to3)

```sh
uv venv --seed --python 3.9 /tmp/wheelbuild-2to3
uv pip install --python /tmp/wheelbuild-2to3/bin/python setuptools==57.5.0 wheel
/tmp/wheelbuild-2to3/bin/python -m pip wheel --no-deps --no-build-isolation \
    -w /tmp/built-wheels feedparser==5.2.1
```

Verify the 2to3 conversion landed: `unzip -p <wheel> feedparser.py | grep
'urllib.request'` (py2 original imports `urllib2`).

## Finding new failures on a fresh pin set

```sh
# 1. download the release's versions.cfg + extended Zope ones
# 2. scan all pins for metadata uv can't parse:
python3 tools/scan_legacy_reqs.py plone-*.cfg zope-*.cfg
# 3. list pins with no compatible wheel (=> sdist builds):
python3 tools/find_sdists.py plone-*.cfg zope-*.cfg
# 4. replicate uv's isolated build per pin (inside devenv shell):
xargs -P 8 -I@ bash tools/probe_one.sh @ < probe-list.txt
```
