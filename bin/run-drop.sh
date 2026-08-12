#!/usr/bin/env bash
#
# AUG//RUN Drop keeper.
#
# Firing a Drop is three on-chain steps and cannot be fewer: 333 units' weights
# will not fit in one transaction, and the aggregate purchase can only happen
# once every weight is known. That is operations, not gameplay — an operator
# standing at the Courier's window should press one button to COLLECT and never
# be asked to run the machinery. So the machinery lives here, on a schedule.
#
# The steps are permissionless: weights are read off the Stock//Runners
# themselves and never supplied, so whoever runs this chooses only WHEN a Drop
# happens, never who earns from it. Anyone may run it; it just needs to be run.
#
# Like bin/deploy.sh, the key is NOT kept in the repo — the project lives on a
# fuseblk mount where chmod does not persist. It is read from ~/.aug_run/.env
# (mode 0600) at run time.
#
# Usage:
#   bin/run-drop.sh                 # open, weigh and buy this cycle's Drop
#   bin/run-drop.sh --status        # report where the current Drop is, change nothing
#   bin/run-drop.sh --dry           # simulate every step, broadcast nothing
#   NETWORK=rh_mainnet bin/run-drop.sh
#
# Cron it once a cycle, a few minutes after the boundary:
#   5 0 * * 1  cd /path/to/aug_run && bin/run-drop.sh >> ~/.aug_run/drop.log 2>&1
#
# Safe to run repeatedly: each step is skipped if the round is already past it,
# so a re-run after a failure resumes rather than restarting.
#
set -euo pipefail

ENV_FILE="${AUGRUN_ENV_FILE:-$HOME/.aug_run/.env}"
NETWORK="${NETWORK:-rh_testnet}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$HOME/.foundry/bin:$PATH"

BATCH="${BATCH:-50}"   # units weighed per accumulate() call
MAX_BATCHES="${MAX_BATCHES:-40}"

DRY=0
STATUS_ONLY=0
for arg in "$@"; do
  case "$arg" in
    --dry) DRY=1 ;;
    --status) STATUS_ONLY=1 ;;
    *) echo "unknown argument: $arg" >&2; exit 64 ;;
  esac
done

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: $ENV_FILE not found." >&2
  echo "Create it with mode 0600 and set PRIVATE_KEY. See .env.example." >&2
  exit 66
fi

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

: "${PRIVATE_KEY:?PRIVATE_KEY is not set in $ENV_FILE}"
: "${DROP_ADDRESS:?DROP_ADDRESS is not set in $ENV_FILE — see DEPLOYMENTS.md}"

cd "$ROOT"

RPC="$NETWORK"
CALL=(cast call --rpc-url "$RPC")
SEND=(cast send --rpc-url "$RPC" --private-key "$PRIVATE_KEY")

PHASE_NAME=(none accumulating claimable closed)

hex2dec() { printf '%d\n' "$1"; }

current_id() { hex2dec "$("${CALL[@]}" "$DROP_ADDRESS" 'currentDropId()(uint256)')"; }

phase_of() {
  # rounds() returns (cycle, pool, totalWeight, cursor, spent, claimDeadline, phase)
  "${CALL[@]}" "$DROP_ADDRESS" 'rounds(uint256)(uint256,uint256,uint256,uint256,uint256,uint256,uint8)' "$1" \
    | tail -1
}

report() {
  local id phase
  id="$(current_id)"
  if [[ "$id" == "0" ]]; then
    echo "drop     : none opened yet"
    return
  fi
  phase="$(phase_of "$id")"
  echo "drop     : #$id"
  echo "phase    : ${PHASE_NAME[$phase]} ($phase)"
  "${CALL[@]}" "$DROP_ADDRESS" 'accumulationProgress(uint256)(uint256,uint256)' "$id" \
    | paste -sd'/' - | sed 's/^/weighed  : /'
}

echo "network  : $NETWORK"
echo "drop     : $DROP_ADDRESS"
echo

if [[ "$STATUS_ONLY" == "1" ]]; then
  report
  exit 0
fi

if [[ "$DRY" == "1" ]]; then
  echo "DRY RUN — reporting state, broadcasting nothing."
  report
  exit 0
fi

# --- 1. open -----------------------------------------------------------------
ID="$(current_id)"
PHASE=0
[[ "$ID" != "0" ]] && PHASE="$(phase_of "$ID")"

if [[ "$ID" == "0" || "$PHASE" != "1" ]]; then
  echo "1/3  opening a Drop…"
  "${SEND[@]}" "$DROP_ADDRESS" 'openDrop()' >/dev/null
  ID="$(current_id)"
  echo "     opened #$ID"
else
  echo "1/3  #$ID already open — resuming"
fi

# --- 2. weigh ----------------------------------------------------------------
echo "2/3  weighing the collection (batches of $BATCH)…"
n=0
while (( n < MAX_BATCHES )); do
  read -r cursor total < <("${CALL[@]}" "$DROP_ADDRESS" 'accumulationProgress(uint256)(uint256,uint256)' "$ID" | paste -sd' ' -)
  if (( cursor > total )); then
    echo "     done ($total units)"
    break
  fi
  "${SEND[@]}" "$DROP_ADDRESS" 'accumulate(uint256,uint256)' "$ID" "$BATCH" >/dev/null
  n=$(( n + 1 ))
  echo "     batch $n — $cursor / $total"
done

if (( n >= MAX_BATCHES )); then
  echo "ERROR: still weighing after $MAX_BATCHES batches. Re-run to continue." >&2
  exit 75
fi

# --- 3. buy ------------------------------------------------------------------
echo "3/3  buying — one purchase per ticker…"
"${SEND[@]}" "$DROP_ADDRESS" 'finalize(uint256)' "$ID" >/dev/null

echo
report
echo
echo "Packages are on the shelf. Operators collect at the Drop; nothing further to run."
