# Default buildout under test; override: just check 6.0.15 5.3.0a3
default_buildout := "5.3.0a2"

# Clean, run buildout for a Plone release, serve in foreground.
# Python comes from the series mapping in tools/cell.sh (5.2->3.9,
# 6.0->3.10, 6.1->3.12, 6.2->3.13); pass a third arg to override.
fg plone_version buildout_version=default_buildout python_version="":
	bash tools/cell.sh fg {{ plone_version }} {{ buildout_version }} "{{ python_version }}"

# Clean + run buildout only
build plone_version buildout_version=default_buildout python_version="":
	bash tools/cell.sh build {{ plone_version }} {{ buildout_version }} "{{ python_version }}"

# Clean, build, boot, assert HTTP 200 on :8080, tear down (CI-style proof)
check plone_version buildout_version=default_buildout python_version="":
	bash tools/cell.sh check {{ plone_version }} {{ buildout_version }} "{{ python_version }}"

# Free :8080 when a foreground instance was killed ungracefully
kill:
	kill -9 $(lsof -ti :8080) 2>/dev/null || true
