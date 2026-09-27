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

echo ""
echo "Ozet: $PASS_COUNT PASS, $FAIL_COUNT FAIL"

if [ "$FAIL_COUNT" -gt 0 ]; then
    exit 1
fi
exit 0
