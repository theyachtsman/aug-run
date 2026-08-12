#!/usr/bin/env bash
#
# Mainnet launch preflight for AUG//RUN.
#
# The $RUN deploy is irreversible in every way that matters: fixed supply, no owner, no mint
# function, no upgrade path. The treasury address you pass holds the entire supply forever. This
# script refuses to let the obvious mistakes through, and only ever SIMULATES — it never broadcasts.
#
# Usage:
#   NETWORK=rh_mainnet bin/preflight-mainnet.sh
#
set -uo pipefail

ENV_FILE="${AUGRUN_ENV_FILE:-$HOME/.aug_run/.env}"
NETWORK="${NETWORK:-rh_mainnet}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$HOME/.foundry/bin:$PATH"

TESTNET_DEPLOYER="0x5a56B2f1E1e7ecf34F74039B656D88361E208957"

FAIL=0
pass() { printf "  \033[32mPASS\033[0m  %s\n" "$1"; }
warn() { printf "  \033[33mWARN\033[0m  %s\n" "$1"; }
fail() { printf "  \033[31mFAIL\033[0m  %s\n" "$1"; FAIL=1; }

echo "AUG//RUN mainnet preflight  (simulation only — nothing is broadcast)"
echo

[[ -f "$ENV_FILE" ]] || { fail "$ENV_FILE not found"; exit 1; }
PERMS="$(stat -c '%a' "$ENV_FILE")"
[[ "$PERMS" == "600" || "$PERMS" == "400" ]] && pass "key file mode $PERMS" || fail "key file mode $PERMS (want 600)"

set -a; source "$ENV_FILE"; set +a

# ---------------------------------------------------------------- flags
if [[ "${AUGRUN_TESTNET:-}" == "false" ]]; then
  pass "AUGRUN_TESTNET=false (faucets disabled, full supply to recipients)"
else
  fail "AUGRUN_TESTNET is '${AUGRUN_TESTNET:-unset}' — MUST be false for mainnet"
fi

# ------------------------------------------------------------- identity
if [[ -z "${PRIVATE_KEY:-}" || "$PRIVATE_KEY" == "0x" ]]; then
  fail "PRIVATE_KEY not set"
else
  DEPLOYER="$(cast wallet address --private-key "$PRIVATE_KEY" 2>/dev/null)"
  pass "deployer $DEPLOYER"
  if [[ "${DEPLOYER,,}" == "${TESTNET_DEPLOYER,,}" ]]; then
    fail "deployer is the TESTNET throwaway key. It has signed dozens of testnet txs and lives in
        a plaintext file. Do not let it hold the mainnet supply. Use a fresh key, ideally a
        hardware wallet or multisig."
  fi
fi

# ------------------------------------------------------------- treasury
if [[ -z "${TREASURY:-}" ]]; then
  fail "TREASURY not set. It defaults to the deployer, which is almost never what you want on
        mainnet — this address holds 1,000,000,000 \$RUN permanently."
else
  pass "TREASURY $TREASURY"
  if [[ "${TREASURY,,}" == "${TESTNET_DEPLOYER,,}" ]]; then
    fail "TREASURY is the testnet throwaway address"
  fi
  if [[ "${TREASURY,,}" == "${DEPLOYER,,}" ]]; then
    warn "TREASURY == deployer. Fine only if that is deliberately your treasury."
  fi
  CODE="$(cast code "$TREASURY" --rpc-url "$NETWORK" 2>/dev/null || echo "")"
  if [[ -n "$CODE" && "$CODE" != "0x" ]]; then
    pass "TREASURY is a contract (multisig?) — confirm it can transfer ERC-20s"
  else
    warn "TREASURY is an EOA. A multisig is the safer home for an entire token supply."
  fi
fi

# ---------------------------------------------------------------- chain
CHAINID="$(cast chain-id --rpc-url "$NETWORK" 2>/dev/null || echo "")"
if [[ -z "$CHAINID" ]]; then
  fail "cannot reach $NETWORK — no RPC. Supply a working mainnet endpoint."
elif [[ "$CHAINID" == "4663" ]]; then
  pass "connected to chain 4663 (Robinhood Chain mainnet)"
elif [[ "$CHAINID" == "46630" ]]; then
  fail "connected to 46630 (TESTNET) while running a mainnet preflight"
else
  fail "unexpected chain id $CHAINID"
fi

# ------------------------------------------------------------------ gas
if [[ -n "${DEPLOYER:-}" && -n "$CHAINID" ]]; then
  BAL="$(cast balance "$DEPLOYER" --rpc-url "$NETWORK" 2>/dev/null || echo 0)"
  if [[ "$BAL" == "0" ]]; then fail "deployer has no ETH for gas"; else pass "deployer balance $BAL wei"; fi
fi

# ----------------------------------------------------------- simulation
echo
if [[ "$FAIL" == "0" ]]; then
  echo "Running deploy SIMULATION (no broadcast)..."
  cd "$ROOT"
  if forge script script/DeployPhase1.s.sol:DeployPhase1 --rpc-url "$NETWORK" -vv 2>&1 | tail -25; then
    pass "simulation completed"
  else
    fail "simulation failed"
  fi
fi

echo
if [[ "$FAIL" == "0" ]]; then
  echo "Preflight clean. To broadcast for real:"
  echo "    NETWORK=$NETWORK bin/deploy.sh phase1"
  echo
  echo "This cannot be undone. Supply is fixed, there is no owner and no mint function."
else
  echo "Preflight FAILED. Do not deploy."
  exit 1
fi
