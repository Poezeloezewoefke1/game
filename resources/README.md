# Resources

Godot `.tres` resource files.

| Folder | Intended for | Current state |
|---|---|---|
| `items/` | Per-item definition resources | **Empty.** The three Power Crystals and the Star Map are identified by stable string ids in `GameConfig`, and their behaviour lives in their scenes. |
| `missions/` | Mission definition resources | **Empty.** *The Lost Signal* is the only mission, and its rules are in `scripts/core/mission_rules.gd`. |
| `settings/` | Shipped default settings | **Empty.** Local preferences are stored per machine in `user://settings.cfg` by `SettingsManager`. |

## Why tuning lives in `GameConfig` rather than in resources here

Every gameplay-significant number is a constant in
`scripts/core/game_config.gd`, and that is a deliberate choice rather than an
oversight.

The values are read by three different consumers that **must** agree: the host
when it validates a request, the client when it predicts and draws a prompt, and
the automated tests when they assert behaviour. A constant is resolved at parse
time and cannot be out of sync between them. A `.tres` file can be edited,
partially loaded, or shipped in one build and not another — and a divergence
between the value a client predicts with and the value the host validates with
is exactly the shape of a desync bug that is painful to diagnose.

The trade-off is that changing a value needs a rebuild rather than a resource
edit. For a fixed-scope single-mission slice that is the better side of the
trade. If this ever grows to several missions with per-mission tuning, a mission
resource loaded by the host and replicated to clients as part of the session
handshake is the right shape — and it belongs in `missions/`.
