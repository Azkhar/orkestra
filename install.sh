#!/usr/bin/env bash
# orkestra skill'ini ve kontrolcu alt ajanini Claude Code ve/veya Codex icin kurar.
# bash 3.2 (macOS) ve Git Bash ile uyumlu, set -euo pipefail.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SCOPE="Global"
PROJECT_PATH=""
TARGET="both"
FORCE=0
DRYRUN=0
UNINSTALL=0
HOME_DIR="${HOME:-}"
ALWAYS=0
LOCAL=0
PROFILE_ARG=""
PURGE=0
BLOCK_ONLY=0

print_usage() {
    cat <<'EOF'
Usage: install.sh [--scope=Global|Project] [--path=<dir>] [--target=both|claude|codex]
                   [--force] [--dry-run] [--uninstall] [--home-dir=<dir>]
                   [--always] [--local] [--profile=lean|balanced|generous]
                   [--purge] [--block-only]
EOF
}

require_value() {
    # $1: bayrak adi (mesaj icin), $2: cagri anindaki kalan arguman sayisi ($#)
    if [ "$2" -lt 2 ]; then
        echo "$1 bir deger bekliyor" >&2
        exit 1
    fi
}

while [ $# -gt 0 ]; do
    case "$1" in
        --scope=*) SCOPE="${1#*=}"; shift ;;
        --scope)
            require_value "--scope" "$#"
            SCOPE="$2"; shift 2 ;;
        --path=*) PROJECT_PATH="${1#*=}"; shift ;;
        --path)
            require_value "--path" "$#"
            PROJECT_PATH="$2"; shift 2 ;;
        --target=*) TARGET="${1#*=}"; shift ;;
        --target)
            require_value "--target" "$#"
            TARGET="$2"; shift 2 ;;
        --force) FORCE=1; shift ;;
        --dry-run) DRYRUN=1; shift ;;
        --uninstall) UNINSTALL=1; shift ;;
        --home-dir=*) HOME_DIR="${1#*=}"; shift ;;
        --home-dir)
            require_value "--home-dir" "$#"
            HOME_DIR="$2"; shift 2 ;;
        --always) ALWAYS=1; shift ;;
        --local) LOCAL=1; shift ;;
        --profile=*) PROFILE_ARG="${1#*=}"; shift ;;
        --profile)
            require_value "--profile" "$#"
            PROFILE_ARG="$2"; shift 2 ;;
        --purge) PURGE=1; shift ;;
        --block-only) BLOCK_ONLY=1; shift ;;
        -h|--help) print_usage; exit 0 ;;
        *)
            echo "bilinmeyen parametre: $1" >&2
            print_usage
            exit 1
            ;;
    esac
done

# scope/target buyuk-kucuk harf duyarsiz (ps1 ValidateSet ile tutarli)
SCOPE_LOWER="$(printf '%s' "$SCOPE" | tr '[:upper:]' '[:lower:]')"
case "$SCOPE_LOWER" in
    global) SCOPE="Global" ;;
    project) SCOPE="Project" ;;
    *)
        echo "gecersiz --scope: $SCOPE (Global veya Project olmali)" >&2
        exit 1
        ;;
esac

TARGET_LOWER="$(printf '%s' "$TARGET" | tr '[:upper:]' '[:lower:]')"
case "$TARGET_LOWER" in
    both) TARGET="both" ;;
    claude) TARGET="claude" ;;
    codex) TARGET="codex" ;;
    *)
        echo "gecersiz --target: $TARGET (both, claude veya codex olmali)" >&2
        exit 1
        ;;
esac

if [ "$BLOCK_ONLY" -eq 1 ] && [ "$ALWAYS" -ne 1 ]; then
    echo "--block-only yalnizca --always ile birlikte kullanilir" >&2
    exit 1
fi

if [ "$PURGE" -eq 1 ] && [ "$UNINSTALL" -ne 1 ]; then
    echo "--purge yalnizca --uninstall ile birlikte kullanilir" >&2
    exit 1
fi

if [ "$ALWAYS" -eq 1 ] && [ "$SCOPE" != "Project" ]; then
    echo "Conductor modu (--always) proje bazlidir: --scope=Project ve --path kullanin" >&2
    exit 1
fi

