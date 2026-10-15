# Contributing to orkestra

Thanks for helping. orkestra is small on purpose: one skill, one reviewer agent, two
installers and their tests. Changes should keep it that way.

## Setup

```bash
git clone https://github.com/Azkhar/orkestra.git
cd orkestra
```

Install your working copy to try it, without touching your real setup:

```powershell
.\install.ps1 -Scope Project -Path <some-test-project> -DryRun
```

## Tests

Run all of them before opening a pull request or pushing to `main`. They use a temporary
home folder and never touch your real `~/.claude`, `~/.agents` or `~/.orkestra`.

```bash
pwsh -NoProfile -File tests/test-install.ps1                                   # PowerShell 7
powershell -NoProfile -ExecutionPolicy Bypass -File tests/test-install.ps1     # Windows PowerShell 5.1
bash tests/test-install.sh                                                     # bash (Linux, macOS, Git Bash)
python3 tests/check-presets.py                                                 # config.md presets == templates
```

CI runs the same on Windows, Linux and macOS (system bash 3.2) for every push and pull request.

**Turn it red.** A new test must fail on the code before your change. Run it against the old
installer once and say so in the pull request or commit message. A test that passes either
way measures nothing.

## How we work

- Changes come in as a pull request into `main`, from a branch or a fork. A maintainer other
  than the author reviews it; nobody approves their own pull request.
- The repository owner ([@Azkhar](https://github.com/Azkhar)) pushes straight to `main`. CI
  runs the same tests on every push, and a red `main` is fixed before anything else.
- Keep changes small. A skill wording change and an installer change are two pull requests
  (or two commits).
- The skill (`skills/orkestra/SKILL.md`) and all docs are in English. `README.tr.md` is the
  Turkish summary; update it when the README's meaning changes.
- Every behavior change gets a `CHANGELOG.md` line. Releases are tagged `vX.Y.Z`.

## Rules for changes

- **Presets live in two places:** `templates/profiles/*.json` (used by the installer) and the
  JSON blocks in `skills/orkestra/config.md` (read by agents), whose preset table repeats the
  `budget` values. Change all of them; `tests/check-presets.py` fails if they drift.
- **SKILL.md is loaded into every conductor session**, so it is tokens too: keep it under
  17,500 characters. Long examples, reasons and scripts go to `skills/orkestra/reference.md`.
- **The conductor block** comes only from `templates/conductor-block.md`. Never hard-code it in
  the installers.
- **Models:** use Claude aliases (`opus`, `sonnet`, `haiku`), not dated model IDs, so the skill
  keeps working when new models ship. Don't hard-code Codex model names.
- **Installers only touch their own targets:** the skill folder, `kontrolcu.md`, the marked
  conductor block, and `~/.orkestra/config.json`. Anything else, including user text next to
  the block, stays byte for byte the same. Keep PowerShell 5.1 and bash 3.2 compatibility.
- **Claims need sources.** If the skill states how Claude Code or Codex behaves, link the
  official docs in the pull request or commit message.
- No secrets, no personal paths, no machine-specific settings in commits.
