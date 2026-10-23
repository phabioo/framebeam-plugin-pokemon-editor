# Roadmap

Status: planned, nothing implemented. Needs `memory.write` in the Uzume plugin API, planned in Uzume 0.20 ([Uzume roadmap](https://github.com/phabioo/uzume/blob/main/docs/roadmap.md)).

## Planned

- Starts after the SoulLink MVP; depends on `uzume-plugin-soullink-core` and on the `memory.write` permission (Uzume 0.20).
- Edit team and box Pokémon: species, level, nature, IVs/EVs, moves, shiny; items; money.
- Re-encryption and checksum on write, per game generation.
- Safety: save snapshot before the first write, write queue, run log event "editor used", run rule whether editing is allowed.
- First game: Omega Ruby / Alpha Sapphire, then the games of `uzume-plugin-soullink-core`.
