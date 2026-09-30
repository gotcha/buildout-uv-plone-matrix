# buildout-uv-plone-matrix — proof harness for the refactored zc.buildout

**Goal:** supplementary proof that new releases of the refactored
zc.buildout (uv installer, no `pkg_resources`) keep working — and stay
useful — across a matrix of Plone releases, Python versions, and the
setuptools eras their pin sets come from.

## Usage

```sh
just check 5.2.15                 # clean, run buildout, boot, assert HTTP 200, tear down
just fg 6.0.10                    # clean, run buildout, serve in foreground
just build 6.2.2                  # clean + buildout only (no boot assertion)

just check 5.2.7 5.3.0a3          # second arg: zc.buildout release under test
just check 6.2.2 5.3.0a2 3.14     # third arg: explicit Python override
just kill                         # free :8080 if a foreground instance died hard
```

Each recipe maps the Plone series to its Python and re-enters the devenv
through devenv's own CLI override
(`devenv shell --option languages.python.version:string <py>`), the same
spirit as buildout's `versions:x=y` CLI args. The mapping lives in
`tools/cell.sh`:

| Plone series | Python |
|---|---|
| 5.2.x | 3.9 |
| 6.0.x | 3.10 |
| 6.1.x | 3.12 |
| 6.2.x | 3.13 (3.14 verified too, via explicit override) |

Interpreters come from the devenv (nixpkgs-python input), never from uv.

## Status matrix

zc.buildout 5.3.0a2, macOS arm64. Every green cell ran from scratch
(`rm -rf bin eggs parts var .installed.cfg`) to HTTP 200 on :8080.

| Plone | Python | `just check` |
|-------|--------|--------------|
| 6.2.2 | 3.13, 3.14 | ✅ |
| 6.1.1, 6.1.5 | 3.12 | ✅ |
| 6.0.10, 6.0.15 | 3.10 | ✅ |
| 6.0.10 | 3.9 | ✅ (also passes here) |
| 5.2.15 – 5.2.12 | 3.9 | ✅ (no repair wheels needed) |
| 5.2.11 | 3.9 | ✅ |
| 5.2.10 | 3.9 | ✅ |
| 5.2.9, 5.2.8 | 3.9 | ✅ |
| 5.2.7 – 5.2.5 | 3.9 | ✅ |
| 5.2.4 – 5.2.2 | 3.9 | ❌ ditched — buildout OK, Plone won't boot on 3.9 |
| 5.2.1 – 5.2.0 | 3.9 | ❌ ditched — pre-PEP-517 build era |

The 6.x cells needed **zero** repair wheels: 1100 pinned releases across
their version sets contain no unparseable requirement metadata, and every
sdist-only pin builds cleanly on its target Python. The only probe failure
anywhere in the 6.x sets is `backports.zoneinfo 0.2.1`, which is
marker-gated to `python_version < "3.9"` and never enters a 3.10+ resolve.

## Why 5.2.0–5.2.4 are ditched

Owner decision (2026-09-30): digging further into the past is not worth the
reach. The goal is proving buildout, not fixing Plone. The precise walls,
for the record:

- **5.2.4 – 5.2.2 (Zope 4.5.x): buildout completes; the instance does not
  boot on Python 3.9.** Plone code from 2019–2020 predates Python 3.9:
  `plone.app.portlets` 4.4.5/4.4.6 calls `base64.decodestring` (removed in
  3.9) while loading `portlets/configure.zcml`. Getting further means
  patching Plone runtime sources — a Plone-on-3.9 backporting project, not
  a buildout proof. Note the distinction: with the repair wheels present,
  `just build 5.2.4` *succeeds* — buildout+uv handles the complete
  2020-era pin set; it's Plone's own code that doesn't run on 3.9.
  (5.2.5 is the first 5.2.x whose pins boot on 3.9.)
- **5.2.1 – 5.2.0 (Zope 4.1.x): the *build* itself is pre-PEP-517 era.**
  - zope.interface 4.6.0, zope.proxy 4.3.1/4.3.2, zope.hookable 4.2.0,
    zope.i18nmessageid 4.3.1, zope.security 4.3.1, pyScss 1.3.5:
    `from setuptools import Feature` (removed in setuptools 46, 2020) —
    would need setuptools<46 build environments.
  - zope.testbrowser 5.3.3: `install_requires` rejected by modern
    setuptools outright.
  - persistent 4.5.0: C calls `_Py_ForgetReference`, which Python 3.9
    removed from public headers (needs a source patch).
  - lxml 4.3.4: pre-generated Cython C calls `PyCode_New` with the
    Python 3.8 arity — incompatible with 3.9 itself; would need
    re-cythonization with a newer Cython at build time.
  - cffi 1.12.3: legacy libffi closure API (see the cffi entry in
    `local-wheels/README.md`).

Anything Archetypes is out of scope by owner decision (and irrelevant in
practice: CMFPlone gates the Archetypes stack behind
`python_version < "3"` markers, so it never enters these Python 3.9
resolutions).

## How it works

- `justfile` + `tools/cell.sh` + `tools/cell-inner.sh` — the CLI surface:
  series→Python mapping, devenv CLI override entry, build/fg/check modes,
  port-8080 lifecycle handling.
- `devenv.nix` — the Python shell (3.9 by default, overridden per cell)
  carrying the toolchain fixes old pin sets need: multiverse libxml2 2.11.5
  + libxslt 1.1.38 (lxml 4.x sdist builds), libjpeg-turbo/zlib (Pillow 6.x),
  libffi (cffi 1.14.x), `CFLAGS=-Wno-int-conversion` (2019-era C vs
  clang ≥16), and `UV_BUILD_CONSTRAINT` + the generated
  `build-constraints.txt` (setuptools==69.0.3 in isolated build envs, so
  lxml's extras survive).
- `buildout.cfg` — a single `[instance]` part; `find-links` points at
  `local-wheels/`.
- `local-wheels/` — version-preserving repair wheels (`+local1`): same
  versions as PyPI, repairing legacy metadata specifiers, build-time
  sibling lookups, and toolchain mismatches that uv (correctly) refuses.
  Only the 5.2.x cells need them. Full table + rebuild procedures in
  `local-wheels/README.md`.
- `tools/` — the scan/probe/repack/build pipeline that produced
  `local-wheels/`, re-runnable for other platforms or new releases.

## Notes

- The binary wheels in `local-wheels/` are `cp39 macosx_14_0_arm64` — they
  match this machine's 3.9 devenv interpreter. On another platform, rebuild
  them with `tools/` (procedure in `local-wheels/README.md`).
- Regenerable state (bin/, eggs/, parts/, var/, .installed.cfg,
  build-constraints.txt, .wheel-work/) is gitignored on purpose.
