// Objectives (the story spine) and the contextual tutorial.

import * as THREE from 'three';
import { SITES } from '../world/layout.js';

const V = (x, y, z) => new THREE.Vector3(x, y, z);
const LIFEFORMS = ['glimmerfin', 'lanternDrifter', 'shellback', 'razormaw', 'cantor', 'veilRay', 'hollowStalker',
  'seagrass', 'kelp', 'branchCoral', 'fanCoral', 'brainCoral', 'tubeSponge', 'anemone', 'lanternPlant', 'tubeWorm'];

export const OBJECTIVES = [
  {
    id: 'survey', title: 'Systems Check', side: true,
    text: (g) => `Swim out through the moonpool and scan three different lifeforms. (${Math.min(3, g.lifeformCount())}/3)`,
    done: (g) => g.lifeformCount() >= 3,
  },
  {
    id: 'power', title: 'Restore Power',
    text: (g) => {
      const c = g.state.flags.cellCrafted;
      if (g.state.flags.power) return 'Power restored.';
      if (c || g.hasItem('powerCell')) return 'Install the Power Cell in the station’s power core (opposite the terminal).';
      return `Collect Ferrite Nodules (${g.count('ferrite')}/3) and Lumen Crystals (${g.count('lumen')}/2) on the shelf, then fabricate a Power Cell at the station terminal.`;
    },
    target: (g) => (g.state.flags.cellCrafted || g.hasItem('powerCell') || (g.count('ferrite') >= 3 && g.count('lumen') >= 2) ? V(0, -19.5, 0) : null),
    done: (g) => g.state.flags.power,
  },
  {
    id: 'echo', title: 'Echo Lab',
    text: () => 'Lindqvist’s logs point to Echo Lab on the coral terraces to the south (~95 m). Follow the crew’s lanternbloom trail. Take the Kestrel, or craft a Pressure Suit Mk I.',
    target: () => V(SITES.echoLab.x, SITES.echoLab.floor + 3, SITES.echoLab.z),
    done: (g) => g.state.logs.includes('varga2') || g.state.logs.includes('mensah2') || g.state.logs.includes('hara1'),
  },
  {
    id: 'hull', title: 'Deep Hull Plating',
    text: (g) => `Salvage titanite plating from the wreck of the Corvid in the eastern canyon (~160 m) and fabricate the Kestrel Hull Reinforcement. Titanite: ${g.count('titanite')}/4`,
    target: (g) => (g.count('titanite') >= 4 ? V(0, -19.5, 0) : V(SITES.wreck.x, -150, SITES.wreck.z)),
    done: (g) => g.state.upgrades.hull >= 1,
  },
  {
    id: 'shards', title: 'The Three Shards',
    text: (g) => {
      const have = ['shardA', 'shardB', 'shardC'].filter((s) => g.hasItem(s) || g.state.picked.includes(s)).length;
      return `Recover the resonance shards (${have}/3): Echo Lab, the far end of the Whisper Caves (west, beyond the kelp), and the altar of the Veyru ruins in the Hadal Rift (~265 m).`;
    },
    target: (g) => {
      const p = g.state.picked;
      if (!p.includes('shardB')) return V(SITES.echoLab.x, SITES.echoLab.floor + 3, SITES.echoLab.z);
      if (!p.includes('shardA')) return g.world.structures.caveChamber.clone();
      if (!p.includes('shardC')) return V(SITES.ruins.x, SITES.ruins.floor + 4, SITES.ruins.z);
      return null;
    },
    done: (g) => ['shardA', 'shardB', 'shardC'].every((s) => g.state.picked.includes(s)),
  },
  {
    id: 'key', title: 'Finish the Chord',
    text: () => 'Bring the shards and a fragment of Veyru alloy to Meridian Station and fabricate the Resonance Key.',
    target: () => V(0, -19.5, 0),
    done: (g) => g.hasItem('resonanceKey') || g.state.flags.ending,
  },
  {
    id: 'abyss', title: 'Into the Abyss',
    text: (g) => (g.state.blueprints.includes('hull3')
      ? 'Fabricate the Kestrel Abyssal Hull at Meridian Station (void glass, Veyru alloy, titanite).'
      : 'The Kestrel will be crushed in the Abyss. Study the Veyru pressure lattice beside the ruins in the Hadal Rift.'),
    target: (g) => (g.state.blueprints.includes('hull3') ? V(0, -19.5, 0) : g.world.latticePos),
    done: (g) => g.state.upgrades.hull >= 2,
  },
  {
    id: 'threshold', title: 'The Threshold',
    text: () => 'Take the Kestrel down into the Abyss (~600 m) and sing the Resonance Key at the Threshold.',
    target: (g) => g.world.structures.gateCenter.clone(),
    done: (g) => g.state.flags.ending,
  },
  {
    id: 'beyond', title: 'The Other Half', side: false,
    text: () => 'The Low Song was answered from the north, beyond the survey line. Meridian’s beacon is transmitting again. The rest of Maren is waiting. (Chapter II)',
    target: () => V(0, -10, -820),
    done: () => false,
  },
];

