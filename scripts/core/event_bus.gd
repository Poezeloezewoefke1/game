extends Node
## Global signal hub. Autoload name: EventBus.

# Economy / run state
signal emeralds_changed(amount: int)
signal lives_changed(lives: int, max_lives: int)
signal wave_started(index: int, total: int, wave_name: String)
signal wave_cleared(index: int)
signal all_waves_cleared()
signal run_victory(stats: Dictionary)
signal run_defeat(stats: Dictionary)
signal game_speed_changed(speed: float)
signal paused_changed(paused: bool)

# Enemies (slot indices into EnemyManager's pools)
signal enemy_spawned(slot: int, type_id: String)
signal enemy_killed(slot: int, type_id: String, killer_id: String)
signal enemy_leaked(slot: int, type_id: String, damage: int)
signal enemy_downgraded(slot: int, from_type: String, to_type: String)
signal boss_slot_changed(slot: int)

# Towers
signal tower_placed(tower)
signal tower_sold(tower)
signal tower_upgraded(tower, path: int, tier: int)
signal tower_selected(tower)
signal tower_deselected()
signal placement_started(tower_id: String)
signal placement_cancelled()
signal relationship_activated(a_id: String, b_id: String, bonus: Dictionary)

# Hero
signal hero_level_up(level: int)
signal hero_xp_changed(xp: int, next: int)
signal hero_ability_used(index: int)
signal hero_ability_ready(index: int)
signal hero_placed(hero)

# Boss
signal boss_phase_changed(phase_index: int, phase_name: String, description: String)
signal boss_health_changed(current: float, maximum: float)
signal boss_spawned(boss)
signal boss_defeated(boss)
signal boss_event(event_id: String, payload: Dictionary)

# Presentation
signal announce(text: String, subtitle: String, duration: float)
signal dialogue(speaker_id: String, text: String, duration: float)
signal float_text(position: Vector3, text: String, color: Color)
signal camera_shake(strength: float, duration: float)
signal codex_unlocked(entry_id: String)
