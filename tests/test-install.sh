#!/usr/bin/env bash
# install.sh icin test paketi. Gecici bir HOME ve gecici bir proje klasoru
# (bosluk + Turkce karakterli) kullanir, gercek ~/.claude, ~/.codex, ~/.agents
# klasorlerine dokunmaz. bash 3.2 uyumlu, Git Bash'te de calisir.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INSTALL_SH="$REPO_ROOT/install.sh"

if [ ! -f "$INSTALL_SH" ]; then
    echo "FAIL: install.sh bulunamadi: $INSTALL_SH"
    exit 1
fi

TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/orkestra-test.XXXXXX")"

PASS_COUNT=0
FAIL_COUNT=0

record() {
    code="$1"; msg="$2"
    if [ "$code" -eq 0 ]; then
        PASS_COUNT=$((PASS_COUNT + 1))
        echo "PASS: $msg"
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        echo "FAIL: $msg"
    fi
}

run_install() {
    OUTPUT="$(bash "$INSTALL_SH" "$@" 2>&1)"
    EXIT_CODE=$?
}

cleanup() {
    rm -rf "$TEST_ROOT" 2>/dev/null || true
}
trap cleanup EXIT

FAKE_HOME="$TEST_ROOT/home"
FAKE_PROJECT="$TEST_ROOT/proje ğüş"
mkdir -p "$FAKE_HOME"
mkdir -p "$FAKE_PROJECT"

CLAUDE_SKILL_FILE="$FAKE_HOME/.claude/skills/orkestra/SKILL.md"
ORIG_SKILL_FILE="$REPO_ROOT/skills/orkestra/SKILL.md"

# ---- Senaryo 1: global both temiz kurulum ----
run_install --scope=Global --target=both --home-dir="$FAKE_HOME"
[ "$EXIT_CODE" -eq 0 ]; record $? "Senaryo1: exit kodu 0"
[ -f "$CLAUDE_SKILL_FILE" ]; record $? "Senaryo1: claude skill kuruldu"
[ -f "$FAKE_HOME/.claude/agents/kontrolcu.md" ]; record $? "Senaryo1: claude agent kuruldu"
[ -f "$FAKE_HOME/.agents/skills/orkestra/SKILL.md" ]; record $? "Senaryo1: codex skill kuruldu"
echo "$OUTPUT" | grep -q 'kuruldu'; record $? "Senaryo1: cikti 'kuruldu' iceriyor"
[ -z "$(find "$FAKE_HOME/.agents" -type f -name 'kontrolcu.md' 2>/dev/null)" ]; record $? "Senaryo1: kontrolcu.md codex hedefine gitmedi"

# ---- Senaryo 2: tekrar kosu -> guncel ----
run_install --scope=Global --target=both --home-dir="$FAKE_HOME"
[ "$EXIT_CODE" -eq 0 ]; record $? "Senaryo2: exit kodu 0"
guncel_count="$(echo "$OUTPUT" | grep -c '^guncel ')"
[ "$guncel_count" -eq 3 ]; record $? "Senaryo2: uc hedef de guncel raporlandi (bulunan: $guncel_count)"

# ---- Senaryo 3: kurulu SKILL.md'yi degistir -> tekrar kosu atlar, exit 2 ----
printf '\nEXTRA LINE\n' >> "$CLAUDE_SKILL_FILE"
run_install --scope=Global --target=both --home-dir="$FAKE_HOME"
[ "$EXIT_CODE" -eq 2 ]; record $? "Senaryo3: exit kodu 2"
echo "$OUTPUT" | grep -q 'atlandi'; record $? "Senaryo3: 'atlandi' mesaji var"
grep -q 'EXTRA LINE' "$CLAUDE_SKILL_FILE"; record $? "Senaryo3: dosyaya dokunulmadi"

