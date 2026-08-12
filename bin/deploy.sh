#!/usr/bin/env bash
#
# AUG//RUN deploy wrapper.
#
# The project lives on a fuseblk mount where chmod does not persist — every file
# in the repo is world-readable and cannot be locked down. So the private key is
# NOT kept here. It lives in ~/.aug_run/.env (mode 0600), which this script
# sources at run time. Nothing secret is ever written to the USB drive.
#
# Usage:
#   bin/deploy.sh phase1                  # deploy to Robinhood testnet
#   bin/deploy.sh phase1 --dry            # simulate only, no broadcast
#   NETWORK=localhost bin/deploy.sh phase1
#
set -euo pipefail

ENV_FILE="${AUGRUN_ENV_FILE:-$HOME/.aug_run/.env}"
NETWORK="${NETWORK:-rh_testnet}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$HOME/.foundry/bin:$PATH"

PHASE="${1:-}"
if [[ -z "$PHASE" ]]; then
  echo "usage: bin/deploy.sh <phase1|phase2|phase3|phase4|phase5|phase6|phase7|phase8> [--dry]" >&2
  exit 64
fi
shift || true

DRY=0
for arg in "$@"; do
  [[ "$arg" == "--dry" ]] && DRY=1
done

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: $ENV_FILE not found." >&2
  echo "Create it with mode 0600 and set PRIVATE_KEY. See .env.example." >&2
  exit 66
fi

# Refuse to run if the key file is readable by anyone but the owner.
PERMS="$(stat -c '%a' "$ENV_FILE")"
if [[ "$PERMS" != "600" && "$PERMS" != "400" ]]; then
  echo "ERROR: $ENV_FILE has mode $PERMS; expected 600." >&2
  echo "Fix with: chmod 600 $ENV_FILE" >&2
  exit 77
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

if [[ -z "${PRIVATE_KEY:-}" ]]; then
  echo "ERROR: PRIVATE_KEY is not set in $ENV_FILE" >&2
  exit 78
fi

case "$PHASE" in
  phase1) SCRIPT="script/DeployPhase1.s.sol:DeployPhase1" ;;
  phase2) SCRIPT="script/DeployPhase2.s.sol:DeployPhase2" ;;
  phase3) SCRIPT="script/DeployPhase3.s.sol:DeployPhase3" ;;
  phase4) SCRIPT="script/DeployPhase4.s.sol:DeployPhase4" ;;
  phase5) SCRIPT="script/DeployPhase5.s.sol:DeployPhase5" ;;
  phase6) SCRIPT="script/DeployPhase6.s.sol:DeployPhase6" ;;
  phase7) SCRIPT="script/DeployPhase7.s.sol:DeployPhase7" ;;
  phase8) SCRIPT="script/DeployPhase8.s.sol:DeployPhase8" ;;
  *) echo "unknown phase: $PHASE" >&2; exit 64 ;;
esac

BROADCAST="--broadcast"
[[ "$DRY" == "1" ]] && BROADCAST=""

echo "network : $NETWORK"
echo "script  : $SCRIPT"
echo "mode    : $([[ $DRY == 1 ]] && echo 'DRY RUN (no broadcast)' || echo 'BROADCAST')"
echo

cd "$ROOT"
# shellcheck disable=SC2086
forge script "$SCRIPT" --rpc-url "$NETWORK" $BROADCAST -vvv
