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

The reasons behind the rules, measured numbers, helper scripts and the Codex notes are in
[reference.md](reference.md). Read only the section you need.

## 1. Decide first: is orchestration worth it?

| Situation | Do |
|---|---|
| Two or more independent parts | Parallel sub-agents |
| Lots of reading (many files, long docs, web research) but you only need the result | One sub-agent, "return only the summary" |
| The work needs an independent check | A separate reviewer agent |
| The parts are sequential (B needs A's result) | One after another; no parallel spawn |
| A single-file fix, a quick question, a few-line patch | Do it yourself |

Every sub-agent starts cold: about 40K tokens of context before it reads anything (measured),
resent with every request it makes. Delegating small work costs more than doing it. Applying a
reviewer's ready "old → new" fixes, a comment line, a notes file: that is conductor work.

## 2. Read the config

Before the first spawn, read the config (details and presets: [config.md](config.md)):
1. `<project>/.orkestra/config.json`, then 2. `~/.orkestra/config.json`. Project values win
per key. Neither exists → use the `balanced` preset.

It tells you:
- **routing**: which tier (`strong` or `fast`) each class of work gets: `mechanical`
  (documented installs, bulk scans, experiments, question sets), `judgment` (rewriting that
  must keep meaning, hard fixes, spec writing), `review`.
- **models**: what `strong` and `fast` mean per tool. Claude defaults are the aliases `opus`
  and `sonnet`, which follow new releases. For Codex, `null` means "use the Codex default".
- **maxParallel**: never run more sub-agents at once than this.
- **askBeforeSpawning**: `always` (ask before any spawn), `expensive` (ask when the plan is
  long or uses several strong-tier agents), `never` (announce the plan and go).
- **budget**: per-agent limits for every brief's Budget block (section 4): `toolCalls`,
  `webCalls`, `outputChars` per call, `wholeFileKB`. Missing → take it from the `profile`
  preset.

## 3. Flow

0. **Plan.** List the parts and which files each part owns. Two hands never touch one file;
   on a conflict, split the work, give it its own worktree, or run it in sequence. Before
   spawning, tell the user in one line: how many agents, which models, roughly how long and
   roughly how many tokens (section 8). Follow `askBeforeSpawning`.
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

## Budget (hard limits)
- At most <toolCalls> tool calls, <webCalls> of them web calls (search, fetch, curl).
- Each call returns at most ~<outputChars> characters: trim with head, grep, wc.
- Files over ~<wholeFileKB> KB: search inside, never read end to end. No images unless
  this brief asks for them.
- Bulk text work (matching, counting, extracting) is done by a local script; only its
  summary comes back to you.
- Sources: check <scratch>/sources/INDEX.md before downloading; add a row per download.
- After each major step write <notes file> with references to the source (file:line,
  page). Out of budget: stop, write what you have, say what is left.

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
  something different, it works from the measurement and says so.
- **The Budget block**, filled from the config's `budget`. Those numbers are ceilings: size
  it to the job (Anthropic's research prompts give a fact-finding agent 3-10 calls, a
  comparison 10-15 per agent); raise it only with a reason you can name.
- **Notes on disk.** Name the notes file for each major step. If the agent dies, its work is
  recovered from these files (section 7), not from its context.
- If an earlier, interrupted attempt left files behind, say so: "read it, use it if correct".
- Never tell a sub-agent to ask the user questions: sub-agents have no question tool. The
  conductor asks.

Budget rules:
- **A call budget is not a token budget.** Every request (one per round of tool calls)
  resends the agent's whole, growing context: tokens ≈ requests × context length (measured:
  39 budgeted calls in 21 requests processed 7M tokens).
  The lever is stopping the growth: short outputs, search instead of reading, scripts
  instead of the model, notes on disk instead of in context.
- **The Budget block is an instruction, not a brake.** For a hard stop, set `maxTurns` in a
  custom agent's frontmatter: the output comes back marked partial and can be resumed.
  `kontrolcu` ships with one.
- **One source cache per job.** Every download goes into `<scratch>/sources/` with a row in
  its `INDEX.md`: path, format, page-marker convention, who fetched it, what it holds. You
  create the index and put its path in every brief; agents look there before downloading.
  WebFetch returns a model's extraction, lossy by design: for quotes and numbers, download
  the page into the cache and search the text.

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
- **Two tiers.** Mechanical evidence first, by script: quotes matched against the source
  text, numbers, dates, test runs. Model judgment goes only to what the script flags and to
  what no script can check. The reviewer writes its scripts to scratch, keeps their output
  short and gets a Budget block like any agent.