const UNLOCK = {
  survey: () => true,
  power: () => true,
  echo: (g) => g.state.flags.power,
  hull: (g) => g.state.flags.power,
  shards: (g) => g.state.logs.includes('mensah2') || g.state.picked.some((p) => p.startsWith('shard')),
  key: (g) => g.isDone('shards'),
  abyss: (g) => g.isDone('hull') && (g.state.discovered.includes('ruins') || g.state.logs.includes('mensah3') || g.isDone('shards')),
  threshold: (g) => g.isDone('key') && g.isDone('abyss'),
  beyond: (g) => g.state.flags.ending,
};

export function evaluateObjectives(g) {
  const changes = [];
  for (const o of OBJECTIVES) {
    const st = g.state.objectives[o.id];
    if (!st && UNLOCK[o.id](g)) {
      g.state.objectives[o.id] = 'active';
      changes.push({ type: 'new', o });
    }
    if (g.state.objectives[o.id] === 'active' && o.done(g)) {
      g.state.objectives[o.id] = 'done';
      changes.push({ type: 'done', o });
    }
  }
  return changes;
}

export function mainObjective(g) {
  const act = OBJECTIVES.filter((o) => g.state.objectives[o.id] === 'active');
  return act.find((o) => !o.side) || act[0] || null;
}

export { LIFEFORMS };

// Contextual tutorial, shown one at a time.
export const HINTS = [
  { id: 'move', key: 'W A S D · Mouse', text: 'Swim and look around. You are floating in Meridian Station’s moonpool.', done: (g) => g.stats.moved > 6 },
  { id: 'dive', key: 'Space · C · Shift', text: 'Rise, descend and sprint. Dive down through the pool to leave the station.', done: (g) => g.player.pos.y < -24 },
  { id: 'o2', key: 'O₂', text: 'Oxygen refills at the surface, in the moonpool and aboard the Kestrel. Watch the bar bottom-left.', done: (g) => g.player.pos.y < -24, time: 9 },
  { id: 'scan', key: 'Hold Right Mouse / F', text: 'Aim at a creature or plant and hold to scan it into your databank.', done: (g) => g.state.databank.length > 0 },
  { id: 'collect', key: 'E / Left Click', text: 'Collect resource deposits. Glowing orange-flecked rocks are Ferrite; cyan crystals are Lumen.', done: (g) => g.stats.collected > 0 },
  { id: 'pda', key: 'Tab', text: 'Open your wrist PDA: objectives, map, databank, logs and inventory.', done: (g) => g.stats.pdaOpened > 0 },
  { id: 'sonar', key: 'Q', text: 'Sonar ping reveals terrain beyond visibility and marks nearby deposits.', done: (g) => g.stats.pings > 0 },
  { id: 'lamp', key: 'L', text: 'Toggle your headlamp. It drains your suit cell slowly — and some things are drawn to light.', done: (g) => g.stats.lampToggles > 0, when: (g) => g.player.depth > 45 },
  { id: 'kestrel', key: 'E', text: 'The Kestrel is docked beneath the station’s north module. Approach it and press E to board.', done: (g) => g.stats.boarded > 0, when: (g) => g.state.flags.power },
];