# ---- Senaryo 4: --force -> yedek skills/ disina (bir ust seviyeye) tasinir, kaynakla ayni olur ----
run_install --scope=Global --target=both --home-dir="$FAKE_HOME" --force
[ "$EXIT_CODE" -eq 0 ]; record $? "Senaryo4: exit kodu 0"
echo "$OUTPUT" | grep -q 'yedeklendi ve kuruldu'; record $? "Senaryo4: 'yedeklendi ve kuruldu' mesaji var"
bak_count="$(find "$FAKE_HOME/.claude" -maxdepth 1 -type d -name 'orkestra.bak-*' 2>/dev/null | wc -l | tr -d ' ')"
[ "$bak_count" -ge 1 ]; record $? "Senaryo4: yedek klasoru .claude altinda (skills disinda) olustu"
skills_bak_count="$(find "$FAKE_HOME/.claude/skills" -maxdepth 1 -name '*.bak-*' 2>/dev/null | wc -l | tr -d ' ')"
[ "$skills_bak_count" -eq 0 ]; record $? "Senaryo4: skills/ altinda hicbir .bak-* yok"
diff -q "$CLAUDE_SKILL_FILE" "$ORIG_SKILL_FILE" >/dev/null 2>&1; record $? "Senaryo4: kurulan dosya kaynakla birebir ayni"

# ---- Senaryo 5: Project modu ----
run_install --scope=Project --path="$FAKE_PROJECT" --target=both
[ "$EXIT_CODE" -eq 0 ]; record $? "Senaryo5: exit kodu 0"
[ -f "$FAKE_PROJECT/.claude/skills/orkestra/SKILL.md" ]; record $? "Senaryo5: proje claude skill kuruldu"
[ -f "$FAKE_PROJECT/.claude/agents/kontrolcu.md" ]; record $? "Senaryo5: proje claude agent kuruldu"
[ -f "$FAKE_PROJECT/.agents/skills/orkestra/SKILL.md" ]; record $? "Senaryo5: proje codex skill kuruldu"

# ---- Senaryo 6: --target=claude yalniz Claude'a kurar ----
FAKE_HOME2="$TEST_ROOT/home2"
mkdir -p "$FAKE_HOME2"
run_install --scope=Global --target=claude --home-dir="$FAKE_HOME2"
[ "$EXIT_CODE" -eq 0 ]; record $? "Senaryo6: exit kodu 0"
[ -f "$FAKE_HOME2/.claude/skills/orkestra/SKILL.md" ]; record $? "Senaryo6: claude skill kuruldu"
[ ! -d "$FAKE_HOME2/.agents/skills/orkestra" ]; record $? "Senaryo6: codex hedefine dokunulmadi"

# ---- Senaryo 7: --dry-run hicbir sey yazmaz ----
FAKE_HOME3="$TEST_ROOT/home3"
mkdir -p "$FAKE_HOME3"
run_install --scope=Global --target=both --home-dir="$FAKE_HOME3" --dry-run
[ "$EXIT_CODE" -eq 0 ]; record $? "Senaryo7: exit kodu 0"
[ ! -d "$FAKE_HOME3/.claude" ]; record $? "Senaryo7: .claude yazilmadi"
[ ! -d "$FAKE_HOME3/.agents" ]; record $? "Senaryo7: .agents yazilmadi"
echo "$OUTPUT" | grep -q 'kurulacak'; record $? "Senaryo7: 'kurulacak' mesaji var"

# ---- Senaryo 8: --uninstall yalniz bizimkini kaldirir ----
FAKE_HOME4="$TEST_ROOT/home4"
mkdir -p "$FAKE_HOME4"
UNRELATED_DIR="$FAKE_HOME4/.claude/skills/baska-skill"
mkdir -p "$UNRELATED_DIR"
printf -- '---\nname: baska-skill\ndescription: test\n---\n# Baska\n' > "$UNRELATED_DIR/SKILL.md"

run_install --scope=Global --target=both --home-dir="$FAKE_HOME4"

