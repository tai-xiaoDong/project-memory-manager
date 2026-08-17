#!/usr/bin/env bash
# validate.sh — Dev-log consistency validator for project-memory-manager skill.
#
# Usage:
#   bash validate.sh <dev-log-dir/> [--summary <dev-log-summary.md>] [--strict]
#
# Checks:
#   1. File count: warn if > 15 daily files (overflow), error if > 30 (circuit breaker)
#   2. Entry format: each entry must have "### [HH:MM]" header and "**Change**" field
#   3. Entry size: warn if any single entry exceeds 500 characters
#   4. Per-file line count: warn if any daily file exceeds 200 lines
#   5. Filename format: must match YYYY-MM-DD.md pattern
#   6. Chronological order within each daily file (entries oldest-first)
#
# Exit codes: 0 = pass, 1 = errors found

set -euo pipefail

# --- Constants ---
MAX_FILES_NORMAL=15
MAX_FILES_HARD=30
MAX_LINES=200
MAX_ENTRY_CHARS=500

# --- Colors ---
RED='\033[91m'
YELLOW='\033[93m'
GREEN='\033[92m'
BOLD='\033[1m'
RESET='\033[0m'

DEVLOG_DIR=""
SUMMARY=""
STRICT=0
ERRORS=0
WARNINGS=0

# --- Parse args ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        --summary)
            SUMMARY="$2"
            shift 2
            ;;
        --strict)
            STRICT=1
            shift
            ;;
        -*)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
        *)
            if [[ -z "$DEVLOG_DIR" ]]; then
                DEVLOG_DIR="$1"
            else
                echo "Unexpected argument: $1" >&2
                exit 1
            fi
            shift
            ;;
    esac
done

if [[ -z "$DEVLOG_DIR" ]]; then
    echo "Usage: bash validate.sh <dev-log-dir/> [--summary <summary.md>] [--strict]" >&2
    exit 1
fi

# --- Helpers ---
print_error() {
    echo -e "  ${RED}✗${RESET} $1"
    ERRORS=$((ERRORS + 1))
}

print_warning() {
    echo -e "  ${YELLOW}⚠${RESET} $1"
    WARNINGS=$((WARNINGS + 1))
}

print_ok() {
    echo -e "  ${GREEN}✓${RESET} $1"
}

# ============================================================
# Validate dev-log directory
# ============================================================
echo -e "\n${BOLD}Dev-log Validation Report${RESET}\n"

if [[ ! -d "$DEVLOG_DIR" ]]; then
    print_error "Directory not found: $DEVLOG_DIR"
    echo ""
    exit 1
fi

# Collect daily log files (only YYYY-MM-DD.md pattern)
# (while-read instead of mapfile: mapfile needs bash >= 4, macOS ships 3.2)
FILES=()
while IFS= read -r f; do
    FILES+=("$f")
