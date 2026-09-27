"""config.md içindeki profil JSON'ları templates/profiles/*.json ile aynı mı?

İki yerde duran aynı bilgi zamanla ayrışır; bu kontrol ayrışmayı yakalar.
Çalıştır: python3 tests/check-presets.py  (çıkış 0 = aynı, 1 = fark var)
"""
import json, pathlib, re, sys

try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

root =pathlib.Path(__file__).resolve().parent.parent
md = (root / "skills" / "orkestra" / "config.md").read_text(encoding="utf-8")
blocks = {}
for name, body in re.findall(r"`(\w+)`\s*\n```json\n(.*?)\n```", md, re.S):
    blocks[name] = json.loads(body)

fail = 0
for path in sorted((root / "templates" / "profiles").glob("*.json")):
    name = path.stem
    tpl = json.loads(path.read_text(encoding="utf-8"))
    if name not in blocks:
        print(f"FAIL {name}: config.md'de yok"); fail = 1
    elif blocks[name] != tpl:
        print(f"FAIL {name}: config.md ile şablon farklı"); fail = 1
    else:
        print(f"PASS {name}")
extra = set(blocks) - {p.stem for p in (root / "templates" / "profiles").glob("*.json")}
for name in sorted(extra):
    print(f"FAIL {name}: config.md'de var, şablonu yok"); fail = 1
sys.exit(fail)
