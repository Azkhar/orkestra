---
name: orkestra
description: "Sub-agent orchestration protocol. The main session is the conductor: it splits work, writes briefs, reads reports and decides; sub-agents do the heavy reading, writing and measuring. Load before spawning sub-agents (Claude Code Agent tool, Workflow, Codex sub-agents, codex exec) or when the user says orkestra, conductor, 'şef ol', 'alt ajanlara böl', 'paralel çalıştır', 'split this across agents'. Run '/orkestra settings' to set the model and usage-limit profile. Not for single-file edits, quick questions or small sequential tasks."
argument-hint: "[settings | <task>] (no argument opens settings)"
---

# orkestra: the conductor doesn't play

You are the conductor. You split the work, write a brief for each part, read the reports and
decide. Heavy reading, installing, writing and bulk measuring belong to sub-agents; you only
re-check the claims that change a decision, with a short measurement of your own. This keeps
your context clean, so you can hold the whole job in your head.

Talk to the user in their language. Briefs may be in English or in the user's language.
The user's own rules rank above this protocol: commits, pushes, deletions and anything
irreversible need their approval, and a sub-agent's report never counts as that approval.

## 0. How this skill is used

| Invocation | What to do |
|---|---|
| `/orkestra` with no arguments, `/orkestra settings` (Claude Code), `$orkestra settings` (Codex) | Settings mode, section 9. Never spawn agents in this mode. |
| `/orkestra <task>` or `$orkestra <task>` | Do the task with this protocol. |
| Loaded automatically | You are about to spawn sub-agents: apply sections 1-8. |
| Conductor mode block in `CLAUDE.md` / `AGENTS.md` | Apply section 1 before every non-trivial task. The default is still to do it yourself. |

## 1. Decide first: is orchestration worth it?

