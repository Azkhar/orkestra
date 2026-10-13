# Field note: two research agents, one usage limit, 30 minutes

2026-10-13. Page-referenced research on 18th-century books for a YouTube documentary, then a
fact check. Conductor Opus, research agents Sonnet, reviewer Opus (`kontrolcu`). This run is
why orkestra 0.3.0 has budgets. Sources and method: [research notes](../research/2026-10-token-budget.md).

## What happened

Two Sonnet research agents ran in parallel. Their briefs had files, boundaries and acceptance
criteria, but no budget. After about 30 minutes both hit the plan's usage limit (HTTP 429), and
the main session stopped with them.

- Agent A took page-by-page notes into 8 files (about 80 KB, the whole book), then prepared
  scanned page images (0.4-2.2 MB JPG each) to check quotes and spent its last 15 minutes
  reading them.
- Agent B downloaded 2-4 MB OCR XML files and worked through them: 87 Bash calls, 20
  searches, 16 fetches. It never wrote its output file.

A's notes on disk saved half the job. B was not resumed; a new brief pointed to the files B
had downloaded, with a budget: at most 40 tool calls, 8 web calls, no images, a helper script
that searches the text. It finished in 34 minutes with 39 tool calls. The reviewer matched 36
quotes against the source text with a script first, then read only the suspects: REVISE, 9
fact problems, all valid.

## What the numbers really were

During the run we read token counts from the task notifications: 560,851 for the rerun,
196,443 for the reviewer. Afterwards we summed the agents' transcripts and found that the
notification number is the agent's context at the end, not its usage. Usage is every request
summed, and every request resends the whole context.

| Agent | Requests | Context at the end | Tokens processed |
|---|---|---|---|
| A (died, no budget) | 132 | up to 541,185 | 39,469,768 |
| B (died, no budget) | 114 | up to 461,962 | 36,071,444 |
| B, budgeted rerun | 21 | 560,851 | 7,050,785 |
| `kontrolcu` | 30 | 196,443 | 2,856,088 |

Over 43 sub-agent runs on the same machine, the notification matched the final context every
time, and the transcript sum was 4 to 122 times larger (median 24.5). Most of it is cache
reads, which the plan counts at a lower rate; how much lower is not documented.

## What changed in orkestra 0.3.0

- Every brief carries a Budget block: tool calls, web calls, about 2,000 characters per call,
  files over 50 KB searched instead of read, no images unless asked, bulk text work by script.
- One shared source folder with an index, so nobody downloads the same 4 MB file twice; quotes
  and numbers come from raw downloads, not from WebFetch, which returns an extraction.
- Notes on disk after each major step. A dead agent's work is recovered from them first.
- Resume only small contexts. A large one gets a new small brief that points to its files: a
  sub-agent's cache lives five minutes, so after a limit reset everything is read again.
- Two-tier review: scripts for quotes, numbers and dates, judgment only on what they flag.
- Before a wave, an estimate in tokens; on a 429, nothing new is started.
- The token table shows both numbers, final context and processed, from the transcripts.

## What we did not do, and what is still open

- Claude Code has no per-agent token cap. The Budget block is an instruction; `maxTurns` in a
  custom agent's frontmatter is the nearest hard stop, and only `kontrolcu` uses it.
- The new rules have not yet been through a second real research job. The estimate formula is
  checked against three runs.
- How a subscription plan weighs cache reads, cache writes and output is not documented, so
  "processed" overstates what cache reads cost against the limit.
- "Notification = final context" is a measurement, not a documented contract.
- The conductor is not budgeted. Writing 0.3.0 itself cost 17.5M processed tokens, and the
  conductor's share was 60%, mostly because it read every file up front and then carried them
  in every request.
- Codex: we found no per-agent call budget setting, only output and compaction limits.
