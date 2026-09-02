# Textures

Generated, not downloaded. Every file here is produced by
`tools/generate_textures.gd`:

```
godot --headless --path . --script tools/generate_textures.gd
```

They are committed rather than generated at build time so that a fresh clone
runs without a generation step, and so a texture change shows up as a reviewable
diff rather than as a silent shift in what the build produces.

Each material has an albedo, a tangent-space normal and a roughness map; `hull`
adds a metallic map. All of them tile: the base noise is generated seamless and
every derived map is computed with wrapping neighbour lookups.

See `docs/ASSET_PROVENANCE.md` for why nothing here came from the internet, and
for how to drop real photography into the sky.
