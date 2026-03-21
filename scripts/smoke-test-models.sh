#!/usr/bin/env bash
# smoke-test-models.sh — Test all LLM models and integrations
#
# Usage:
#   smoke-test-models.sh --key-file /tmp/.smoke-key --models "model1,model2,..."
#   smoke-test-models.sh --key-file /tmp/.smoke-key --models "model1" --telegram-key-file /tmp/.tg-key
#   smoke-test-models.sh --key-file /tmp/.smoke-key --models "model1" --no-integrations --dry-run
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
TELEGRAM_KEY_FILE=""
INTEGRATIONS=true
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
    --container)          CONTAINER="$2"; shift 2 ;;
    --telegram-key-file)  TELEGRAM_KEY_FILE="$2"; shift 2 ;;
    --integrations)       INTEGRATIONS=true; shift ;;
    --no-integrations)    INTEGRATIONS=false; shift ;;
    --dry-run)            DRY_RUN=true; shift ;;
    -h|--help)
      echo "Usage: $0 --key-file <path> --models <comma-list> [--telegram-key-file <path>] [--no-integrations] [--dry-run]"
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

# ── Model Summary ─────────────────────────────────────────────────────
printf '%s\n' "──────────────────────────────────────────────────────────────────────────────────────"
printf 'Total: %d | Pass: %d | Fail: %d | Time: %ss\n' "$TOTAL" "$PASS" "$FAIL" "$TOTAL_TIME"

MODEL_FAIL=$FAIL

# ── Integration Checks ───────────────────────────────────────────────
if $INTEGRATIONS && ! $DRY_RUN; then
  INT_PASS=0
  INT_FAIL=0

  printf '\n%s\n' "═══ Integration Checks ═══"
  printf '%-50s %-8s %-8s %s\n' "Check" "Status" "Time(s)" "Detail"
  printf '%s\n' "──────────────────────────────────────────────────────────────────────────────────────"

  # ── Telegram Bot Token ──────────────────────────────────────────────
  if [[ -n "$TELEGRAM_KEY_FILE" && -f "$TELEGRAM_KEY_FILE" ]]; then
    TG_TOKEN=$(cat "$TELEGRAM_KEY_FILE")
    START=$(date +%s%N)
    # Route through egress proxy (Telegram domain must be whitelisted in smokescreen)
    TG_RESP=$(docker exec "$CONTAINER" curl -s --max-time 10 \
      -x http://openclaw-egress:4750 \
      "https://api.telegram.org/bot${TG_TOKEN}/getMe" 2>&1) || true
    END=$(date +%s%N)
    ELAPSED=$(python3 -c "print(f'{($END - $START) / 1e9:.2f}')")

    TG_OK=$(python3 -c "
import json, sys
try:
    data = json.loads(sys.argv[1])
    if data.get('ok'):
        r = data['result']
        print(f'PASS|@{r[\"username\"]} (id: {r[\"id\"]})')
    else:
        print(f'FAIL|{data.get(\"description\", \"unknown error\")[:40]}')
except Exception as e:
    print(f'FAIL|{e}')
" "$TG_RESP" 2>&1)

    TG_STATUS="${TG_OK%%|*}"
    TG_DETAIL="${TG_OK#*|}"
    printf '%-50s %-8s %-8s %s\n' "Telegram Bot (getMe)" "$TG_STATUS" "$ELAPSED" "$TG_DETAIL"
    if [[ "$TG_STATUS" == "PASS" ]]; then INT_PASS=$((INT_PASS + 1)); else INT_FAIL=$((INT_FAIL + 1)); fi
  else
    printf '%-50s %-8s %-8s %s\n' "Telegram Bot (getMe)" "SKIP" "-" "no --telegram-key-file"
  fi

  # ── OpenClaw Doctor ─────────────────────────────────────────────────
  START=$(date +%s%N)
  DOCTOR_OUT=$(docker exec "$CONTAINER" openclaw doctor --non-interactive 2>&1) || true
  END=$(date +%s%N)
  ELAPSED=$(python3 -c "print(f'{($END - $START) / 1e9:.2f}')")

  # Doctor exits 0 on success, non-zero on critical failures.
  # Warnings (like groupPolicy) are expected and not failures.
  DOCTOR_SUMMARY=$(echo "$DOCTOR_OUT" | grep -c -i "fatal\|crash\|panic" || true)
  if [[ "$DOCTOR_SUMMARY" -eq 0 ]]; then
    printf '%-50s %-8s %-8s %s\n' "OpenClaw Doctor" "PASS" "$ELAPSED" "no critical issues"
    INT_PASS=$((INT_PASS + 1))
  else
    printf '%-50s %-8s %-8s %s\n' "OpenClaw Doctor" "FAIL" "$ELAPSED" "critical issues found"
    INT_FAIL=$((INT_FAIL + 1))
  fi

  # ── Egress: whitelisted domain ──────────────────────────────────────
  START=$(date +%s%N)
  EGRESS_OK=$(docker exec "$CONTAINER" curl -sf -o /dev/null -w '%{http_code}' \
    --max-time 10 -x http://openclaw-egress:4750 \
    https://api.anthropic.com 2>&1) || true
  END=$(date +%s%N)
  ELAPSED=$(python3 -c "print(f'{($END - $START) / 1e9:.2f}')")

  # Any HTTP response (even 401/404) means the proxy allowed the connection
  if [[ "$EGRESS_OK" =~ ^[2345] ]]; then
    printf '%-50s %-8s %-8s %s\n' "Egress: whitelisted domain" "PASS" "$ELAPSED" "api.anthropic.com -> $EGRESS_OK (connected)"
    INT_PASS=$((INT_PASS + 1))
  else
    printf '%-50s %-8s %-8s %s\n' "Egress: whitelisted domain" "FAIL" "$ELAPSED" "api.anthropic.com -> ${EGRESS_OK:-no response}"
    INT_FAIL=$((INT_FAIL + 1))
  fi

  # ── Egress: blocked domain ─────────────────────────────────────────
  START=$(date +%s%N)
  EGRESS_BLOCK=$(docker exec "$CONTAINER" curl -sf -o /dev/null -w '%{http_code}' \
    --max-time 10 -x http://openclaw-egress:4750 \
    https://example.com 2>&1) || true
  END=$(date +%s%N)
  ELAPSED=$(python3 -c "print(f'{($END - $START) / 1e9:.2f}')")

  if [[ "$EGRESS_BLOCK" =~ ^[45] ]] || [[ "$EGRESS_BLOCK" == "000" ]] || [[ -z "$EGRESS_BLOCK" ]]; then
    printf '%-50s %-8s %-8s %s\n' "Egress: blocked domain" "PASS" "$ELAPSED" "example.com -> blocked"
    INT_PASS=$((INT_PASS + 1))
  else
    printf '%-50s %-8s %-8s %s\n' "Egress: blocked domain" "FAIL" "$ELAPSED" "example.com -> $EGRESS_BLOCK (should be blocked)"
    INT_FAIL=$((INT_FAIL + 1))
  fi

  # ── Integration Summary ─────────────────────────────────────────────
  printf '%s\n' "──────────────────────────────────────────────────────────────────────────────────────"
  printf 'Total: %d | Pass: %d | Fail: %d\n' "$((INT_PASS + INT_FAIL))" "$INT_PASS" "$INT_FAIL"

  FAIL=$((MODEL_FAIL + INT_FAIL))
fi

if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
exit 0
