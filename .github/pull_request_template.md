## What and why

<!-- One paragraph. Link the issue if there is one. -->

## Checklist

- [ ] Tests pass locally (`pwsh -File tests/test-install.ps1`, `bash tests/test-install.sh`)
- [ ] New behavior has a test, and the test fails on the old code (turn it red)
- [ ] `python3 tests/check-presets.py` passes if presets or `config.md` changed
- [ ] `CHANGELOG.md` updated
- [ ] No dated model IDs where an alias works; no secrets, no personal paths

## Review

The other maintainer reviews before merge. Nobody approves their own work.
