"""config.md içindeki profil JSON'ları templates/profiles/*.json ile aynı mı?

İki yerde duran aynı bilgi zamanla ayrışır; bu kontrol ayrışmayı yakalar.
Bütçe (budget) için ayrıca: her profilde dört alan var mı, pozitif tam sayı mı,
lean <= balanced <= generous mi, config.md'deki preset tablosu JSON ile aynı mı?
Çalıştır: python3 tests/check-presets.py  (çıkış 0 = aynı, 1 = fark var)
"""
import json, pathlib, re, sys

try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

BUDGET_KEYS = ("toolCalls", "webCalls", "outputChars", "wholeFileKB")
ORDER = ("lean", "balanced", "generous")

root =pathlib.Path(__file__).resolve().parent.parent
md = (root / "skills" / "orkestra" / "config.md").read_text(encoding="utf-8")
blocks = {}
for name, body in re.findall(r"`(\w+)`\s*\n```json\n(.*?)\n```", md, re.S):
    blocks[name] = json.loads(body)

fail = 0
templates = {}
for path in sorted((root / "templates" / "profiles").glob("*.json")):
    name = path.stem
    tpl = json.loads(path.read_text(encoding="utf-8"))
    templates[name] = tpl
    if name not in blocks:
        print(f"FAIL {name}: config.md'de yok"); fail = 1
    elif blocks[name] != tpl:
        print(f"FAIL {name}: config.md ile şablon farklı"); fail = 1
    else:
        print(f"PASS {name}")
extra = set(blocks) - {p.stem for p in (root / "templates" / "profiles").glob("*.json")}
for name in sorted(extra):
    print(f"FAIL {name}: config.md'de var, şablonu yok"); fail = 1

# ---- budget alanları ----
for name, tpl in sorted(templates.items()):
    budget = tpl.get("budget")
    if not isinstance(budget, dict):
        print(f"FAIL {name}: budget yok"); fail = 1; continue
    bad = [k for k in BUDGET_KEYS
           if not (type(budget.get(k)) is int and budget[k] > 0)]
    unknown = sorted(set(budget) - set(BUDGET_KEYS))
    if bad or unknown:
        print(f"FAIL {name}: budget alanı eksik/geçersiz {bad}, bilinmeyen {unknown}"); fail = 1
    else:
        print(f"PASS {name} budget")

# lean <= balanced <= generous (dar profil hiçbir alanda daha cömert olamaz)
if all(isinstance(templates.get(n, {}).get("budget"), dict) for n in ORDER):
    order_ok = True
    for key in BUDGET_KEYS:
        vals = [templates[n]["budget"].get(key) for n in ORDER]
        if all(type(v) is int for v in vals) and not (vals[0] <= vals[1] <= vals[2]):
            print(f"FAIL budget.{key}: lean <= balanced <= generous değil {vals}")
            fail = 1; order_ok = False
    if order_ok:
        print("PASS budget sırası")
else:
    print("FAIL budget sırası: üç profilin hepsi yok"); fail = 1

# config.md preset tablosu: | `budget.<alan>` | lean | balanced | generous |
header = re.search(r"^\|\s*\|\s*`(\w+)`\s*\|\s*`(\w+)`\s*\|\s*`(\w+)`\s*\|\s*$", md, re.M)
rows = {k: [int(v) for v in vs] for k, *vs in
        re.findall(r"^\|\s*`budget\.(\w+)`\s*\|\s*(\d+)\s*\|\s*(\d+)\s*\|\s*(\d+)\s*\|\s*$", md, re.M)}
if not header:
    print("FAIL tablo: preset başlığı bulunamadı"); fail = 1
else:
    cols = header.groups()
    for key in BUDGET_KEYS:
        want = [templates.get(n, {}).get("budget", {}).get(key) for n in cols]
        if key not in rows:
            print(f"FAIL tablo: budget.{key} satırı yok"); fail = 1
        elif rows[key] != want:
            print(f"FAIL tablo: budget.{key} {rows[key]} != JSON {want}"); fail = 1
        else:
            print(f"PASS tablo budget.{key}")
sys.exit(fail)