PROFILE_NORMALIZED=""
if [ -n "$PROFILE_ARG" ]; then
    PROFILE_NORMALIZED="$(printf '%s' "$PROFILE_ARG" | tr '[:upper:]' '[:lower:]')"
    case "$PROFILE_NORMALIZED" in
        lean|balanced|generous) ;;
        *)
            echo "gecersiz --profile: $PROFILE_ARG (lean, balanced veya generous olmali)" >&2
            exit 1
            ;;
    esac
fi

if [ "$SCOPE" = "Global" ] && [ -n "$PROJECT_PATH" ]; then
    echo "uyari: Global scope'ta --path yok sayiliyor" >&2
fi

if [ "$SCOPE" = "Project" ]; then
    if [ -z "$PROJECT_PATH" ]; then
        echo "Project scope icin --path zorunlu" >&2
        exit 1
    fi
    if [ ! -d "$PROJECT_PATH" ]; then
        echo "Proje yolu bulunamadi: $PROJECT_PATH" >&2
        exit 1
    fi
    BASE="$(cd "$PROJECT_PATH" && pwd)"
else
    BASE="$HOME_DIR"
fi

if [ -z "$BASE" ]; then
    echo "gecerli bir taban dizin yok (HOME bos ve --home-dir verilmedi); --home-dir ile belirtin" >&2
    exit 1
fi

SRC_SKILL_DIR="$SCRIPT_DIR/skills/orkestra"
SRC_AGENT_FILE="$SCRIPT_DIR/agents/kontrolcu.md"
SRC_CONDUCTOR_BLOCK="$SCRIPT_DIR/templates/conductor-block.md"
SRC_PROFILES_DIR="$SCRIPT_DIR/templates/profiles"

if [ "$BLOCK_ONLY" -ne 1 ]; then
    if [ ! -d "$SRC_SKILL_DIR" ]; then
        echo "Kaynak skill klasoru bulunamadi: $SRC_SKILL_DIR" >&2
        exit 1
    fi
    if [ ! -f "$SRC_AGENT_FILE" ]; then
        echo "Kaynak agent dosyasi bulunamadi: $SRC_AGENT_FILE" >&2
        exit 1
    fi
fi

if [ "$ALWAYS" -eq 1 ] && [ ! -f "$SRC_CONDUCTOR_BLOCK" ]; then
    echo "Kaynak conductor blogu bulunamadi: $SRC_CONDUCTOR_BLOCK" >&2
    exit 1
fi
if [ -n "$PROFILE_NORMALIZED" ] && [ ! -f "$SRC_PROFILES_DIR/$PROFILE_NORMALIZED.json" ]; then
    echo "Kaynak profil dosyasi bulunamadi: $SRC_PROFILES_DIR/$PROFILE_NORMALIZED.json" >&2
    exit 1
fi

TMP_A="$(mktemp "${TMPDIR:-/tmp}/orkestra-cmp-a.XXXXXX")"
TMP_B="$(mktemp "${TMPDIR:-/tmp}/orkestra-cmp-b.XXXXXX")"
WORK_TMP="$(mktemp -d "${TMPDIR:-/tmp}/orkestra-work.XXXXXX")"
PLAIN_FILE="$WORK_TMP/plain"
RAW_FILE="$WORK_TMP/raw"
NEWLF_FILE="$WORK_TMP/newlf"
FINAL_FILE="$WORK_TMP/final"
BOM_FILE="$WORK_TMP/bom"
printf '\357\273\277' > "$BOM_FILE"
trap 'rm -f "$TMP_A" "$TMP_B"; rm -rf "$WORK_TMP"' EXIT

hash_file() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum -- "$1" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 -- "$1" | awk '{print $1}'
    else
        openssl dgst -sha256 -- "$1" | awk '{print $NF}'
    fi
}

dirs_identical() {
    src="$1"; dst="$2"
    [ -d "$dst" ] || return 1
    (cd "$src" && find . -type f | sort) > "$TMP_A"
    (cd "$dst" && find . -type f | sort) > "$TMP_B"
    if ! diff -q "$TMP_A" "$TMP_B" >/dev/null 2>&1; then
        return 1
    fi
    while IFS= read -r rel; do
        [ -z "$rel" ] && continue
        ha="$(hash_file "$src/$rel")"
        hb="$(hash_file "$dst/$rel")"
        if [ "$ha" != "$hb" ]; then
            return 1
        fi
    done < "$TMP_A"
    return 0
}

