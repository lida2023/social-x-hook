/**
 * 🐦 SocialX Autonomous Agent
 *    Auto-posts tweets → reads engagement → pushes scores on-chain.
 *
 * ── One-time setup ─────────────────────────────
 *  1. Go to https://developer.twitter.com → create a Free tier app
 *  2. Generate "API Key & Secret" + "Access Token & Secret"
 *     (must be Read+Write, NOT Bearer Token)
 *  3. Fill .env with your credentials
 *  4. Run: node keeper/index.js
 *
 * ── The agent does the rest ────────────────────
 *  • Posts tweets on a pre-configured schedule
 *  • Waits for engagement to accumulate
 *  • Reads likes/RTs/replies
 *  • Calculates social score
 *  • Pushes score on-chain to SocialXHook
 *
 *  No manual tweeting. No manual anything.
 */

const { ethers } = require("ethers");
const crypto = require("crypto");

// ────────────────────────────────────────────────
//  CONFIG — all from .env
// ────────────────────────────────────────────────

const CONFIG = {
  // Chain
  rpcUrl: process.env.XLAYER_RPC_URL || "https://rpc.xlayer.tech",
  privateKey: process.env.PRIVATE_KEY || "",
  hookAddress: process.env.HOOK_ADDRESS || "",

  // X API v2 OAuth 1.0a (for posting)
  xApiKey: process.env.X_API_KEY || "",
  xApiSecret: process.env.X_API_KEY_SECRET || "",
  xAccessToken: process.env.X_ACCESS_TOKEN || "",
  xAccessSecret: process.env.X_ACCESS_TOKEN_SECRET || "",

  // X API v2 Bearer (for reading — can be same app)
  xBearerToken: process.env.X_BEARER_TOKEN || "",

  // KOL handles to track
  trackedKols: process.env.TRACKED_KOLS
    ? process.env.TRACKED_KOLS.split(",").map((h) => h.trim())
    : [],

  // Scoring
  scoreThreshold: 100,
  likeWeight: 1,
  retweetWeight: 2,
  replyWeight: 3,
  quoteWeight: 2,

  // Posting schedule (seconds between tweets)
  postIntervalSec: parseInt(process.env.POST_INTERVAL_SEC || "14400"), // 4h default

  // Engagement check delay (seconds after posting before reading)
  engagementDelaySec: parseInt(process.env.ENGAGEMENT_DELAY_SEC || "900"), // 15min

  // Score update interval
  scoreUpdateIntervalSec: parseInt(process.env.SCORE_UPDATE_INTERVAL_SEC || "600"), // 10min

  dryRun: process.env.DRY_RUN === "true" || false,
};

// ────────────────────────────────────────────────
//  TWEET SCHEDULE
//  ── Posts in order, loops when exhausted
// ────────────────────────────────────────────────

