# Changelog

## 0.2.0 (2026-09-27)

- Skill rewritten in English; the description keeps Turkish trigger phrases and the agent
  talks to the user in their language.
- `/orkestra settings` (Codex: `$orkestra settings`): settings mode with multiple-choice
  questions; writes `~/.orkestra/config.json` or `<project>/.orkestra/config.json`.
- Config with three profiles (`lean`, `balanced`, `generous`): routing of mechanical,
  judgment and review work to a fast or strong tier, parallel cap, when to ask before
  spawning. Claude models are aliases (`opus`, `sonnet`) that follow new releases.
- Conductor mode: `-Always` writes a managed block to the project's `AGENTS.md` / `CLAUDE.md`
  (or `CLAUDE.local.md` with `-Local`), so every session starts as the conductor with
  "do it yourself" as the default. `-BlockOnly` adds just the block when the skill is global.
- `-Profile` and `-Purge` installer options.
- `INSTALL.md`: install by giving an agent the repo URL.
- Protocol additions: measurable acceptance criteria that are never relaxed, "not found" is a
  claim too, one-line plan before spawning, narrow re-review rounds, on-disk state for
  multi-session work, sub-agents never ask the user questions.
- MIT license, public README.

## 0.1.0 (2026-09-27)

- First version (Turkish): protocol, `kontrolcu` reviewer, installers for PowerShell and bash,
  tests on pwsh 7, Windows PowerShell 5.1 and bash.
