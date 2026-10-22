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


const inGame = (cmd) => `execute as ${cmd.who} at @s run ${cmd.run}`;
const voidPlayer = (name) => rcon(inGame({ who: name, run: 'tp @s ~ 5 ~' }));
const said = (bot, re) => bot.chatLog.some((m) => re.test(m));
const clearLogs = (...bots) => bots.forEach((x) => { x.chatLog.length = 0; });

async function startMatch(a, b, game) {
  clearLogs(a, b);
  a.chat(`/play ${game}`);
  b.chat(`/play ${game}`);
  await sleep(1500);
  a.chat('/fc start');
  const ok = await waitFor(() => /RUNNING/.test(rcon('fc list')), 25000, 1000);
  await sleep(4000); // spawn protection runs out
  return ok;
}

async function finishMatch(a, b) {
  await waitFor(() => !/RUNNING|ENDING/.test(rcon('fc list')), 25000, 1000);
  a.chat('/leave');
  b.chat('/leave');
  await sleep(2000);
}

/** Alice hits Bob until the game says he died. */
async function fight(a, b, ms) {
  const end = Date.now() + ms;
  let hits = 0;
  while (Date.now() < end && !said(a, /BotBob .*BotAlice/)) {
    const target = a.players.BotBob && a.players.BotBob.entity;
    if (!target || target.position.distanceTo(a.entity.position) > 3) {
      rcon(inGame({ who: 'BotAlice', run: 'tp @s BotBob' }));
      await sleep(300);
      continue;
    }
    await a.lookAt(target.position.offset(0, 1.5, 0), true);
    a.attack(target);
    hits++;
    await sleep(650);
  }
  return hits;
}

