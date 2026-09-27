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

print_usage() {
    cat <<'EOF'
Usage: install.sh [--scope=Global|Project] [--path=<dir>] [--target=both|claude|codex]
                   [--force] [--dry-run] [--uninstall] [--home-dir=<dir>]
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

if [ ! -d "$SRC_SKILL_DIR" ]; then
    echo "Kaynak skill klasoru bulunamadi: $SRC_SKILL_DIR" >&2
    exit 1
fi
if [ ! -f "$SRC_AGENT_FILE" ]; then
    echo "Kaynak agent dosyasi bulunamadi: $SRC_AGENT_FILE" >&2
    exit 1
fi

TMP_A="$(mktemp "${TMPDIR:-/tmp}/orkestra-cmp-a.XXXXXX")"
TMP_B="$(mktemp "${TMPDIR:-/tmp}/orkestra-cmp-b.XXXXXX")"
trap 'rm -f "$TMP_A" "$TMP_B"' EXIT

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

CLAUDE_BASE="$BASE/.claude"
CODEX_SKILL_DST="$BASE/.agents/skills/orkestra"

NAMES=()
SRCS=()
DSTS=()
KINDS=()

if [ "$TARGET" = "both" ] || [ "$TARGET" = "claude" ]; then
    NAMES+=("claude-skill"); SRCS+=("$SRC_SKILL_DIR"); DSTS+=("$CLAUDE_BASE/skills/orkestra"); KINDS+=("dir")
    NAMES+=("claude-agent"); SRCS+=("$SRC_AGENT_FILE"); DSTS+=("$CLAUDE_BASE/agents/kontrolcu.md"); KINDS+=("file")
fi
if [ "$TARGET" = "both" ] || [ "$TARGET" = "codex" ]; then
    NAMES+=("codex-skill"); SRCS+=("$SRC_SKILL_DIR"); DSTS+=("$CODEX_SKILL_DST"); KINDS+=("dir")
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

if [ "$HAD_SKIP" -eq 1 ]; then
    exit 2
fi
exit 0
