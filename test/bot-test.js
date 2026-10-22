// End-to-end test: two bots join the server, queue for games, play a bit and leave.
// Needs a running server (offline mode) in a docker container named "mc".
const mineflayer = require('mineflayer');
const { execSync } = require('child_process');

const VERSION = process.env.MC_VERSION || false;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const rcon = (cmd) => execSync(`docker exec mc rcon-cli ${JSON.stringify(cmd)}`).toString().replace(/§./g, '');
let failures = 0;

function check(ok, what) {
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${what}`);
  if (!ok) failures++;
}

function join(name) {
  return new Promise((resolve, reject) => {
    const bot = mineflayer.createBot({ host: '127.0.0.1', port: 25565, username: name, version: VERSION, auth: 'offline' });
    bot.chatLog = [];
    bot.on('messagestr', (m) => bot.chatLog.push(m));
    bot.once('spawn', () => resolve(bot));
    bot.once('kicked', (r) => reject(new Error(`${name} kicked: ${JSON.stringify(r)}`)));
    bot.once('error', reject);
  });
}

async function waitFor(fn, ms, step = 500) {
  const end = Date.now() + ms;
  while (Date.now() < end) {
    if (fn()) return true;
    await sleep(step);
  }
  return fn();
}

const hasItem = (bot, name) => bot.inventory.items().some((i) => i.name === name)
  || [5, 6, 7, 8, 45].some((s) => bot.inventory.slots[s] && bot.inventory.slots[s].name === name);

async function playGame(a, b, game, expectItem) {
  console.log(`\n--- ${game} ---`);
  a.chat(`/play ${game}`);
  b.chat(`/play ${game}`);
  await sleep(1500);
  a.chat('/fc start');
  const started = await waitFor(() => /RUNNING/.test(rcon('fc list')), 25000, 1000);
  check(started, `${game}: match started`);
  console.log(rcon('fc list').trim());
  await sleep(4000);
  if (expectItem) {
    check(hasItem(a, expectItem) && hasItem(b, expectItem), `${game}: both players got ${expectItem}`);
  }
  check(a.entity.position.y > 0 && b.entity.position.y > 0, `${game}: players are in the map (y=${a.entity.position.y.toFixed(1)})`);
  b.chat('/leave');
  await sleep(1500);
  a.chat('/leave');
  const cleaned = await waitFor(() => !/RUNNING|ENDING/.test(rcon('fc list')), 20000, 1000);
  check(cleaned, `${game}: match cleaned up after everyone left`);
  await sleep(1500);
}

(async () => {
  const a = await join('BotAlice');
  const b = await join('BotBob');
  console.log(rcon('op BotAlice'));
  await sleep(3000);
  check(hasItem(a, 'compass'), 'hub: player got the game selector compass');
  check(Math.abs(a.entity.position.x) < 5 && Math.abs(a.entity.position.z) < 5, `hub: player spawned at the hub (${a.entity.position})`);

  await playGame(a, b, 'bedwars', 'wooden_sword');
  await playGame(a, b, 'skywars');
  await playGame(a, b, 'pvp', 'iron_sword');
  await playGame(a, b, 'sumo');
  await playGame(a, b, 'spleef', 'diamond_shovel');
  await playGame(a, b, 'tntrun');
  await playGame(a, b, 'buildbattle');

  console.log('\n--- duel with a kit ---');
  a.chat('/duel BotBob mace');
  await sleep(1500);
  b.chat('/duel accept BotAlice');
  const duel = await waitFor(() => /RUNNING/.test(rcon('fc list')), 20000, 1000);
  check(duel, 'duel: match started');
  await sleep(4000);
  check(hasItem(a, 'mace') && hasItem(b, 'mace'), 'duel: both players got the mace kit');
  b.chat('/leave');
  await waitFor(() => !/RUNNING|ENDING/.test(rcon('fc list')), 20000, 1000);
  a.chat('/leave');
  await sleep(2000);

  console.log('\n--- FFA kit vote event ---');
  a.chat('/fc ffa');
  await sleep(2000);
  check(a.chatLog.some((m) => /FFA event/i.test(m)) && b.chatLog.some((m) => /FFA event/i.test(m)), 'ffa: everyone was told about the vote');
  a.chat('/fc ffa cancel');
  await sleep(1000);
  a.chat('/fc ffa sword');
  const ffa = await waitFor(() => /RUNNING/.test(rcon('fc list')), 25000, 1000);
  check(ffa, 'ffa: everyone online was put into the arena');
  await sleep(4000);
  check(hasItem(a, 'diamond_sword') && hasItem(b, 'diamond_sword'), 'ffa: both players got the Sword kit');
  b.chat('/leave');
  const won = await waitFor(() => a.chatLog.some((m) => /won the game/i.test(m)), 15000, 500);
  check(won, 'ffa: last player standing won');
  await waitFor(() => !/RUNNING|ENDING/.test(rcon('fc list')), 20000, 1000);

  a.quit();
  b.quit();
  await sleep(1000);
  console.log(`\n${failures === 0 ? 'ALL BOT CHECKS PASSED' : failures + ' BOT CHECK(S) FAILED'}`);
  process.exit(failures === 0 ? 0 : 1);
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
