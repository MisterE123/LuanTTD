# Transport Gazette

Open **Inventory → Newspaper** for dated message history (newest first).
Select a headline to read the newspaper. **Last message** walks backwards
through eligible messages and wraps. **Go to this location** moves above
a referenced map tile without changing the camera angle. **Dismiss alerts**
closes the visible alerts without deleting history.

Fresh full bulletins appear at the upper right for 16.650 seconds, without
opening a form or taking input from the player. Summary headlines and
status-only reminders stay in the status area. **News settings** has all
16 stock categories and their original defaults. It affects automatic
display and the Last message button, not what is stored in history.

## RC1 source and verification

The queue, category rules, display selection, expiry and replay follow
[news_gui.cpp](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/news_gui.cpp),
[news_type.h](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/news_type.h)
and [news_display_settings.ini](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/table/settings/news_display_settings.ini).
The journal stores both the calendar date displayed and the economy day
used to evaluate age. Startup does not print already-available models.
Full and summary/status lanes select oldest eligible first independently;
history retains up to 1,024 newest items, pruning aged entries monthly
down to a preferred minimum of 30 with the stock default age multiplier.
Worker station removal invalidates linked arrival news. The worker
checkpoints the journal and its arrival bits; user display choices and
acknowledged automatic lanes are per player. Public news does not transmit
company names, company ledger data, or vehicle internals.

Event sources translated here: public sale of mounted road, rail, ship
and aircraft models (not rail wagons or private previews), first physical
bus/truck/train/ship/aircraft arrivals per station and vehicle kind, and
rail collision (original engine and vehicle controller hooks). The
worker also reports openings and closures seen in the authoritative
mounted industry registries on month transitions.
All 16 presentation categories exist; not every upstream producer is
connected. That includes dynamic local/competitor production notices,
subsidy and acceptance notices, company scripts/AI news, many disasters
and advice events, and NewGRF callbacks. No stories are scheduled or
fabricated to compensate for those gaps.

Native presentation intentionally uses a non-modal HUD, static summary
rather than a scrolling strip, and a newspaper form held open for manual
reading. This pass does not reconstruct OpenTTD's mini-viewport, sprites,
company portraits, original news sounds or slide animation.

Run:

- `python3 tests/news_rc1.py /path/to/OpenTTD-16.0-RC1` compiles the unedited
  selection, last-message and retention functions and compares 240 cases.
- `lua5.1 tests/campaign_transport_commands.lua` observes real paid train,
  ship and plane arrivals, checks the journal across packed checkpoint
  reload, and tests the exact public sale date of a stock bus.
- `lua5.1 tests/campaign_news_road.lua` drives the regular motion controller
  to two road stops, verifies one-shot announcements, reference removal,
  private visibility and the hard history limit.
- `bash tests/campaign_news_native.sh` clicks through history and paper in
  a real Linux Luanti client and confirms the non-modal bulletin expires.
  It needs a graphical test environment with Xvfb, xdotool, ImageMagick
  and Tesseract. Android hardware was not tested.