run_install --scope=Global --target=both --home-dir="$FAKE_HOME4" --uninstall
[ "$EXIT_CODE" -eq 0 ]; record $? "Senaryo8: exit kodu 0"
[ ! -d "$FAKE_HOME4/.claude/skills/orkestra" ]; record $? "Senaryo8: orkestra skill kaldirildi"
[ ! -f "$FAKE_HOME4/.claude/agents/kontrolcu.md" ]; record $? "Senaryo8: kontrolcu.md kaldirildi"
[ ! -d "$FAKE_HOME4/.agents/skills/orkestra" ]; record $? "Senaryo8: codex skill kaldirildi"
[ -d "$UNRELATED_DIR" ]; record $? "Senaryo8: ilgisiz skill klasorune dokunulmadi"
[ -f "$UNRELATED_DIR/SKILL.md" ]; record $? "Senaryo8: ilgisiz skill dosyasi hala var"

write_fake_frontmatter() {
    # $1: hedef dosya yolu, $2: frontmatter name degeri
    mkdir -p -- "$(dirname "$1")"
    printf -- '---\nname: %s\ndescription: baskasinin dosyasi\n---\n# Baska\n' "$2" > "$1"
}

# ---- Senaryo 9: Uninstall frontmatter korumasi -- ayni YOLDA yabanci icerik ----
FAKE_HOME5="$TEST_ROOT/home5"
mkdir -p "$FAKE_HOME5"
CLAUDE_SKILL_DIR5="$FAKE_HOME5/.claude/skills/orkestra"
CLAUDE_AGENT_FILE5="$FAKE_HOME5/.claude/agents/kontrolcu.md"
CODEX_SKILL_DIR5="$FAKE_HOME5/.agents/skills/orkestra"

write_fake_frontmatter "$CLAUDE_SKILL_DIR5/SKILL.md" "baska"
write_fake_frontmatter "$CLAUDE_AGENT_FILE5" "baska"
write_fake_frontmatter "$CODEX_SKILL_DIR5/SKILL.md" "baska"

run_install --scope=Global --target=both --home-dir="$FAKE_HOME5" --uninstall
[ "$EXIT_CODE" -eq 0 ]; record $? "Senaryo9: exit kodu 0"
skip_count9="$(echo "$OUTPUT" | grep -c 'bizim degil')"
[ "$skip_count9" -eq 3 ]; record $? "Senaryo9: uc hedef de 'bizim degil' ile atlandi (bulunan: $skip_count9)"
[ -f "$CLAUDE_SKILL_DIR5/SKILL.md" ]; record $? "Senaryo9: yabanci claude skill dosyasi silinmedi"
[ -f "$CLAUDE_AGENT_FILE5" ]; record $? "Senaryo9: yabanci kontrolcu.md silinmedi"
[ -f "$CODEX_SKILL_DIR5/SKILL.md" ]; record $? "Senaryo9: yabanci codex skill dosyasi silinmedi"

# ---- Senaryo 10: --dry-run + --force ve --dry-run + --uninstall gercekten hicbir sey yapmaz ----
FAKE_HOME6="$TEST_ROOT/home6"
mkdir -p "$FAKE_HOME6"
CLAUDE_SKILL_FILE6="$FAKE_HOME6/.claude/skills/orkestra/SKILL.md"
CLAUDE_AGENT_FILE6="$FAKE_HOME6/.claude/agents/kontrolcu.md"
CODEX_SKILL_FILE6="$FAKE_HOME6/.agents/skills/orkestra/SKILL.md"

run_install --scope=Global --target=both --home-dir="$FAKE_HOME6"
printf '\nEXTRA LINE 6\n' >> "$CLAUDE_SKILL_FILE6"