files_identical() {
    src="$1"; dst="$2"
    [ -f "$dst" ] || return 1
    ha="$(hash_file "$src")"
    hb="$(hash_file "$dst")"
    [ "$ha" = "$hb" ]
}

is_orkestra_skill_dir() {
    d="$1"
    f="$d/SKILL.md"
    [ -f "$f" ] || return 1
    head -n 10 "$f" | grep -Eq '^name:[[:space:]]*orkestra[[:space:]]*$'
}

is_kontrolcu_agent() {
    f="$1"
    [ -f "$f" ] || return 1
    head -n 10 "$f" | grep -Eq '^name:[[:space:]]*kontrolcu[[:space:]]*$'
}

file_has_block() {
    # Dosyada begin/end marker cifti var mi diye bakar, dosyaya dokunmaz.
    f="$1"
    [ -f "$f" ] || return 1
    to_plain_lf "$f"
    begin_line="$(awk -v re="$BLOCK_BEGIN_RE" '$0 ~ re {print NR; exit}' "$PLAIN_FILE")"
    [ -n "$begin_line" ] || return 1
    end_line="$(awk -v re="$BLOCK_END_RE" -v b="$begin_line" 'NR> b && $0 ~ re {print NR; exit}' "$PLAIN_FILE")"
    [ -n "$end_line" ]
}

# ---- Conductor modu (--always) ve profil (--profile) icin yardimci fonksiyonlar ----

BLOCK_BEGIN_RE='^<!--[[:space:]]*orkestra:begin'
BLOCK_END_RE='^<!--[[:space:]]*orkestra:end[[:space:]]*-->[[:space:]]*$'

has_bom() {
    [ -f "$1" ] || return 1
    head -c 3 -- "$1" 2>/dev/null | cmp -s - "$BOM_FILE"
}

is_crlf_file() {
    # grep ile \r arama bazi Git Bash/MSYS ortamlarinda metin-modu donusumu yuzunden
    # guvenilmez calisiyor; bunun yerine tr ile \r silmeden once/sonra byte boyutunu
    # karsilastiriyoruz (fark varsa dosyada \r vardir).
    orig_size="$(wc -c < "$1")"
    stripped_size="$(tr -d '\r' < "$1" | wc -c)"
    [ "$orig_size" != "$stripped_size" ]
}

# Dosyayi BOM'dan arindirip CRLF -> LF cevirir, $PLAIN_FILE'a yazar.
# Global degiskenleri set eder: HADBOM, ISCRLF
to_plain_lf() {
    f="$1"
    HADBOM=0
    ISCRLF=0
    if has_bom "$f"; then
        HADBOM=1
        tail -c +4 -- "$f" > "$RAW_FILE"
    else
        cat -- "$f" > "$RAW_FILE"
    fi
    if is_crlf_file "$RAW_FILE"; then
        ISCRLF=1
    fi
    tr -d '\r' < "$RAW_FILE" > "$PLAIN_FILE"
}

# $PLAIN_FILE'daki LF icerigi verilen BOM/CRLF stiline cevirip hedefe yazar.
write_from_lf() {
    # $1: kaynak LF dosyasi, $2: hedef yol, $3: hadbom(0/1), $4: iscrlf(0/1)
    src="$1"; dst="$2"; hadbom="$3"; iscrlf="$4"
    mkdir -p -- "$(dirname "$dst")"
    if [ "$iscrlf" -eq 1 ]; then
        awk '{printf "%s\r\n", $0}' "$src" > "$FINAL_FILE"
    else
        cat -- "$src" > "$FINAL_FILE"
    fi
    if [ "$hadbom" -eq 1 ]; then
        cat "$BOM_FILE" "$FINAL_FILE" > "$dst"
    else
        cat -- "$FINAL_FILE" > "$dst"
    fi
}