done < <(find "$DEVLOG_DIR" -maxdepth 1 -name '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9].md' | sort)
FILE_COUNT=${#FILES[@]}

# Check 1: File count
if [[ "$FILE_COUNT" -gt "$MAX_FILES_HARD" ]]; then
    print_error "Circuit breaker: ${FILE_COUNT} daily files (max ${MAX_FILES_HARD}). Archive immediately!"
elif [[ "$FILE_COUNT" -gt "$MAX_FILES_NORMAL" ]]; then
    print_warning "Overflow: ${FILE_COUNT} daily files (threshold ${MAX_FILES_NORMAL}). Archive $((FILE_COUNT - MAX_FILES_NORMAL)) oldest."
fi

TOTAL_ENTRIES=0

# Check each daily file ("${FILES[@]+"..."}" guards set -u with an empty array on bash 3.2)
for f in ${FILES[@]+"${FILES[@]}"}; do
    FNAME=$(basename "$f")
    TOTAL_LINES=$(wc -l < "$f" | tr -d ' ')

    # Check 5: Filename format (already filtered by find, but verify)
    if ! echo "$FNAME" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}\.md$'; then
        print_error "Invalid filename: ${FNAME} (expected YYYY-MM-DD.md)"
        continue
    fi

    # Check 4: Per-file line count
    if [[ "$TOTAL_LINES" -gt "$MAX_LINES" ]]; then
        print_warning "${FNAME}: ${TOTAL_LINES} lines (max ${MAX_LINES}). Consider splitting."
    fi

    # Count entries in this file
    ENTRY_COUNT=$(grep -cE '^### \[[0-9]{2}:[0-9]{2}\]' "$f" || true)
    TOTAL_ENTRIES=$((TOTAL_ENTRIES + ENTRY_COUNT))

    # Check 2: Entry format — each header must have a **Change** line
    if [[ "$ENTRY_COUNT" -gt 0 ]]; then
        CHANGE_COUNT=$(grep -cE '^\- \*\*Change\*\*' "$f" || true)
        if [[ "$CHANGE_COUNT" -lt "$ENTRY_COUNT" ]]; then
            print_error "${FNAME}: ${ENTRY_COUNT} entries but only ${CHANGE_COUNT} have \"**Change**\" field"
        fi
    fi

    # Check 3: Entry size — measure CHARACTER count between entry headers.
    # (awk length() counts bytes on BSD awk — Chinese entries false-positive;
    #  wc -m is locale-aware. First line of each temp file = header line number.)
    ENTRY_TMP=$(mktemp -d "${TMPDIR:-/tmp}/pmm.XXXXXX")
    awk -v dir="$ENTRY_TMP" '
        /^### \[[0-9][0-9]:[0-9][0-9]\]/ {
            n++
            out = dir "/e" sprintf("%04d", n)
            print NR > out
        }
        n > 0 { print > out }
    ' "$f"
    for e in "$ENTRY_TMP"/e*; do
        [ -f "$e" ] || continue
        chars=$(wc -m < "$e" | tr -d ' ')
        if [ "$chars" -gt $((MAX_ENTRY_CHARS + 20)) ]; then
            line_num=$(sed -n '1p' "$e")
            header=$(sed -n '2p' "$e" | cut -c1-60)
            print_warning "${FNAME}: oversized entry at ${line_num}: ${header} (${chars} chars)"
        fi
    done
    rm -rf "$ENTRY_TMP"

    # Check 6: Chronological order within file (entries should be oldest-first)
    TIMES=$(grep -oE '^### \[[0-9]{2}:[0-9]{2}\]' "$f" | grep -oE '[0-9]{2}:[0-9]{2}' || true)

    if [[ -n "$TIMES" ]]; then
        PREV=""
        LINE_NUM=0
        while IFS= read -r time; do
            ((LINE_NUM++)) || true
            if [[ -n "$PREV" ]] && [[ "$time" < "$PREV" ]]; then
                print_warning "${FNAME}: entry #${LINE_NUM} (${time}) is older than #$((LINE_NUM - 1)) (${PREV}) — should be oldest-first within a daily file"
            fi
            PREV="$time"
        done <<< "$TIMES"
    fi
done

# Summary for dev-log directory
if [[ "$ERRORS" -eq 0 && "$WARNINGS" -eq 0 ]]; then
    print_ok "dev-log/: All checks passed (${FILE_COUNT} daily files, ${TOTAL_ENTRIES} total entries)"
fi

# ============================================================
# Validate summary (optional)
# ============================================================
if [[ -n "$SUMMARY" ]]; then
    echo ""
    if [[ ! -f "$SUMMARY" ]]; then
        print_error "Summary file not found: $SUMMARY"
    else
        SLABEL="$(basename "$SUMMARY")"
        S_CONTENT=$(cat "$SUMMARY")

        if ! echo "$S_CONTENT" | grep -q "Core Constraints"; then
            print_error "Summary missing required section: Core Constraints"
        fi
        if ! echo "$S_CONTENT" | grep -q "Known Major Issues"; then
            print_error "Summary missing required section: Known Major Issues"
        fi
        if ! echo "$S_CONTENT" | grep -q "Current TODO"; then
            print_error "Summary missing required section: Current TODO"
        fi

        if [[ "$ERRORS" -eq 0 ]]; then
            print_ok "${SLABEL}: All checks passed"
        fi
    fi
fi

echo ""

# --- Exit ---
if [[ "$STRICT" -eq 1 && "$WARNINGS" -gt 0 ]]; then
    exit 1
fi
if [[ "$ERRORS" -gt 0 ]]; then
    exit 1
fi
exit 0
