#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${GREEN}[ok]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
info() { echo -e "${CYAN}[>]${NC} $1"; }

echo ""
echo "=== SocialX v4 Hook deploy ==="
echo ""

if [ ! -f .env ]; then
    cp .env.example .env
    warn "Created .env from .env.example"
    echo ""
    echo "Edit .env before continuing. Required:"
    echo "  PRIVATE_KEY     deployer / owner / initial keeper"
    echo "  POOL_MANAGER    Uniswap v4 PoolManager on the target XLayer network"
    echo "  X_BEARER_TOKEN  optional for dry runs, required for real X metrics"
    echo "  TRACKED_KOLS    comma-separated handles, for example @your_handle"
    echo ""
    read -r -p "Press Enter after editing .env ..."
fi

set -a
# shellcheck disable=SC1091
source .env
set +a

[ -z "${PRIVATE_KEY:-}" ] && { echo "PRIVATE_KEY not set in .env"; exit 1; }
[ -z "${POOL_MANAGER:-}" ] && { echo "POOL_MANAGER not set in .env"; exit 1; }

export PATH="$HOME/.foundry/bin:$PATH"

info "Checking Foundry"
if command -v forge >/dev/null 2>&1; then
    log "$(forge --version)"
else
    warn "Foundry not found. Installing..."
    curl -L https://foundry.paradigm.xyz | bash
    source "$HOME/.zshenv" 2>/dev/null || true
    foundryup
fi

info "Installing Solidity dependencies"
[ ! -d "lib/forge-std" ] && forge install foundry-rs/forge-std
log "Dependencies ready"

info "Building contracts"
forge clean
forge build
log "Build passed"

info "Running tests"
forge test -vvv
log "Tests passed"

info "Deploying SocialXHook to XLayer"
forge script script/Deploy.s.sol:Deploy \
    --rpc-url xlayer \
    --broadcast \
    --private-key "$PRIVATE_KEY" \
    2>&1 | tee deploy_output.log

HOOK_ADDRESS=$(grep -Eo 'Hook: 0x[[:xdigit:]]{40}' deploy_output.log | tail -1 | grep -Eo '0x[[:xdigit:]]{40}' || true)

if [ -z "$HOOK_ADDRESS" ]; then
    warn "Could not extract HOOK_ADDRESS from deploy output."
    read -r -p "Enter HOOK_ADDRESS manually: " HOOK_ADDRESS
fi

if [ -n "$HOOK_ADDRESS" ] && [ ${#HOOK_ADDRESS} -eq 42 ]; then
    if grep -q "^HOOK_ADDRESS=" .env 2>/dev/null; then
        sed -i.bak "s/^HOOK_ADDRESS=.*/HOOK_ADDRESS=$HOOK_ADDRESS/" .env
    else
        echo "HOOK_ADDRESS=$HOOK_ADDRESS" >> .env
    fi
    rm -f .env.bak
fi

log "SocialXHook: $HOOK_ADDRESS"

info "Installing keeper dependencies"
npm --prefix keeper install
log "Keeper ready"

echo ""
echo "=== Done ==="
echo ""
echo "Hook:     ${HOOK_ADDRESS}"
echo "Explorer: https://www.oklink.com/x-layer-test/address/${HOOK_ADDRESS}"
echo ""
echo "Next steps:"
echo "  1. Register your X handle on SocialXHook."
echo "  2. Post manually using TWEETS.md."
echo "  3. Start the read-only keeper:"
echo "       cd keeper && npm start"
echo ""
echo "Dry-run keeper:"
echo "       DRY_RUN=true npm --prefix keeper start"
echo ""
