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
  a.setQuickBarSlot(8);
  await sleep(300);
  const floorMenu = new Promise((resolve) => a.once('windowOpen', resolve));
  a.activateItem();
  const floorWin = await Promise.race([floorMenu, sleep(5000).then(() => null)]);
  check(!!floorWin, 'buildbattle: floor menu opens');
  if (floorWin) {
    await a.clickWindow(4, 0, 0); // snow block
    await sleep(1500);
    const under = a.blockAt(a.entity.position.offset(0, -1, 0));
    check(under && under.name === 'snow_block', `buildbattle: floor changed (${under && under.name})`);
  }
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

  console.log('\n--- Block Party: dance until someone falls ---');
  check(await startMatch(a, b, 'blockparty'), 'blockparty: match started');
  rcon(inGame({ who: 'BotAlice', run: 'tp @s BotBob' }));
  rcon(inGame({ who: 'BotAlice', run: 'tp @s ~1.5 ~ ~' }));
  await sleep(600);
  const bobBefore = b.entity.position.clone();
  const bobEntity = a.players.BotBob && a.players.BotBob.entity;
  if (bobEntity) {
    await a.lookAt(bobEntity.position.offset(0, 1.5, 0), true);
    a.attack(bobEntity);
  }
  await sleep(800);
  check(b.entity.position.distanceTo(bobBefore) > 0.5, `blockparty: punching knocks people back (${b.entity.position.distanceTo(bobBefore).toFixed(2)} blocks)`);
  check(b.health >= 19, `blockparty: punches do no damage (health ${b.health})`);
  check(await waitFor(() => a.inventory.items().some((i) => i.name.endsWith('_concrete')), 15000), 'blockparty: a colour gets called');
  check(await waitFor(() => said(a, /won the game|ended in a draw/), 150000, 1000), 'blockparty: the floor drops until the game ends');
  await finishMatch(a, b);

  console.log('\n--- One in the Chamber: kill, bonus arrow, respawn ---');
  check(await startMatch(a, b, 'oitc'), 'oitc: match started');
  check(hasItem(a, 'bow') && hasItem(a, 'arrow'), 'oitc: bow and one arrow given');
  a.setQuickBarSlot(0);
  await fight(a, b, 45000);
  check(said(a, /BotBob .*BotAlice/), 'oitc: Alice killed Bob');
  await sleep(1000);
  const arrows = a.inventory.items().filter((i) => i.name === 'arrow').reduce((n, i) => n + i.count, 0);
  check(arrows === 2, `oitc: a kill gives an extra arrow (${arrows})`);
  check(await waitFor(() => b.game.gameMode === 'survival', 8000), 'oitc: Bob respawns after dying');
  b.chat('/leave');
  check(await waitFor(() => said(a, /BotAlice won the game/), 6000), 'oitc: last one in wins');
  await finishMatch(a, b);

  console.log('\n--- Party, chat format ---');
  clearLogs(a, b);
  a.chat('/party invite BotBob');
  await sleep(1000);
  b.chat('/party accept BotAlice');
  check(await waitFor(() => said(a, /BotBob joined the party/), 5000), 'party: Bob joined Alice\'s party');
  a.chat('/play spleef');
  check(await waitFor(() => said(b, /party leader took you/), 5000), 'party: the leader\'s /play brings the party along');
  check(/Spleef.*BotAlice.*BotBob|Spleef.*BotBob.*BotAlice/.test(rcon('fc list')), 'party: both are in the same queue');
  a.chat('/leave');
  b.chat('/leave');
  await sleep(1000);
  a.chat('hello from alice');
  const serverSaw = () => /\[\d+✫\] BotAlice: hello from alice/.test(execSync('docker logs mc 2>&1').toString());
  check(await waitFor(serverSaw, 5000), 'chat: rendered as "[level✫] name: message"');
  console.log('      (Bob\'s client got: ' + JSON.stringify(b.chatLog.find((m) => /hello from alice/.test(m))) + ')');
  a.chat('/party leave');
  check(await waitFor(() => said(b, /party was disbanded/), 5000), 'party: leaving a 2-player party disbands it');

  console.log('\n--- BedWars economy: generator -> shop ---');
  check(await startMatch(a, b, 'bedwars'), 'bedwars economy: match started');
  const gen = a.findBlock({ matching: (blk) => blk.name === 'gold_block', maxDistance: 12 });
  check(!!gen, 'bedwars: found my generator');
  if (gen) {
    rcon(inGame({ who: 'BotAlice', run: `tp @s ${gen.position.x + 0.5} ${gen.position.y + 1} ${gen.position.z + 0.5}` }));
    check(await waitFor(() => a.inventory.items().some((i) => i.name === 'iron_ingot' && i.count >= 6), 15000), 'bedwars: the generator gives iron');
    const villagers = Object.values(a.entities).filter((e) => e.name === 'villager' && e.position.distanceTo(a.entity.position) < 16);
    let bought = false;
    for (const v of villagers) {
      rcon(inGame({ who: 'BotAlice', run: `tp @s ${v.position.x + 1.5} ${v.position.y} ${v.position.z + 0.5}` }));
      await sleep(800);
      const opened = new Promise((resolve) => a.once('windowOpen', resolve));
      a.activateEntity(v);
      const win = await Promise.race([opened, sleep(3000).then(() => null)]);
      if (win && /Item Shop/.test(JSON.stringify(win.title))) {
        const before = a.inventory.items().filter((i) => i.name === 'iron_ingot').reduce((n, i) => n + i.count, 0);
        await a.clickWindow(19, 0, 0); // 16 wool for 4 iron
        await sleep(1500);
        const wool = a.inventory.items().filter((i) => i.name.endsWith('_wool')).reduce((n, i) => n + i.count, 0);
        const after = a.inventory.items().filter((i) => i.name === 'iron_ingot').reduce((n, i) => n + i.count, 0);
        check(wool >= 16, `bedwars: bought 16 wool (${wool})`);
        check(after < before, `bedwars: paid with iron (${before} -> ${after})`);
        bought = true;
        a.closeWindow(a.currentWindow || win);
        break;
      }
      if (win) {
        a.closeWindow(win);
      }
    }
    check(bought, 'bedwars: found and used the item shop villager');
  }
  b.chat('/leave');
  await finishMatch(a, b);

  console.log('\n--- Bed Fight: auto teams, spam-click PvP, bed break ---');
  check(await startMatch(a, b, 'bedfight'), 'bedfight: match started');
  check((hasItem(a, 'red_wool') && hasItem(b, 'blue_wool')) || (hasItem(a, 'blue_wool') && hasItem(b, 'red_wool')),
    'bedfight: players were split into red and blue teams');
  const atk = a.entity.attributes && (a.entity.attributes['minecraft:attack_speed'] || a.entity.attributes['minecraft:generic.attack_speed']
    || a.entity.attributes['generic.attack_speed'] || a.entity.attributes.attack_speed);
  console.log('      attack speed attribute: ' + JSON.stringify(atk && atk.value));
  check(!atk || atk.value >= 100, 'bedfight: 1.8 spam-click combat (no attack cooldown)');
  rcon(inGame({ who: 'BotAlice', run: 'tp @s BotBob' }));
  await sleep(1500);
  const fightBed = a.findBlock({ matching: (blk) => blk.name.endsWith('_bed'), maxDistance: 16 });
  check(!!fightBed, 'bedfight: Alice found Bob\'s bed');
  if (fightBed) {
    rcon(inGame({ who: 'BotAlice', run: `tp @s ${fightBed.position.x + 0.5} ${fightBed.position.y + 1} ${fightBed.position.z - 1.5}` }));
    await sleep(1000);
    try {
      await a.dig(a.blockAt(fightBed.position), true);
    } catch (e) {
      console.log('dig error', e.message);
    }
    check(await waitFor(() => said(a, /BED DESTRUCTION/), 5000), 'bedfight: Alice broke Bob\'s bed');
  }
  voidPlayer('BotBob');
  check(await waitFor(() => said(a, /FINAL KILL/), 6000), 'bedfight: no bed means a final kill');
  check(await waitFor(() => said(a, /won the game/), 6000), 'bedfight: the other team wins');
  await finishMatch(a, b);

  console.log('\n--- Fireball Fight: fireball jump ---');
  check(await startMatch(a, b, 'fireball'), 'fireball fight: match started');
  check(hasItem(a, 'fire_charge'), 'fireball fight: kit has fireballs');
  const ballSlot = a.inventory.items().find((i) => i.name === 'fire_charge');
  if (ballSlot) {
    a.setQuickBarSlot(ballSlot.slot - 36);
    await a.look(a.entity.yaw, -Math.PI / 2, true);
    await sleep(300);
    const startY = a.entity.position.y;
    let maxY = startY;
    const tracker = setInterval(() => { maxY = Math.max(maxY, a.entity.position.y); }, 50);
    a.activateItem();
    await sleep(2000);
    clearInterval(tracker);
    check(maxY - startY > 2, `fireball fight: a fireball at your feet launches you (+${(maxY - startY).toFixed(1)} blocks)`);
    check(a.health >= 19, `fireball fight: fireballs only knock back (health ${a.health})`);
  }
  b.chat('/leave');
  await finishMatch(a, b);

  console.log('\n--- The Bridge: score in the enemy portal ---');
  check(await startMatch(a, b, 'bridge'), 'bridge: match started');
  await sleep(3000); // cages
  check(hasItem(a, 'iron_sword') && (hasItem(a, 'red_terracotta') || hasItem(a, 'blue_terracotta')), 'bridge: bridge kit in team colours');
  rcon(inGame({ who: 'BotAlice', run: 'tp @s BotBob' }));
  await sleep(1500);
  const portal = a.findBlock({ matching: (blk) => blk.name === 'end_portal', maxDistance: 24 });
  check(!!portal, 'bridge: Alice found the enemy goal');
  if (portal) {
    rcon(inGame({ who: 'BotAlice', run: `tp @s ${portal.position.x + 0.5} ${portal.position.y + 1.5} ${portal.position.z + 0.5}` }));
    check(await waitFor(() => said(a, /BotAlice scored/), 6000), 'bridge: jumping in the enemy portal scores a point');
  }
  b.chat('/leave');
  check(await waitFor(() => said(a, /won the game/), 6000), 'bridge: last team in wins');
  await finishMatch(a, b);

  console.log('\n--- Creeper kit: deep map, lit creepers ---');
  a.chat('/duel BotBob creeperpvp');
  await sleep(1500);
  b.chat('/duel accept BotAlice');
  check(await waitFor(() => /RUNNING/.test(rcon('fc list')), 25000, 1000), 'creeper duel: match started');
  await sleep(4000);
  const below = a.blockAt(a.entity.position.offset(0, -12, 0));
  check(below && below.name !== 'air', `creeper duel: the map is deep (12 blocks down: ${below && below.name})`);
  const eggItem = a.inventory.items().find((i) => i.name === 'creeper_spawn_egg');
  if (eggItem) {
    a.setQuickBarSlot(eggItem.slot - 36);
    rcon(inGame({ who: 'BotAlice', run: 'tp @s ~4 ~ ~' }));
    await sleep(800);
    const ground = a.blockAt(a.entity.position.offset(0, -1, 0));
    await a.lookAt(ground.position.offset(0.5, 1, 0.5), true);
    try {
      await a.activateBlock(ground);
    } catch (e) {
      console.log('egg error', e.message);
    }
    let creeper = null;
    await waitFor(() => (creeper = Object.values(a.entities).find((e) => e.name === 'creeper')) != null, 3000, 100);
    check(!!creeper, 'creeper duel: the egg spawned a creeper');
    if (creeper) {
      const spot = creeper.position.clone();
      await sleep(800);
      const moved = creeper.isValid !== false && a.entities[creeper.id] ? a.entities[creeper.id].position.distanceTo(spot) : 0;
      check(moved < 0.5, `creeper duel: the creeper stands still (${moved.toFixed(2)} blocks)`);
      check(await waitFor(() => !a.entities[creeper.id], 4000, 100), 'creeper duel: it explodes by itself');
    }
  }
  b.chat('/leave');
  await waitFor(() => !/RUNNING|ENDING/.test(rcon('fc list')), 20000, 1000);
  a.chat('/leave');
  await sleep(2000);

  console.log('\n--- Spleef: snowballs knock you back ---');
  check(await startMatch(a, b, 'spleef'), 'spleef: match started');
  rcon('give BotBob snowball 8');
  rcon(inGame({ who: 'BotBob', run: 'tp @s BotAlice' }));
  rcon(inGame({ who: 'BotBob', run: 'tp @s ~3 ~ ~' }));
  await sleep(1200);
  const target = b.players.BotAlice && b.players.BotAlice.entity;
  if (target) {
    const ball = b.inventory.items().find((i) => i.name === 'snowball');
    if (ball) {
      b.setQuickBarSlot(ball.slot - 36);
    }
    await b.lookAt(target.position.offset(0, 1.2, 0), true);
    await sleep(200);
    const before = a.entity.position.clone();
    b.activateItem();
    await sleep(1200);
    const moved = a.entity.position.distanceTo(before);
    check(moved > 0.8, `spleef: a snowball knocks Alice back (${moved.toFixed(2)} blocks)`);
  } else {
    check(false, 'spleef: Bob can see Alice');
  }
  b.chat('/leave');
  await finishMatch(a, b);

  console.log('\n--- Sumo: three lives ---');
  check(await startMatch(a, b, 'sumo'), 'sumo lives: match started');
  rcon(inGame({ who: 'BotAlice', run: 'tp @s BotBob' }));
  rcon(inGame({ who: 'BotAlice', run: 'tp @s ~1.5 ~ ~' }));
  await sleep(600);
  const sumoBob = a.players.BotBob && a.players.BotBob.entity;
  const sumoBefore = b.entity.position.clone();
  if (sumoBob) {
    await a.lookAt(sumoBob.position.offset(0, 1.5, 0), true);
    a.attack(sumoBob);
  }
  await sleep(800);
  check(b.entity.position.distanceTo(sumoBefore) > 0.5, `sumo: punches knock people back (${b.entity.position.distanceTo(sumoBefore).toFixed(2)} blocks)`);
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

  console.log('\n--- Anti-cheat ---');
  const acLines = () => execSync('docker logs mc 2>&1').toString().split('\n').filter((l) => l.includes('[AC]'));
  const legitFlags = acLines();
  legitFlags.forEach((l) => console.log('      false positive? ' + l.trim()));
  check(legitFlags.length === 0, `anticheat: no flags during all the legit play above (${legitFlags.length})`);
  check(await startMatch(a, b, 'pvp'), 'anticheat: match started');
  // reach: hit Bob from 6 blocks away
  rcon(inGame({ who: 'BotAlice', run: 'tp @s BotBob' }));
  rcon(inGame({ who: 'BotAlice', run: 'tp @s ~6 ~ ~' }));
  await sleep(2500);
  const farBob = a.players.BotBob && a.players.BotBob.entity;
  const bobHealth = b.health;
  if (farBob) {
    await a.lookAt(farBob.position.offset(0, 1.5, 0), true);
    a.attack(farBob);
    a.attack(farBob);
  }
  await sleep(1000);
  check(acLines().some((l) => /BotAlice failed Reach/.test(l)), 'anticheat: catches a 6-block reach hit');
  check(b.health >= bobHealth, `anticheat: the reach hit did no damage (${bobHealth} -> ${b.health})`);
  // fly: float straight up with no gravity
  await sleep(2000);
  const groundY = a.entity.position.y;
  a.physics.gravity = 0;
  for (let i = 0; i < 40; i++) {
    a.entity.position.y += 0.3;
    a.entity.velocity.y = 0;
    await sleep(50);
  }
  a.physics.gravity = 0.08;
  await sleep(1500);
  check(acLines().some((l) => /BotAlice failed Fly/.test(l)), 'anticheat: catches flying');
  check(a.entity.position.y < groundY + 6, `anticheat: the flyer was pulled back (${(a.entity.position.y - groundY).toFixed(1)} blocks up)`);
  b.chat('/leave');
  await finishMatch(a, b);
  check(!execSync('docker logs mc 2>&1').toString().includes('was kicked for'), 'anticheat: nobody got kicked during the test');

  a.quit();
  b.quit();
  await sleep(1000);
  console.log(`\n${failures === 0 ? 'ALL BOT CHECKS PASSED' : failures + ' BOT CHECK(S) FAILED'}`);
  process.exit(failures === 0 ? 0 : 1);
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