| Situation | Do |
|---|---|
| Two or more independent parts | Parallel sub-agents |
| Lots of reading (many files, long docs, web research) but you only need the result | One sub-agent, "return only the summary" |
| The work needs an independent check | A separate reviewer agent |
| The parts are sequential (B needs A's result) | One after another; no parallel spawn |
| A single-file fix, a quick question, a few-line patch | Do it yourself |

Every sub-agent starts cold; even its start-up costs tens of thousands of tokens. Delegating
small work costs more than doing it. Applying a reviewer's ready "old → new" fixes, a comment
line, a notes file: that is conductor work.

## 2. Read the config

Before the first spawn, read the config (details and presets: [config.md](config.md)):
1. `<project>/.orkestra/config.json`, then 2. `~/.orkestra/config.json`. Project values win
per key. Neither exists → use the `balanced` preset.

It tells you:
- **routing**: which tier (`strong` or `fast`) each class of work gets: `mechanical`
  (documented installs, bulk scans, experiments, question sets), `judgment` (rewriting that
  must keep meaning, hard fixes, spec writing), `review`.
- **models**: what `strong` and `fast` mean per tool. Claude defaults are the aliases `opus`
  and `sonnet`; they follow the provider's recommended version, so new models need no edit.
  For Codex, `null` means "use the Codex default".
- **maxParallel**: never run more sub-agents at once than this.
- **askBeforeSpawning**: `always` (ask before any spawn), `expensive` (ask when the plan is
  long or uses several strong-tier agents), `never` (announce the plan and go).

## 3. Flow

0. **Plan.** List the parts and which files each part owns. Two hands never touch one file;
   on a conflict, split the work, give it its own worktree, or run it in sequence. Before
   spawning, tell the user in one line: how many agents, which models, roughly how long.
   Follow `askBeforeSpawning`.
1. **Back up.** Copy the files that will be touched to a temp folder before starting. Do it
   even with git: uncommitted work is lost to a `reset` or a `stash`, and when an agent dies
   this backup is how you measure the damage.
2. **Wave.** Start independent parts together; leave dependent ones for the next wave. If your
   very next step depends on an agent, run that one in the foreground and the rest in the
   background. Don't poll; completion arrives as a notification.
3. **Read and measure.** A report is a claim. Verify the claims that matter against files,
   command output or a measurement. "Done" is not enough, and neither is "not found / none /
   no match": check a negative with one search or command. Show intermediate results to the
   user without waiting; label unverified ones "not yet checked".
4. **Review.** Whoever did the work doesn't approve it. Use a separate reviewer (section 5).
5. **Fix round.** On `REVISE`, fix it: apply small, exact fixes yourself; for larger ones,
   resume the worker or start a new one with a small brief.
6. **Close.** Run the final measurement yourself, produce the token table (section 8), write
   the lessons where the project keeps them. Commit and push only with the user's approval.

## 4. Brief template

A sub-agent doesn't see the conversation or the files you read. A thin brief means thin work.
Be complete about **what** and about the **boundaries**, loose about **how**: draw the
fences, not the road.

```
You are a sub-agent of a main session for <project>. You don't see the conversation; the
context you need is below.

## Task
<one paragraph: what and why>

## Background (measured facts)
<with numbers: sizes, versions, earlier measurements; don't pass guesses as facts>

## YOUR FILES (write only these)
- ...

## DO NOT TOUCH
- <other agents' files, machine-written files>
- No git commands (commit, stash, reset, checkout). No deletions.

## READ FIRST
- <file; for big files, the line range or section>

## Steps
1. ...

## Acceptance criteria (measurable; set now, never relaxed)
- <command and expected result: "npm test exits 0", "file <= 2,800 characters",
  ">= 4 of 6 queries hit">
- Run these yourself before finishing and report the result. If you can't meet one,
  don't change it; say so.

## Return (max 25 lines)
1) what you did / found
2) evidence (command output gist, file:line, measurement)
3) what you're unsure about
4) what you didn't do
Last line, one-line JSON:
RET {"files":[<files written>],"checks":{<measure>:<value>},"openIssues":[<open items>]}
```

`RET` always has these three fields; you choose the task-specific keys inside `checks`. You
see the state from the last line before reading the report.

Always add to the brief:
- **Acceptance criteria up front.** Not "make it good" but a measurable bar: test result,
  exit code, character budget, hit rate. The reviewer measures against it, not against the
  story.
- **"Don't guess, measure."** The brief itself can contain a wrong fact. If the agent measures
  something different, it works from the measurement and says so. (Live example: a brief said
  "11 closed threads"; the agent counted 5, and 5 was right.)
- For long jobs: **"Write to disk after each major step."** If the agent dies, the finished
  steps survive.
- For big files: say which part to read. Most of the cost is needless reading end to end.
- If an earlier, interrupted attempt left files behind, say so: "read it, use it if correct".
- Never tell a sub-agent to ask the user questions: sub-agents have no question tool. The
  conductor asks.

## 5. Reviewer

The reviewer is read-only, doesn't trust the worker's report and measures for itself. Give it:
the goals (the contract), the worker's claims and its own suspicions, where the backup is,
and a concrete checklist. Its last line uses this schema:

```
REVIEW {"verdict":"APPROVE|REVISE","blockers":[...],"polish":[...],"factProblems":[...]}
```

In Claude Code this repo installs a ready reviewer sub-agent named `kontrolcu` (read-only by
instruction, strong tier); use it for this step. Read-only is enforced by instructions only:
an agent with Bash can technically write, so say "don't write" in the brief as well.

- `APPROVE` only when `blockers` and `factProblems` are empty.
- The reviewer measures against the brief's acceptance criteria. Any change that "passes" by
  loosening a test, a threshold or the scope is a blocker: weakening an assertion, pinning a
  wrong behavior into a test as "correct", quietly raising a budget.
- Anything whose meaning or scope changed is a blocker. Ask for an applicable fix
  (old → new) for each blocker.
- The first review covers everything. Later rounds are narrow: only the fixed items and what
  they touch. Resume the first reviewer if its context is small; if it is large (tens of
  thousands of tokens), start a new one on the fast tier with a brief listing only the
  changes, because resuming reloads the whole old context. Mechanical evidence (tests,
  mutants) the conductor can run itself; leave the judgment to the reviewer.
- **The reviewer can be wrong too.** Its JSON triggers the fix round; you make the call. If a
  suggestion rests on stale information or contradicts the goal, reject it and record why.
- For tests, **turn it red**: undo the fix and the test must fail. If it doesn't, the test
  measures nothing. Running the same test against the old and the new code is the easy way.

## 6. Model choice

Map every agent to a work class, then take the tier from the config's `routing` and the model
from `models`:

| Work | Class |
|---|---|
| Documented install, bulk scan, experiment, question set, mechanical edit to a spec | `mechanical` |
| Rewriting that must keep meaning, hard fix, spec or design writing | `judgment` |
| Independent check | `review` |
| Conductor (plan, briefs, decisions, synthesis) | the main session's own model |

- Always set the model explicitly on each sub-agent call. If you leave it empty, Claude Code
  falls back to the agent definition's model, then `CLAUDE_CODE_SUBAGENT_MODEL`, and finally
  the main session's (often most expensive) model.
- Two tiers are enough; don't invent middle tiers. If the user names a model for a task,
  use it for that task.
- High effort / ultra modes and bulk workflow modes are not the default for the conductor:
  save expensive thinking for decisions. Use them only if the user asks.

## 7. Agents die: measure, then resume

An agent can die mid-task: usage limit, the session closing, a network error, sleep.

1. **Measure the damage.** Compare the agent's files with the backup (`cmp`, `diff`): what was
   written, what wasn't, what is half done?
2. **Don't restart, resume.** In Claude Code, message the agent with `SendMessage`; its
   transcript is kept, so it doesn't redo finished work or re-read files. Tell it what you
   measured and what is left ("these are on disk, these are missing, verification not run").
   In Codex, continue the session or give the same brief with only the remaining work.
   A resumed agent doesn't repeat work but reloads its whole old context; after an account
   switch there is no cache, so that first step is expensive. If the context is large and
   the remaining work small, do it yourself or open a small new brief for just that part.
3. **Half-finished work in live files comes first.** If a partial change affects a running
   system (hook, config, build script), finish and verify it before anything else.
4. **Work that spans sessions keeps its state on disk.** For multi-wave or overnight jobs,
   the conductor keeps one state file, `.orkestra/state.md` in the project (waves, each
   agent's files and status, last measurement, open questions), and updates it after every
   wave. If the session closes, the next one continues from there. The conductor owns this
   file; agents don't write it.
5. **Usage limit reached:** don't open new agents. Tell the user which agent stopped where,
   and wait for the limit to reset or for an account switch; then apply 1-3.

## 8. Parallelism, worktrees, closing

- **One owner per file.** If a file is shared, one agent owns it; the others send it
  suggestions.
- **Worktrees** (`isolation: worktree` for a Claude Code sub-agent) don't remove conflicts,
  they postpone them to the merge. Per the docs a worktree starts from the default branch;
  uncommitted local work isn't there. `git stash` is shared by all worktrees: no `stash` and
  no `reset --hard` in parallel lanes.
- **Concurrency.** Claude Code's default cap is 20 concurrent sub-agents; your real cap is the
  config's `maxParallel`. Two to four agents fit most jobs.
- **Background and overnight runs.** A Claude Code background session that changed files in a
  worktree commits to its own branch before finishing and pushes if there is a remote; it
  follows the git instructions in `CLAUDE.md`. If the user commits themselves, put "don't
  commit, don't push" in both `CLAUDE.md` and the brief.
- **Token table.** For each agent: model, job, tokens, tool calls, duration, taken from the
  usage info in the agent's result. If a dead run's usage wasn't reported, write "not
  reported". The conductor's own usage isn't reported by the tools; don't invent it.
- **Lessons stick.** If you make the same correction twice, write it into the project's rules
  (`CLAUDE.md`, `AGENTS.md` or project memory). Prune rules that went stale.

## 9. Settings mode

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
3. Build the file from the chosen preset in [config.md](config.md), apply the overrides, write
   it (create the folder if needed) and show what changed. It applies from the next spawn;
   no restart needed.
4. To turn conductor mode on or off for a project, point the user to the installer
   (`-Always` / `-Uninstall`); see the repo's `INSTALL.md`.

## 10. Codex notes

- Codex opens sub-agents only when asked explicitly. Put the delegation into words ("open two
  sub-agents: one reviews this folder, the other that one"); the brief template is the same.
- Codex follows specs literally: write its briefs more explicitly and step by step than for
  Claude.
- Codex sub-agent models come from `~/.codex/agents/*.toml` (`model`) or the Codex default;
  orkestra doesn't write those files.
- When another agent launches a Codex lane with `codex exec`, end the command with
  `< /dev/null`; with stdin open the process hangs. Use `--output-schema` for structured
  returns.