run_install --scope=Global --target=both --home-dir="$FAKE_HOME6" --force --dry-run
[ "$EXIT_CODE" -eq 0 ]; record $? "Senaryo10a: --force+--dry-run exit kodu 0"
bak_count10="$(find "$FAKE_HOME6/.claude" -name '*.bak-*' 2>/dev/null | wc -l | tr -d ' ')"
[ "$bak_count10" -eq 0 ]; record $? "Senaryo10a: --force+--dry-run sonrasi hicbir .bak-* yok"
grep -q 'EXTRA LINE 6' "$CLAUDE_SKILL_FILE6"; record $? "Senaryo10a: degisiklik hala duruyor"

run_install --scope=Global --target=both --home-dir="$FAKE_HOME6" --uninstall --dry-run
[ "$EXIT_CODE" -eq 0 ]; record $? "Senaryo10b: --uninstall+--dry-run exit kodu 0"
[ -f "$CLAUDE_SKILL_FILE6" ]; record $? "Senaryo10b: claude skill hala duruyor"
[ -f "$CLAUDE_AGENT_FILE6" ]; record $? "Senaryo10b: claude agent hala duruyor"
[ -f "$CODEX_SKILL_FILE6" ]; record $? "Senaryo10b: codex skill hala duruyor"

new_test_project() {
    # $1: benzersiz sonek. Bosluk + Turkce karakterli, izole proje klasoru dondurur.
    p="$TEST_ROOT/proje ğüş $1"
    mkdir -p -- "$p"
    printf '%s' "$p"
}

marker_count() {
    [ -f "$1" ] || { echo 0; return 0; }
    grep -c 'orkestra:begin' "$1" 2>/dev/null || true
}

# ============================================================
# Conductor modu (--always) ve limit profili (--profile) testleri
# ============================================================

# ---- Senaryo 11 (a): --always --target=both, bos proje ----
PROJ11="$(new_test_project 11)"
HOME11="$TEST_ROOT/home11"
run_install --scope=Project --path="$PROJ11" --always --target=both --home-dir="$HOME11"
[ "$EXIT_CODE" -eq 0 ]; record $? "Senaryo11: exit kodu 0"
AGENTS11="$PROJ11/AGENTS.md"
CLAUDE11="$PROJ11/CLAUDE.md"
[ -f "$AGENTS11" ]; record $? "Senaryo11: AGENTS.md olustu"
grep -q 'orkestra:begin' "$AGENTS11"; record $? "Senaryo11: AGENTS.md blogu iceriyor"
[ "$(cat "$CLAUDE11")" = "@AGENTS.md" ]; record $? "Senaryo11: CLAUDE.md tam olarak @AGENTS.md"

# ---- Senaryo 12 (b): CLAUDE.md zaten @AGENTS.md iceriyor -> degismez ----
PROJ12="$(new_test_project 12)"
HOME12="$TEST_ROOT/home12"
printf '@AGENTS.md' > "$PROJ12/CLAUDE.md"
run_install --scope=Project --path="$PROJ12" --always --target=both --home-dir="$HOME12"
[ "$EXIT_CODE" -eq 0 ]; record $? "Senaryo12: exit kodu 0"
echo "$OUTPUT" | grep -q 'AGENTS.md uzerinden'; record $? "Senaryo12: 'AGENTS.md uzerinden' raporlandi"
[ "$(cat "$PROJ12/CLAUDE.md")" = "@AGENTS.md" ]; record $? "Senaryo12: CLAUDE.md hala yalniz @AGENTS.md"

