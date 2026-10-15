# Changelog

## 0.3.0 (2026-10-15)

Budgets, from a field run in which two unbudgeted research agents hit the plan's usage limit
in about 30 minutes after processing 75.5M tokens (numbers in `skills/orkestra/reference.md`,
sources in `docs/research/2026-10-token-budget.md`).

- Brief template: a Budget block (tool calls, web calls, output per call, whole-file limit,
  no images unless asked, scripts for bulk text, source index, notes on disk). Profile
  numbers are ceilings; the brief sizes the budget to the job.
- "A call budget is not a token budget": tokens ≈ requests × context length; the lever is
  keeping the context from growing.
- The Budget block is an instruction; a hard stop needs `maxTurns`, and `kontrolcu` now has
  `maxTurns: 60`.
- One shared source cache per job (`<scratch>/sources/INDEX.md`), checked before every
  download; quotes and numbers come from raw downloads, not from WebFetch (lossy by design).
- Notes on disk after each major step; a dead agent's work is recovered from them first.
- Resume policy: read the agent's context size first; small → `SendMessage`, large → a new
  budgeted brief that points to its files. A sub-agent's prompt cache lives five minutes.
- Two-tier review: mechanical checks by script first, judgment only on what they flag.
  `kontrolcu` writes its scripts to scratch, keeps output short and stays within a budget.
- One plan limit for everyone: a token estimate in the one-line plan before each wave
  (processed ≈ requests × (start + final context) / 2); `rate_limits` from the status line JSON
  when it is saved; `lean` runs agents in sequence or at most two; on HTTP 429 nothing new is
  opened.
- Token table: the token number in a task notification is the agent's final context, not its
  usage (measured on 43 runs); processed tokens come from the transcript (script in
  `reference.md`), dead agents included; totals per wave and tokens per deliverable, written to
  the project's lessons file.
- Config: `budget` per profile (`toolCalls`, `webCalls`, `outputChars`, `wholeFileKB`); a
  config without it falls back to its profile's preset. `tests/check-presets.py` checks the
  fields, lean ≤ balanced ≤ generous, and that the `config.md` table matches the JSON.
- New `skills/orkestra/reference.md` (reasons, measured numbers, helper scripts, Codex notes),
  read on demand; settings-mode steps moved to `config.md`. SKILL.md stays under 17,500
  characters (rule in `CONTRIBUTING.md`).
- `docs/research/2026-10-token-budget.md`: sources with reading dates, and the measurements
  behind the rules.
- README: a Budgets section and a measured one-line "why" at the top (English and Turkish).
- `docs/field-notes/2026-10-13-research-budget.md`: the field run as a short case study, including what is still open.
- CI on Windows (PowerShell 7 and 5.1, Git Bash), Linux and macOS (system bash 3.2).
- `CONTRIBUTING.md` and a pull request template.

## 0.2.1 (2026-09-27)

- `/orkestra` with no arguments opens settings mode (it was undefined; found on first real
  use). Settings mode now also reports whether conductor mode is on in the project.

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
