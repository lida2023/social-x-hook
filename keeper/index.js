/**
 * SocialX Keeper
 *
 * Read-only X engagement collector:
 * 1. Reads latest public tweets for configured X handles.
 * 2. Computes a 0-100 social score.
 * 3. Resolves each handle to a registered KOL wallet on SocialXHook.
 * 4. Pushes scores on-chain through batchUpdateScores().
 *
 * Tweets are posted manually from TWEETS.md. X API write access is not required.
 */

const fs = require("fs");
const path = require("path");
const { ethers } = require("ethers");

loadEnv(path.resolve(__dirname, "..", ".env"));

const CONFIG = {
  rpcUrl: process.env.XLAYER_RPC_URL || "https://testnet.xlayer.tech",
  privateKey: process.env.PRIVATE_KEY || "",
  hookAddress: process.env.HOOK_ADDRESS || "",
  xBearerToken: process.env.X_BEARER_TOKEN || "",
  trackedKols: process.env.TRACKED_KOLS
    ? process.env.TRACKED_KOLS.split(",").map((h) => h.trim()).filter(Boolean)
    : [],
  scoreThreshold: Number.parseInt(process.env.SCORE_THRESHOLD || "100", 10),
  likeWeight: Number.parseInt(process.env.LIKE_WEIGHT || "1", 10),
  retweetWeight: Number.parseInt(process.env.RETWEET_WEIGHT || "2", 10),
  replyWeight: Number.parseInt(process.env.REPLY_WEIGHT || "3", 10),
  quoteWeight: Number.parseInt(process.env.QUOTE_WEIGHT || "2", 10),
  scoreUpdateIntervalSec: Number.parseInt(process.env.SCORE_UPDATE_INTERVAL_SEC || "600", 10),
  dryRun: process.env.DRY_RUN === "true",
  runOnce: process.env.RUN_ONCE === "true",
};

const SOCIAL_X_HOOK_ABI = [
  "function handleToAddress(string) view returns (address)",
  "function getKOL(address) view returns (tuple(string xHandle, uint256 socialScore, uint256 registeredAt, bool active))",
  "function batchUpdateScores(address[] calldata kols, uint256[] calldata scores) external",
  "function keepers(address) view returns (bool)",
];

function loadEnv(envPath) {
  if (!fs.existsSync(envPath)) return;

  const lines = fs.readFileSync(envPath, "utf8").split(/\r?\n/);
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;

    const eq = trimmed.indexOf("=");
    if (eq === -1) continue;

    const key = trimmed.slice(0, eq).trim();
    let value = trimmed.slice(eq + 1).trim();
    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }

    if (!process.env[key]) process.env[key] = value;
  }
}

async function resolveHandle(handle) {
  const username = handle.startsWith("@") ? handle.slice(1) : handle;
  if (!CONFIG.xBearerToken) return `sim_${username}`;

  let resp;
  try {
    const url = `https://api.twitter.com/2/users/by/username/${username}`;
    resp = await fetch(url, {
      headers: { Authorization: `Bearer ${CONFIG.xBearerToken}` },
    });
  } catch (err) {
    console.warn(`  X resolve failed for ${handle}: ${err.message}`);
    return null;
  }

  if (!resp.ok) {
    console.warn(`  X resolve failed for ${handle}: ${resp.status}`);
    return null;
  }

  const data = await resp.json();
  return data.data?.id || null;
}

async function fetchLatestTweetByHandle(handle) {
  const userId = await resolveHandle(handle);
  if (!userId) return null;

  if (!CONFIG.xBearerToken) {
    return {
      id: `sim_${Date.now()}`,
      text: "[simulated tweet]",
      metrics: {
        like_count: Math.floor(Math.random() * 50),
        retweet_count: Math.floor(Math.random() * 10),
        reply_count: Math.floor(Math.random() * 5),
        quote_count: Math.floor(Math.random() * 3),
      },
    };
  }

  let resp;
  try {
    const url =
      `https://api.twitter.com/2/users/${userId}/tweets` +
      "?max_results=5&tweet.fields=public_metrics,created_at&exclude=retweets,replies";
    resp = await fetch(url, {
      headers: { Authorization: `Bearer ${CONFIG.xBearerToken}` },
    });
  } catch (err) {
    console.warn(`  X tweet fetch failed for ${handle}: ${err.message}`);
    return null;
  }

  if (!resp.ok) {
    console.warn(`  X tweet fetch failed for ${handle}: ${resp.status}`);
    return null;
  }

  const data = await resp.json();
  if (!data.data || data.data.length === 0) return null;

  const tweet = data.data[0];
  return { id: tweet.id, text: tweet.text, metrics: tweet.public_metrics };
}