# ---- Senaryo 13 (c): kullanici metni olan AGENTS.md + import'suz CLAUDE.md -> ikisine de eklenir, metin korunur ----
PROJ13="$(new_test_project 13)"
HOME13="$TEST_ROOT/home13"
printf 'Kullanici notu satiri.\n' > "$PROJ13/AGENTS.md"
printf 'CLAUDE ozel not.\n' > "$PROJ13/CLAUDE.md"
run_install --scope=Project --path="$PROJ13" --always --target=both --home-dir="$HOME13"
[ "$EXIT_CODE" -eq 0 ]; record $? "Senaryo13: exit kodu 0"
grep -q 'Kullanici notu satiri\.' "$PROJ13/AGENTS.md"; record $? "Senaryo13: AGENTS.md kullanici metni korundu"
grep -q 'orkestra:begin' "$PROJ13/AGENTS.md"; record $? "Senaryo13: AGENTS.md bloğu aldi"
grep -q 'CLAUDE ozel not\.' "$PROJ13/CLAUDE.md"; record $? "Senaryo13: CLAUDE.md kullanici metni korundu"
grep -q 'orkestra:begin' "$PROJ13/CLAUDE.md"; record $? "Senaryo13: CLAUDE.md bloğu aldi"
[ "$(marker_count "$PROJ13/AGENTS.md")" -eq 1 ]; record $? "Senaryo13: AGENTS.md'de tek blok"
[ "$(marker_count "$PROJ13/CLAUDE.md")" -eq 1 ]; record $? "Senaryo13: CLAUDE.md'de tek blok"

# ---- Senaryo 14 (d): tekrar kosu -> guncel, marker sayisi hala 1 ----
run_install --scope=Project --path="$PROJ13" --always --target=both --home-dir="$HOME13"
[ "$EXIT_CODE" -eq 0 ]; record $? "Senaryo14: exit kodu 0"
echo "$OUTPUT" | grep -q 'guncel'; record $? "Senaryo14: 'guncel' raporlandi"
[ "$(marker_count "$PROJ13/AGENTS.md")" -eq 1 ]; record $? "Senaryo14: AGENTS.md'de hala tek blok"
[ "$(marker_count "$PROJ13/CLAUDE.md")" -eq 1 ]; record $? "Senaryo14: CLAUDE.md'de hala tek blok (import satiriyla)"

# ---- Senaryo 15 (e): sablon degisti (gecici repo kopyasinda) -> blok degisir, cogalmaz ----
TMP_REPO15="$TEST_ROOT/repo-copy-15"
mkdir -p "$TMP_REPO15"
cp "$REPO_ROOT/install.sh" "$TMP_REPO15/install.sh"
cp -R "$REPO_ROOT/skills" "$TMP_REPO15/skills"
cp -R "$REPO_ROOT/agents" "$TMP_REPO15/agents"
cp -R "$REPO_ROOT/templates" "$TMP_REPO15/templates"
PROJ15="$(new_test_project 15)"
HOME15="$TEST_ROOT/home15"
bash "$TMP_REPO15/install.sh" --scope=Project --path="$PROJ15" --always --block-only --target=codex --home-dir="$HOME15" >/dev/null
printf '<!-- orkestra:begin (managed by the orkestra installer; edit via /orkestra settings or reinstall) -->\nNEW BLOCK CONTENT CHANGED\n<!-- orkestra:end -->' > "$TMP_REPO15/templates/conductor-block.md"
bash "$TMP_REPO15/install.sh" --scope=Project --path="$PROJ15" --always --block-only --target=codex --home-dir="$HOME15" >/dev/null
grep -q 'NEW BLOCK CONTENT CHANGED' "$PROJ15/AGENTS.md"; record $? "Senaryo15: yeni blok icerigi yazildi"
[ "$(marker_count "$PROJ15/AGENTS.md")" -eq 1 ]; record $? "Senaryo15: blok cogalmadi (tek marker)"

# ---- Senaryo 16 (f): --local -> yalniz CLAUDE.local.md, AGENTS.md dokunulmaz ----
PROJ16="$(new_test_project 16)"
HOME16="$TEST_ROOT/home16"
run_install --scope=Project --path="$PROJ16" --always --local --target=both --home-dir="$HOME16"
[ "$EXIT_CODE" -eq 0 ]; record $? "Senaryo16: exit kodu 0"
[ ! -f "$PROJ16/AGENTS.md" ]; record $? "Senaryo16: AGENTS.md olusturulmadi"
[ ! -f "$PROJ16/CLAUDE.md" ]; record $? "Senaryo16: CLAUDE.md olusturulmadi"
[ -f "$PROJ16/CLAUDE.local.md" ]; record $? "Senaryo16: CLAUDE.local.md olustu"
grep -q 'orkestra:begin' "$PROJ16/CLAUDE.local.md"; record $? "Senaryo16: CLAUDE.local.md blogu iceriyor"

