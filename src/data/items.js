// Items, recipes and upgrades.

export const ITEMS = {
  ferrite: { name: 'Ferrite Nodule', icon: 'nodule', color: '#9fb0bd', desc: 'Iron-nickel concretion that forms around volcanic vents on the shelf. Basic structural metal.' },
  lumen: { name: 'Lumen Crystal', icon: 'crystal', color: '#62e6ff', desc: 'Piezo-luminescent crystal. Stores and releases energy as cold light. Used in power systems.' },
  kelpFiber: { name: 'Kelp Fibre', icon: 'fiber', color: '#8fcf7a', desc: 'Tough, flexible fibre from lumen kelp seed pods. Woven into seals, harnesses and suit liners.' },
  silica: { name: 'Coral Silica', icon: 'shard', color: '#f0c9b8', desc: 'Glassy skeletal plates shed by ember coral. Excellent pressure-resistant composite filler.' },
  titanite: { name: 'Titanite Plate', icon: 'plate', color: '#e0975a', desc: 'Salvaged titanium-ceramic hull plating from the Corvid’s cargo. Rated for deep work.' },
  voidGlass: { name: 'Void Glass', icon: 'crystal', color: '#a387ff', desc: 'Black-violet volcanic glass from deep fissures. Absurdly strong under compression.' },
  veyruAlloy: { name: 'Veyru Alloy', icon: 'glyph', color: '#9ef5e0', desc: 'Fragment of an alloy no human foundry could make. It is slightly warm and hums at 7 Hz.' },
  medkit: { name: 'Field Medkit', icon: 'med', color: '#ff8a8a', desc: 'Coagulant foam, stimulant and pressure bandage. Restores 50 health.', consumable: true },
  powerCell: { name: 'Station Power Cell', icon: 'cell', color: '#ffd27a', desc: 'Lumen-core power cell sized for Meridian Station’s main bus.', story: true },
  shardA: { name: 'Resonance Shard (Caves)', icon: 'glyph', color: '#b48cff', desc: 'A curved shard of Veyru crystal from deep inside the Whisper Caves. Its glyphs pulse when held near the others.', story: true },
  shardB: { name: 'Resonance Shard (Echo Lab)', icon: 'glyph', color: '#b48cff', desc: 'The shard June Hara brought back from the caves and Dr. Mensah studied at Echo Lab. Annotated in pencil along its edge: “this one is the tonic”.', story: true },
  shardC: { name: 'Resonance Shard (Rift)', icon: 'glyph', color: '#b48cff', desc: 'Taken from the altar of the Veyru ruins. It was resting in a socket shaped for exactly three.', story: true },
  resonanceKey: { name: 'Resonance Key', icon: 'key', color: '#e6d1ff', desc: 'Three shards fused into a single chord. When it sings, the Low Song answers.', story: true },
};

export const UPGRADES = {
  tank: { name: 'Oxygen Tank', levels: [75, 120, 170], unit: 's', label: 'O₂ capacity' },
  suit: { name: 'Pressure Suit', levels: [60, 180, 340], unit: 'm', label: 'Suit depth rating' },
  fins: { name: 'Hydro-fins', levels: [1, 1.3], unit: '×', label: 'Swim speed' },
  sonar: { name: 'Sonar', levels: [150, 320], unit: 'm', label: 'Sonar range' },
  battery: { name: 'Suit Battery', levels: [100, 160], unit: '%', label: 'Battery capacity' },
  hull: { name: 'Kestrel Hull', levels: [200, 450, 900], unit: 'm', label: 'Kestrel depth rating' },
};

// where: 'station' (Meridian upgrade bay) or 'any' (station or Kestrel fabricator)
export const RECIPES = [
  { id: 'powerCell', name: 'Station Power Cell', cost: { ferrite: 3, lumen: 2 }, gives: { item: 'powerCell' }, where: 'station', emergency: true, known: true,
    desc: 'Restores Meridian Station’s main power bus.' },
  { id: 'medkit', name: 'Field Medkit', cost: { kelpFiber: 2, lumen: 1 }, gives: { item: 'medkit' }, where: 'any', emergency: true, known: true,
    desc: 'Restores 50 health. Use from the inventory or press H.' },
  { id: 'tank2', name: 'High-Capacity O₂ Tank', cost: { ferrite: 3, kelpFiber: 2 }, gives: { upgrade: 'tank', level: 1 }, where: 'station', known: true,
    desc: 'Oxygen capacity 75 s → 120 s.' },
  { id: 'suit1', name: 'Pressure Suit Mk I', cost: { kelpFiber: 2, silica: 3, ferrite: 1 }, gives: { upgrade: 'suit', level: 1 }, where: 'station', known: true,
    desc: 'Safe diving depth 60 m → 180 m.' },
  { id: 'battery2', name: 'Lumen Cell Pack', cost: { lumen: 3, ferrite: 2 }, gives: { upgrade: 'battery', level: 1 }, where: 'station', known: true,
    desc: 'Suit battery capacity +60%. Powers headlamp, scanner and sonar.' },
  { id: 'fins', name: 'Hydro-fins', cost: { kelpFiber: 2, silica: 1 }, gives: { upgrade: 'fins', level: 1 }, where: 'station', blueprint: 'fins',
    desc: 'Swim speed +30%.' },
  { id: 'sonar2', name: 'Sonar Booster', cost: { lumen: 2, titanite: 1 }, gives: { upgrade: 'sonar', level: 1 }, where: 'station', blueprint: 'sonar',
    desc: 'Sonar range 150 m → 320 m and marks resource deposits.' },
  { id: 'tank3', name: 'Deep O₂ Tank', cost: { titanite: 2, silica: 2, lumen: 1 }, gives: { upgrade: 'tank', level: 2 }, where: 'station', blueprint: 'tank3', requires: { tank: 1 },
    desc: 'Oxygen capacity 120 s → 170 s.' },
  { id: 'suit2', name: 'Pressure Suit Mk II', cost: { titanite: 3, voidGlass: 2, kelpFiber: 1 }, gives: { upgrade: 'suit', level: 2 }, where: 'station', blueprint: 'suit2', requires: { suit: 1 },
    desc: 'Safe diving depth 180 m → 340 m.' },
  { id: 'hull2', name: 'Kestrel Hull Reinforcement', cost: { titanite: 4, ferrite: 2 }, gives: { upgrade: 'hull', level: 1 }, where: 'station', blueprint: 'hull2',
    desc: 'Kestrel crush depth 200 m → 450 m.' },
  { id: 'hull3', name: 'Kestrel Abyssal Hull', cost: { voidGlass: 3, veyruAlloy: 2, titanite: 2 }, gives: { upgrade: 'hull', level: 2 }, where: 'station', blueprint: 'hull3', requires: { hull: 1 },
    desc: 'Kestrel crush depth 450 m → 900 m. Required to survive the Abyss.' },
  { id: 'key', name: 'Resonance Key', cost: { shardA: 1, shardB: 1, shardC: 1, veyruAlloy: 1 }, gives: { item: 'resonanceKey' }, where: 'station', blueprint: 'key',
    desc: 'Fuse the three resonance shards into a single chord.' },
];

export const INVENTORY_CAPACITY = 40;
