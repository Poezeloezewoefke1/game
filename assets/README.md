# Assets

Every asset in this project is **original**. Nothing here is downloaded,
purchased, or third-party, so the repository carries no asset licence question.

| Folder | Holds | Current state |
|---|---|---|
| `audio/` | Sound cues | **Empty on purpose.** All cues are tones synthesised at runtime by `scripts/core/audio_director.gd`. Dropping a real `.wav`/`.ogg` here and pointing `AudioDirector` at it is a one-line change with no call-site edits. |
| `materials/` | Shared `.tres` materials | **Empty.** Materials are built in code and cached per palette entry in `scripts/utility/world_block.gd`, so a level of ~80 blocks allocates one material per palette rather than one per block. |
| `models/` | Imported meshes | **Empty.** All geometry is Godot primitives (`BoxMesh`, `CapsuleMesh`, `CylinderMesh`, `PrismMesh`, `SphereMesh`, `TorusMesh`) placed by hand in the level scenes. |
| `particles/` | Particle materials | **Empty.** Effects are lights, emissive materials and tweens. |
| `textures/` | Images | **Empty** apart from `icon.svg` at the project root. |

## Why the folders exist while empty

They are the agreed home for each asset kind. Creating them at the point someone
first needs one invites a parallel structure to appear somewhere else. Keeping
them here — with this file explaining what belongs where — costs nothing and
keeps the answer to "where does this go?" in one place.
