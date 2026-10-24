#!/usr/bin/env node
// orkestra limit guard: a Claude Code PreToolUse hook (matcher "*"). Node 18+, no dependencies.
//
// Reads the plan's usage (5-hour and 7-day used_percentage) from files a status line or a hook
// saved, then:
//   - main session, Agent/Task call: from warnAt adds the usage to the conductor's context,
//     from stopAt denies the spawn;
//   - inside a sub-agent (the hook input has agent_id): from agentStopAt denies every tool but
//     file writes, so the agent saves its notes and returns before the limit cuts it off.
// No data, an unreadable file or any error: the call goes through (fail open).
// Install and thresholds: reference.md, "Limit guard".
import { readFileSync, statSync } from 'node:fs'
import { homedir } from 'node:os'
import { delimiter, join } from 'node:path'

const DEFAULTS = { enabled: true, warnAt: 70, stopAt: 90, agentStopAt: 95 }
const SPAWN_TOOLS = new Set(['Agent', 'Task'])
const WRITE_TOOLS = new Set(['Write', 'Edit', 'MultiEdit', 'NotebookEdit'])
const SAME_WINDOW_MS = 5 * 60 * 1000 // two readings whose resets are this close describe one window

function readJson(path) {
  try {
    return JSON.parse(readFileSync(path, 'utf8'))
  } catch {
    return null
  }
}

// User file first, then the project file: project values win per key (config.md).
function settings(cwd) {
  const s = { ...DEFAULTS }
  for (const p of [join(homedir(), '.orkestra', 'config.json'), cwd ? join(cwd, '.orkestra', 'config.json') : null]) {
    const g = p ? readJson(p)?.limitGuard : null
    if (!g || typeof g !== 'object') continue
    for (const k of Object.keys(DEFAULTS)) if (typeof g[k] === typeof DEFAULTS[k]) s[k] = g[k]
  }
  if (/^(0|off|false|no)$/i.test(process.env.ORKESTRA_GUARD || '')) s.enabled = false
  return s
}

function resetMs(v) {
  if (typeof v === 'number') return v < 1e12 ? v * 1000 : v
  if (typeof v === 'string') {
    const t = Date.parse(v)
    return Number.isNaN(t) ? null : t
  }
  return null
}

// Accepts the status line JSON ({rate_limits: {five_hour: ...}}) or a flat {five_hour: ...}.
// Per window the freshest reading wins. Within one window usage only grows, so the higher
// number is the newer one. Two files that describe different windows: the file written last
// wins (ties: the later reset). A window that is still running only gets replaced by a newer
// observation, e.g. after an account switch; a later reset alone doesn't prove it is newer.
// A reading without resets_at, or whose window has already reset, is dropped: there is no way
// to tell how old it is.
function readings(now) {
  const files = process.env.ORKESTRA_LIMITS_FILE
    ? process.env.ORKESTRA_LIMITS_FILE.split(delimiter).filter(Boolean)
    : [join(homedir(), '.claude', 'statusline.json'), join(homedir(), '.claude', 'limits.json')]
  const best = {}
  for (const f of files) {
    const j = readJson(f)
    if (!j || typeof j !== 'object') continue
    let mtime = 0
    try {
      mtime = statSync(f).mtimeMs
    } catch {}
    const src = j.rate_limits && typeof j.rate_limits === 'object' ? j.rate_limits : j
    for (const w of ['five_hour', 'seven_day']) {
      const r = src[w]
      if (!r || typeof r.used_percentage !== 'number') continue
      const at = resetMs(r.resets_at)
      if (at === null || at <= now) continue
      const cur = best[w]
      const sameWindow = cur && Math.abs(at - cur.at) <= SAME_WINDOW_MS
      const take = !cur ||
        (sameWindow ? r.used_percentage > cur.pct : mtime > cur.mtime || (mtime === cur.mtime && at > cur.at))
      if (take) best[w] = { pct: r.used_percentage, at, mtime }
    }
  }
  return best
}

// Local time; with the date when the reset is not within the next 20 hours (7-day window).
function resetTime(ms, now) {
  const d = new Date(ms)
  const p = v => String(v).padStart(2, '0')
  const time = `${p(d.getHours())}:${p(d.getMinutes())}`
  return ms - now < 20 * 3600 * 1000 ? time : `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ${time}`
}

function decide(input, s, best, now) {
  let top = null
  for (const [w, r] of Object.entries(best)) {
    if (!top || r.pct > top.pct) top = { window: w === 'five_hour' ? '5-hour' : '7-day', ...r }
  }
  if (!top) return null
  const usage = `${top.window} usage is ${top.pct}% (resets ${resetTime(top.at, now)})`
  const deny = reason => ({
    hookSpecificOutput: { hookEventName: 'PreToolUse', permissionDecision: 'deny', permissionDecisionReason: reason },
  })
  if (input.agent_id) {
    if (top.pct < s.agentStopAt) return null
    return deny(
      `orkestra limit guard (a hook the user installed): ${usage}, at or above ${s.agentStopAt}%. Until the ` +
        'reset only file writes go through. Save your progress the way your brief asks (notes file), then return ' +
        'a partial report: what is done, what is left, file paths.',
    )
  }
  if (top.pct >= s.stopAt) {
    return deny(
      `orkestra limit guard: ${usage}, at or above ${s.stopAt}%. Don't open a new agent: finish in this ` +
        'session or wait for the reset. The threshold is limitGuard.stopAt in .orkestra/config.json.',
    )
  }
  if (top.pct >= s.warnAt) {
    return {
      hookSpecificOutput: {
        hookEventName: 'PreToolUse',
        additionalContext: `orkestra limit guard: ${usage}. Every agent draws on this limit; size the wave to what is left.`,
      },
    }
  }
  return null
}

function main() {
  const input = JSON.parse(readFileSync(0, 'utf8'))
  const tool = input.tool_name || ''
  // Fast exit for the common case: a main-session call that is not a spawn, or a sub-agent writing.
  if (input.agent_id ? WRITE_TOOLS.has(tool) : !SPAWN_TOOLS.has(tool)) return
  const s = settings(input.cwd)
  if (!s.enabled) return
  const now = Date.now()
  const out = decide(input, s, readings(now), now)
  // No process.exit() after the write: stdout to a pipe is asynchronous on some platforms.
  if (out) process.stdout.write(JSON.stringify(out))
}

try {
  main()
} catch {
  // fail open: exit code 0, no output
}
