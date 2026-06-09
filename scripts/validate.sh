#!/usr/bin/env bash
# validate.sh — Dev-log consistency validator for project-memory-manager skill.
#
# Usage:
#   bash validate.sh <dev-log.md> [--summary <dev-log-summary.md>] [--strict]
#
# Checks:
#   1. Entry count: warn if > 15 (overflow), error if > 30 (circuit breaker)
#   2. Entry format: each entry must start with "## [YYYY-MM-DD]" and have "**Change**"
#   3. Entry size: warn if any single entry exceeds 500 characters
#   4. Line count: warn if total file exceeds 200 lines
#   5. Reverse chronological order
#
# Exit codes: 0 = pass, 1 = errors found

set -euo pipefail

# --- Constants ---
MAX_ENTRIES_NORMAL=15
MAX_ENTRIES_HARD=30
MAX_LINES=200
MAX_ENTRY_CHARS=500

# --- Colors ---
RED='\033[91m'
YELLOW='\033[93m'
GREEN='\033[92m'
BOLD='\033[1m'
RESET='\033[0m'

DEVLOG=""
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
            if [[ -z "$DEVLOG" ]]; then
                DEVLOG="$1"
            else
                echo "Unexpected argument: $1" >&2
                exit 1
            fi
            shift
            ;;
    esac
done

if [[ -z "$DEVLOG" ]]; then
    echo "Usage: bash validate.sh <dev-log.md> [--summary <summary.md>] [--strict]" >&2
    exit 1
fi

# --- Helpers ---
print_error() {
    echo -e "  ${RED}✗${RESET} $1"
    ((ERRORS++))
}

print_warning() {
    echo -e "  ${YELLOW}⚠${RESET} $1"
    ((WARNINGS++))
}

print_ok() {
    echo -e "  ${GREEN}✓${RESET} $1"
}

# ============================================================
# Validate dev-log
# ============================================================
echo -e "\n${BOLD}Dev-log Validation Report${RESET}\n"

if [[ ! -f "$DEVLOG" ]]; then
    print_error "File not found: $DEVLOG"
    echo ""
    exit 1
fi

LABEL="$(basename "$DEVLOG")"

# Check: file exists — count lines and entries
TOTAL_LINES=$(wc -l < "$DEVLOG" | tr -d ' ')
ENTRY_COUNT=$(grep -cE '^## \[[0-9]{4}-[0-9]{2}-[0-9]{2}\]' "$DEVLOG" || true)

# Check 1: Entry count
if [[ "$ENTRY_COUNT" -gt "$MAX_ENTRIES_HARD" ]]; then
    print_error "Circuit breaker: ${ENTRY_COUNT} entries (max ${MAX_ENTRIES_HARD}). Archive immediately!"
elif [[ "$ENTRY_COUNT" -gt "$MAX_ENTRIES_NORMAL" ]]; then
    print_warning "Overflow: ${ENTRY_COUNT} entries (threshold ${MAX_ENTRIES_NORMAL}). Archive $((ENTRY_COUNT - MAX_ENTRIES_NORMAL)) oldest."
fi

# Check 2: Entry format — each entry header must be followed by a **Change** line
# We check that the number of ## [date] headers matches the number of - **Change** lines
CHANGE_COUNT=$(grep -cE '^\- \*\*Change\*\*' "$DEVLOG" || true)
if [[ "$CHANGE_COUNT" -lt "$ENTRY_COUNT" ]]; then
    print_error "Format: ${ENTRY_COUNT} entries but only ${CHANGE_COUNT} have \"**Change**\" field"
fi

# Check 3: Entry size — split file by entry headers and measure each chunk
# Use awk to measure character count between entry headers
OVERSIZED=$(awk -v max="$MAX_ENTRY_CHARS" '
    /^## \[[0-9]{4}-[0-9]{2}-[0-9]{2}\]/ {
        if (buf != "" && length(buf) > max) {
            print line_num ": " substr(header, 1, 60) " (" length(buf) " chars)"
        }
        header = $0
        line_num = NR
        buf = $0
        next
    }
    { buf = buf "\n" $0 }
    END {
        if (buf != "" && length(buf) > max) {
            print line_num ": " substr(header, 1, 60) " (" length(buf) " chars)"
        }
    }
' "$DEVLOG")

if [[ -n "$OVERSIZED" ]]; then
    while IFS= read -r line; do
        print_warning "Oversized entry at $line (max ${MAX_ENTRY_CHARS} chars)"
    done <<< "$OVERSIZED"
fi

# Check 4: Line count
if [[ "$TOTAL_LINES" -gt "$MAX_LINES" ]]; then
    print_warning "File has ${TOTAL_LINES} lines (max ${MAX_LINES}). Consider archiving."
fi

# Check 5: Reverse chronological order
DATES=$(grep -oE '^## \[[0-9]{4}-[0-9]{2}-[0-9]{2}\]' "$DEVLOG" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' || true)

if [[ -n "$DATES" ]]; then
    PREV=""
    LINE_NUM=0
    while IFS= read -r date; do
        ((LINE_NUM++)) || true
        if [[ -n "$PREV" ]] && [[ "$date" > "$PREV" ]]; then
            print_warning "Order: entry #${LINE_NUM} (${date}) is newer than entry #$((LINE_NUM - 1)) (${PREV}) — should be newest-first"
        fi
        PREV="$date"
    done <<< "$DATES"
fi

# Summary for dev-log
if [[ "$ERRORS" -eq 0 && "$WARNINGS" -eq 0 ]]; then
    print_ok "${LABEL}: All checks passed (${ENTRY_COUNT} entries, ${TOTAL_LINES} lines)"
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