- The first review covers everything. Later rounds are narrow: only the fixed items and what
  they touch. Resume the first reviewer only if its context is small (section 7); otherwise
  start a new one on the fast tier with a brief listing only the changes. Mechanical evidence
  (tests, mutants) the conductor can run itself; leave the judgment to the reviewer.
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

- Always set the model explicitly on each sub-agent call. Left empty, Claude Code falls back
  to the agent definition's model, then `CLAUDE_CODE_SUBAGENT_MODEL`, and finally the main
  session's (often most expensive) model.
- Two tiers are enough; don't invent middle tiers. If the user names a model for a task,
  use it for that task.
- High effort / ultra modes and bulk workflow modes are not the default for the conductor:
  save expensive thinking for decisions. Use them only if the user asks.

## 7. Agents die: measure, then resume

An agent can die mid-task: usage limit, the session closing, a network error, sleep.

1. **Measure the damage.** Compare the agent's files with the backup (`cmp`, `diff`) and read
   its notes files first: what was written, what wasn't, what is half done? A dead agent's
   notes often hold half the job.
2. **Resume only a small context.** The token number in an agent's task notification is its
   context size at the end, which is what a resume reloads; for a dead agent without one, run
   the usage script (reference.md) on its transcript. Small (up to ~50K tokens): in Claude
   Code, resume it with `SendMessage`; it doesn't redo finished work, so tell it what you
   measured and what is left. Larger: don't resume. A sub-agent's
   cache lives five minutes, so after a limit reset or an account switch the whole context
   is read again uncached, and it rides along on every later call. Open a new, small,
   budgeted brief that points to the files the dead agent left, or do the rest yourself if
   it is small. In Codex, continue the session or give the same brief with only the
   remaining work.
3. **Half-finished work in live files comes first.** If a partial change affects a running
   system (hook, config, build script), finish and verify it before anything else.
4. **Work that spans sessions keeps its state on disk.** For multi-wave or overnight jobs,
   the conductor keeps one state file, `.orkestra/state.md` in the project (waves, each
   agent's files and status, last measurement, open questions), and updates it after every
   wave. If the session closes, the next one continues from there. The conductor owns this
   file; agents don't write it.
5. **Usage limit reached (HTTP 429):** open nothing new; every new agent draws on the same
   limit. Tell the user which agent stopped where, and wait for the limit to reset or for an
   account switch; then apply 1-3.

## 8. Parallelism, worktrees, closing

- **One owner per file.** If a file is shared, one agent owns it; the others send it
  suggestions.
- **Worktrees** (`isolation: worktree`) don't remove conflicts, they postpone them to the
  merge. A worktree starts from the default branch, without uncommitted local work, and the
  stash is shared: no `stash` and no `reset --hard` in parallel lanes. A background session
  in a worktree commits and may push on its own: if the user commits themselves, put
  "don't commit, don't push" in both `CLAUDE.md` and the brief.
- **One limit for everyone.** Parallel sub-agents and the main session draw on the same plan
  limit. Before a wave, estimate per agent: processed tokens ≈ requests × (start + final
  context) / 2 (requests ≤ tool calls), start ≈ 40K (reference.md has the growth numbers), and put the wave total in
  the one-line plan. If the status line saves its JSON, read
  `rate_limits.five_hour.used_percentage` before and after the first wave and extrapolate.
  Your cap is `maxParallel` (two to four agents fit most jobs); in `lean` run in sequence or
  at most two. On a 429, section 7. The optional limit guard hook (reference.md) blocks new
  agents near the limit and stops running ones before it.
- **Token table.** One row per agent: model, job, tool calls, duration, final context (the
  token number in its task notification: its context size at the end, not its usage) and
  processed tokens (its transcript summed by the script in reference.md, typically 25×
  more). A dead agent has no notification: sum its transcript, and if there is none, write
  "not reported". Add a total per wave and a "tokens per deliverable" line, both from
  processed tokens. Your own row: sum your session transcript
  the same way, else "not measured"; never invent it. Write the table into the project's
  lessons file.
- **Lessons stick.** If you make the same correction twice, write it into the project's rules
  (`CLAUDE.md`, `AGENTS.md` or project memory). Prune rules that went stale.

## 9. Settings mode

Triggered by `/orkestra` alone or `/orkestra settings` (Codex: `$orkestra settings`). Never
spawn agents here. Follow the steps in [config.md](config.md#settings-mode): show the
effective config, ask up to four questions, write the file from the chosen preset.

## 10. Codex

Before the first Codex sub-agent or `codex exec` lane, read
[reference.md § Codex](reference.md#codex): explicit delegation, literal briefs, where the
models come from, `< /dev/null`, and the Codex knobs that cap a sub-agent's context.