# Blogu dosyada kurar/gunceller/ekler. Sonuc $UPSERT_ACTION'da doner.
# $1: hedef yol, $2: blok sablon dosyasi (LF, sondaki newline'siz), $3: dryrun(0/1)
upsert_block_file() {
    target="$1"; blockfile="$2"; dryrun="$3"
    if [ ! -f "$target" ]; then
        if [ "$dryrun" -eq 1 ]; then UPSERT_ACTION="kurulacak"; return 0; fi
        mkdir -p -- "$(dirname "$target")"
        { cat -- "$blockfile"; printf '\n'; } > "$target"
        UPSERT_ACTION="kuruldu"
        return 0
    fi

    to_plain_lf "$target"
    hadbom=$HADBOM
    iscrlf=$ISCRLF

    begin_line="$(awk -v re="$BLOCK_BEGIN_RE" '$0 ~ re {print NR; exit}' "$PLAIN_FILE")"
    end_line=""
    if [ -n "$begin_line" ]; then
        end_line="$(awk -v re="$BLOCK_END_RE" -v b="$begin_line" 'NR> b && $0 ~ re {print NR; exit}' "$PLAIN_FILE")"
    fi

    if [ -n "$begin_line" ] && [ -n "$end_line" ]; then
        existingblock="$(sed -n "${begin_line},${end_line}p" "$PLAIN_FILE")"
        templateblock="$(cat -- "$blockfile")"
        if [ "$existingblock" = "$templateblock" ]; then
            UPSERT_ACTION="guncel"
            return 0
        fi
        if [ "$dryrun" -eq 1 ]; then UPSERT_ACTION="guncellenecek"; return 0; fi
        before_end=$((begin_line - 1))
        after_start=$((end_line + 1))
        {
            if [ "$before_end" -ge 1 ]; then sed -n "1,${before_end}p" "$PLAIN_FILE"; fi
            cat -- "$blockfile"
            printf '\n'
            sed -n "${after_start},\$p" "$PLAIN_FILE"
        } > "$NEWLF_FILE"
        UPSERT_ACTION="guncellendi"
    else
        if [ "$dryrun" -eq 1 ]; then UPSERT_ACTION="eklenecek"; return 0; fi
        original="$(cat -- "$PLAIN_FILE")"
        if [ -z "$original" ]; then
            { cat -- "$blockfile"; printf '\n'; } > "$NEWLF_FILE"
        else
            {
                printf '%s\n\n' "$original"
                cat -- "$blockfile"
                printf '\n'
            } > "$NEWLF_FILE"
        fi
        UPSERT_ACTION="eklendi"
    fi

    write_from_lf "$NEWLF_FILE" "$target" "$hadbom" "$iscrlf"
    return 0
}

# Blogu (ondeki bos satiriyla) dosyadan kaldirir. Sonuc $REMOVE_ACTION, $REMOVE_DELETED,
# $REMOVE_NOBLOCK_CONTENT (blok yoksa kalan icerik) icinde doner.
# $1: hedef yol, $2: dryrun(0/1)
remove_block_file() {
    target="$1"; dryrun="$2"
    REMOVE_DELETED=0
    REMOVE_NOBLOCK_CONTENT=""
    if [ ! -f "$target" ]; then
        REMOVE_ACTION="yok"
        return 0
    fi

    to_plain_lf "$target"
    hadbom=$HADBOM
    iscrlf=$ISCRLF

    begin_line="$(awk -v re="$BLOCK_BEGIN_RE" '$0 ~ re {print NR; exit}' "$PLAIN_FILE")"
    end_line=""
    if [ -n "$begin_line" ]; then
        end_line="$(awk -v re="$BLOCK_END_RE" -v b="$begin_line" 'NR> b && $0 ~ re {print NR; exit}' "$PLAIN_FILE")"
    fi

    if [ -z "$begin_line" ] || [ -z "$end_line" ]; then
        REMOVE_ACTION="atlandi: blok yok"
        REMOVE_NOBLOCK_CONTENT="$(cat -- "$PLAIN_FILE")"
        return 0
    fi

    remove_from=$begin_line
    if [ "$begin_line" -gt 1 ]; then
        prevline="$(sed -n "$((begin_line - 1))p" "$PLAIN_FILE")"
        if [ -z "$prevline" ]; then
            remove_from=$((begin_line - 1))
        fi
    fi

    before_end=$((remove_from - 1))
    after_start=$((end_line + 1))
    {
        if [ "$before_end" -ge 1 ]; then sed -n "1,${before_end}p" "$PLAIN_FILE"; fi
        sed -n "${after_start},\$p" "$PLAIN_FILE"
    } > "$NEWLF_FILE"

    newcontent="$(cat -- "$NEWLF_FILE")"
    trimmedcheck="$(printf '%s' "$newcontent" | tr -d '[:space:]')"
    if [ -z "$trimmedcheck" ]; then
        if [ "$dryrun" -eq 1 ]; then REMOVE_ACTION="silinecek"; return 0; fi
        rm -f -- "$target"
        REMOVE_ACTION="silindi"
        REMOVE_DELETED=1
        return 0
    fi

    if [ "$dryrun" -eq 1 ]; then REMOVE_ACTION="kaldirilacak"; return 0; fi

    write_from_lf "$NEWLF_FILE" "$target" "$hadbom" "$iscrlf"
    REMOVE_ACTION="kaldirildi"
    return 0
}

