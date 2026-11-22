# Porting and verification method

LuanTTD targets recognizable OpenTTD behavior behind a Luanti-native 3D
interface. Treat simplified legacy simulations as scaffolding, not a port.
Port core behavior and its data together. Keep OpenTTD's own client as the
reference executable and retain named source files, notices, source revision
and regression fixtures. Original models, environments and UI are separate from
the simulation; do not distribute proprietary or unverified art.

## Version and license

The first pin is [OpenTTD 14.1](https://github.com/OpenTTD/OpenTTD/tree/14.1),
the version used in the reference tests. Integrated game code containing or
linking these ports is GPL-2.0-only. The complete corresponding Lua,
asset-authoring inputs in the project and packaging scripts accompany releases.
See [COPYING.OpenTTD.md](COPYING.OpenTTD.md) for the upstream license and [art provenance](../art/README.md). Keep additional notices when importing more code.

## Preview acceptance checks

The released scope can be small but must be complete. First candidate:
one two-town road-passenger service, only controls and modes that are ready.
Use the 3D viewport for construction and orders; hotbar for primary tools,
compact side/context windows for secondary controls. Keep billboards optional
and skip them if they detract.

- **Terrain:** OpenTTD corner rules, matched raise/lower and leveling outcomes,
  clear slopes, real 3D foundation and road ramps. Terrain and infrastructure
  share a height truth; previews, ray picking, routes and vehicles agree.
- **Seams:** Native views at street and survey height for straight roads, both
  orientations of a bend, junctions, stops and sloped joins. No misalignment,
  gaps, flipped directions, obvious tiles beneath infrastructure or wheels
  that float/clip on ramps. Real vehicles successfully drive test routes.
- **Art:** Recognizable temperate palette, readable silhouettes and appropriately
  dense little towns, foliage, roads and station scenery. Every visible feature
  in this release needs a finished 3D asset, not a marker, labeled box or
  placeholder prop. This applies to buildings, nature and infrastructure,
  not just moving vehicles. No in-progress features in released scenarios
  or UI. Keep the original Blender sources and verify CC reference provenance
  when derivative; no copied OpenGFX sprites.
- **Playtest:** Human-equivalent mouse and keyboard from a fresh world in the
  graphical Linux client: build roads/stops/depot, purchase, assign two
  world-picked stops, dispatch, observe boarding and payout, then save and
  reload while service continues. Run the equivalent OpenTTD task and record
  what diverges, including a matching slope/foundation case. Inspect snapshots
  at multiple heights and a short video of moving vehicles. Tests supplement
  this, not replace it. No numbered release until the experience passes.
