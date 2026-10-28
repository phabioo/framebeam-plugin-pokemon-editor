# Roadmap

Status: v0.2.0 (plugin id `uzume.creature-editor`, repository uzume-plugin-creature-editor; was `uzume.monster-editor`); v0.1.1 (API namespace `uz`, falls back to `fb` on older apps); v0.1.0 in progress: the "Editor" panel tab with team, boxes and money for Omega Ruby / Alpha Sapphire. Needs Uzume 0.20 (`memory.write`) and `uzume-plugin-soullink-core` >= 0.5.0; nothing is verified on a real game yet.

## Known limits

- Items: the core has no bag offsets (`encode_item` answers unsupported), so the Bag tab shows only money and a note.
- New moves start with 5 PP (message shown); abilities are not editable and a species change keeps the old ability (message shown).
- No UI for the live level/stat refresh limits beyond the core's note (no issue yet).
- Games: only Omega Ruby / Alpha Sapphire; later the other games of the core.