# ---- Senaryo 17 (g): CRLF dosya CRLF kaliyor ----
PROJ17="$(new_test_project 17)"
HOME17="$TEST_ROOT/home17"
printf 'CRLF user line\r\n' > "$PROJ17/AGENTS.md"
run_install --scope=Project --path="$PROJ17" --always --block-only --target=codex --home-dir="$HOME17"
[ "$EXIT_CODE" -eq 0 ]; record $? "Senaryo17: exit kodu 0"
orig_size17="$(wc -c < "$PROJ17/AGENTS.md")"
stripped_size17="$(tr -d '\r' < "$PROJ17/AGENTS.md" | wc -c)"
[ "$orig_size17" != "$stripped_size17" ]; record $? "Senaryo17: dosyada CRLF var"
# basit kontrol: orijinal boyut - LF-only boyut == satir sayisi (her satirda tam bir \r farki olmali)
line_count17="$(wc -l < "$PROJ17/AGENTS.md")"
[ "$((orig_size17 - stripped_size17))" -eq "$line_count17" ]; record $? "Senaryo17: tek basina LF yok, hepsi CRLF"

# ---- Senaryo 18 (h): uninstall bloklari kaldirir, kullanici metnini korur, sadece blok iceren dosyalari siler ----
run_install --scope=Project --path="$PROJ13" --always --target=both --home-dir="$HOME13" --uninstall
[ "$EXIT_CODE" -eq 0 ]; record $? "Senaryo18: exit kodu 0"
[ "$(cat "$PROJ13/AGENTS.md")" = "Kullanici notu satiri." ]; record $? "Senaryo18: AGENTS.md yalniz kullanici metnini icersin"
[ "$(cat "$PROJ13/CLAUDE.md")" = "CLAUDE ozel not." ]; record $? "Senaryo18: CLAUDE.md yalniz kullanici metnini icersin"

PROJ18B="$(new_test_project 18b)"
HOME18B="$TEST_ROOT/home18b"
run_install --scope=Project --path="$PROJ18B" --always --block-only --target=both --home-dir="$HOME18B"
run_install --scope=Project --path="$PROJ18B" --always --block-only --target=both --home-dir="$HOME18B" --uninstall
[ "$EXIT_CODE" -eq 0 ]; record $? "Senaryo18b: exit kodu 0"
[ ! -f "$PROJ18B/AGENTS.md" ]; record $? "Senaryo18b: sadece blok iceren AGENTS.md silindi"
[ ! -f "$PROJ18B/CLAUDE.md" ]; record $? "Senaryo18b: sadece @AGENTS.md iceren CLAUDE.md silindi"

# ---- Senaryo 19 (i): profil kurulum / guncel / farkli-atlandi(exit2) / --force yedek / gecersiz isim(exit1) ----
HOME19="$TEST_ROOT/home19"
run_install --scope=Global --home-dir="$HOME19" --profile=balanced
[ "$EXIT_CODE" -eq 0 ]; record $? "Senaryo19a: exit kodu 0"
CONFIG19="$HOME19/.orkestra/config.json"
[ -f "$CONFIG19" ]; record $? "Senaryo19a: config.json olustu"
diff -q "$REPO_ROOT/templates/profiles/balanced.json" "$CONFIG19" >/dev/null 2>&1; record $? "Senaryo19a: config icerigi kaynakla birebir ayni"

run_install --scope=Global --home-dir="$HOME19" --profile=balanced
[ "$EXIT_CODE" -eq 0 ]; record $? "Senaryo19b: exit kodu 0"
echo "$OUTPUT" | grep -q 'guncel'; record $? "Senaryo19b: 'guncel' raporlandi"

