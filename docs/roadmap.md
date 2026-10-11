# Roadmap

Status: planned, nothing implemented. Depends on FrameBeam plugin API v1 (0.11, planned); see https://github.com/phabioo/framebeam `docs/roadmap.md`.

## Planned

- Starts after the SoulLink MVP; depends on `framebeam-plugin-pokemon-core` and on the `memory.write` permission (not part of the first FrameBeam plugin release).
- Edit team and box Pokémon: species, level, nature, IVs/EVs, moves, shiny; items; money.
- Re-encryption and checksum on write, per game generation.
- Safety: save snapshot before the first write, write queue, run log event "editor used", run rule whether editing is allowed.
- First game: Omega Ruby / Alpha Sapphire, then the games of `framebeam-plugin-pokemon-core`.

Requires plugin API v1 (FrameBeam 0.11, planned) with `memory.write`.
