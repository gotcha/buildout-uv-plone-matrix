fg plone_version:
	rm -rf bin/ eggs/ develop/ parts/ var/ .installed.cfg
	uvx --from "zc.buildout==5.3.0a2" buildout extends=https://dist.plone.org/release/{{ plone_version }}/versions.cfg versions:zc.buildout=5.3.0a2 versions:packaging=24.0 versions:setuptools=81.0.0 allow-unknown-extras=true installer=uv install instance
	bin/instance fg
