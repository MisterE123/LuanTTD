# LuanTTD provenance

LuanTTD is an independent, incomplete transport simulation for Luanti.
It is not an official OpenTTD release and is not endorsed by the OpenTTD
project or the original Transport Tycoon publishers.

The integrated game code is distributed under the GNU General Public
License, version 2 only. See [LICENSE](../LICENSE).

## Derived OpenTTD code and data

LuanTTD contains adapted Lua ports and data from [OpenTTD 14.1](https://github.com/OpenTTD/OpenTTD/tree/14.1),
copyright the OpenTTD contributors as identified in the upstream
source. The files are adaptations for the Luanti game, not unmodified
OpenTTD C++ files. See [PORTING.md](PORTING.md) and the port source
headers for component-level provenance and an accounting of what is
not yet implemented. The upstream license is reproduced in
[COPYING.OpenTTD.md](COPYING.OpenTTD.md).

No OpenTTD executable, commercial Transport Tycoon assets, or OpenGFX
sprite sets are part of the runtime archive. See [art/README.md](../art/README.md)
for the model, texture and audio provenance, and the repository's `art/`
and `tests/` directories for authoring inputs and generation scripts.