(async () => {
  const a = await join('BotAlice');
  await sleep(5000); // Bukkit throttles connections from the same IP within 4 seconds
  const b = await join('BotBob');
  console.log(rcon('op BotAlice'));
  await sleep(3000);
  check(hasItem(a, 'compass'), 'hub: player got the game selector compass');
  check(Math.abs(a.entity.position.x) < 5 && Math.abs(a.entity.position.z) < 5, `hub: player spawned at the hub (${a.entity.position})`);

  const plate = a.findBlock({ matching: (blk) => blk.name === 'light_weighted_pressure_plate', maxDistance: 48 });
  check(!!plate, `hub: parkour start plate exists${plate ? ' at ' + plate.position : ''}`);

  console.log('\n--- BedWars team picker ---');
  a.chat('/play bedwars');
  await sleep(1500);
  check(hasItem(a, 'white_wool'), 'bedwars queue: team picker item given');
  a.setQuickBarSlot(2);
  await sleep(300);
  const picker = new Promise((resolve) => a.once('windowOpen', resolve));
  a.activateItem();
  const win = await Promise.race([picker, sleep(5000).then(() => null)]);
  check(!!win, 'bedwars queue: team picker menu opens');
  if (win) {
    await a.clickWindow(1, 0, 0);
    check(await waitFor(() => said(a, /You picked the Red team/), 5000), 'bedwars queue: picked the Red team');
  }
  a.chat('/leave');
  await sleep(1500);

  await playGame(a, b, 'bedwars', 'wooden_sword');
  await playGame(a, b, 'skywars');
  await playGame(a, b, 'pvp', 'iron_sword');
  await playGame(a, b, 'sumo');
  await playGame(a, b, 'spleef', 'diamond_shovel');
  await playGame(a, b, 'tntrun');
  await playGame(a, b, 'buildbattle');


  console.log('\n--- PvP: a real fight to the death ---');
  check(await startMatch(a, b, 'pvp'), 'pvp fight: match started');
  a.setQuickBarSlot(0);
  const hits = await fight(a, b, 45000);
  check(said(a, /BotBob .*BotAlice/), `pvp fight: Alice killed Bob (${hits} hits)`);
  check(await waitFor(() => said(a, /BotAlice won the game/), 5000), 'pvp fight: Alice won');
  check(b.game.gameMode === 'spectator', `pvp fight: Bob spectates after dying (${b.game.gameMode})`);
  check(said(a, /PLAY AGAIN/), 'pvp fight: Play Again button shown');
  a.chat('/play pvp');
  await sleep(1500);
  check(/WAITING/.test(rcon('fc list')), 'play again: clicking it puts you back in the queue');
  a.chat('/leave');
  await finishMatch(a, b);

  console.log('\n--- BedWars: void respawn, bed break, final kill ---');
  check(await startMatch(a, b, 'bedwars'), 'bedwars deep: match started');
  voidPlayer('BotBob');
  check(await waitFor(() => said(a, /BotBob fell into the void/), 5000), 'bedwars: falling into the void kills you');
  check(await waitFor(() => b.game.gameMode === 'survival' && b.entity.position.y > 60, 12000), 'bedwars: Bob respawned (his bed is still there)');
  await sleep(1000);
  check(hasItem(b, 'wooden_sword'), 'bedwars: respawn kit given');
  rcon(inGame({ who: 'BotAlice', run: 'tp @s BotBob' }));
  await sleep(1500);
  const bed = a.findBlock({ matching: (blk) => blk.name.endsWith('_bed'), maxDistance: 16 });
  check(!!bed, 'bedwars: Alice can see Bob\'s bed');
  if (bed) {
    rcon(inGame({ who: 'BotAlice', run: `tp @s ${bed.position.x + 0.5} ${bed.position.y + 1} ${bed.position.z + 2.5}` }));
    await sleep(1000);
    try {
      await a.dig(a.blockAt(bed.position), true);
    } catch (e) {
      console.log('dig error', e.message);
    }
    check(await waitFor(() => said(a, /BED DESTRUCTION/), 5000), 'bedwars: Alice broke Bob\'s bed');
  }
  voidPlayer('BotBob');
  check(await waitFor(() => said(a, /FINAL KILL/), 5000), 'bedwars: next death is a final kill');
  check(await waitFor(() => said(a, /won the game/), 5000), 'bedwars: last team standing wins');
  await finishMatch(a, b);

  console.log('\n--- Build Battle: build time, voting, results ---');
  check(await startMatch(a, b, 'buildbattle'), 'buildbattle deep: match started');
  check(a.game.gameMode === 'creative', `buildbattle: builders are in creative (${a.game.gameMode})`);
  a.chat('/fc skip');
  check(await waitFor(() => hasItem(a, 'yellow_terracotta'), 8000), 'buildbattle: voting items handed out');
  for (let round = 0; round < 2; round++) {
    await sleep(1500);
    for (const bot of [a, b]) {
      bot.setQuickBarSlot(6);
      await sleep(200);
      bot.activateItem();
      bot.deactivateItem();
    }
    await sleep(1000);
    a.chat('/fc skip');
  }
  check(await waitFor(() => said(a, /Build Battle results/), 10000), 'buildbattle: results announced');
  check(await waitFor(() => said(a, /won the game/), 5000), 'buildbattle: a winner was picked');
  await finishMatch(a, b);

  console.log('\n--- SkyWars: cages open and starter kit ---');
  check(await startMatch(a, b, 'skywars'), 'skywars kit: match started');
  check(await waitFor(() => hasItem(a, 'stone_sword'), 8000), 'skywars: default Fighter kit given when cages open');
  b.chat('/leave');
  check(await waitFor(() => said(a, /BotAlice won the game/), 6000), 'skywars: last player standing wins');
  await finishMatch(a, b);

  console.log('\n--- Sumo: three lives ---');
  check(await startMatch(a, b, 'sumo'), 'sumo lives: match started');
  voidPlayer('BotBob');
  check(await waitFor(() => said(a, /BotBob .*2 lives left/), 6000), 'sumo: first fall costs a life');
  await sleep(1500);
  voidPlayer('BotBob');
  check(await waitFor(() => said(a, /BotBob .*1 life left/), 6000), 'sumo: second fall costs a life');
  await sleep(1500);
  voidPlayer('BotBob');
  check(await waitFor(() => said(a, /BotAlice won the game/), 6000), 'sumo: out of lives means out');
  await finishMatch(a, b);

  console.log('\n--- duel with a kit ---');
  a.chat('/duel BotBob mace');
  await sleep(1500);
  b.chat('/duel accept BotAlice');
  const duel = await waitFor(() => /RUNNING/.test(rcon('fc list')), 20000, 1000);
  check(duel, 'duel: match started');
  await sleep(4000);
  check(hasItem(a, 'mace') && hasItem(b, 'mace'), 'duel: both players got the mace kit');
  clearLogs(a);
  b.chat('/leave');
  check(await waitFor(() => said(a, /REMATCH/), 5000), 'duel: rematch button shown to the winner');
  await waitFor(() => !/RUNNING|ENDING/.test(rcon('fc list')), 20000, 1000);
  a.chat('/leave');
  await sleep(2000);

  console.log('\n--- duel with an uploaded kit (fireball fight) ---');
  a.chat('/duel BotBob fireballfight');
  await sleep(1500);
  b.chat('/duel accept BotAlice');
  check(await waitFor(() => /RUNNING/.test(rcon('fc list')), 20000, 1000), 'fireball duel: match started');
  await sleep(4000);
  check(hasItem(a, 'fire_charge') && hasItem(b, 'blue_wool'), 'fireball duel: kit has fireballs and wool');
  a.setQuickBarSlot(4);
  await sleep(300);
  a.activateItem();
  await sleep(1000);
  const ballsLeft = a.inventory.items().filter((i) => i.name === 'fire_charge').reduce((n, i) => n + i.count, 0);
  check(ballsLeft === 5, `fireball duel: right-click threw a fireball (${ballsLeft} left)`);
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
