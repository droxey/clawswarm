#!/usr/bin/env bash
set -euo pipefail

# Distribute SSH public key to fresh CapRover servers via sshpass.
# Usage: bash scripts/caprover-bootstrap-keys.sh [host:ip ...]
#
# With no arguments, reads hosts from inventory/caprover-hosts.yml.
# With arguments, expects pairs like: nyc:107.174.35.212 chi:172.245.242.59
#
# Requires: sshpass, ssh-keyscan, ssh-copy-id

readonly PUBKEY="${CAPROVER_SSH_PUBKEY:-${HOME}/.ssh/id_ed25519.pub}"
readonly INVENTORY="inventory/caprover-hosts.yml"

# ── Preflight ────────────────────────────────────────────────────────
if ! command -v sshpass >/dev/null 2>&1; then
  echo "ERROR: sshpass not found. Install with: brew install hudochenkov/sshpass/sshpass" >&2
  exit 1
fi

if [[ ! -f "${PUBKEY}" ]]; then
  echo "ERROR: SSH public key not found at ${PUBKEY}" >&2
  echo "  Set CAPROVER_SSH_PUBKEY to override, or run: ssh-keygen -t ed25519" >&2
  exit 1
fi

# ── Parse hosts ──────────────────────────────────────────────────────
declare -a HOSTS=()  # name:ip pairs

if [[ $# -gt 0 ]]; then
  HOSTS=("$@")
else
  if [[ ! -f "${INVENTORY}" ]]; then
    echo "ERROR: Inventory file not found at ${INVENTORY}" >&2
    echo "  Pass hosts as arguments: $0 nyc:107.174.35.212 chi:172.245.242.59" >&2
    exit 1
  fi
  # Extract ansible_host values from YAML (simple grep — no yq dependency)
  while IFS= read -r line; do
    name="$(echo "${line}" | grep -oP '^\s+\K[a-z0-9_-]+(?=:)' || true)"
    ip="$(echo "${line}" | grep -oP 'ansible_host:\s*\K[0-9.]+' || true)"
    if [[ -n "${name}" && -n "${ip}" ]]; then
      HOSTS+=("${name}:${ip}")
    fi
  done < <(grep -A1 'hosts:' "${INVENTORY}" | grep 'ansible_host')
  # Fallback: broader parse
  if [[ ${#HOSTS[@]} -eq 0 ]]; then
    while IFS= read -r ip; do
      HOSTS+=("host:${ip}")
    done < <(grep -oP 'ansible_host:\s*\K[0-9.]+' "${INVENTORY}")
  fi
fi

if [[ ${#HOSTS[@]} -eq 0 ]]; then
  echo "ERROR: No hosts found. Pass hosts as arguments or check ${INVENTORY}" >&2
  exit 1
fi

# ── Distribute keys ─────────────────────────────────────────────────
ok=0
fail=0

for entry in "${HOSTS[@]}"; do
  name="${entry%%:*}"
  ip="${entry#*:}"

  echo ""
  echo "── ${name} (${ip}) ──────────────────────────────"

  # Check if key already works
  if ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new \
       "root@${ip}" true 2>/dev/null; then
    echo "[OK] SSH key already accepted — skipping"
    ((ok++))
    continue
  fi

  # Prompt for password (never echoed)
  printf "Enter root password for %s (%s): " "${name}" "${ip}"
  read -rs password
  echo ""

  if [[ -z "${password}" ]]; then
    echo "[SKIP] Empty password — skipping ${name}"
    ((fail++))
    continue
  fi

  # Accept host key
  ssh-keyscan -T 5 "${ip}" >> "${HOME}/.ssh/known_hosts" 2>/dev/null || true

  # Copy public key
  if sshpass -p "${password}" ssh-copy-id \
       -o StrictHostKeyChecking=accept-new \
       -i "${PUBKEY}" \
       "root@${ip}" 2>/dev/null; then

    # Verify key-based login
    if ssh -o BatchMode=yes -o ConnectTimeout=5 "root@${ip}" true 2>/dev/null; then
      echo "[OK] Key distributed and verified"
      ((ok++))
    else
      echo "[WARN] Key copied but verification failed — check sshd config" >&2
      ((fail++))
    fi
  else
    echo "[FAIL] sshpass/ssh-copy-id failed — check password" >&2
    ((fail++))
  fi
done

# ── Summary ──────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════"
echo "  Bootstrap complete: ${ok} OK, ${fail} failed (${#HOSTS[@]} total)"
echo "════════════════════════════════════════════════"

if [[ ${fail} -gt 0 ]]; then
  exit 1
fi