function calculateScore(metrics) {
  if (!metrics) return 0;

  const raw =
    (metrics.like_count || 0) * CONFIG.likeWeight +
    (metrics.retweet_count || 0) * CONFIG.retweetWeight +
    (metrics.reply_count || 0) * CONFIG.replyWeight +
    (metrics.quote_count || 0) * CONFIG.quoteWeight;

  return Math.min(100, Math.floor((raw / CONFIG.scoreThreshold) * 100));
}

async function collectScores(hook) {
  const kolsToUpdate = [];
  const scoresToUpdate = [];

  for (const handle of CONFIG.trackedKols) {
    const tweet = await fetchLatestTweetByHandle(handle);
    if (!tweet) {
      console.log(`  ${handle}: no tweet data`);
      continue;
    }

    const score = calculateScore(tweet.metrics);
    const preview = tweet.text.replace(/\s+/g, " ").slice(0, 72);
    console.log(`  ${handle}: score ${score}/100 from "${preview}"`);

    if (CONFIG.dryRun || !hook) {
      kolsToUpdate.push(handle);
      scoresToUpdate.push(score);
      continue;
    }

    const kolAddress = await hook.handleToAddress(handle);
    if (kolAddress === ethers.ZeroAddress) {
      console.warn(`    skipped: ${handle} is not registered on-chain`);
      continue;
    }

    kolsToUpdate.push(kolAddress);
    scoresToUpdate.push(score);
  }

  return { kolsToUpdate, scoresToUpdate };
}

async function pushScoresOnChain(hook, kolsToUpdate, scoresToUpdate) {
  if (kolsToUpdate.length === 0) {
    console.log("  no score updates");
    return;
  }

  if (CONFIG.dryRun) {
    console.log(`  dry run: would update ${kolsToUpdate.length} score(s)`);
    for (let i = 0; i < kolsToUpdate.length; i++) {
      console.log(`    ${kolsToUpdate[i]} -> ${scoresToUpdate[i]}`);
    }
    return;
  }

  const tx = await hook.batchUpdateScores(kolsToUpdate, scoresToUpdate);
  console.log(`  tx: ${tx.hash}`);
  await tx.wait();
  console.log(`  updated ${kolsToUpdate.length} score(s)`);
}

async function buildHookClient() {
  if (CONFIG.dryRun) return null;

  if (!CONFIG.privateKey) throw new Error("PRIVATE_KEY is required when DRY_RUN=false");
  if (!ethers.isAddress(CONFIG.hookAddress)) throw new Error("HOOK_ADDRESS is required when DRY_RUN=false");

  const provider = new ethers.JsonRpcProvider(CONFIG.rpcUrl);
  const wallet = new ethers.Wallet(CONFIG.privateKey, provider);
  const hook = new ethers.Contract(CONFIG.hookAddress, SOCIAL_X_HOOK_ABI, wallet);

  const isKeeper = await hook.keepers(wallet.address);
  if (!isKeeper) {
    throw new Error(`wallet ${wallet.address} is not an authorized keeper`);
  }

  console.log(`  keeper wallet: ${wallet.address}`);
  return hook;
}

async function main() {
  console.log("SocialX Keeper");
  console.log(`  rpc: ${CONFIG.rpcUrl}`);
  console.log(`  hook: ${CONFIG.hookAddress || "(dry run / unset)"}`);
  console.log(`  handles: ${CONFIG.trackedKols.join(", ") || "(none)"}`);
  console.log(`  interval: ${CONFIG.scoreUpdateIntervalSec}s`);
  console.log(`  dry run: ${CONFIG.dryRun}`);
  console.log(`  run once: ${CONFIG.runOnce}`);
  console.log("");

  if (CONFIG.trackedKols.length === 0) {
    throw new Error("TRACKED_KOLS is empty");
  }

  const hook = await buildHookClient();

  // eslint-disable-next-line no-constant-condition
  while (true) {
    console.log(`--- ${new Date().toISOString()} ---`);
    const { kolsToUpdate, scoresToUpdate } = await collectScores(hook);
    await pushScoresOnChain(hook, kolsToUpdate, scoresToUpdate);
    console.log("");
    if (CONFIG.runOnce) break;
    await sleep(CONFIG.scoreUpdateIntervalSec * 1000);
  }
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

main().catch((err) => {
  console.error(`Fatal: ${err.message}`);
  process.exit(1);
});
