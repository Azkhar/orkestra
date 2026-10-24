# orkestra config

## Where it lives

1. `<project>/.orkestra/config.json`: optional, only this project.
2. `~/.orkestra/config.json`: the user's default for every project.

Read the project file first, then the user file; project values win per key. If neither
exists, use the `balanced` preset below. A key missing from both files (for example
`budget` in a config written before 0.3.0) comes from the preset named in `profile`, else
from `balanced`. The installer writes the user file when it is given `-Profile` /
`--profile`; `/orkestra settings` writes either file.

## Fields

| Field | Values | Meaning |
|---|---|---|
| `version` | `1` | Schema version. |
| `profile` | `lean` / `balanced` / `generous` | The preset this file started from. |
| `routing.mechanical` | `fast` / `strong` | Tier for documented installs, bulk scans, experiments, question sets. |
| `routing.judgment` | `fast` / `strong` | Tier for meaning-preserving rewrites, hard fixes, spec writing. |
| `routing.review` | `fast` / `strong` | Tier for the independent reviewer. |
| `models.claude.strong` / `.fast` | alias or full model ID | Claude Code model per tier. Aliases (`opus`, `sonnet`, `haiku`) follow the provider's recommended version and update over time; use a full ID only to pin a version. |
| `models.codex.strong` / `.fast` | model name or `null` | `null` = use the Codex default. Codex sub-agent models are really set in `~/.codex/agents/*.toml`. |
| `maxParallel` | integer | Never run more sub-agents at once. |
| `askBeforeSpawning` | `always` / `expensive` / `never` | When to ask the user before spawning. The one-line plan is announced in every case. |
| `budget.toolCalls` | integer | Most tool calls per sub-agent, the reviewer included. |
| `budget.webCalls` | integer | Most web calls (search, fetch, curl) within `toolCalls`. |
| `budget.outputChars` | integer | Most characters one call may return into the agent's context; larger output is trimmed (`head`, `grep`, `wc`). |
| `budget.wholeFileKB` | integer | Files larger than this are searched, never read end to end. |
| `limitGuard.warnAt` / `.stopAt` / `.agentStopAt` | percent | Optional limit guard hook (reference.md): from `warnAt` the conductor sees the plan usage on every spawn, from `stopAt` new agents are denied, from `agentStopAt` running agents may only write files. Defaults 70 / 90 / 95; not part of the presets. |
| `limitGuard.enabled` | `true` / `false` | `false` turns the hook off for this project or user. |

The budget goes into every brief's Budget block (SKILL.md section 4). It caps calls, not
tokens: every request resends the agent's whole context, so the output and file-size caps
matter as much as the call count.

## Presets

| | `lean` | `balanced` | `generous` |
|---|---|---|---|
| For | tight usage (small plans, often hitting limits, switching accounts) | normal usage | plenty of headroom (large plans) |
| mechanical / judgment / review | fast / fast / fast | fast / strong / strong | strong / strong / strong |
| maxParallel | 2 | 3 | 5 |
| askBeforeSpawning | always | expensive | never |
| `budget.toolCalls` | 25 | 40 | 60 |
| `budget.webCalls` | 6 | 10 | 15 |
| `budget.outputChars` | 2000 | 2000 | 4000 |
| `budget.wholeFileKB` | 50 | 50 | 100 |

In `lean`, use the strong tier only when the user asks for it, and run agents one after
another unless the parts are truly independent.

The exact files (kept identical to `templates/profiles/*.json` in the repo):

`lean`
```json
{
  "version": 1,
  "profile": "lean",
  "routing": { "mechanical": "fast", "judgment": "fast", "review": "fast" },
  "models": {
    "claude": { "strong": "opus", "fast": "sonnet" },
    "codex": { "strong": null, "fast": null }
  },
  "maxParallel": 2,
  "askBeforeSpawning": "always",
  "budget": { "toolCalls": 25, "webCalls": 6, "outputChars": 2000, "wholeFileKB": 50 }
}
```

`balanced`
```json
{
  "version": 1,
  "profile": "balanced",
  "routing": { "mechanical": "fast", "judgment": "strong", "review": "strong" },
  "models": {
    "claude": { "strong": "opus", "fast": "sonnet" },
    "codex": { "strong": null, "fast": null }
  },
  "maxParallel": 3,
  "askBeforeSpawning": "expensive",
  "budget": { "toolCalls": 40, "webCalls": 10, "outputChars": 2000, "wholeFileKB": 50 }
}
```

`generous`
```json
{
  "version": 1,
  "profile": "generous",
  "routing": { "mechanical": "strong", "judgment": "strong", "review": "strong" },
  "models": {
    "claude": { "strong": "opus", "fast": "sonnet" },
    "codex": { "strong": null, "fast": null }
  },
  "maxParallel": 5,
  "askBeforeSpawning": "never",
  "budget": { "toolCalls": 60, "webCalls": 15, "outputChars": 4000, "wholeFileKB": 100 }
}
```

## Settings mode

Triggered by `/orkestra` alone or `/orkestra settings` (Codex: `$orkestra settings`). Never
spawn agents here.

1. Read the current config (project file, then user file) and show a short table of the
   effective values and where each comes from, or "no config, using balanced". Also say
   whether conductor mode is on in this project (the orkestra block in `AGENTS.md`,
   `CLAUDE.md` or `CLAUDE.local.md`).
2. Ask the user. In Claude Code use the AskUserQuestion tool once, with up to four questions;
   in Codex, ask the same as a short numbered list:
   - **Usage headroom:** tight (small plans, often hitting limits) → `lean`; normal →
     `balanced`; plenty (large plans) → `generous`.
   - **Ask before spawning:** always / only when expensive / never.
   - **Max parallel agents:** 2 / 3 / 5 (or keep the preset).
   - **Save where:** for all projects (`~/.orkestra/config.json`) or this project only
     (`.orkestra/config.json`).
3. Build the file from the chosen preset above (budget included), apply the overrides, write
   it (create the folder if needed) and show what changed. It applies from the next spawn;
   no restart needed.
4. To turn conductor mode on or off for a project, point the user to the installer
   (`-Always` / `-Uninstall`); see the repo's `INSTALL.md`.

## Changing it

- Run `/orkestra settings` (Codex: `$orkestra settings`) and answer the questions, or edit the
  JSON by hand.
- A change applies from the next spawn; nothing to restart.
- When new models ship, the Claude aliases move with them. Edit `models` only to pin a
  specific version or to name a Codex model.
