#!/usr/bin/env bash
set -euo pipefail

# ╔══════════════════════════════════════════════════════════╗
# ║  🐦 SocialX Hook — One-Click Deploy + Launch Agent      ║
# ║                                                        ║
# ║  What this does:                                       ║
# ║    1. Installs Foundry (if missing)                    ║
# ║    2. Installs Solidity dependencies                   ║
# ║    3. Builds contracts                                 ║
# ║    4. Runs tests                                       ║
# ║    5. Deploys to XLayer                                ║
# ║    6. Installs keeper deps                             ║
# ║    7. Prints command to launch the autonomous agent     ║
# ║                                                        ║
# ║  After this script, run:                               ║
# ║    cd keeper && npm start                              ║
# ║                                                        ║
# ║  The agent will auto-post tweets, read engagement,     ║
# ║  and push scores on-chain. Fully autonomous.           ║
# ╚══════════════════════════════════════════════════════════╝

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
info() { echo -e "${CYAN}[>]${NC} $1"; }

echo ""
echo "=== SocialX Hook - Deploy & Launch ==="
echo ""

# ── .env check ─────────────────────────────────
if [ ! -f .env ]; then
    cp .env.example .env
    echo ""
    warn "Created .env from .env.example"
    echo ""
    echo "  ⚠️  YOU MUST EDIT .env before continuing:"
    echo ""
    echo "  REQUIRED:"
    echo "    PRIVATE_KEY              — deployer wallet private key"
    echo ""
    echo "  For engagement tracking:"
    echo "    X_BEARER_TOKEN           — from developer.twitter.com (READ only, Free tier)"
    echo "    TRACKED_KOLS             — @your_x_handle"
    echo ""
    echo "  Tweets are posted manually from TWEETS.md (no Write API needed)."
    echo "  Agent reads engagement + pushes scores on-chain automatically."
    echo ""
    echo "  Set DRY_RUN=true to test without real txs first."
    echo ""
    read -p "  Press Enter after editing .env ..."
fi

set -a; source .env; set +a

[ -z "${PRIVATE_KEY:-}" ] && { echo "❌ PRIVATE_KEY not set in .env"; exit 1; }

# ── Step 1: Foundry ────────────────────────────
info "Step 1/7: Checking Foundry..."
if command -v forge &> /dev/null; then
    log "Foundry: $(forge --version)"
else
    warn "Installing Foundry..."
    curl -L https://foundry.paradigm.xyz | bash
    export PATH="$HOME/.foundry/bin:$PATH"
    foundryup
    log "Foundry installed"
fi

# ── Step 2: Solidity deps ──────────────────────
info "Step 2/7: Solidity dependencies..."

# forge install needs a git repo
if [ ! -d .git ]; then
    git init && git add -A && git commit -m "init" --quiet
fi

[ ! -d "lib/v4-core" ] && forge install Uniswap/v4-core && log "v4-core"
[ ! -d "lib/v4-periphery" ] && forge install Uniswap/v4-periphery && log "v4-periphery"
[ ! -d "lib/openzeppelin-contracts" ] && forge install OpenZeppelin/openzeppelin-contracts && log "openzeppelin"
log "Dependencies ready"

# ── Step 3: Build ──────────────────────────────
info "Step 3/7: Building..."
forge build
log "Build OK"

# ── Step 4: Test ───────────────────────────────
info "Step 4/7: Running tests..."
forge test -vvv
log "Tests passed"

# ── Step 5: Deploy PoolManager + SocialXHook ────
info "Step 5/7: Deploying to XLayer..."

forge script script/DeployAll.s.sol:DeployAll \
    --rpc-url xlayer \
    --broadcast \
    --private-key "$PRIVATE_KEY" \
    --json > deploy_output.json 2>&1 || true

HOOK_ADDRESS=$(grep -oP 'SocialXHook:\s*\K0x[a-fA-F0-9]{40}' deploy_output.json || echo "")
POOL_MANAGER_ADDR=$(grep -oP 'PoolManager:\s*\K0x[a-fA-F0-9]{40}' deploy_output.json || echo "")

if [ -z "$HOOK_ADDRESS" ]; then
    warn "Auto-extraction failed. Showing deploy output:"
    cat deploy_output.json | tail -30
    read -p "  Enter HOOK_ADDRESS manually: " HOOK_ADDRESS
fi

log "PoolManager: $POOL_MANAGER_ADDR"
log "SocialXHook: $HOOK_ADDRESS"

# Update .env
if grep -q "^HOOK_ADDRESS=" .env 2>/dev/null; then
    sed -i.bak "s/^HOOK_ADDRESS=.*/HOOK_ADDRESS=$HOOK_ADDRESS/" .env
else
    echo "HOOK_ADDRESS=$HOOK_ADDRESS" >> .env
fi

# ── Step 6: Keeper deps ────────────────────────
info "Step 6/7: Installing keeper dependencies..."
cd keeper
npm install --silent 2>&1 | tail -2
cd ..
log "Keeper ready"

# ── Step 7: Launch instructions ────────────────
info "Step 7/7: Ready to launch"

echo ""
echo "=== ALL DONE ==="
echo ""
echo "  PoolManager: ${POOL_MANAGER_ADDR}"
echo "  SocialXHook: ${HOOK_ADDRESS}"
echo "  Explorer:    https://www.oklink.com/x-layer/address/${HOOK_ADDRESS}"
echo ""
echo "  ── Launch the autonomous agent ──────────────────"
echo ""
echo "    cd keeper && npm start"
echo ""
echo "  The agent will:"
echo "    🐦  Auto-post tweets on schedule"
echo "    📊  Read engagement (likes/RTs/replies)"
echo "    📈  Calculate social scores"
echo "    ⛓️   Push scores on-chain → fees update automatically"
echo ""
echo "  Test first with:  DRY_RUN=true npm start"
echo ""
echo "  ═════════════════════════════════════════════════"
echo "  🏆  Good luck in Build X Hackathon!"
echo "  ═════════════════════════════════════════════════"
echo ""

rm -f deploy_output.json
