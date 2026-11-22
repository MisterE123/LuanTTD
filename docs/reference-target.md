# OpenTTD reference target

The pinned target is [OpenTTD 16.0-RC1](https://www.openttd.org/news/2026/10/31/openttd-16-0-rc1),
upstream commit [`07b339c`](https://github.com/OpenTTD/OpenTTD/releases/tag/16.0-RC1).
The supplied [Linux amd64 reference](https://cdn.openttd.org/openttd-releases/16.0-RC1/openttd-16.0-RC1-linux-generic-amd64.tar.xz)
reports `OpenTTD 16.0-RC1`; it is not included with LuanTTD.

- **Compared:** the [AutoRoad hotspot fix](https://github.com/OpenTTD/OpenTTD/pull/16101)
  is ported for single-tile clicks. The native tile projection and half selection
  are checked over all 256 fractional positions.
- **Compared:** the plain-track signal command and straight-track signal
  height in [rail_cmd.cpp](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/rail_cmd.cpp).
  Signals can be purchased on either stock straight grade, with the mast base
  sampled at its exact source anchor rather than the tile's lowest corner.
  This does not add signal heads on curves or overlapping track.
- **Compared:** retained world-generation options have counterparts in
  [world settings](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/table/settings/world_settings.ini)
  and [difficulty settings](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/table/settings/difficulty_settings.ini).
  Road servicing interval and units come from
  [company settings](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/table/settings/company_settings.ini).
  LuanTTD currently supports narrower map sizes and some narrower vehicle
  rules; matching option names does not establish gameplay parity.
- **Pending comparison:** the RC1 rail end-of-line reverse and reservation fix,
  station coverage highlighting and the larger changes from OpenTTD 15 and 16.
  Re-run subsystem-level comparisons against 16.0-RC1 before moving their
  version-specific claims in [State of the Port](PORTING.md). Keep each
  source file's original provenance until explicitly updated.
