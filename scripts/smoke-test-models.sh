#!/usr/bin/env bash
# smoke-test-models.sh — Send a tiny prompt to each LLM model via LiteLLM
# and report pass/fail with response time.
#
# Usage:
#   smoke-test-models.sh --key-file /tmp/.smoke-key --models "model1,model2,..."
#   smoke-test-models.sh --key-file /tmp/.smoke-key --models "model1" --dry-run
#
# Exit codes: 0 = all pass, 1 = one or more failures, 2 = usage error
set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────────
MAX_TOKENS=15
TIMEOUT=30
DRY_RUN=false
CONTAINER="openclaw"
KEY_FILE=""
MODELS=""
LITELLM_URL="http://openclaw-litellm:4000/chat/completions"
PROMPT="Say hello in exactly 3 words"
DELAY=1

# ── Parse args ────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --key-file)   KEY_FILE="$2"; shift 2 ;;
    --models)     MODELS="$2"; shift 2 ;;
    --max-tokens) MAX_TOKENS="$2"; shift 2 ;;
    --timeout)    TIMEOUT="$2"; shift 2 ;;
    --container)  CONTAINER="$2"; shift 2 ;;
    --dry-run)    DRY_RUN=true; shift ;;
    -h|--help)
      echo "Usage: $0 --key-file <path> --models <comma-list> [--max-tokens N] [--timeout S] [--dry-run]"
      exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$KEY_FILE" || -z "$MODELS" ]]; then
  echo "Error: --key-file and --models are required" >&2
  exit 2
fi

if [[ ! -f "$KEY_FILE" ]]; then
  echo "Error: key file not found: $KEY_FILE" >&2
  exit 2
fi

API_KEY=$(cat "$KEY_FILE")

# ── Split models into array ───────────────────────────────────────────
IFS=',' read -ra MODEL_LIST <<< "$MODELS"
TOTAL=${#MODEL_LIST[@]}
PASS=0
FAIL=0
TOTAL_TIME=0

# ── Header ────────────────────────────────────────────────────────────
printf '\n%s\n' "═══ LLM Smoke Test Results ═══"
printf '%-50s %-8s %-8s %s\n' "Model" "Status" "Time(s)" "Response"
printf '%s\n' "──────────────────────────────────────────────────────────────────────────────────────"

# ── Test each model ───────────────────────────────────────────────────
for model in "${MODEL_LIST[@]}"; do
  model=$(echo "$model" | xargs)  # trim whitespace

  PAYLOAD=$(python3 -c "
import json, sys
print(json.dumps({
    'model': sys.argv[1],
    'messages': [{'role': 'user', 'content': sys.argv[2]}],
    'max_tokens': int(sys.argv[3])
}))
" "$model" "$PROMPT" "$MAX_TOKENS")

  if $DRY_RUN; then
    printf '%-50s %-8s %-8s %s\n' "$model" "DRY_RUN" "-" "(would send: $PROMPT)"
    continue
  fi

  START=$(date +%s%N)

  HTTP_RESPONSE=$(docker exec "$CONTAINER" curl -s --max-time "$TIMEOUT" \
    -w '\n%{http_code}' \
    -H "Authorization: Bearer $API_KEY" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" \
    "$LITELLM_URL" 2>&1) || true

  END=$(date +%s%N)
  ELAPSED=$(python3 -c "print(f'{($END - $START) / 1e9:.2f}')")
  TOTAL_TIME=$(python3 -c "print(f'{$TOTAL_TIME + ($END - $START) / 1e9:.1f}')")

  # Split response body and HTTP status code
  HTTP_CODE=$(echo "$HTTP_RESPONSE" | tail -1)
  BODY=$(echo "$HTTP_RESPONSE" | sed '$d')

  if [[ "$HTTP_CODE" == "200" ]]; then
    # Extract response text
    REPLY=$(python3 -c "
import json, sys
try:
    data = json.loads(sys.argv[1])
    content = data['choices'][0]['message'].get('content') or ''
    text = content.strip()
    print(text[:40] if text else '(empty response)')
except Exception as e:
    print(f'PARSE_ERROR: {e}')
" "$BODY" 2>&1)

    if [[ "$REPLY" == PARSE_ERROR* ]]; then
      printf '%-50s %-8s %-8s %s\n' "$model" "FAIL" "$ELAPSED" "$REPLY"
      FAIL=$((FAIL + 1))
    else
      printf '%-50s %-8s %-8s %s\n' "$model" "PASS" "$ELAPSED" "$REPLY"
      PASS=$((PASS + 1))
    fi
  elif [[ "$HTTP_CODE" == "429" ]]; then
    printf '%-50s %-8s %-8s %s\n' "$model" "FAIL" "$ELAPSED" "RATE_LIMITED"
    FAIL=$((FAIL + 1))
  elif [[ "$HTTP_CODE" == "401" || "$HTTP_CODE" == "403" ]]; then
    printf '%-50s %-8s %-8s %s\n' "$model" "FAIL" "$ELAPSED" "AUTH_ERROR ($HTTP_CODE)"
    FAIL=$((FAIL + 1))
  elif [[ -z "$HTTP_CODE" || "$HTTP_CODE" == "000" ]]; then
    printf '%-50s %-8s %-8s %s\n' "$model" "FAIL" "$ELAPSED" "TIMEOUT"
    FAIL=$((FAIL + 1))
  else
    # Extract error message from body
    ERR_MSG=$(python3 -c "
import json, sys
try:
    data = json.loads(sys.argv[1])
    msg = data.get('error', {}).get('message', 'unknown error')
    print(msg[:50])
except Exception:
    print(sys.argv[1][:50] if sys.argv[1] else 'empty response')
" "$BODY" 2>&1)
    printf '%-50s %-8s %-8s %s\n' "$model" "FAIL" "$ELAPSED" "HTTP $HTTP_CODE: $ERR_MSG"
    FAIL=$((FAIL + 1))
  fi

  # Delay between requests to respect RPM limits
  if [[ "$model" != "${MODEL_LIST[-1]}" ]]; then
    sleep "$DELAY"
  fi
done

# ── Summary ───────────────────────────────────────────────────────────
printf '%s\n' "──────────────────────────────────────────────────────────────────────────────────────"
printf 'Total: %d | Pass: %d | Fail: %d | Time: %ss\n\n' "$TOTAL" "$PASS" "$FAIL" "$TOTAL_TIME"

if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
exit 0