CLAUDE_BASE="$BASE/.claude"
CODEX_SKILL_DST="$BASE/.agents/skills/orkestra"

NAMES=()
SRCS=()
DSTS=()
KINDS=()

if [ "$BLOCK_ONLY" -ne 1 ]; then
if [ "$TARGET" = "both" ] || [ "$TARGET" = "claude" ]; then
    NAMES+=("claude-skill"); SRCS+=("$SRC_SKILL_DIR"); DSTS+=("$CLAUDE_BASE/skills/orkestra"); KINDS+=("dir")
    NAMES+=("claude-agent"); SRCS+=("$SRC_AGENT_FILE"); DSTS+=("$CLAUDE_BASE/agents/kontrolcu.md"); KINDS+=("file")
fi
if [ "$TARGET" = "both" ] || [ "$TARGET" = "codex" ]; then
    NAMES+=("codex-skill"); SRCS+=("$SRC_SKILL_DIR"); DSTS+=("$CODEX_SKILL_DST"); KINDS+=("dir")
fi
fi

HAD_SKIP=0
i=0
n=${#NAMES[@]}
while [ "$i" -lt "$n" ]; do
    src="${SRCS[$i]}"
    dst="${DSTS[$i]}"
    kind="${KINDS[$i]}"

    if [ "$UNINSTALL" -eq 1 ]; then
        if [ "$kind" = "dir" ]; then
            if [ ! -d "$dst" ]; then
                echo "yok  $dst"
            elif ! is_orkestra_skill_dir "$dst"; then
                echo "atlandi: bizim degil  $dst"
            elif [ "$DRYRUN" -eq 1 ]; then
                echo "kaldirilacak  $dst"
            else
                rm -rf -- "$dst"
                echo "kaldirildi  $dst"
            fi
        else
            if [ ! -f "$dst" ]; then
                echo "yok  $dst"
            elif ! is_kontrolcu_agent "$dst"; then
                echo "atlandi: bizim degil  $dst"
            elif [ "$DRYRUN" -eq 1 ]; then
                echo "kaldirilacak  $dst"
            else
                rm -f -- "$dst"
                echo "kaldirildi  $dst"
            fi
        fi
        i=$((i + 1))
        continue
    fi

    # kurulum modu
    if [ "$kind" = "dir" ]; then
        if [ ! -d "$dst" ]; then
            if [ "$DRYRUN" -eq 1 ]; then
                echo "kurulacak  $dst"
            else
                mkdir -p -- "$(dirname "$dst")"
                cp -R "$src" "$dst"
                echo "kuruldu  $dst"
            fi
        elif dirs_identical "$src" "$dst"; then
            echo "guncel  $dst"
        else
            if [ "$FORCE" -ne 1 ]; then
                echo "atlandi: farkli, --force ile uzerine yaz  $dst"
                HAD_SKIP=1
            else
                if [ "$DRYRUN" -eq 1 ]; then
                    echo "yedeklenecek-ve-kurulacak  $dst"
                else
                    # yedegi skills/ klasorunun disina (bir ust seviyeye) tasi:
                    # <...>/.claude/orkestra.bak-<ts> / <...>/.agents/orkestra.bak-<ts>
                    # boylece Claude/Codex onu ayri bir skill olarak taramaz.
                    skills_parent="$(dirname "$dst")"
                    container_base="$(dirname "$skills_parent")"
                    leaf="$(basename "$dst")"
                    ts="$(date +%Y%m%d%H%M%S)"
                    bak="$container_base/$leaf.bak-$ts"
                    mv -- "$dst" "$bak"
                    cp -R "$src" "$dst"
                    echo "yedeklendi ve kuruldu  $dst"
                fi
            fi
        fi
    else
        if [ ! -f "$dst" ]; then
            if [ "$DRYRUN" -eq 1 ]; then
                echo "kurulacak  $dst"
            else
                mkdir -p -- "$(dirname "$dst")"
                cp "$src" "$dst"
                echo "kuruldu  $dst"
            fi
        elif files_identical "$src" "$dst"; then
            echo "guncel  $dst"
        else
            if [ "$FORCE" -ne 1 ]; then
                echo "atlandi: farkli, --force ile uzerine yaz  $dst"
                HAD_SKIP=1
            else
                if [ "$DRYRUN" -eq 1 ]; then
                    echo "yedeklenecek-ve-kurulacak  $dst"
                else
                    ts="$(date +%Y%m%d%H%M%S)"
                    mv -- "$dst" "$dst.bak-$ts"
                    cp "$src" "$dst"
                    echo "yedeklendi ve kuruldu  $dst"
                fi
            fi
        fi
    fi

    i=$((i + 1))
done

# ---- Conductor modu (--always): AGENTS.md / CLAUDE.md / CLAUDE.local.md ----
if [ "$ALWAYS" -eq 1 ]; then
    AGENTS_PATH="$BASE/AGENTS.md"
    CLAUDE_MD_PATH="$BASE/CLAUDE.md"
    CLAUDE_LOCAL_PATH="$BASE/CLAUDE.local.md"

    if [ "$UNINSTALL" -eq 1 ]; then
        AGENTS_DELETED=0
        if [ "$TARGET" = "both" ] || [ "$TARGET" = "codex" ]; then
            remove_block_file "$AGENTS_PATH" "$DRYRUN"
            echo "$REMOVE_ACTION  $AGENTS_PATH"
            if [ "$REMOVE_DELETED" -eq 1 ]; then AGENTS_DELETED=1; fi
        fi
        if [ "$TARGET" = "both" ] || [ "$TARGET" = "claude" ]; then
            remove_block_file "$CLAUDE_MD_PATH" "$DRYRUN"
            claude_action="$REMOVE_ACTION"
            if [ "$claude_action" = "atlandi: blok yok" ] && [ "$AGENTS_DELETED" -eq 1 ] && [ "$REMOVE_NOBLOCK_CONTENT" = "@AGENTS.md" ]; then
                if [ "$DRYRUN" -eq 1 ]; then
                    claude_action="silinecek"
                else
                    rm -f -- "$CLAUDE_MD_PATH"
                    claude_action="silindi"
                fi
            fi
            echo "$claude_action  $CLAUDE_MD_PATH"

            remove_block_file "$CLAUDE_LOCAL_PATH" "$DRYRUN"
            echo "$REMOVE_ACTION  $CLAUDE_LOCAL_PATH"
        fi
    else
        BLOCK_TEMPLATE_FILE="$WORK_TMP/block-template"
        printf '%s' "$(cat -- "$SRC_CONDUCTOR_BLOCK")" > "$BLOCK_TEMPLATE_FILE"

        AGENTS_HAS_BLOCK=0
        if [ "$LOCAL" -ne 1 ] && file_has_block "$AGENTS_PATH"; then
            AGENTS_HAS_BLOCK=1
        fi
        if [ "$LOCAL" -ne 1 ] && { [ "$TARGET" = "both" ] || [ "$TARGET" = "codex" ]; }; then
            upsert_block_file "$AGENTS_PATH" "$BLOCK_TEMPLATE_FILE" "$DRYRUN"
            echo "$UPSERT_ACTION  $AGENTS_PATH"
            AGENTS_HAS_BLOCK=1
        fi
        if [ "$LOCAL" -eq 1 ] && { [ "$TARGET" = "both" ] || [ "$TARGET" = "codex" ]; }; then
            echo "atlandi: Codex icin yerel talimat dosyasi yok  $AGENTS_PATH"
        fi
        if [ "$TARGET" = "both" ] || [ "$TARGET" = "claude" ]; then
            if [ "$LOCAL" -eq 1 ]; then
                upsert_block_file "$CLAUDE_LOCAL_PATH" "$BLOCK_TEMPLATE_FILE" "$DRYRUN"
                echo "$UPSERT_ACTION  $CLAUDE_LOCAL_PATH"
                case "$UPSERT_ACTION" in
                    kuruldu|guncellendi|eklendi)
                        echo "not: CLAUDE.local.md dosyasini .gitignore'a ekleyin (gizli tutulmasi onerilir)"
                        ;;
                esac
            else
                has_import=0
                if [ -f "$CLAUDE_MD_PATH" ] && tr -d '\r' < "$CLAUDE_MD_PATH" | grep -qx '@AGENTS.md'; then
                    has_import=1
                fi
                if [ "$AGENTS_HAS_BLOCK" -eq 1 ] && [ -f "$CLAUDE_MD_PATH" ] && [ "$has_import" -eq 1 ]; then
                    echo "AGENTS.md uzerinden  $CLAUDE_MD_PATH"
                elif [ "$AGENTS_HAS_BLOCK" -eq 1 ] && [ ! -f "$CLAUDE_MD_PATH" ]; then
                    if [ "$DRYRUN" -eq 1 ]; then
                        echo "kurulacak  $CLAUDE_MD_PATH"
                    else
                        mkdir -p -- "$(dirname "$CLAUDE_MD_PATH")"
                        printf '@AGENTS.md\n' > "$CLAUDE_MD_PATH"
                        echo "kuruldu  $CLAUDE_MD_PATH"
                    fi
                else
                    upsert_block_file "$CLAUDE_MD_PATH" "$BLOCK_TEMPLATE_FILE" "$DRYRUN"
                    echo "$UPSERT_ACTION  $CLAUDE_MD_PATH"
                fi
            fi
        fi
    fi
