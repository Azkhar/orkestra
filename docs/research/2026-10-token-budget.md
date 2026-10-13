# Token budgets for sub-agents: research notes (2026-10)

Background for orkestra 0.3.0. On 2026-10-13 two research sub-agents without a budget hit the
plan's usage limit in about 30 minutes (the field run is told in
[reference.md](../../skills/orkestra/reference.md#why-the-budget-rules)). These notes collect
what the official sources say about where the tokens go, plus what we measured ourselves.

**Method.** All official pages were downloaded once, on 2026-10-13, into a shared source cache
(the Markdown versions of the docs pages, the engineering post as stripped text). Two Sonnet
research agents with a budget searched that cache and wrote each finding with an exact quote;
a script then matched every quote verbatim against its cached page (66 of 66 and 79 of 79
matched), and the conductor re-checked the quotes behind every rule change. Local
measurements come from Claude Code transcripts on the maintainer's machine.

**Labels.** VERIFIED: exact quote found in the official page. MEASURED: our own measurement,
method given; the transcript format is not documented, so treat it as an observation of
Claude Code as of October 2026. ESTIMATE: arithmetic on verified numbers. UNVERIFIED: not
found in the official sources we read.

Every source below was read on 2026-10-13.

## Findings that changed the skill

| # | Finding | Label | Evidence | What changed |
|---|---|---|---|---|
| 1 | The token number in a task notification (`subagent_tokens`) is the agent's context size at the end, not its usage. The usage (every request summed) is 4-122 times larger, median 25. | MEASURED | M-1, M-2 below | Token table has two columns (final context, processed); the resume decision reads the final context; the field run's "560,851 tokens" was a context size, the agent processed 7.05M. |
| 2 | Every request carries the whole conversation; cached re-reads are cheaper per token but still draw usage. | VERIFIED | R1-Q2-7, R1-Q2-8 ([costs](https://code.claude.com/docs/en/costs)) | "A call budget is not a token budget" now rests on a documented mechanism. |
| 3 | A sub-agent has its own prompt cache with a five-minute lifetime, even on a subscription; its first request doesn't read the parent's cache. | VERIFIED | R1-Q4-1, R1-Q4-2 ([prompt caching](https://code.claude.com/docs/en/prompt-caching)) | Resume policy: after any wait longer than five minutes the whole context is read again uncached. |
| 4 | `maxTurns` in a sub-agent's frontmatter stops it after that many agentic turns; the output comes back marked partial and can be resumed. | VERIFIED | R1-Q6-6 ([sub-agents](https://code.claude.com/docs/en/sub-agents)) | The Budget block is called an instruction, not a brake; `kontrolcu` ships with `maxTurns: 60`. |
| 5 | The status line's JSON input carries `rate_limits.five_hour` / `seven_day` `used_percentage`; nothing lets the model read its remaining limit by itself. | VERIFIED / UNVERIFIED | R1-Q7-8 ([statusline](https://code.claude.com/docs/en/statusline)), R1-Q7-15 | Before and after a wave, read that percentage if the status line saves its JSON; otherwise estimate. |
| 6 | WebFetch hands the page to a separate model call with an extraction prompt and is "lossy by design". | VERIFIED | R1-Q5-1, R1-Q5-2 ([tools reference](https://code.claude.com/docs/en/tools-reference)) | Quotes and numbers come from a raw download in the source cache, searched with a script. |
| 7 | Anthropic's own research system scales effort in the prompt: 1 agent with 3-10 tool calls for simple fact-finding, 2-4 sub-agents with 10-15 calls each for comparisons. | VERIFIED | R2-Q4-5 ([multi-agent research system](https://www.anthropic.com/engineering/multi-agent-research-system)) | Profile budgets are ceilings; the brief sizes the budget to the job. |
| 8 | A cold sub-agent starts at about 40K tokens of context (median of 68 transcripts); `kontrolcu`, with four tools, started at 10,453-13,922. The docs state no number. | MEASURED / UNVERIFIED | M-3, R1-Q1-11 | Section 1 of SKILL.md gives the measured start-up cost. |

## Findings reported, no rule change

- **Multipliers** (R2-Q4-1, R2-Q4-3, R2-Q4-8, R2-Q4-9): "agents typically use about 4× more
  tokens than chat interactions, and multi-agent systems use about 15× more tokens than
  chats"; "token usage by itself explains 80% of the variance"; an Opus 4 lead with Sonnet 4
  sub-agents beat single-agent Opus 4 "by 90.2%" on Anthropic's internal research eval (older
  models). Agent teams in plan mode: about 7× a standard session (R1-Q2-4). These support the
  existing rule "decide first", they don't change it.
- **Plan limit accounting** (R1-Q2-1, R1-Q2-2, R1-Q2-9): sub-agent requests count toward the
  same usage limits as the main conversation; delegating saves the main context, not usage;
  `/usage` attributes usage to sub-agents. How a subscription plan weighs cache reads,
  cache writes and output: UNVERIFIED (not in the pages we read).
- **API cache prices** (R2-Q1-*): default TTL 5 minutes, a 1-hour option; cache write 1.25×
  base input (5 minutes), read 0.1× (0.05× on Opus 5.5 and Sonnet 5.5); minimum 512 tokens on
  the newest models; caches are isolated per workspace and never shared across organizations, so an
  account switch starts cold. API rate limits (ITPM) don't count cache reads on most models
  (R2-Q2-2); that is the API, not a subscription plan.
- **Images** (R2-Q3-1/2/3/9/11/14, R2-Q3-est): an image costs ⌈width/28⌉ × ⌈height/28⌉
  tokens, capped at 1,568 (standard tier, 1,568 px long edge) or 4,784 (Claude 4.7 and later,
  2,576 px). 51 scanned pages at the cap: 79,968 or 243,984 tokens once, and the same again on
  every later call while they stay in context (ESTIMATE: +1.2M or +3.7M over 15 more calls).
  Claude Code resizes large images before sending them. Supports the existing "no images
  unless asked".
- **Per-call caps already in Claude Code** (R1-Q5-3, R1-Q5-5, R1-Q6-4, R1-Q6-5): WebFetch
  reads at most 100,000 characters of a page; Bash output 30,000 characters by default
  (`BASH_MAX_OUTPUT_LENGTH`, max 150,000); Read 25,000 tokens; MCP output 25,000 tokens. The
  Budget block's ~2,000 characters per call is far tighter, by design.
- **Context limiters** (R1-Q3-8, R1-Q6-1, R2-Q5-*): auto-compaction applies to sub-agents with
  the same logic as the main conversation (`CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` lowers the
  trigger). The API has context editing (clear old tool results; default trigger 100,000
  input tokens, keeps the last 3 tool uses) and server-side compaction (beta); whether Claude
  Code exposes them: UNVERIFIED (R2-Q5-cc).
- **Sub-agent start-up content** (R1-Q1-1/4/5, R1-Q1-7): a sub-agent sees only its own prompt
  and the delegation message, plus CLAUDE.md files and git status (except the built-in Explore
  and Plan agents); only its final text and a small trailer with token counts and duration
  come back to the parent.
- **Resume and transcripts** (R1-Q3-2/3/5): `SendMessage` resumes an agent with its full
  history; sub-agent transcripts are kept under `~/.claude/projects/{project}/{sessionId}/subagents/`.
- **Codex** (R2-Q6-1..4): concurrency is `agents.max_concurrent_threads_per_session`
  (`max_threads` is a legacy alias); `tool_output_token_limit` caps what a tool output keeps
  in history; `model_auto_compact_token_limit` sets the auto-compaction threshold; OpenAI
  states that sub-agent workflows use more tokens than a single agent. A Codex setting for
  sub-agent depth or a per-agent call budget: UNVERIFIED (not found).
- **WebFetch model size** (R1-Q5-6): "a smaller model" for the extraction step: UNVERIFIED; the
  docs say only "a separate model call".

## Local measurements (MEASURED, 2026-10-13)

Method: Claude Code writes each session and each sub-agent as a JSONL transcript; every API
response carries `message.usage`. We summed `input_tokens + cache_creation_input_tokens +
cache_read_input_tokens + output_tokens` per response id ("processed") and took the last
response's context plus its output ("final context"). The scripts are in
[reference.md](../../skills/orkestra/reference.md#token-table).

- **M-1, notification vs transcript.** 69 sub-agent transcripts on the maintainer's machine,
  44 with a task notification (`<subagent_tokens>`) in the parent's transcript; 43 can be
  compared (in one, the last request failed). Notification ÷ final context: 1.000 to 1.012
  in all 43. Processed ÷ notification: min 4.3, median 24.5, max 122.5. Processed per API
  request: median about 102K tokens (50K to 351K). A first, looser pattern also caught
  three unrelated numbers; the reviewer flagged it, and the numbers here use the strict one.
- **M-2, the field run's own agents.** Wave 1, both died on HTTP 429 without a notification;
  measured from their transcripts: agent A 132 API responses, context up to 541,185,
  processed **39,469,768** (34 image blocks in its transcript); agent B 114 responses, context
  up to 461,962, processed **36,071,444**. The budgeted rerun: 21 API responses (39 tool calls),
  start 42,603, final context 560,851 (= its notification), processed **7,050,785**.
  `kontrolcu`: 30 responses, start 13,922, final context 196,443 (= its notification),
  processed **2,856,088**.
- **M-3, cold start.** Context of the first request, 68 transcripts: median 40,272 tokens,
  min 10,453, max 46,946. Agents with a short tool list sit at the low end.
- **M-4, this research.** R1: 30 requests, start 37,410, final context 163,186 (= its
  notification), processed 2,618,653. R2: 30 requests, start 37,501, final context 218,497
  (= its notification), processed 3,010,693. Review (`kontrolcu`): 27 requests, start
  10,453, final context 94,540, processed 1,349,845. All three stayed within their budget
  of 30 tool calls.

## A practical rule for the pre-wave estimate (question B5)

No tool lets a running session read its remaining plan limit (R1-Q7-15). Two routes:

1. **Measure.** If the user's status line saves its JSON input to a file, read
   `rate_limits.five_hour.used_percentage` before and after the first wave. The difference is
   the wave's real price on this plan; extrapolate for the next waves.
2. **Estimate.** Processed tokens per agent ≈ requests × (start + final context) / 2, with
   start ≈ 40K (≈ 10-14K with a short tool list) and final ≈ start + requests × growth per
   request; requests ≤ tool calls, since parallel calls share one. With the 2,000-character
   output cap, R1 grew about 4K per request, mostly from its own writing. Check against M-2
   and M-4: R1 predicts 30 × (37K + 163K) / 2 ≈ 3.0M (measured 2.6M); the rerun predicts
   21 × (43K + 561K) / 2 ≈ 6.3M (measured 7.05M).

## Open questions

- How a subscription plan weighs cache reads, cache writes and output tokens.
- Whether `maxTurns` counts API responses or tool calls (the docs say "agentic turns").
- "Notification = final context" is measured, not documented, and may change.
- Codex: a sub-agent depth setting, the default of `max_concurrent_threads_per_session`.

## Cost of this work

The token table of the 0.3.0 research and edit run, as the skill asks (section 8). Final
context is the task notification's number; processed is the transcript sum. The conductor's
row was measured just before this section was written, so its last few requests are
missing.

| Agent | Model | Job | Tool calls | Duration | Final context | Processed |
|---|---|---|---|---|---|---|
| R1 | sonnet | research: Claude Code docs | 30 | 13.7 min | 163,186 | 2,618,653 |
| R2 | sonnet | research: API, vision, engineering post, Codex | 30 | 20.3 min | 218,497 | 3,010,693 |
| Wave 1 (parallel) | | | 60 | | | 5,629,346 |
| kontrolcu | opus | review of the change set | 29 | 10.9 min | 94,540 | 1,349,845 |
| Conductor | opus | plan, source cache, edits, synthesis, checks | 85 | 53 min | 271,693 | 10,524,926 |
| Total | | | 174 | | | 17,504,117 |
| Tokens per deliverable | | 1 accepted change set (0.3.0) | | | | 17,504,117 |

## Appendix: findings with quotes

Selected from the two research agents' notes (65 of 150 findings). The "For orkestra" lines
are the agents' own readings; where they differ from the summary above, notably on what the
notification's token count means (M-1), the summary wins. For UNVERIFIED findings the source
line says where we searched. Links inside quotes are reduced to their text.

### Claude Code docs (research agent R1)

#### R1-Q1-1: A non-fork sub-agent starts with a fresh, isolated context and does not see the parent conversation
- Quote: "Each subagent starts with a fresh, isolated context window. It doesn't see your conversation history, the skills you've already invoked, or the files Claude has already read."
- Source: https://code.claude.com/docs/en/sub-agents, read 2026-10-13
- Status: VERIFIED
- For orkestra (our reading): the brief must carry everything the worker needs (paths, constraints, output format); do not assume it knows what the conductor already read.

#### R1-Q1-4: CLAUDE.md files and git status load into every sub-agent except the built-in Explore and Plan
- Quote: "Explore and Plan skip your CLAUDE.md files and the git status snapshot to keep research fast and inexpensive."
- Source: https://code.claude.com/docs/en/sub-agents, read 2026-10-13
- Status: VERIFIED
- For orkestra (our reading): every general-purpose or custom worker pays for the full CLAUDE.md chain + git status at start; for read-only research prefer Explore or set `omitClaudeMd: true`.

#### R1-Q1-5: Which CLAUDE.md levels reach the sub-agent (the user's global ~/.claude/CLAUDE.md included)
- Quote: "**CLAUDE.md files**: every level of the CLAUDE.md hierarchy the main conversation loads, including `~/.claude/CLAUDE.md`, project rules, `CLAUDE.local.md`, managed policy files"
- Source: https://code.claude.com/docs/en/sub-agents, read 2026-10-13
- Status: VERIFIED
- For orkestra (our reading): global and project CLAUDE.md size is multiplied by the number of sub-agents spawned.

#### R1-Q1-7: Only the final text and a small metadata trailer return to the parent
- Quote: "Only the subagent's final text response comes back to your context, plus a small metadata trailer with token counts and duration."
- Source: https://code.claude.com/docs/en/context-window, read 2026-10-13
- Status: VERIFIED
- For orkestra (our reading): the conductor's context only grows by the report length; cap report size in the brief (the worker's own tokens are spent elsewhere, see Q2).

#### R1-Q1-11: A stated fixed start-up cost (token number) for a sub-agent
- Quote: (none)
- Source: searched cc-sub-agents.md and cc-context-window.md for "startup cost", "fixed cost", "overhead", "subagent...token"; no fixed per-sub-agent token figure is stated (only an illustrative widget: 6,100 tokens read / 420-token result, and a 15,000-token description-warning threshold), read 2026-10-13
- Status: UNVERIFIED
- For orkestra (our reading): do not hard-code a start-up number in the skill; say "start-up cost is unstated, measured per run".
- Searched / based on (read 2026-10-13): https://code.claude.com/docs/en/context-window, https://code.claude.com/docs/en/sub-agents

#### R1-Q2-1: A sub-agent sends its own requests, and they count toward the same usage limits as the main conversation
- Quote: "It also sends its own requests, which count toward the same usage limits as your main conversation."
- Source: https://code.claude.com/docs/en/sub-agents, read 2026-10-13
- Status: VERIFIED
- For orkestra (our reading): parallel workers draw on one shared plan limit; spawning N workers does not give N separate budgets.

#### R1-Q2-2: Delegating verbose work saves the main context, not usage
- Quote: "The subagent's own requests still draw on your usage."
- Source: https://code.claude.com/docs/en/costs, read 2026-10-13
- Status: VERIFIED
- For orkestra (our reading): delegation is a context-hygiene tool, not a token saver; the docs' own cost lever is a smaller model for the sub-agent.

#### R1-Q2-4: Stated multiplier - agent teams use approximately 7x more tokens than standard sessions (plan mode)
- Quote: "Agent teams use approximately 7x more tokens than standard sessions when teammates run in plan mode, because each teammate maintains its own context window and runs as a separate Claude instance."
- Source: https://code.claude.com/docs/en/costs, read 2026-10-13
- Status: VERIFIED
- For orkestra (our reading): the only numeric multiplier in the docs is for agent teams (7x, plan mode); there is no stated multiplier for ordinary sub-agents. Orkestra uses Agent-tool sub-agents, not agent teams.

#### R1-Q2-7: Every request carries the full conversation; every tool call is another request
- Quote: "Claude Code sends your full conversation with every request, and each time Claude uses tools it sends another request carrying that batch of tool results."
- Source: https://code.claude.com/docs/en/costs, read 2026-10-13
- Status: VERIFIED
- For orkestra (our reading): supports the hypothesis "tokens ~ calls x context length": a worker's usage is roughly the sum, over its tool calls, of the context size at that call, so it grows faster than linearly when each call appends big output. Cap tool-call count and per-call output size.

#### R1-Q2-8: Cached re-reads are cheaper per token but still draw plan usage for the whole conversation
- Quote: "With prompt caching, Claude Code re-reads that history at the [cached token rate](https://platform.claude.com/docs/en/about-claude/pricing), so a one-line question in a session that has been open all day still draws usage for the whole conversation."
- Source: https://code.claude.com/docs/en/costs, read 2026-10-13
- Status: VERIFIED
- For orkestra (our reading): do not assume caching makes long worker contexts free; keep each worker's context short and its call count low.

#### R1-Q2-9: Attribution of plan usage to sub-agents is visible in /usage
- Quote: "**Attribution**: recent usage attributed to skills, subagents, plugins, and individual MCP servers, each shown as a percentage of the total."
- Source: https://code.claude.com/docs/en/costs, read 2026-10-13
- Status: VERIFIED
- For orkestra (our reading): after a run, the user can read the sub-agent share in /usage (see Q7).

#### R1-Q3-2: Resume goes through SendMessage with the agent ID or name
- Quote: "Claude uses the `SendMessage` tool with the agent's ID or name as the `to` field to resume it."
- Source: https://code.claude.com/docs/en/sub-agents, read 2026-10-13
- Status: VERIFIED
- For orkestra (our reading): the conductor can continue a worker by ID; the brief for the resume turn only needs the new instruction.

#### R1-Q3-3: A resumed sub-agent keeps its full conversation history
- Quote: "Resumed subagents retain their full conversation history, including all previous tool calls, results, and reasoning."
- Source: https://code.claude.com/docs/en/sub-agents, read 2026-10-13
- Status: VERIFIED
- For orkestra (our reading): resuming re-loads the entire old context (every later request carries it, see R1-Q2-7); the docs state no separate re-load cost. Resume only a small or still-needed context; otherwise spawn a fresh worker with a short brief.

#### R1-Q3-5: Where sub-agent transcripts live
- Quote: "You can also ask Claude for the agent ID if you want to reference it explicitly, or find IDs in the transcript files at `~/.claude/projects/{project}/{sessionId}/subagents/`. Each transcript is stored as `agent-{agentId}.jsonl`."
- Source: https://code.claude.com/docs/en/sub-agents, read 2026-10-13
- Status: VERIFIED
- For orkestra (our reading): the conductor can inspect a worker's real context growth from its .jsonl after the run (measure, don't guess).

#### R1-Q3-8: Auto-compaction applies to sub-agents with the same logic as the main conversation
- Quote: "Subagents support automatic compaction using the same logic as the main conversation. Compaction triggers under the same conditions, and `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` applies to subagents as well."
- Source: https://code.claude.com/docs/en/sub-agents, read 2026-10-13
- Status: VERIFIED
- For orkestra (our reading): a long worker does not fail on context overflow, but compaction itself costs a summarisation request and does not reduce the call count; limit calls instead of relying on compaction.

#### R1-Q4-1: A sub-agent warms a cache of its own; it does not read the parent's cache
- Quote: "A subagent starts its own conversation with its own system prompt and tool set, separate from the parent's. Its first request doesn't read the parent's cache, because the two prefixes differ, and it warms a cache of its own across its turns."
- Source: https://code.claude.com/docs/en/prompt-caching, read 2026-10-13
- Status: VERIFIED
- For orkestra (our reading): every new worker's first request is a full uncached read of its start-up context; many short-lived workers mean many cold starts.

#### R1-Q4-2: Sub-agents get a five-minute TTL even on a subscription (unless the TTL is chosen)
- Quote: "Subagents fall outside the main-conversation TTL bucket, so they get five minutes even on a subscription until you choose a longer one."
- Source: https://code.claude.com/docs/en/prompt-caching, read 2026-10-13
- Status: VERIFIED
- For orkestra (our reading): a worker that pauses more than five minutes between requests (long build, long wait) pays a full uncached re-read of its whole context on the next request; keep workers' tool calls short, and resume a worker within five minutes if its context is big.

#### R1-Q4-10: Per-sub-agent TTL knob in frontmatter
- Quote: "For a subagent's requests, the `cacheTtl` value in the subagent's `experimental` frontmatter field"
- Source: https://code.claude.com/docs/en/prompt-caching, read 2026-10-13
- Status: VERIFIED
- For orkestra (our reading): custom agents (the kontrolcu agent, for example) can set their own cache TTL in frontmatter; the version requirement is on the doc page.

#### R1-Q4-12: Per-bucket TTL controls for sub-agent (and other non-main) requests
- Quote: "**Everything else**: the `subagentPromptCacheTtl` setting, or the `CLAUDE_CODE_SUBAGENT_PROMPT_CACHE_TTL` environment variable"
- Source: https://code.claude.com/docs/en/prompt-caching, read 2026-10-13
- Status: VERIFIED
- For orkestra (our reading): these are user/settings knobs (each takes 5m or 1h per line 279 of the page); the skill can mention them but cannot change them mid-run. The page says the five-minute TTL charges a lower rate for cache writes (line 275), so 1h is a trade-off, not a free win.

#### R1-Q5-1: WebFetch runs the prompt in a separate model call; Claude receives that result, not the raw page
- Quote: "For most fetches, it then runs the prompt against the content in a separate model call, and Claude receives the result of that call rather than the raw page."
- Source: https://code.claude.com/docs/en/tools-reference, read 2026-10-13
- Status: VERIFIED
- For orkestra (our reading): WebFetch keeps raw HTML/Markdown out of the worker's context (only the extracted answer enters), so for web pages prefer WebFetch with a precise extraction prompt over curl|cat.

#### R1-Q5-2: The docs call WebFetch lossy by design
- Quote: "This makes WebFetch lossy by design. The extraction prompt determines what reaches Claude,"
- Source: https://code.claude.com/docs/en/tools-reference, read 2026-10-13
- Status: VERIFIED
- For orkestra (our reading): when exact wording matters (quotes, numbers), the brief must tell the worker to ask for verbatim passages in the extraction prompt, or fetch the raw file to disk and grep it.

#### R1-Q5-3: WebFetch reads at most 100,000 characters of a page per call
- Quote: "WebFetch reads up to 100,000 characters of a page's content per call."
- Source: https://code.claude.com/docs/en/tools-reference, read 2026-10-13
- Status: VERIFIED
- For orkestra (our reading): long pages are cut at 100,000 characters before extraction; large docs need targeted fetches or a local download plus grep.

#### R1-Q5-5: Bash output is capped at BASH_MAX_OUTPUT_LENGTH characters (default 30000, max 150000)
- Quote: "`BASH_MAX_OUTPUT_LENGTH` | Maximum number of characters of bash output that Claude Code reads back into a command's result (default: 30000; maximum: 150000)."
- Source: https://code.claude.com/docs/en/env-vars, read 2026-10-13
- Status: VERIFIED
- For orkestra (our reading): one unfiltered Bash call can still add up to 30,000 characters to the context, and every later request re-sends it; filter in the command (grep, head -c, a script that prints a short summary).

#### R1-Q5-6: WebFetch uses a "smaller model" for the extraction step
- Quote: (none)
- Source: searched cc-tools-reference.md for "extraction model", "smaller", "small model", "fast model", "haiku"; the WebFetch section (lines 600-642) only says "a separate model call" and names no model or size (hits at lines 254, 583, 653, 674 are unrelated). No doc text compares WebFetch with curl; the documented facts are R1-Q5-1..5. Read 2026-10-13
- Status: UNVERIFIED
- For orkestra (our reading): do not claim "WebFetch uses Haiku"; say only that the page is processed in a separate model call and Claude receives that result.
- Searched / based on (read 2026-10-13): https://code.claude.com/docs/en/tools-reference

#### R1-Q6-1: CLAUDE_AUTOCOMPACT_PCT_OVERRIDE lowers the auto-compact trigger (applies to sub-agents too, R1-Q3-8)
- Quote: "`CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` | Set the percentage (1-100) of the auto-compact window at which auto-compaction triggers. Use lower values like `50` to compact earlier;"
- Source: https://code.claude.com/docs/en/env-vars, read 2026-10-13
- Status: VERIFIED
- For orkestra (our reading): a user-side env var; the skill can suggest it but a running session cannot set it. The docs do not say how compaction changes total tokens used.

#### R1-Q6-4: MCP tool output cap (default 25000 tokens, warning above 10,000)
- Quote: "`MAX_MCP_OUTPUT_TOKENS` | Maximum number of tokens allowed in MCP tool responses (default: 25000). Claude Code displays a warning when output exceeds 10,000 tokens."
- Source: https://code.claude.com/docs/en/env-vars, read 2026-10-13
- Status: VERIFIED
- For orkestra (our reading): one MCP call can add up to 25000 tokens to a worker's context; prefer MCP calls that accept a filter or limit parameter.

#### R1-Q6-5: A single Read call returns at most 25,000 tokens by default
- Quote: "By default one call returns at most 25,000 tokens, or the value you set in `CLAUDE_CODE_FILE_READ_MAX_OUTPUT_TOKENS`,"
- Source: https://code.claude.com/docs/en/tools-reference, read 2026-10-13
- Status: VERIFIED
- For orkestra (our reading): reading a big file in 25k-token pieces adds each piece to the context permanently; use grep/ranges. Bash has its own cap, see R1-Q5-5.

#### R1-Q6-6: Sub-agent frontmatter field maxTurns stops the sub-agent and marks its output partial
- Quote: "Maximum number of agentic turns before the subagent stops. When the subagent reaches the limit, Claude Code returns its output marked as partial"
- Source: https://code.claude.com/docs/en/sub-agents, read 2026-10-13
- Status: VERIFIED
- For orkestra (our reading): the one hard per-worker brake in the docs; since tokens grow with calls x context, a maxTurns cap bounds worst-case spend. Only available for custom agent definitions (frontmatter), not for an ad-hoc Agent call.

#### R1-Q7-1: /usage shows session cost, plan usage limits and activity stats (user-typed command)
- Quote: "Show session cost, plan usage limits, and activity stats."
- Source: https://code.claude.com/docs/en/commands, read 2026-10-13
- Status: VERIFIED
- For orkestra (our reading): this is where plan-limit percentages are visible, but it is a slash command the user types; the docs do not give the model a way to run it.

#### R1-Q7-8: The status line JSON carries 5-hour and 7-day plan-limit fields (rate_limits)
- Quote: "`rate_limits.five_hour.used_percentage`, `rate_limits.seven_day.used_percentage` | Percentage of the 5-hour or 7-day rate limit consumed, from 0 to 100"
- Source: https://code.claude.com/docs/en/statusline, read 2026-10-13
- Status: VERIFIED
- For orkestra (our reading): the only documented non-slash-command source of plan-limit percentages found; availability conditions are in the quoted row. A status line script could write them to a file the conductor reads with Bash (my inference, not doc text).

#### R1-Q7-13: The token usage metric can be broken down per agent
- Quote: "`claude_code.token.usage` | Break down by token `type`, user, team, model, `skill.name`, `plugin.name`, or `agent.name`"
- Source: https://code.claude.com/docs/en/monitoring-usage, read 2026-10-13
- Status: VERIFIED
- For orkestra (our reading): per-agent attribution exists in telemetry (agent.name), so a worker's share can be measured after a run if telemetry is enabled.

#### R1-Q7-14: The Agent tool result gives the parent a token-count and duration trailer for each sub-agent
- Quote: "Only the subagent's final text response comes back to your context, plus a small metadata trailer with token counts and duration."
- Source: https://code.claude.com/docs/en/context-window, read 2026-10-13
- Status: VERIFIED
- For orkestra (our reading): the one in-session way found for the conductor to read a worker's token count without a user command; log it per worker after every call.

#### R1-Q7-15: The model (a running session) reading its own remaining plan limit without a user-typed command
- Quote: (none)
- Source: searched cc-tools-reference.md (0 lines match rate limit|usage limit|plan usage|remaining tokens|token usage, lines , not inspected one by one), cc-commands.md, cc-statusline.md and cc-costs.md; found only user-run slash commands (R1-Q7-1..3), status line JSON for a user-configured command, OpenTelemetry export, and the per-sub-agent result trailer (R1-Q7-14); no documented tool or API through which the model itself reads plan limits was found in the pages read. Read 2026-10-13
- Status: UNVERIFIED
- For orkestra (our reading): the skill cannot assume the conductor can read the remaining plan limit; it should ask the user to run /usage, or rely on per-worker token counts from the Agent result trailer.
- Searched / based on (read 2026-10-13): https://code.claude.com/docs/en/commands, https://code.claude.com/docs/en/costs, https://code.claude.com/docs/en/statusline, https://code.claude.com/docs/en/tools-reference


### Claude API docs, engineering post, Codex docs (research agent R2)

#### R2-Q1-1: Default cache TTL is 5 minutes; each use refreshes it for free
- Quote: "By default, the cache has a 5-minute lifetime. The cache is refreshed for no additional cost each time the cached content is used."
- Source: https://platform.claude.com/docs/en/build-with-claude/prompt-caching, read 2026-10-13
- Status: VERIFIED (exact quote found)
- For orkestra (our reading): A prefix stays warm only while calls arrive less than 5 min apart; an idle gap over 5 min means a cold restart (full 1.25x write again).

#### R2-Q1-5: 5-minute cache write costs 1.25x base input price
- Quote: "5-minute cache write tokens are 1.25 times the base input tokens price"
- Source: https://platform.claude.com/docs/en/build-with-claude/prompt-caching, read 2026-10-13
- Status: VERIFIED (exact quote found)
- For orkestra (our reading): A prefix used only once costs 1.25x instead of 1x; from the second use on it is cheaper (1.25+0.1 = 1.35x vs 2x for two calls).

#### R2-Q1-7: Cache read costs 0.1x base input price by default (per-model exceptions in footnotes)
- Quote: "Cache read tokens are 0.1 times the base input tokens price (see the table footnote for per-model exceptions)"
- Source: https://platform.claude.com/docs/en/build-with-claude/prompt-caching, read 2026-10-13
- Status: VERIFIED (exact quote found)
- For orkestra (our reading): Re-reading a long cached context is cheap per call but not free; total cost still grows with the number of calls.

#### R2-Q1-8: Exception: Opus 5.5 and Sonnet 5.5 cache reads are 0.05x base
- Quote: "Cache hits and refreshes on Claude Opus 5.5 and Claude Sonnet 5.5 are priced at 0.05x the base input price."
- Source: https://platform.claude.com/docs/en/build-with-claude/prompt-caching, read 2026-10-13
- Status: VERIFIED (exact quote found)
- For orkestra (our reading): On Sonnet 5.5 / Opus 5.5 a cache hit costs 0.05x base input (1/20).

#### R2-Q1-16: Changing the effort setting invalidates the message cache
- Quote: "Changing the `output_config.effort` value always invalidates message blocks"
- Source: https://platform.claude.com/docs/en/build-with-claude/prompt-caching, read 2026-10-13
- Status: VERIFIED (exact quote found)
- For orkestra (our reading): Switching effort mid-conversation re-bills the conversation history at full price.

#### R2-Q1-17: Changing thinking parameters invalidates the message cache
- Quote: "The thinking configuration (mode, and `budget_tokens` in extended mode) is rendered into the prompt, so changing it always invalidates message blocks"
- Source: https://platform.claude.com/docs/en/build-with-claude/prompt-caching, read 2026-10-13
- Status: VERIFIED (exact quote found)
- For orkestra (our reading): Do not toggle thinking mode mid-conversation.

#### R2-Q1-19: Caches are isolated per workspace (Claude API) within an organization
- Quote: "Prompt caching uses workspace-level isolation. Caches are isolated per workspace, ensuring data separation between workspaces within the same organization."
- Source: https://platform.claude.com/docs/en/build-with-claude/prompt-caching, read 2026-10-13
- Status: VERIFIED (exact quote found)
- For orkestra (our reading): A key/workspace switch loses the cache even inside one organization.

#### R2-Q1-20: Caches are never shared across organizations
- Quote: "Caches are isolated between organizations. Different organizations never share caches, even if they use identical prompts."
- Source: https://platform.claude.com/docs/en/build-with-claude/prompt-caching, read 2026-10-13
- Status: VERIFIED (exact quote found)
- For orkestra (our reading): INFERENCE: switching to an account in another organization starts with a cold cache (full write again). The page speaks of API orgs/workspaces; consumer-plan accounts are not covered.

#### R2-Q2-2: Cache reads do not count, cache writes and input_tokens do
- Quote: "For rate limit purposes on most models, only `input_tokens` + `cache_creation_input_tokens` count toward your ITPM limit, making prompt caching an effective way to increase your effective throughput."
- Source: https://platform.claude.com/docs/en/api/rate-limits, read 2026-10-13
- Status: VERIFIED (exact quote found)
- For orkestra (our reading): The first pass over 51 images counts fully (input or cache write); only later re-reads of the cached prefix are free against ITPM.

#### R2-Q3-1: Official image token formula: 28x28-pixel patches, one visual token per patch
- Quote: "Claude views images in patches instead of pixels. Each patch is a 28×28-pixel block of the image, referred to as a visual token. An image, therefore, costs `⌈width / 28⌉ × ⌈height / 28⌉` visual tokens."
- Source: https://platform.claude.com/docs/en/build-with-claude/vision, read 2026-10-13
- Status: VERIFIED (exact quote found)
- For orkestra (our reading): Token count depends on pixel dimensions only, not on JPG file size; a 2 MB scan and a 0.4 MB scan of the same pixel size cost the same.

#### R2-Q3-2: High-resolution tier (Claude 4.7 and later models): max 2576 px long edge, 4784 visual tokens
- Quote: "High-resolution | Claude 4.7 and later models | 2576 px | 4784"
- Source: https://platform.claude.com/docs/en/build-with-claude/vision, read 2026-10-13
- Status: VERIFIED (exact quote found)
- For orkestra (our reading): On Claude 4.7+ models plan for up to about 4,784 tokens per image.

#### R2-Q3-3: Standard tier (all other models): max 1568 px long edge, 1568 visual tokens
- Quote: "Standard | All other models | 1568 px | 1568"
- Source: https://platform.claude.com/docs/en/build-with-claude/vision, read 2026-10-13
- Status: VERIFIED (exact quote found)
- For orkestra (our reading): On older models plan for up to about 1,568 tokens per image.

#### R2-Q3-9: More than 20 images in one request triggers a stricter per-image dimension limit
- Quote: "If a single API request contains more than 20 images, a stricter per-image dimension limit applies to every image in that request."
- Source: https://platform.claude.com/docs/en/build-with-claude/vision, read 2026-10-13
- Status: VERIFIED (exact quote found)
- For orkestra (our reading): 51 page images in one conversation exceed the 20-image threshold.

#### R2-Q3-11: Way to stay under the stricter limit: neither dimension above 2000 px, or at most 20 images
- Quote: "To stay under the limit on all platforms, either resize each image so that neither dimension exceeds 2000 px, or keep the request to 20 or fewer image and document blocks."
- Source: https://platform.claude.com/docs/en/build-with-claude/vision, read 2026-10-13
- Status: VERIFIED (exact quote found)
- For orkestra (our reading): Rule candidate: at most 20 images per agent context, or downsize every scan to 2000 px or less.

#### R2-Q3-14: Claude Code resizes and recompresses large images before sending them to the model
- Quote: "Claude Code resizes and recompresses large images to fit the model's image size limits before sending them, so Claude may see a downscaled version of a large screenshot."
- Source: https://code.claude.com/docs/en/tools-reference, read 2026-10-13
- Status: VERIFIED (exact quote found)
- For orkestra (our reading): In Claude Code the per-image token count stays under the tier cap (R2-Q3-2, R2-Q3-3) and raw file size matters less than image count; token traffic from many images still accumulates (R2-Q3-est).

#### R2-Q3-est: ESTIMATE: 51 scanned page JPGs in one agent context, then 15 more tool calls
- Status: ESTIMATE (computed from the quoted formula, tier limits and prices; not a source quote)
- Assumptions: N = 51 scans; pixel size unknown but larger than the resize limit, so every image is capped at the tier maximum (R2-Q3-2, R2-Q3-3); the JPG file size (0.4-2.2 MB) does not change the token count; prices = Sonnet 5.5 row of the caching table: $2 base input, $2.50 5m cache write, $0.10 cache read per MTok (R2-Q1-8).
- Per image (cap): standard tier 1,568 tokens; high-resolution tier (Claude 4.7 and later models) 4,784 tokens. A scan below the cap costs ceil(w/28)*ceil(h/28), e.g. 1500x2200 px = 54*79 = 4,266 tokens on the high-res tier (capped at 1,568 on the standard tier).
- (1) Images once: 51 x 1,568 = 79,968 tokens (standard); 51 x 4,784 = 243,984 tokens (high-res).
- (2) Extra if the 51 images stay in context for 15 more tool calls (each call re-sends them): 15 x 79,968 = 1,199,520 tokens (standard); 15 x 243,984 = 3,659,760 tokens (high-res).
- (3) If the pages were opened one per tool call, request k+1 re-sends the k-1 earlier images: T x (1+2+...+50) = T x 1,275 = 1,999,200 (standard) / 6,099,600 (high-res) tokens of re-sends before the 15 extra calls. Total image-token traffic = 51T + 1,275T + 765T = 2,091T = 3,278,688 (standard) / 10,003,344 (high-res).
- Priced on Sonnet 5.5 (first appearance as 5m cache write, every re-send as cache read): whole run $0.52 (standard) / $1.59 (high-res); item (2) alone $0.12 / $0.37. If the cache misses (TTL expired or prefix changed, R2-Q1-1, R2-Q1-15, R2-Q1-16) the same traffic bills at $2/MTok: whole run $6.56 / $20.01; item (2) alone $2.40 / $7.32. Opus 5.5 is exactly 2x these dollar figures (R2-Q1 pricing table: $4 / $5 / $0.20).
- Size check: 51 x 0.4 MB = 20.4 MB up to 51 x 2.2 MB = 112.2 MB of JPG bytes; the quoted request-size limit is 32 MB on standard endpoints (R2-Q3-12), reached at an average of 32/51 = 0.63 MB per file (before any base64 overhead, which the cached docs do not quantify). Claude Code itself resizes and recompresses large images before sending (R2-Q3-14), so this raw-size check mostly applies to direct API use.
- Compare with the field rerun (conductor-measured fact): 560,851 tokens in 39 tool calls. Image-token traffic alone here is 3,278,688 (standard) / 10,003,344 (high-res) tokens = 5.8x / 17.8x of that figure when every re-send is counted at full size. How plan limits weigh cache reads is not described in the cached API docs (R2-Q2 covers API ITPM only).
- For orkestra (our reading): image cost grows quadratically when pages are opened one per call and stay in context; cap images per agent, downsample first (R2-Q3-8), or split pages across fresh sub-agents (one batch each) instead of one agent holding all 51.
- Searched / based on (read 2026-10-13): https://platform.claude.com/docs/en/build-with-claude/vision, https://platform.claude.com/docs/en/build-with-claude/prompt-caching

#### R2-Q4-1: (a) Token multipliers: agents about 4x chat, multi-agent systems about 15x chat
- Quote: "In our data, agents typically use about 4× more tokens than chat interactions, and multi-agent systems use about 15× more tokens than chats."
- Source: https://www.anthropic.com/engineering/multi-agent-research-system, read 2026-10-13
- Status: VERIFIED (exact quote found)
- For orkestra (our reading): Budget a multi-agent run at roughly 15x a chat session (single agent about 4x); parallelism is a token multiplier, not a saver.

#### R2-Q4-3: (b) Token usage alone explains 80% of the variance
- Quote: "We found that token usage by itself explains 80% of the variance, with the number of tool calls and the model choice as the two other explanatory factors."
- Source: https://www.anthropic.com/engineering/multi-agent-research-system, read 2026-10-13
- Status: VERIFIED (exact quote found)
- For orkestra (our reading): A hard token cap is also a quality cap on research-style tasks; set it knowingly.

#### R2-Q4-5: (c) Effort-scaling rules embedded in the prompt (agents and tool calls by query complexity)
- Quote: "Simple fact-finding requires just 1 agent with 3-10 tool calls, direct comparisons might need 2-4 subagents with 10-15 calls each, and complex research might use more than 10 subagents with clearly divided responsibilities."
- Source: https://www.anthropic.com/engineering/multi-agent-research-system, read 2026-10-13
- Status: VERIFIED (exact quote found)
- For orkestra (our reading): Ready-made effort tiers for the conductor brief: simple = 1 agent, 3-10 tool calls; comparison = 2-4 subagents, 10-15 calls each; complex = 10+ subagents with divided scopes.

#### R2-Q4-8: (d) Opus 4 lead + Sonnet 4 subagents beat single-agent Opus 4 by 90.2% on the internal research eval
- Quote: "We found that a multi-agent system with Claude Opus 4 as the lead agent and Claude Sonnet 4 subagents outperformed single-agent Claude Opus 4 by 90.2% on our internal research eval."
- Source: https://www.anthropic.com/engineering/multi-agent-research-system, read 2026-10-13
- Status: VERIFIED (exact quote found)
- For orkestra (our reading): Strong lead plus cheaper workers is the measured best config, but on read-heavy research tasks; the post gives no token-cost figure for this config.

#### R2-Q4-9: (e) Economic viability: task value must pay for the extra tokens
- Quote: "For economic viability, multi-agent systems require tasks where the value of the task is high enough to pay for the increased performance."
- Source: https://www.anthropic.com/engineering/multi-agent-research-system, read 2026-10-13
- Status: VERIFIED (exact quote found)
- For orkestra (our reading): Split into sub-agents only when the task value justifies about 15x tokens; otherwise run one agent.

#### R2-Q5-2: Context editing trigger: default 100,000 input tokens (or a tool_uses count)
- Quote: "trigger | 100,000 input tokens | Defines when the context editing strategy activates. Once the prompt exceeds this threshold, clearing begins."
- Source: https://platform.claude.com/docs/en/build-with-claude/context-editing, read 2026-10-13
- Status: VERIFIED (exact quote found)
- For orkestra (our reading): Nothing is cleared below 100,000 input tokens unless the trigger is lowered; a tighter trigger is the budget knob.

#### R2-Q5-3: Context editing keep: default keeps the 3 most recent tool use/result pairs
- Quote: "keep | 3 tool uses | Defines how many recent tool use/result pairs to keep after clearing occurs."
- Source: https://platform.claude.com/docs/en/build-with-claude/context-editing, read 2026-10-13
- Status: VERIFIED (exact quote found)
- For orkestra (our reading): After clearing, only the last 3 tool results remain unless keep is changed.

#### R2-Q5-8: Server-side compaction: older turns are replaced by a summary Claude writes on the server
- Quote: "Compaction replaces the older turns of a conversation with a summary that Claude writes on the server, so you need no summarization code of your own."
- Source: https://platform.claude.com/docs/en/build-with-claude/compaction, read 2026-10-13
- Status: VERIFIED (exact quote found)
- For orkestra (our reading): API-side summarization of old turns; keeps long agent tasks inside the context window.

#### R2-Q5-9: Compaction has two modes: on demand (you decide) and at a token threshold (the API decides)
- Quote: "Who decides when | You, by sending a request | The API, when input tokens reach the trigger you set"
- Source: https://platform.claude.com/docs/en/build-with-claude/compaction, read 2026-10-13
- Status: VERIFIED (exact quote found)
- For orkestra (our reading): Token-threshold mode is the automatic one: set the trigger as the context budget.

#### R2-Q5-10: Compaction on demand: beta header compact-2026-09-04 and the top-level compaction parameter
- Quote: "Beta header, parameter, and platforms | compact-2026-09-04 and the top-level compaction parameter."
- Source: https://platform.claude.com/docs/en/build-with-claude/compaction, read 2026-10-13
- Status: VERIFIED (exact quote found)
- For orkestra (our reading): Needs the beta header plus the compaction parameter in the request.

#### R2-Q5-11: Both compaction modes are in beta
- Quote: "While both it and Compaction at a token threshold are in beta"
- Source: https://platform.claude.com/docs/en/build-with-claude/compaction, read 2026-10-13
- Status: VERIFIED (exact quote found)
- For orkestra (our reading): Treat as beta: availability and behavior can change.

#### R2-Q5-cc: Does Claude Code expose API context editing or server-side compaction?
- Quote: none found
- Source: https://code.claude.com/docs/en (11 cached cc-*.md pages), read 2026-10-13
- Status: UNVERIFIED (searched: grep -i for: context editing, clear_tool_uses, context_management, server-side compaction across all cached Claude Code pages (cc-*.md): no matches. Claude Code's own /compact and auto-compact are separate client features; the cached pages do not say it exposes the API features.)
- For orkestra (our reading): Do not tell the skill that Claude Code can set these API options; they are API-level (Messages API) features.

#### R2-Q6-1: Codex: sub-agent concurrency cap key is agents.max_concurrent_threads_per_session (max_threads is a legacy alias)
- Quote: "Legacy alias for agents.max_concurrent_threads_per_session."
- Source: https://developers.openai.com/codex/config-reference, read 2026-10-13
- Status: VERIFIED (exact quote found)
- For orkestra (our reading): Codex sub-agent budget knob: the cap on concurrently open agent threads per session.

#### R2-Q6-2: Codex: tool_output_token_limit caps the tokens stored per tool output in history
- Quote: "Token budget for storing individual tool/function outputs in history."
- Source: https://developers.openai.com/codex/config-reference, read 2026-10-13
- Status: VERIFIED (exact quote found)
- For orkestra (our reading): Codex equivalent of capping tool-result size (setting key tool_output_token_limit).

#### R2-Q6-3: Codex: model_auto_compact_token_limit is the token threshold for automatic history compaction
- Quote: "Token threshold that triggers automatic history compaction (unset uses model defaults)."
- Source: https://developers.openai.com/codex/config-reference, read 2026-10-13
- Status: VERIFIED (exact quote found)
- For orkestra (our reading): Codex equivalent of an auto-compaction budget (setting key model_auto_compact_token_limit).

#### R2-Q6-4: OpenAI states subagent workflows consume more tokens than single-agent runs
- Quote: "Because each subagent does its own model and tool work, subagent workflows consume more tokens than comparable single-agent runs."
- Source: https://developers.openai.com/codex/subagents, read 2026-10-13
- Status: VERIFIED (exact quote found)
- For orkestra (our reading): Same direction as Anthropic's multiplier (R2-Q4-1): sub-agents multiply tokens.
