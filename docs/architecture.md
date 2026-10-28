# Architecture

Overview: a small Lua plugin with one panel slot. `src/model/form.lua` turns a core record into form values and back into the changed fields; `src/ui/panel.lua` builds the declarative tree; `src/app/editor.lua` holds the state, talks to `pokemon.core` and writes.

- Manifest: id `uzume.monster-editor`, name "Creature Editor", permissions `ui`, `memory.write`, `requires` `uzume.soullink-core >= 0.5.0`, `min_player` 0.20.0, `ui.panel` titled "Editor". Reads go through the core (no `memory.read`).
- Core calls (`uz.call("pokemon.core", ...)`, always in `pcall`): `info` (supported, `features.edit_pokemon`), `edit_limits`, `team`, `box(n)`, `box_count`, `trainer`, `names_list(kind)` (species, move, item), `name("nature", id)`, `encode_pokemon(location, fields)`, `encode_money(value)`. The contract is in `uzume-plugin-soullink-core` `docs/architecture.md` ("Write helpers").
- Write path: `encode_pokemon` -> `{ ops = { {addr, bytes}, ... }, warnings }`; every op goes to `uz.memory.write(addr, bytes)` in order. A refusal stops the sequence and is shown (`consent_required` asks to allow it and press Apply again; a failure after the first op says that part of the change may be written). A pending write is read back every 5th tick for up to 12 tries; success shows "Applied" and rebuilds the form from the game's values, otherwise a warning.
- Gates (panel shows an empty state): core missing, game not supported by the core, app without `uz.memory.write`, data not ready (retried every 30 ticks).
- Lists: the panel select holds at most 100 options, so species, moves and items have a find field (live) that narrows the list; the current value always stays first.
- UI limits: textfields use `live = true` (0.20) so values arrive while typing; fields are validated against the core's `edit_limits`.
- Tests use only synthetic data: `tests/support/fake_core.lua` implements the write helper contract with invented names; the real encoding is tested in `uzume-plugin-soullink-core`.