const TWEET_SCHEDULE = [
  // Day 1 — Project launch
  {
    text: `🚀 Building on @XLayerOfficial for the Build X Hackathon!

Introducing SocialX Hook — the first Uniswap V4 Hook that connects your X influence directly to on-chain swap fees.

The louder you tweet, the cheaper your pool trades. 🐦

@Uniswap @flapdotsh
#BuildXHackathon #XLayer #UniswapV4`,
  },
  {
    text: `DeFi pools are SILENT 🤫

KOLs drive attention on X, but that value never reaches their on-chain pool.

SocialX Hook fixes this:
• Your tweets → lower swap fees
• More volume → more LP revenue  
• KOL earns 30% of swap fees

Retweet if this clicks 🔁
@XLayerOfficial @Uniswap @flapdotsh`,
  },
  {
    text: `🛠️ How it works under the hood:

SocialX Hook uses @Uniswap V4's beforeSwap hook to override LP fees dynamically.

socialScore = f(likes, RTs, replies)
→ pushed on-chain by keeper
→ fee adjusts in real-time

Pure V4 magic. No oracle. No extra gas for LPs. ✨
@XLayerOfficial @flapdotsh`,
  },
  // Day 2 — Demo + engagement
  {
    text: `🎥 Watch SocialX Hook live:

1. Agent posts a tweet 🐦
2. Engagement flows in (likes + RTs)
3. Social score goes up 📈
4. Pool fee drops from 1% → 0.01% ⚡

Your X presence now has on-chain consequences.

@XLayerOfficial @Uniswap @flapdotsh
#DeFi #Web3Social`,
  },
  {
    text: `💭 Who benefits most from SocialX Hook?

• Crypto traders 📊
• NFT artists 🎨
• Gaming streamers 🎮
• DeFi educators 📚

Tag a creator who should launch their own SocialX pool 👇

@XLayerOfficial @Uniswap @flapdotsh`,
  },
  {
    text: `Why Uniswap V4 Hooks > V3?

V3: Static fees. Set once, never changes.
V4 + SocialX Hook: Dynamic fees. Change per-block based on external signals.

Hooks make pools PROGRAMMABLE. That's the unlock. 🧵
@Uniswap @flapdotsh`,
  },
  // Day 3 — Submit
  {
    text: `✅ Submitted SocialX Hook to the @XLayerOfficial Build X Hackathon!

Contract live on XLayer (Chain 196) 🏗️
Autonomous agent running ⚡
Dynamic fees working 🔥

Your social graph → on-chain liquidity.
That's the thesis.

@Uniswap @flapdotsh`,
  },
  {
    text: `🏆 Final call!

If you believe social signals belong on-chain, give us a follow and RT 🚀

Built with @Uniswap V4 Hooks on @XLayerOfficial.
Shoutout @flapdotsh for pushing social × DeFi forward.

LFG! 💪
#BuildXHackathon`,
  },
];

// ────────────────────────────────────────────────
//  ABI
// ────────────────────────────────────────────────

const SOCIAL_X_HOOK_ABI = [
  "function handleToAddress(string) view returns (address)",
  "function getKOL(address) view returns (tuple(string xHandle, uint256 socialScore, uint256 totalFeesEarned, uint256 pendingFees, uint256 poolCreatedAt, bool registered))",
  "function updateSocialScore(address kol, uint256 newScore) external",
  "function batchUpdateScores(address[] calldata kols, uint256[] calldata scores) external",
  "function keepers(address) view returns (bool)",
];

// ────────────────────────────────────────────────
//  OAuth 1.0a Signing (no external deps needed)
// ────────────────────────────────────────────────

function oauthSign(method, url, params, consumerSecret, tokenSecret) {
  const allParams = { ...params };
  allParams.oauth_consumer_key = CONFIG.xApiKey;
  allParams.oauth_nonce = crypto.randomBytes(16).toString("hex");
  allParams.oauth_signature_method = "HMAC-SHA1";
  allParams.oauth_timestamp = Math.floor(Date.now() / 1000).toString();
  allParams.oauth_token = CONFIG.xAccessToken;
  allParams.oauth_version = "1.0";

  // Build signature base string
  const sortedKeys = Object.keys(allParams).sort();
  const paramStr = sortedKeys
    .map((k) => `${encodeURIComponent(k)}=${encodeURIComponent(allParams[k])}`)
    .join("&");

  const sigBase =
    method.toUpperCase() +
    "&" +
    encodeURIComponent(url) +
    "&" +
    encodeURIComponent(paramStr);

  const signingKey =
    encodeURIComponent(consumerSecret) + "&" + encodeURIComponent(tokenSecret || "");

  const signature = crypto
    .createHmac("sha1", signingKey)
    .update(sigBase)
    .digest("base64");

  allParams.oauth_signature = signature;

  // Build Authorization header
  const authHeader =
    "OAuth " +
    sortedKeys
      .concat(["oauth_signature"])
      .filter((k) => k.startsWith("oauth_"))
      .map((k) => `${encodeURIComponent(k)}="${encodeURIComponent(allParams[k])}"`)
      .join(", ");

  return authHeader;
}

