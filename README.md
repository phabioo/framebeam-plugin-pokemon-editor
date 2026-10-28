# Uzume Plugin: Creature Editor

Creature editor for Uzume: edit team, box, items and money through memory writes.

Status: **v0.2.1** (manifest `replaces` `uzume.monster-editor`, so Uzume servers offer it as the replacement of the old id). Before: **v0.2.0** (plugin id `uzume.creature-editor`, repository uzume-plugin-creature-editor; was `uzume.monster-editor`); **v0.1.1** (API namespace `uz`, falls back to `fb` on older apps); **v0.1.0: team and box creatures (species, level, nature, IVs/EVs, moves, shiny, held item) and money for Omega Ruby / Alpha Sapphire; items follow when the core knows the bag; not yet tested on a real game.**

Requires Uzume 0.20 (`memory.write` in the plugin API; [Uzume roadmap](https://github.com/phabioo/uzume/blob/main/docs/roadmap.md)) and [uzume-plugin-soullink-core](https://github.com/phabioo/uzume-plugin-soullink-core). Part of [Uzume](https://github.com/phabioo/uzume); plugin API: `docs/guides/plugin-api.md` there. Plan: [docs/roadmap.md](docs/roadmap.md).

Every PR description needs a `## Changelog` section (see `.github/pull_request_template.md`); CI checks it with `tools/changelog.py`, and releases should build their notes from these sections.

License: GPL-3.0-or-later, see [LICENSE](LICENSE) and [NOTICE.md](NOTICE.md). Contributions under the [CLA](CLA.md).

Pokémon and Nintendo are trademarks of their owners. This project is not affiliated with them and contains no game content.