run_install --scope=Global --home-dir="$HOME19" --profile=lean
[ "$EXIT_CODE" -eq 2 ]; record $? "Senaryo19c: farkli profil --force olmadan exit kodu 2"
echo "$OUTPUT" | grep -q 'atlandi'; record $? "Senaryo19c: 'atlandi' mesaji var"
grep -q '"balanced"' "$CONFIG19"; record $? "Senaryo19c: config hala eskisi (balanced)"

run_install --scope=Global --home-dir="$HOME19" --profile=lean --force
[ "$EXIT_CODE" -eq 0 ]; record $? "Senaryo19d: --force ile exit kodu 0"
grep -q '"lean"' "$CONFIG19"; record $? "Senaryo19d: config artik lean"
bak_count19="$(find "$HOME19/.orkestra" -name 'config.json.bak-*' 2>/dev/null | wc -l | tr -d ' ')"
[ "$bak_count19" -ge 1 ]; record $? "Senaryo19d: eski config yedeklendi"

run_install --scope=Global --home-dir="$TEST_ROOT/home19e" --profile=bogus-profile
[ "$EXIT_CODE" -eq 1 ]; record $? "Senaryo19e: gecersiz profil adi exit kodu 1"

# ---- Senaryo 20 (j): uninstall config'i korur, --purge kaldirir ----
run_install --scope=Global --home-dir="$HOME19" --uninstall
[ "$EXIT_CODE" -eq 0 ]; record $? "Senaryo20a: exit kodu 0"
[ -f "$CONFIG19" ]; record $? "Senaryo20a: --purge olmadan config hala duruyor"

run_install --scope=Global --home-dir="$HOME19" --uninstall --purge
[ "$EXIT_CODE" -eq 0 ]; record $? "Senaryo20b: exit kodu 0"
[ ! -f "$CONFIG19" ]; record $? "Senaryo20b: --purge ile config kaldirildi"

# ---- Senaryo 21 (k): --dry-run ile --always + --profile hicbir sey yazmaz ----
PROJ21="$(new_test_project 21)"
HOME21="$TEST_ROOT/home21"
run_install --scope=Project --path="$PROJ21" --always --block-only --profile=generous --home-dir="$HOME21" --dry-run
[ "$EXIT_CODE" -eq 0 ]; record $? "Senaryo21: exit kodu 0"
proj21_count="$(find "$PROJ21" -mindepth 1 2>/dev/null | wc -l | tr -d ' ')"
[ "$proj21_count" -eq 0 ]; record $? "Senaryo21: proje klasorune hicbir sey yazilmadi"
[ ! -d "$HOME21" ]; record $? "Senaryo21: home dizini hic olusmadi"

# ---- Senaryo 22 (l): --always ile --scope=Global -> exit 1 ----
run_install --scope=Global --always --home-dir="$TEST_ROOT/home22"
[ "$EXIT_CODE" -eq 1 ]; record $? "Senaryo22: --always + Global exit kodu 1"

# ---- Senaryo 23 (m): --always --block-only bos projede -> skill dosyalari kopyalanmaz ----
PROJ23="$(new_test_project 23)"
HOME23="$TEST_ROOT/home23"
run_install --scope=Project --path="$PROJ23" --always --block-only --target=both --home-dir="$HOME23"
[ "$EXIT_CODE" -eq 0 ]; record $? "Senaryo23: exit kodu 0"
[ -f "$PROJ23/AGENTS.md" ]; record $? "Senaryo23: AGENTS.md olustu"
[ "$(cat "$PROJ23/CLAUDE.md")" = "@AGENTS.md" ]; record $? "Senaryo23: CLAUDE.md @AGENTS.md"
[ ! -d "$PROJ23/.claude/skills/orkestra" ]; record $? "Senaryo23: claude skill kopyalanmadi"
[ ! -d "$PROJ23/.agents/skills/orkestra" ]; record $? "Senaryo23: codex skill kopyalanmadi"
[ ! -f "$PROJ23/.claude/agents/kontrolcu.md" ]; record $? "Senaryo23: kontrolcu.md kopyalanmadi"