// ────────────────────────────────────────────────
//  X API: Post a tweet
// ────────────────────────────────────────────────

async function postTweet(text) {
  if (CONFIG.dryRun) {
    console.log(`  🔸 DRY RUN — would post: "${text.slice(0, 80)}..."`);
    return { id: `dry_${Date.now()}`, text };
  }

  if (!CONFIG.xApiKey || !CONFIG.xAccessToken) {
    console.warn("  ⚠️  X API credentials not set — skipping post");
    return null;
  }

  const url = "https://api.twitter.com/2/tweets";
  const method = "POST";

  try {
    const authHeader = oauthSign(method, url, {}, CONFIG.xApiSecret, CONFIG.xAccessSecret);

    const resp = await fetch(url, {
      method: "POST",
      headers: {
        Authorization: authHeader,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ text }),
    });

    if (!resp.ok) {
      const errBody = await resp.text();
      console.error(`  ❌ Post failed: ${resp.status} — ${errBody.slice(0, 200)}`);
      return null;
    }

    const data = await resp.json();
    console.log(`  ✅ Posted: https://x.com/i/status/${data.data.id}`);
    return data.data;
  } catch (err) {
    console.error(`  ❌ Post error:`, err.message);
    return null;
  }
}

// ────────────────────────────────────────────────
//  X API: Read tweet engagement
// ────────────────────────────────────────────────

async function fetchTweetMetrics(tweetId) {
  if (!CONFIG.xBearerToken) {
    // Simulated for dry runs
    return {
      like_count: Math.floor(Math.random() * 50),
      retweet_count: Math.floor(Math.random() * 10),
      reply_count: Math.floor(Math.random() * 5),
      quote_count: Math.floor(Math.random() * 3),
      impression_count: Math.floor(Math.random() * 500),
    };
  }

  try {
    const url = `https://api.twitter.com/2/tweets/${tweetId}?tweet.fields=public_metrics`;
    const resp = await fetch(url, {
      headers: { Authorization: `Bearer ${CONFIG.xBearerToken}` },
    });
    if (!resp.ok) return null;
    const data = await resp.json();
    return data.data?.public_metrics || null;
  } catch {
    return null;
  }
}

async function resolveHandle(handle) {
  const username = handle.startsWith("@") ? handle.slice(1) : handle;
  if (!CONFIG.xBearerToken) return `sim_${username}`;

  try {
    const url = `https://api.twitter.com/2/users/by/username/${username}`;
    const resp = await fetch(url, {
      headers: { Authorization: `Bearer ${CONFIG.xBearerToken}` },
    });
    if (!resp.ok) return null;
    const data = await resp.json();
    return data.data?.id || null;
  } catch {
    return null;
  }
}

async function fetchLatestTweetByHandle(handle) {
  const userId = await resolveHandle(handle);
  if (!userId) return null;

  if (!CONFIG.xBearerToken) {
    return {
      id: `sim_${Date.now()}`,
      text: "[Simulated tweet]",
      metrics: {
        like_count: Math.floor(Math.random() * 50),
        retweet_count: Math.floor(Math.random() * 10),
        reply_count: Math.floor(Math.random() * 5),
        quote_count: Math.floor(Math.random() * 3),
      },
    };
  }

  try {
    const url = `https://api.twitter.com/2/users/${userId}/tweets?max_results=5&tweet.fields=public_metrics,created_at&exclude=retweets,replies`;
    const resp = await fetch(url, {
      headers: { Authorization: `Bearer ${CONFIG.xBearerToken}` },
    });
    if (!resp.ok) return null;
    const data = await resp.json();
    if (!data.data || data.data.length === 0) return null;
    const tweet = data.data[0];
    return { id: tweet.id, text: tweet.text, metrics: tweet.public_metrics };
  } catch {
    return null;
  }
}

