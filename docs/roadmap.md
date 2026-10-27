# Roadmap

Status: v0.1.0 in progress: the "Editor" panel tab with team, boxes and money for Omega Ruby / Alpha Sapphire. Needs Uzume 0.20 (`memory.write`) and `uzume-plugin-soullink-core` >= 0.5.0; nothing is verified on a real game yet.

## v0.1.0

- Panel tab "Editor" (Uzume design name: Creature Editor): Team, Boxes, Bag tabs; an edit form per creature (species with find box, level, nature, shiny, 4 moves with find box, IVs, EVs with total, held item with find box), Apply, Reset, Back. Nothing nests deeper than list -> form.
- Money: one field plus "Set money".
- Apply = `encode_pokemon` / `encode_money` of `pokemon.core` (changed fields only), then `fb.memory.write` for every returned operation, then a read-back through the core ("Applied" only when the game shows the values; otherwise "Sent, but the game still shows the old values").
- Messages for `consent_required`, `blocked_by_run_rule`, `unmapped`, a missing permission, a partial write and every core error.
- Consent, the save snapshot "Before memory changes", the write queue limits and the run log event are the app's job (Uzume 0.20).

## Open

- Items: the core has no bag offsets (`encode_item` answers unsupported), so the Bag tab shows only money and a note.
- PP of newly chosen moves: no move table is read, new moves start with 5 PP (message shown).
- Abilities are not editable and a species change keeps the old ability (message shown).
- No UI for the live level/stat refresh limits beyond the core's note; real-game verification of everything (Fabio, local).
- Games: only Omega Ruby / Alpha Sapphire (the games `uzume-plugin-soullink-core` has write helpers for); later the other games of the core.
