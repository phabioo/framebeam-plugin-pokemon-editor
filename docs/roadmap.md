# Roadmap

Status: v0.3.0 (Bag tab edits items: pouch chips, list with find field, set count, remove, add by name; needs soullink-core 0.7.0 `bag` / `encode_item`, detected through the feature flags `bag` and `edit_items`, older cores keep money plus a note; all ops of one change are written in one step; real-game behaviour untested).; v0.2.1 (manifest `replaces` `uzume.monster-editor`, so Uzume servers offer it as the replacement of the old id); v0.2.0 (plugin id `uzume.creature-editor`, repository uzume-plugin-creature-editor; was `uzume.monster-editor`); v0.1.1 (API namespace `uz`, falls back to `fb` on older apps); v0.1.0 in progress: the "Editor" panel tab with team, boxes and money for Omega Ruby / Alpha Sapphire. Needs Uzume 0.20 (`memory.write`) and `uzume-plugin-soullink-core` >= 0.5.0; nothing is verified on a real game yet.

## Known limits

- Items: done in 0.3.0 against the core's unverified bag offsets (item-to-pouch assignment is not checked by the core; the editor lets the person pick the pouch). Open: check on a real game.
- New moves start with 5 PP (message shown); abilities are not editable and a species change keeps the old ability (message shown).
- No UI for the live level/stat refresh limits beyond the core's note (no issue yet).
- Games: only Omega Ruby / Alpha Sapphire; later the other games of the core.