// ────────────────────────────────────────────────
//  Scoring engine
// ────────────────────────────────────────────────

function calculateScore(metrics) {
  if (!metrics) return 0;
  const raw =
    (metrics.like_count || 0) * CONFIG.likeWeight +
    (metrics.retweet_count || 0) * CONFIG.retweetWeight +
    (metrics.reply_count || 0) * CONFIG.replyWeight +
    (metrics.quote_count || 0) * CONFIG.quoteWeight;
  return Math.min(100, Math.floor((raw / CONFIG.scoreThreshold) * 100));
}

// ────────────────────────────────────────────────
//  On-chain: push scores
// ────────────────────────────────────────────────

async function pushScoresOnChain(hook, kolsToUpdate, scoresToUpdate) {
  if (kolsToUpdate.length === 0) return;

  if (CONFIG.dryRun) {
    console.log(`  🔸 DRY RUN — would update ${kolsToUpdate.length} KOLs`);
    for (let i = 0; i < kolsToUpdate.length; i++) {
      console.log(`      ${kolsToUpdate[i]} → score ${scoresToUpdate[i]}`);
    }
    return;
  }

  try {
    const tx = await hook.batchUpdateScores(kolsToUpdate, scoresToUpdate);
    console.log(`  📤 Tx: ${tx.hash}`);
    await tx.wait();
    console.log(`  ✅ On-chain scores updated for ${kolsToUpdate.length} KOLs`);
  } catch (err) {
    console.error(`  ❌ Tx failed:`, err.message);
  }
}

// ────────────────────────────────────────────────
//  Main Autonomous Loop
// ────────────────────────────────────────────────

