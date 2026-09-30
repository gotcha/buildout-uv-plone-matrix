# local-wheels — version-preserving repair wheels for Plone 5.2.10/5.2.11

Why this exists is documented in `../buildout.cfg` (the `find-links` comment).
No Plone/Zope pin is changed: every wheel here is the *same version* as the
PyPI artifact, labeled `+local1` (PEP 440 local label — sorts above the public
release for the resolver, still satisfies `==X.Y` pins).

## Contents

| Wheel | Same-version PyPI artifact | Repair |
|---|---|---|
| `Products.CMFPlone-5.2.8+local1-py2.py3-none-any.whl` | `Products.CMFPlone-5.2.8-py2.py3-none-any.whl` | metadata only: drop legacy specifiers `plone.app.contentmenu (>=1.1.6dev-r22380)`, `plone.app.layout (>=1.1.7dev-r23744)` → bare names (upstream's own 5.2.12 cleanup) |
| `Products.CMFPlone-5.2.9+local1-py2.py3-none-any.whl` | `Products.CMFPlone-5.2.9-py2.py3-none-any.whl` | same |
| `Products.CMFPlone-5.2.10+local1-py2.py3-none-any.whl` | `Products.CMFPlone-5.2.10-py2.py3-none-any.whl` | same |
| `Products.CMFPlone-5.2.11+local1-py2.py3-none-any.whl` | `Products.CMFPlone-5.2.11-py2.py3-none-any.whl` | same |
| `BTrees-4.10.0+local1-cp39-cp39-macosx_14_0_arm64.whl` | `BTrees-4.10.0.tar.gz` | binary build in non-isolated env (needs `persistent` importable at build time) |
| `zope.container-4.5.0+local1-cp39-cp39-macosx_14_0_arm64.whl` | `zope.container-4.5.0.tar.gz` | binary build in non-isolated env (needs `persistent` + `zope.proxy` headers; building against *today's* persistent 6.x breaks — its `cPersistence.h` dropped the `PY3K` define) |
| `zope.security-5.2+local1-cp39-cp39-macosx_14_0_arm64.whl` | `zope.security-5.2.tar.gz` | binary build in non-isolated env (needs `zope.proxy` headers) |
| `zope.security-5.3+local1-cp39-cp39-macosx_14_0_arm64.whl` | `zope.security-5.3.tar.gz` | same |

Coverage: 5.2.8/5.2.9 need CMFPlone + zope.security 5.2 + BTrees 4.10.0 +
zope.container 4.5.0; 5.2.10 needs CMFPlone + zope.security 5.3 + BTrees +
zope.container; 5.2.11 needs only CMFPlone (Zope 4.8.7's remaining sdists
build in isolation).

## Rebuild procedure

Metadata patches (CMFPlone): download the PyPI wheel, unzip, edit
`*.dist-info/METADATA` (fix the two `Requires-Dist` lines, bump `Version:` to
`+local1`), rename the dist-info dir accordingly, regenerate `RECORD`
(sha256/size for every file), rezip under the `+local1` filename.

Binary wheels (BTrees, zope.container, zope.security), inside the devenv
(Python 3.9, CFLAGS/CPATH/LIBRARY_PATH already set):

```sh
uv venv --seed --python 3.9 /tmp/wheelbuild-39
uv pip install --python /tmp/wheelbuild-39/bin/python \
    setuptools==69.0.3 wheel \
    persistent==4.9.0 zope.proxy==4.5.0 zope.interface==5.4.0
/tmp/wheelbuild-39/bin/python -m pip wheel --no-deps --no-build-isolation \
    -w /tmp/built-wheels <sdist-url>
# then apply the same +local1 repack as above
```

Verify a built wheel actually contains its `.so`s before trusting it —
BTrees' `setup.py` silently falls back to pure Python when the C build fails
(`optional_build_ext`).

Platform note: the binary wheels are `cp39 macosx_14_0_arm64` — they match
this machine's devenv interpreter. On another platform, rebuild them there.
