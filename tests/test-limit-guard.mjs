// skills/orkestra/hooks/limit-guard.mjs testleri. Gecici bir ev klasoru kullanir, gercek ~/.claude'a dokunmaz.
// Calistir: node tests/test-limit-guard.mjs  (cikis 0 = hepsi gecti, 1 = hata var)
// LIMIT_GUARD_HOOK ile baska bir hook dosyasi denenebilir (ornegin bos bir dosyayla testin kirmiziya dondugunu gormek icin).
import { spawnSync } from 'node:child_process'
import { mkdirSync, mkdtempSync, rmSync, utimesSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { delimiter, dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const root = join(dirname(fileURLToPath(import.meta.url)), '..')
const hook = process.env.LIMIT_GUARD_HOOK || join(root, 'skills', 'orkestra', 'hooks', 'limit-guard.mjs')
const tmp = mkdtempSync(join(tmpdir(), 'orkestra-guard-'))
const home = join(tmp, 'home')
const proj = join(tmp, 'proj')
mkdirSync(join(home, '.claude'), { recursive: true })
mkdirSync(proj, { recursive: true })

const H = 3600 * 1000
const inFuture = ms => new Date(Date.now() + ms).toISOString()
const epochIn = ms => Math.floor((Date.now() + ms) / 1000)
let n = 0
// ageSec: dosyanin kac saniye once yazilmis gibi gorunecegi (mtime)
function limits(name, obj, ageSec = 0) {
  const p = join(tmp, `${name}-${++n}.json`)
  writeFileSync(p, JSON.stringify(obj))
  if (ageSec) {
    const t = new Date(Date.now() - ageSec * 1000)
    utimesSync(p, t, t)
  }
  return p
}
const flat = (five, seven = 10, at = inFuture(2 * H)) => ({
  five_hour: { used_percentage: five, resets_at: at },
  seven_day: { used_percentage: seven, resets_at: inFuture(48 * H) },
})

function run(input, { files, env = {}, raw } = {}) {
  const e = { ...process.env, HOME: home, USERPROFILE: home }
  delete e.ORKESTRA_GUARD
  Object.assign(e, env)
  if (files) e.ORKESTRA_LIMITS_FILE = files.join(delimiter)
  else delete e.ORKESTRA_LIMITS_FILE
  const r = spawnSync(process.execPath, [hook], { input: raw ?? JSON.stringify({ cwd: proj, ...input }), env: e, encoding: 'utf8' })
  let out = null
  try {
    out = r.stdout.trim() ? JSON.parse(r.stdout) : null
  } catch {
    out = { unparsable: r.stdout }
  }
  return { code: r.status, out }
}
const decision = o => o?.hookSpecificOutput?.permissionDecision ?? null
const context = o => o?.hookSpecificOutput?.additionalContext ?? null
const reason = o => o?.hookSpecificOutput?.permissionDecisionReason ?? ''

let fail = 0
function check(name, ok) {
  console.log(`${ok ? 'PASS' : 'FAIL'} ${name}`)
  if (!ok) fail = 1
}
const spawn = { tool_name: 'Agent' }
const sub = tool => ({ tool_name: tool, agent_id: 'a1', agent_type: 'general-purpose' })

try {
  let r = run({ tool_name: 'Read' }, { files: [limits('l', flat(99))] })
  check('ana oturum, Agent disi arac, %99: sessiz gecer', r.code === 0 && r.out === null)

  r = run(spawn, { files: [limits('l', flat(50))] })
  check('Agent, %50: sessiz gecer', r.code === 0 && r.out === null)

  r = run(spawn, { files: [limits('l', flat(75))] })
  check('Agent, %75: uyari baglama eklenir, engel yok', decision(r.out) === null && /75%/.test(context(r.out) || ''))

  r = run(spawn, { files: [limits('l', flat(92))] })
  check('Agent, %92: engellenir', decision(r.out) === 'deny' && /92%/.test(reason(r.out)))

  r = run(spawn, { files: [limits('l', flat(92, 10, inFuture(-1 * H)))] })
  check('Agent, %92 ama pencere sifirlanmis: sessiz gecer', r.out === null)

  r = run(spawn, { files: [limits('l', flat(10, 96))] })
  check('Agent, 7 gunluk %96: engellenir, 7-day yazar', decision(r.out) === 'deny' && /7-day/.test(reason(r.out)))

  r = run(sub('Read'), { files: [limits('l', flat(96))] })
  check('alt ajan Read, %96: engellenir, not yaz der', decision(r.out) === 'deny' && /notes/.test(reason(r.out)))

  r = run(sub('Write'), { files: [limits('l', flat(96))] })
  check('alt ajan Write, %96: gecer (notlarini yazabilsin)', r.out === null)

  r = run(sub('Bash'), { files: [limits('l', flat(93))] })
  check('alt ajan Bash, %93: gecer (agentStopAt 95)', r.out === null)

  // Ayni pencere, iki kaynak: ISO tarihli 72 ile epoch saniyeli 91 -> 91 kazanir
  const at = Date.now() + 2 * H
  const a = limits('iso', { five_hour: { used_percentage: 72, resets_at: new Date(at + 314).toISOString() } })
  const b = limits('sl', { rate_limits: { five_hour: { used_percentage: 91, resets_at: Math.floor(at / 1000) } } })
  // Iki sira da denenir: "son dosya kazanir" gibi bir hata tek sirada gizlenebilir
  for (const order of [[a, b], [b, a]]) {
    r = run(spawn, { files: order })
    check(`ayni pencerede yuksek okuma kazanir (status line bicimi dahil), sira ${order[0] === a ? 'iso>sl' : 'sl>iso'}`,
      decision(r.out) === 'deny' && /91%/.test(reason(r.out)))
  }

  // Farkli pencere: son yazilan dosya kazanir. Yeni pencere (%10) sonra yazildi -> gecer
  const old = limits('old', { five_hour: { used_percentage: 95, resets_at: inFuture(0.5 * H) } }, 600)
  const fresh = limits('new', { five_hour: { used_percentage: 10, resets_at: epochIn(4.5 * H) } })
  for (const order of [[old, fresh], [fresh, old]]) {
    r = run(spawn, { files: order })
    check(`farkli pencerede son yazilan kazanir (yeni pencere), sira ${order[0] === old ? 'eski>yeni' : 'yeni>eski'}`, r.out === null)
  }

  // Hesap degisimi: eski hesabin %94'u daha GEC sifirlaniyor ama daha once yazildi; yeni hesabin %9'u sonra yazildi.
  // "Gec sifirlanan kazanir" kurali burada eski hesabi secip yanlis engellerdi.
  const prevAcct = limits('acctA', { five_hour: { used_percentage: 94, resets_at: inFuture(27 * 60 * 1000) } }, 300)
  const newAcct = limits('acctB', { rate_limits: { five_hour: { used_percentage: 9, resets_at: epochIn(17 * 60 * 1000) } } })
  for (const order of [[prevAcct, newAcct], [newAcct, prevAcct]]) {
    r = run(spawn, { files: order })
    check(`hesap degisimi: son yazilan hesap kazanir, sira ${order[0] === prevAcct ? 'eski>yeni' : 'yeni>eski'}`, r.out === null)
  }
  const prevLater = limits('acctA2', { five_hour: { used_percentage: 94, resets_at: inFuture(27 * 60 * 1000) } })
  const newEarlier = limits('acctB2', { five_hour: { used_percentage: 9, resets_at: inFuture(17 * 60 * 1000) } }, 300)
  r = run(spawn, { files: [newEarlier, prevLater] })
  check('farkli pencere, %94 sonra yazildiysa o kazanir: engellenir', decision(r.out) === 'deny')

  r = run(spawn, { files: [limits('nodate', { five_hour: { used_percentage: 95 } })] })
  check('resets_at olmayan okuma yok sayilir', r.out === null)

  r = run({ tool_name: 'Task' }, { files: [limits('l', flat(92))] })
  check('Task araci da spawn sayilir: %92 engellenir', decision(r.out) === 'deny')

  for (const tool of ['Edit', 'MultiEdit', 'NotebookEdit']) {
    r = run(sub(tool), { files: [limits('l', flat(96))] })
    check(`alt ajan ${tool}, %96: gecer`, r.out === null)
  }

  const far = limits('far', { seven_day: { used_percentage: 92, resets_at: inFuture(50 * H) } })
  r = run(spawn, { files: [far] })
  check('7 gunluk sifirlanma uzaksa mesajda tarih var', /resets \d{4}-\d{2}-\d{2} \d{2}:\d{2}/.test(reason(r.out)))

  // Varsayilan yol: ~/.claude/limits.json
  writeFileSync(join(home, '.claude', 'limits.json'), JSON.stringify(flat(93)))
  r = run(spawn, {})
  check('varsayilan ~/.claude/limits.json okunur', decision(r.out) === 'deny')

  // Ayarlar: proje dosyasi kullanici dosyasini ezer; ORKESTRA_GUARD=off kapatir
  mkdirSync(join(home, '.orkestra'), { recursive: true })
  writeFileSync(join(home, '.orkestra', 'config.json'), JSON.stringify({ limitGuard: { stopAt: 99, warnAt: 99 } }))
  r = run(spawn, { files: [limits('l', flat(93))] })
  check('kullanici ayari stopAt 99: %93 gecer', r.out === null)
  mkdirSync(join(proj, '.orkestra'), { recursive: true })
  writeFileSync(join(proj, '.orkestra', 'config.json'), JSON.stringify({ limitGuard: { stopAt: 80 } }))
  r = run(spawn, { files: [limits('l', flat(85))] })
  check('proje ayari stopAt 80 kullaniciyi ezer: %85 engellenir', decision(r.out) === 'deny')
  writeFileSync(join(proj, '.orkestra', 'config.json'), JSON.stringify({ limitGuard: { stopAt: '80', warnAt: '99' } }))
  r = run(spawn, { files: [limits('l', flat(85))] })
  check('metin esikler yok sayilir: kullanici ayari (99) gecerli, %85 gecer', r.out === null)
  r = run(spawn, { files: [limits('l', flat(99))], env: { ORKESTRA_GUARD: 'off' } })
  check('ORKESTRA_GUARD=off: %99 gecer', r.out === null)
  writeFileSync(join(proj, '.orkestra', 'config.json'), JSON.stringify({ limitGuard: { enabled: false } }))
  r = run(spawn, { files: [limits('l', flat(99))] })
  check('limitGuard.enabled false: %99 gecer', r.out === null)
  rmSync(join(proj, '.orkestra'), { recursive: true, force: true })
  rmSync(join(home, '.orkestra'), { recursive: true, force: true })

  // Hata durumlari: hepsi acik kalir (fail open), cikis 0
  r = run(spawn, { raw: 'bozuk json' })
  check('bozuk girdi: cikis 0, cikti yok', r.code === 0 && r.out === null)
  r = run(spawn, { files: [join(tmp, 'yok.json')] })
  check('limit dosyasi yok: gecer', r.code === 0 && r.out === null)
  r = run(spawn, { files: [limits('bad', { five_hour: { used_percentage: '93', resets_at: inFuture(2 * H) } })] })
  check('sayi olmayan yuzde: yok sayilir', r.out === null)
} finally {
  rmSync(tmp, { recursive: true, force: true })
}
console.log(fail ? 'FAIL' : 'ALL PASS')
process.exitCode = fail