async function main() {
  console.log("╔══════════════════════════════════════════╗");
  console.log("║  🐦 SocialX Autonomous Agent            ║");
  console.log("║  Post → Read → Score → Update (loop)    ║");
  console.log("╚══════════════════════════════════════════╝");
  console.log("");
  console.log(`  RPC:        ${CONFIG.rpcUrl}`);
  console.log(`  Hook:       ${CONFIG.hookAddress}`);
  console.log(`  KOLs:       ${CONFIG.trackedKols.join(", ") || "(none)"}`);
  console.log(`  Post every: ${CONFIG.postIntervalSec}s`);
  console.log(`  Dry run:    ${CONFIG.dryRun}`);
  console.log("");

  // ── Validate ────────────────────────────────
  if (!CONFIG.dryRun) {
    if (!CONFIG.privateKey) {
      console.error("❌ PRIVATE_KEY not set");
      process.exit(1);
    }
    if (!CONFIG.hookAddress || CONFIG.hookAddress === "0x0000000000000000000000000000000000000000") {
      console.error("❌ HOOK_ADDRESS not set");
      process.exit(1);
    }
  }

  // ── Connect chain ────────────────────────────
  const provider = new ethers.JsonRpcProvider(CONFIG.rpcUrl);
  const wallet = CONFIG.privateKey
    ? new ethers.Wallet(CONFIG.privateKey, provider)
    : null;
  const hook = new ethers.Contract(CONFIG.hookAddress, SOCIAL_X_HOOK_ABI, wallet || provider);

  if (wallet) {
    console.log(`  Agent: ${wallet.address}`);
    try {
      const isKeeper = await hook.keepers(wallet.address);
      if (!isKeeper) {
        console.error("❌ Agent address is not a keeper! Owner must call addKeeper() first.");
        process.exit(1);
      }
      console.log("  ✅ Keeper verified on-chain");
    } catch (err) {
      console.error("❌ Cannot connect to hook contract:", err.message);
      process.exit(1);
    }
  }

  // ── Detect mode ───────────────────────────────
  const hasOAuth = !!(CONFIG.xApiKey && CONFIG.xAccessToken);
  if (hasOAuth) {
    console.log(`  📋 ${TWEET_SCHEDULE.length} tweets queued (auto-post ON)`);
  } else {
    console.log(`  📋 ${TWEET_SCHEDULE.length} tweets queued (manual post — see TWEETS.md)`);
    console.log(`  🤖 Auto-post OFF — agent reads + scores only`);
  }
  console.log("");

  // ── State ─────────────────────────────────────
  let tweetIndex = 0;
  let lastPostTime = 0;
  let postedTweets = [];

  // ── Main loop ────────────────────────────────
  // eslint-disable-next-line no-constant-condition
  while (true) {
    const now = Date.now();
    console.log(`─── ${new Date().toISOString()} ───`);

    // ── Phase 1: Post next tweet (if due AND OAuth configured) ──
    if (hasOAuth && now - lastPostTime >= CONFIG.postIntervalSec * 1000) {
      const tweet = TWEET_SCHEDULE[tweetIndex % TWEET_SCHEDULE.length];
      console.log(`  📝 Posting tweet #${tweetIndex + 1}...`);
      const result = await postTweet(tweet.text);

      if (result) {
        postedTweets.push({ id: result.id, text: tweet.text, postedAt: now });
        tweetIndex++;
        lastPostTime = now;
      } else {
        lastPostTime = now; // skip this slot, try next cycle
      }
    } else if (hasOAuth) {
      const nextPostSec = Math.floor(
        (CONFIG.postIntervalSec * 1000 - (now - lastPostTime)) / 1000
      );
      console.log(`  ⏳ Next auto-post in ${nextPostSec}s`);
    } else {
      console.log(`  📝 Manual mode — tweet from TWEETS.md, agent reads + scores`);
    }

    // ── Phase 2: Read engagement of recent tweets ──
    console.log(`  📊 Reading engagement...`);
    const kolsToUpdate = [];
    const scoresToUpdate = [];
    const processedTweets = [];

    // Check our own posted tweets for engagement
    for (const pt of postedTweets) {
      // Only check tweets older than engagementDelay
      if (now - pt.postedAt < CONFIG.engagementDelaySec * 1000) continue;

      const metrics = await fetchTweetMetrics(pt.id);
      if (!metrics) continue;

      const score = calculateScore(metrics);
      const m = metrics;
      console.log(`    📊 Tweet ${pt.id.slice(-8)}: ❤️${m.like_count} 🔄${m.retweet_count} 💬${m.reply_count} → Score ${score}/100`);
    }

    // Check each tracked KOL's latest tweet
    for (const handle of CONFIG.trackedKols) {
      const tweet = await fetchLatestTweetByHandle(handle);
      if (!tweet) continue;

      const score = calculateScore(tweet.metrics);
      console.log(`    @${handle.replace("@", "")}: "${tweet.text.slice(0, 60)}..." → Score ${score}/100`);

      const kolAddress = await hook.handleToAddress(handle);
      const addrStr = kolAddress.toString();
      if (addrStr === "0x0000000000000000000000000000000000000000") continue;

      kolsToUpdate.push(addrStr);
      scoresToUpdate.push(score);
    }

    // ── Phase 3: Push scores on-chain ──────────
    await pushScoresOnChain(hook, kolsToUpdate, scoresToUpdate);

    // ── Clean old posted tweets (keep last 20) ──
    if (postedTweets.length > 20) {
      postedTweets = postedTweets.slice(-20);
    }

    // ── Wait ───────────────────────────────────
    const waitSec = Math.min(
      CONFIG.scoreUpdateIntervalSec,
      Math.max(60, Math.floor((CONFIG.postIntervalSec * 1000 - (Date.now() - lastPostTime)) / 1000))
    );
    console.log(`  💤 Next cycle in ${waitSec}s...`);
    console.log("");
    await sleep(waitSec * 1000);
  }
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

// ── Run ────────────────────────────────────────
main().catch((err) => {
  console.error("Fatal:", err);
  process.exit(1);
});
