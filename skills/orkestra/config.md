# orkestra config

## Where it lives

1. `<project>/.orkestra/config.json`: optional, only this project.
2. `~/.orkestra/config.json`: the user's default for every project.

Read the project file first, then the user file; project values win per key. If neither
exists, use the `balanced` preset below. The installer writes the user file when it is given
`-Profile` / `--profile`; `/orkestra settings` writes either file.

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

## Presets

| | `lean` | `balanced` | `generous` |
|---|---|---|---|
| For | tight usage (small plans, often hitting limits, switching accounts) | normal usage | plenty of headroom (large plans) |
| mechanical / judgment / review | fast / fast / fast | fast / strong / strong | strong / strong / strong |
| maxParallel | 2 | 3 | 5 |
| askBeforeSpawning | always | expensive | never |

In `lean`, use the strong tier only when the user asks for it.

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
  "askBeforeSpawning": "always"
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
  "askBeforeSpawning": "expensive"
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
  "askBeforeSpawning": "never"
}
```

## Changing it

- Run `/orkestra settings` (Codex: `$orkestra settings`) and answer the questions, or edit the
  JSON by hand.
- A change applies from the next spawn; nothing to restart.
- When new models ship, the Claude aliases move with them. Edit `models` only to pin a
  specific version or to name a Codex model.
