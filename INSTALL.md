# Installing orkestra: instructions for AI agents

A user gave you this repository and asked you to install it ("install
https://github.com/Azkhar/orkestra in this project", "bunu bu projeye kur"). Follow these
steps. Talk to the user in their language. Don't commit or push anything.

## 1. Get the repo

If the user points to a local clone, use it. Otherwise clone into a temp folder:

```bash
git clone --depth 1 https://github.com/Azkhar/orkestra.git <temp>/orkestra
```

Check whether orkestra is already installed for the user: `~/.claude/skills/orkestra/SKILL.md`
(Claude Code) or `~/.agents/skills/orkestra/SKILL.md` (Codex).

## 2. Ask the user

In Claude Code, use the AskUserQuestion tool once. In Codex, ask a short numbered list.

1. **Where should the skill live?** All my projects (global) / only this project.
   If it is already installed globally, don't ask: keep it global.
2. **Conductor mode in this project?** In conductor mode every Claude Code and Codex session
   in the project starts as the conductor and decides by itself whether to split work across
   sub-agents; the default stays "do it yourself".
   - Yes, shared: writes a small block to `AGENTS.md` / `CLAUDE.md` (the team sees it once
     committed).
   - Yes, only for me: writes the block to `CLAUDE.local.md` (Claude Code only; Codex has no
     local instruction file).
   - No.
3. **How much usage headroom do you have?** Tight, often hitting limits → `lean`;
   normal → `balanced`; plenty → `generous`. See `skills/orkestra/config.md` for what each
   profile does.

## 3. Build the command

| Answer | Flag (PowerShell) | Flag (bash) |
|---|---|---|
| Skill global | `-Scope Global` | `--scope global` |
| Skill only in this project | `-Scope Project -Path <project>` | `--scope project --path <project>` |
| Conductor mode, shared | `-Scope Project -Path <project> -Always` | `--scope project --path <project> --always` |
| Conductor mode, only for me | add `-Local` | add `--local` |
| Skill is global, only add conductor mode | add `-BlockOnly` | add `--block-only` |
| Profile | `-Profile lean` | `--profile lean` |
| Only Claude Code or only Codex | `-Target claude` / `-Target codex` | `--target claude` / `--target codex` |

Typical cases:

```powershell
# Windows: global skill + lean profile
pwsh -NoProfile -File <temp>\orkestra\install.ps1 -Scope Global -Profile lean

# Windows: skill already global, turn on conductor mode in this project
pwsh -NoProfile -File <temp>\orkestra\install.ps1 -Scope Project -Path . -Always -BlockOnly
```

```bash
# macOS / Linux
bash <temp>/orkestra/install.sh --scope global --profile balanced
bash <temp>/orkestra/install.sh --scope project --path . --always --block-only
```

Conductor mode is per project, so it always needs `-Scope Project`. If you need both a
global skill and conductor mode, run the installer twice: once `-Scope Global`, once
`-Scope Project -Always -BlockOnly`.

## 4. Dry run, then run

1. Run the command with `-DryRun` / `--dry-run` and show the output to the user.
2. Run it for real. Exit codes: `0` done, `2` something was skipped because a different
   version exists (rerun with `-Force` / `--force` if the user agrees; the old copy is moved
   aside, never deleted), `1` error.

## 5. Report

- List what was installed and where. For conductor mode, show the block that was added.
- Tell the user: open a new session so the skill and the project instructions load;
  `/orkestra settings` (Codex: `$orkestra settings`) changes the profile at any time.
- Don't commit. If conductor mode wrote to `AGENTS.md` / `CLAUDE.md`, the user decides whether
  to commit it; if it wrote `CLAUDE.local.md`, suggest adding it to `.gitignore`.
- If you cloned into a temp folder, you may delete that folder.

## Update and uninstall

- **Update:** `git -C <clone> pull`, then rerun the same command with `-Force` / `--force`.
- **Uninstall:** same scope and path with `-Uninstall` / `--uninstall`. It removes only what
  orkestra installed (the skill folder, `kontrolcu.md`, the conductor block). The config in
  `~/.orkestra/` stays unless you add `-Purge` / `--purge`, which is only valid together with
  `-Uninstall` / `--uninstall`.
