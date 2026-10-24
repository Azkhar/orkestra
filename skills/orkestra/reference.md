# orkestra reference

Read only the section you need; SKILL.md links here. "Measured" numbers come from Claude Code
transcripts (October 2026); the sources behind the documented facts are in
[docs/research/2026-10-token-budget.md](../../docs/research/2026-10-token-budget.md).

## Why the budget rules

Field run, 2026-10-13: page-referenced research on 18th-century books for a documentary,
then a fact check. Conductor Opus, research agents Sonnet, reviewer Opus (`kontrolcu`).

- **Wave 1, no budget in the briefs.** Two Sonnet research agents in parallel. After about
  30 minutes both hit the plan's usage limit (HTTP 429) and the main session stopped too.
  - Agent A took page-by-page notes into 8 files (~80 KB, the whole book), then prepared and
    read scanned page images (0.4-2.2 MB JPG each) to check quotes; its last 15 minutes went
    there. Measured afterwards from its transcript: 132 API responses, context up to 541,185
    tokens, **39,469,768 tokens processed**.
  - Agent B downloaded and processed 2-4 MB OCR XML files: 87 Bash calls, 20 searches, 16
    fetches, a 2.8 MB transcript, no output file. Measured: 114 responses, context up to
    461,962, **36,071,444 processed**.
- **Recovery.** A's notes on disk saved half the job. B was not resumed (its context would
  have been reloaded); a new brief pointed to the files B had downloaded, with a budget: at
  most 40 tool calls, 8 web calls, no images, a helper script that searches the text. Result:
  39 tool calls, 34 minutes, a notification saying 560,851 tokens. That number is the agent's
  context at the end; it **processed 7,050,785 tokens**. Five times less than B, but still a
  lot: the context kept growing, about 25K per API response.
- **Review.** `kontrolcu` hit the limit on its first message; after an account switch it was
  resumed with `SendMessage` (its context was small): 29 tool calls, 8 minutes, final context
  196,443, processed 2,856,088. It first matched 36 quotes against the source text with a
  script, then looked only at the suspects. Verdict REVISE, 9 fact problems, all valid.
- **Measuring.** The conductor couldn't see its own usage, and read each agent's tokens from
  its task notification, which turned out to be a context size, not usage (next section).

## What the token numbers mean

- **Task notification** (`subagent_tokens` in the usage block): the agent's context at the
  end, i.e. the last request's input plus its output. In 43 of 43 comparable runs it matched that
  number within 1.2%. It is what a resume reloads.
- **Processed**: every API response's input, cache read, cache write and output, summed over
  the transcript. That is the work the plan pays for (cache reads at a lower rate). Measured
  over 43 runs: 4 to 122 times the notification, median 25.
- **Cold start**: the first request's context. Median 40K tokens over 68 transcripts; agents
  with a short tool list start lower (`kontrolcu`: 10,453 to 13,922).

Processed per agent ≈ API requests × (start + final context) / 2. Checks: R1 of the 0.3.0
research predicted 30 × (37K + 163K) / 2 ≈ 3.0M, measured 2.6M; the field rerun predicted
21 × (43K + 561K) / 2 ≈ 6.3M, measured 7.05M.

## Estimating a wave

    per agent ≈ requests × (start + final) / 2,   final ≈ start + requests × growth per request

Requests ≤ tool calls (parallel calls share one). Start ≈ 40K. Growth per request is what the
agent keeps: tool output plus its own writing. With
the ~2,000-character output cap it was about 4K per response in the 0.3.0 research (mostly
its own notes); without a cap the field rerun grew about 25K per response. Example: two
agents at the `balanced` budget, 40 calls (at most 40 requests) each, growth 4K → final ≈ 200K, per agent
≈ 40 × 120K = 4.8M, wave ≈ 9.6M processed, mostly cache reads. Say the number in the one-line
plan; in `lean`, one agent at a time.

Your own calls cost your context each time: a long conductor session easily runs 100K+ per
call. That is why bulk work doesn't belong there.

**Reading the plan limit.** No tool lets a session read its remaining limit, but the status
line's JSON input carries `rate_limits.five_hour.used_percentage` and
`rate_limits.seven_day.used_percentage` (with `resets_at`). If the user's status line command
saves its input, e.g. `tee ~/.claude/statusline.json | <their status line>`, read that field
before and after the first wave: the difference is the wave's real price on this plan.

## Limit guard (optional hook)

`hooks/limit-guard.mjs`, installed with the skill, is a `PreToolUse` hook that turns two rules
into code: open nothing new near the limit, and stop an agent before the limit cuts it off.
Field data, one user's last 14 days (24 Oct 2026): 127 sub-agents processed 456.6M tokens; 13
of them were cut off by the session limit, and those 13 had processed 114.3M (25%). Nothing
told them the limit was close.

It reads the plan usage saved on disk and takes the higher of the 5-hour and 7-day windows:

