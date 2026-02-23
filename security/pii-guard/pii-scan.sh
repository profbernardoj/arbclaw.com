#!/usr/bin/env bash
# pii-scan.sh — Scan files, directories, or text for PII patterns
# Part of EverClaw PII Guard
# Usage:
#   pii-scan.sh <file_or_directory>    Scan file(s)
#   pii-scan.sh --text "string"        Scan a string
#   echo "content" | pii-scan.sh -     Scan stdin
#
# Exit codes: 0 = clean, 1 = PII found, 2 = error
set -uo pipefail

# Resolve workspace — check common locations
find_patterns_file() {
  local candidates=(
    "${PII_PATTERNS_FILE:-}"
    "$HOME/.openclaw/workspace/.pii-patterns.json"
    "./.pii-patterns.json"
  )
  for f in "${candidates[@]}"; do
    [[ -n "$f" && -f "$f" ]] && echo "$f" && return 0
  done
  return 1
}

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BOLD='\033[1m'
NC='\033[0m'

PATTERNS_FILE=$(find_patterns_file) || {
  echo -e "${RED}Error: .pii-patterns.json not found.${NC}" >&2
  echo -e "Run the setup script first: bash security/pii-guard/setup.sh" >&2
  exit 2
}

if ! command -v jq &>/dev/null; then
  echo -e "${RED}Error: jq required (brew install jq / apt install jq)${NC}" >&2
  exit 2
fi

# Build grep pattern from JSON
build_patterns() {
  local result=""
  
  # Standard string patterns
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    local escaped
    escaped=$(printf '%s' "$line" | sed 's/[.[\*^$()+?{|]/\\&/g')
    if [[ -n "$result" ]]; then
      result="$result|$escaped"
    else
      result="$escaped"
    fi
  done < <(jq -r '
    (.names // [])[] ,
    (.emails // [])[] ,
    (.phones // [])[] ,
    (.wallets // [])[] ,
    (.organizations // [])[] ,
    (.people // [])[] ,
    (.websites // [])[] ,
    (.keywords // [])[]
  ' "$PATTERNS_FILE" 2>/dev/null)
  
  # Regex patterns (added raw, not escaped)
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    if [[ -n "$result" ]]; then
      result="$result|$line"
    else
      result="$line"
    fi
  done < <(jq -r '(.regex // [])[]' "$PATTERNS_FILE" 2>/dev/null)
  
  echo "$result"
}

# Identify which category a match belongs to
identify_category() {
  local match="$1"
  for cat in names emails phones wallets organizations people websites keywords; do
    if jq -r "(.${cat} // [])[]" "$PATTERNS_FILE" 2>/dev/null | grep -qiF "$match"; then
      echo "$cat"
      return
    fi
  done
  echo "pattern"
}

GREP_PATTERN=$(build_patterns)

if [[ -z "$GREP_PATTERN" ]]; then
  echo -e "${GREEN}✓ PII Guard: no patterns configured${NC}"
  exit 0
fi

scan_content() {
  local source_label="$1"
  local content="$2"
  local matches
  matches=$(echo "$content" | grep -inE "$GREP_PATTERN" 2>/dev/null || true)

  if [[ -n "$matches" ]]; then
    echo -e "${RED}${BOLD}🚫 PII GUARD: Personal data detected!${NC}"
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}Source: ${source_label}${NC}"
    echo ""
    
    local count=0
    while IFS= read -r line; do
      count=$((count + 1))
      [[ $count -gt 20 ]] && echo -e "${YELLOW}... truncated (showing first 20)${NC}" && break
      local line_num="${line%%:*}"
      local line_content="${line#*:}"
      local matched_text
      matched_text=$(echo "$line_content" | grep -oiE "$GREP_PATTERN" 2>/dev/null | head -1)
      local category
      category=$(identify_category "$matched_text")
      echo -e "  Line ${line_num}: ${RED}${matched_text}${NC} (${category})"
    done <<< "$matches"
    
    echo ""
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    return 1
  fi
  return 0
}

# Main
found_any=0

if [[ "${1:-}" == "--text" ]]; then
  shift
  scan_content "text input" "$*" || found_any=1

elif [[ "${1:-}" == "-" ]]; then
  content=$(cat)
  scan_content "stdin" "$content" || found_any=1

elif [[ -n "${1:-}" ]]; then
  for target in "$@"; do
    if [[ -d "$target" ]]; then
      while IFS= read -r -d '' f; do
        if file -b --mime-type "$f" 2>/dev/null | grep -q "^text/"; then
          content=$(cat "$f")
          scan_content "$f" "$content" || found_any=1
        fi
      done < <(find "$target" -type f -not -path '*/.git/*' -not -name '*.png' -not -name '*.jpg' -not -name '*.jpeg' -not -name '*.gif' -not -name '*.ico' -not -name '*.woff*' -print0 2>/dev/null)
    elif [[ -f "$target" ]]; then
      content=$(cat "$target")
      scan_content "$target" "$content" || found_any=1
    else
      echo -e "${YELLOW}Warning: $target not found, skipping${NC}" >&2
    fi
  done
else
  echo "PII Guard Scanner — EverClaw Security"
  echo ""
  echo "Usage:"
  echo "  pii-scan.sh <file_or_dir>     Scan files for PII"
  echo "  pii-scan.sh --text \"string\"    Scan a string"
  echo "  echo \"content\" | pii-scan.sh - Scan stdin"
  echo ""
  echo "Exit codes: 0=clean, 1=PII found, 2=error"
  echo "Patterns: $PATTERNS_FILE"
  exit 2
fi

if [[ $found_any -eq 0 ]]; then
  echo -e "${GREEN}✓ PII Guard: scan clean — no personal data detected${NC}"
  exit 0
else
  exit 1
fi