fi

# ---- Limit profili (--profile) ----
if [ -n "$PROFILE_NORMALIZED" ]; then
    ORKESTRA_DIR="$HOME_DIR/.orkestra"
    CONFIG_PATH="$ORKESTRA_DIR/config.json"
    SRC_PROFILE_FILE="$SRC_PROFILES_DIR/$PROFILE_NORMALIZED.json"

    if [ "$UNINSTALL" -ne 1 ]; then
        if [ ! -f "$CONFIG_PATH" ]; then
            if [ "$DRYRUN" -eq 1 ]; then
                echo "kurulacak  $CONFIG_PATH"
            else
                mkdir -p -- "$ORKESTRA_DIR"
                cp "$SRC_PROFILE_FILE" "$CONFIG_PATH"
                echo "kuruldu  $CONFIG_PATH"
            fi
        elif files_identical "$SRC_PROFILE_FILE" "$CONFIG_PATH"; then
            echo "guncel  $CONFIG_PATH"
        else
            if [ "$FORCE" -ne 1 ]; then
                echo "atlandi: mevcut config farkli, /orkestra settings ile degistirin veya --force kullanin  $CONFIG_PATH"
                HAD_SKIP=1
            else
                if [ "$DRYRUN" -eq 1 ]; then
                    echo "yedeklenecek-ve-kurulacak  $CONFIG_PATH"
                else
                    ts="$(date +%Y%m%d%H%M%S)"
                    mv -- "$CONFIG_PATH" "$CONFIG_PATH.bak-$ts"
                    cp "$SRC_PROFILE_FILE" "$CONFIG_PATH"
                    echo "yedeklendi ve kuruldu  $CONFIG_PATH"
                fi
            fi
        fi
    fi
fi

# ---- Uninstall + --purge: config.json'u da kaldir ----
if [ "$UNINSTALL" -eq 1 ] && [ "$PURGE" -eq 1 ]; then
    ORKESTRA_DIR="$HOME_DIR/.orkestra"
    CONFIG_PATH="$ORKESTRA_DIR/config.json"
    if [ ! -f "$CONFIG_PATH" ]; then
        echo "yok  $CONFIG_PATH"
    elif [ "$DRYRUN" -eq 1 ]; then
        echo "kaldirilacak  $CONFIG_PATH"
    else
        rm -f -- "$CONFIG_PATH"
        echo "kaldirildi  $CONFIG_PATH"
        if [ -d "$ORKESTRA_DIR" ]; then
            remaining="$(find "$ORKESTRA_DIR" -mindepth 1 2>/dev/null | head -n 1)"
            if [ -z "$remaining" ]; then
                rmdir -- "$ORKESTRA_DIR" 2>/dev/null || true
            fi
        fi
    fi
fi

if [ "$HAD_SKIP" -eq 1 ]; then
    exit 2
fi
exit 0