- **Conductor, Agent/Task call:** from `warnAt` (70) the usage and reset time go into the
  conductor's context; from `stopAt` (90) the spawn is denied.
- **Inside a sub-agent** (the hook input has `agent_id`): from `agentStopAt` (95) every tool
  but Write/Edit/MultiEdit/NotebookEdit is denied, with a message asking for notes and a
  partial report. Measured with a haiku agent: it wrote its notes file and returned done /
  left / file paths. Read is denied too, so an agent can update a notes file only if it wrote
  or read it earlier: one more reason to write notes after every step.
- **No data, a window that has reset, an unreadable file, any error:** the call goes through.

Data: `~/.claude/statusline.json` (the status line JSON saved with `tee`, above) and
`~/.claude/limits.json` (`{"five_hour": {"used_percentage": 48, "resets_at": ...}, "seven_day": ...}`),
or the files listed in `ORKESTRA_LIMITS_FILE` (path-list separator). A reading needs
`resets_at` (ISO date or epoch seconds); without it there is no telling how old it is, and it
is ignored. Per window: within one window the higher number wins (usage only grows, so a saved
reading is a lower bound); readings of different windows, e.g. after an account switch, go to
the file written last. A writer should save only the current account's reading. The hook
never calls an API.

Install (Node 18+): add to `~/.claude/settings.json`, with the absolute path of the installed
skill. Matcher `*`, because sub-agent calls arrive under their own tool names; main-session
calls other than Agent/Task exit before any file is read.

```json
{ "hooks": { "PreToolUse": [ { "matcher": "*", "hooks": [ { "type": "command",
  "command": "node \"/home/me/.claude/skills/orkestra/hooks/limit-guard.mjs\"" } ] } ] } }
```

On Windows use forward slashes in the path:
`"command": "node \"C:/Users/me/.claude/skills/orkestra/hooks/limit-guard.mjs\""`.

Thresholds: `limitGuard` in `.orkestra/config.json` (config.md). `ORKESTRA_GUARD=off` turns it
off for one shell. Tests: `node tests/test-limit-guard.mjs`.

## Knobs in Claude Code

- `maxTurns` in a custom agent's frontmatter: a hard stop after that many agentic turns. The output comes back marked
  partial and can be resumed (partial marking needs v2.1.246+). `kontrolcu` uses 60.
- A short `tools:` list lowers the cold start; `omitClaudeMd: true` keeps CLAUDE.md files out
  of a custom agent.
- Sub-agent prompt cache: five minutes, even on a subscription. The `subagentPromptCacheTtl`
  setting, the `CLAUDE_CODE_SUBAGENT_PROMPT_CACHE_TTL` env var or `cacheTtl: 1h` inside a
  custom agent's `experimental` frontmatter map choose a longer one; a one-hour cache write
  costs more, so use it only for agents that wait.
- Per-call caps that already exist: Bash output 30,000 characters (`BASH_MAX_OUTPUT_LENGTH`,
  `bashOutputMaxChars`), Read 25,000 tokens, MCP output 25,000 tokens, WebFetch 100,000
  characters of a page. The Budget block's ~2,000 characters is deliberately far below them.
- Auto-compaction runs in sub-agents too; `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` moves its trigger.

## Images

An image costs ⌈width / 28⌉ × ⌈height / 28⌉ tokens, capped at 1,568 (standard tier, 1,568 px
long edge) or 4,784 (Claude 4.7 and later, 2,576 px). 51 scanned pages at the cap cost
80K-244K tokens once and the same again on every later call while they stay in context. Ask
for images only when the text can't answer, and then in a separate small agent.

## Budget block, filled (`balanced`)

```
## Budget (hard limits)
- At most 40 tool calls, 10 of them web calls (search, fetch, curl).
- Each call returns at most ~2,000 characters: trim with head, grep, wc.
- Files over ~50 KB: search inside, never read end to end. No images unless this brief
  asks for them.
- Bulk text work (matching, counting, extracting) is done by a local script; only its
  summary comes back to you.
- Sources: check C:/tmp/job/sources/INDEX.md before downloading; add a row per download.
- After each major step write C:/tmp/job/notes/A-<step>.md with references to the source
  (file:line, page). Out of budget: stop, write what you have, say what is left.
```

A source index row:

```
| file | url | format | page markers | fetched by | contents |
|---|---|---|---|---|---|
| bk1771.xml | https://... | OCR XML, 2.4 MB | <page n="..."> | B | vol. 2, pp. 1-480 |
```

## Resume or re-brief

Take the agent's context from its last task notification. A dead agent has none: run the
usage script below on its transcript (in Claude Code under
`~/.claude/projects/<project>/<session>/subagents/agent-<id>.jsonl`) and read `context_max`;
`context_last` is often 0 because the last request failed.

| Context | Remaining work | Do |
|---|---|---|
| up to ~50K tokens | any | Resume with `SendMessage`; say what is on disk and what is left. |
| larger | small | Do it yourself, or a new small brief for just that part. |
| larger | large | New budgeted brief that points to the dead agent's files on disk. |
| not measurable | any | Treat it as large. |