# ---- Senaryo 24 (n): --block-only, --always olmadan -> exit 1 ----
PROJ24="$(new_test_project 24)"
run_install --scope=Project --path="$PROJ24" --block-only --home-dir="$TEST_ROOT/home24"
[ "$EXIT_CODE" -eq 1 ]; record $? "Senaryo24: --block-only + --always yok -> exit kodu 1"

# ---- Senaryo 25 (o): both kurulum sonrasi --target=claude tekrar kosu -> CLAUDE.md hala @AGENTS.md, blok cogalmadi (B1) ----
PROJ25="$(new_test_project 25)"
HOME25="$TEST_ROOT/home25"
run_install --scope=Project --path="$PROJ25" --always --block-only --target=both --home-dir="$HOME25"
run_install --scope=Project --path="$PROJ25" --always --block-only --target=claude --home-dir="$HOME25"
[ "$EXIT_CODE" -eq 0 ]; record $? "Senaryo25: exit kodu 0"
CLAUDE25="$PROJ25/CLAUDE.md"
AGENTS25="$PROJ25/AGENTS.md"
[ "$(cat "$CLAUDE25")" = "@AGENTS.md" ]; record $? "Senaryo25: CLAUDE.md hala tam olarak @AGENTS.md"
[ "$(marker_count "$CLAUDE25")" -eq 0 ]; record $? "Senaryo25: CLAUDE.md'de marker yok"
[ "$(marker_count "$AGENTS25")" -eq 1 ]; record $? "Senaryo25: AGENTS.md'de tek marker"

# ---- Senaryo 26 (p): --target=claude, AGENTS.md'de blok zaten var, CLAUDE.md yok -> CLAUDE.md olusturulur (B1) ----
PROJ26="$(new_test_project 26)"
HOME26="$TEST_ROOT/home26"
run_install --scope=Project --path="$PROJ26" --always --block-only --target=codex --home-dir="$HOME26"
AGENTS26="$PROJ26/AGENTS.md"
CLAUDE26="$PROJ26/CLAUDE.md"
[ -f "$AGENTS26" ]; record $? "Senaryo26: on-kosul: AGENTS.md olustu"
[ ! -f "$CLAUDE26" ]; record $? "Senaryo26: on-kosul: CLAUDE.md henuz yok"
run_install --scope=Project --path="$PROJ26" --always --block-only --target=claude --home-dir="$HOME26"
[ "$EXIT_CODE" -eq 0 ]; record $? "Senaryo26: exit kodu 0"
[ -f "$CLAUDE26" ]; record $? "Senaryo26: CLAUDE.md olusturuldu"
[ "$(cat "$CLAUDE26")" = "@AGENTS.md" ]; record $? "Senaryo26: CLAUDE.md tam olarak @AGENTS.md"
[ "$(marker_count "$CLAUDE26")" -eq 0 ]; record $? "Senaryo26: CLAUDE.md'de marker yok"

# ---- Senaryo 27 (q): --purge, --uninstall olmadan -> exit 1, hicbir sey yazilmaz (B2) ----
HOME27="$TEST_ROOT/home27"
run_install --scope=Global --home-dir="$HOME27" --purge
[ "$EXIT_CODE" -eq 1 ]; record $? "Senaryo27: --purge olmadan --uninstall -> exit kodu 1"
[ ! -d "$HOME27" ]; record $? "Senaryo27: home dizini hic olusmadi"

echo ""
echo "Ozet: $PASS_COUNT PASS, $FAIL_COUNT FAIL"

if [ "$FAIL_COUNT" -gt 0 ]; then
    exit 1
fi
exit 0