A resumed agent carries its old context into every later call, not just the first one, and
after a wait of more than five minutes its cache is cold.

## Two-tier review: quote matching

Mechanical first. A sketch the reviewer can adapt (quotes as JSON lines, source as text):

```python
# python -I match_quotes.py quotes.jsonl source.txt  ->  only the misses are printed
import json, re, sys, unicodedata
def norm(s):
    s = unicodedata.normalize("NFKC", s).lower()
    s = s.replace("ſ", "s").replace("’", "'").replace("“", '"').replace("”", '"')
    return re.sub(r"\W+", " ", s).strip()
src = norm(open(sys.argv[2], encoding="utf-8").read())
n = miss = 0
for line in open(sys.argv[1], encoding="utf-8"):
    q = json.loads(line)  # {"id": "Q12", "page": 214, "text": "..."}
    n += 1
    if norm(q["text"]) not in src:
        miss += 1; print(q["id"], q.get("page"), q["text"][:80])
print(f"{miss} of {n} quotes not found verbatim")
```

Then judgment only on the misses: OCR noise, a wrong page, or a real misquote.

## Token table

The field run, rebuilt from the transcripts:

```
| Agent | Model | Job | Tool calls | Duration | Final context | Processed | Status |
|---|---|---|---|---|---|---|---|
| A | sonnet | research vol. 1 | not reported | ~30 min | 541,185 (max) | 39,469,768 | died (429) |
| B | sonnet | research vol. 2 | 123+ | ~30 min | 461,962 (max) | 36,071,444 | died (429) |
| Wave 1 total | | | | | | 75,541,212 | |
| B2 | sonnet | vol. 2, re-brief | 39 | 34 min | 560,851 | 7,050,785 | done |
| kontrolcu | opus | fact check | 29 | 8 min | 196,443 | 2,856,088 | REVISE |
| Tokens per deliverable | | | | | | 85.4M for one fact-checked research package | |
| Conductor | opus | plan, briefs, synthesis | | | | not measured | |
```

Usage script for any transcript, your own session's included (Claude Code keeps it as JSONL
under `~/.claude/projects/<project>/`; the format is not documented, so label the numbers
"measured from transcript"):

```python
# python -I usage.py <transcript.jsonl> [...]
import json, sys
KEYS = ("input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens", "output_tokens")
for path in sys.argv[1:]:
    last = {}  # message id -> usage; one response can span several lines
    for line in open(path, encoding="utf-8", errors="replace"):
        try: d = json.loads(line)
        except ValueError: continue
        m = d.get("message") if isinstance(d, dict) else None
        if d.get("type") == "assistant" and isinstance(m, dict) and m.get("usage"):
            last[m.get("id") or len(last)] = m["usage"]
    ctx = [sum((u.get(k) or 0) for k in KEYS[:3]) for u in last.values()]
    total = sum(sum((u.get(k) or 0) for k in KEYS) for u in last.values())
    print(path, "responses", len(last), "processed", total,
          "context_last", ctx[-1] if ctx else 0, "context_max", max(ctx, default=0))
```

## Worktrees and background runs

- Claude Code's default cap is 20 concurrent sub-agents; `maxParallel` is the real cap.
- A worktree (`isolation: worktree`) starts from the default branch; uncommitted local work
  isn't there. `git stash` is shared by all worktrees.
- A background session that changed files in a worktree commits to its own branch before
  finishing and pushes if there is a remote; it follows the git instructions in `CLAUDE.md`.
  If the user commits themselves, put "don't commit, don't push" in both `CLAUDE.md` and the
  brief.

## Codex

- Codex opens sub-agents only when asked explicitly. Put the delegation into words ("open two
  sub-agents: one reviews this folder, the other that one"); the brief template is the same.
- Codex follows specs literally: write its briefs more explicitly and step by step than for
  Claude.
- Codex sub-agent models come from `~/.codex/agents/*.toml` (`model`) or the Codex default;
  orkestra doesn't write those files.
- When another agent launches a Codex lane with `codex exec`, end the command with
  `< /dev/null`; with stdin open the process hangs. Use `--output-schema` for structured
  returns.
- Budget: the Budget block goes into Codex briefs unchanged. The user-level knobs in
  `~/.codex/config.toml` are `agents.max_concurrent_threads_per_session` (concurrency;
  `max_threads` is the legacy name), `tool_output_token_limit` (how much of one tool output
  stays in history) and `model_auto_compact_token_limit` (when history is compacted).
  orkestra doesn't write them; suggest them to the user if Codex lanes keep growing.

## Earlier examples

- A brief said "11 closed threads"; the agent counted 5, and 5 was right. Briefs can carry
  wrong facts; agents work from their own measurement and say so.
- The first orkestra run repaired a memory system with four agents and a reviewer: two
  agents died mid-task and were resumed without losing work.
