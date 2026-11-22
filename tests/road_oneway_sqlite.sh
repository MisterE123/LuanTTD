#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
server="${1:-luantiserver}"
if [[ "$server" == */* ]]; then server=$(realpath "$server"); fi
port="${2:-39290}"
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
game="$tmp/games/onewayprobe"
mod="$game/mods/onewayprobe"
mkdir -p "$mod/openttd" "$tmp/world" "$tmp/home"
printf 'title = One-way traffic SQLite probe\n' > "$game/game.conf"
printf 'name = onewayprobe\n' > "$mod/mod.conf"
cp mods/luanttd_core/*.lua "$mod/"
cp mods/luanttd_core/openttd/*.lua "$mod/openttd/"
cp tests/road_oneway_live_fixture.lua tests/road_overtake_fixture.lua "$mod/"
cp tests/road_oneway_sqlite.lua "$mod/init.lua"
printf 'gameid = onewayprobe\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' > "$tmp/world/world.mt"
export HOME="$tmp/home" LUANTI_GAME_PATH="$tmp/games" MINETEST_GAME_PATH="$tmp/games"
for phase in SAVE RESTORE; do
  write=false
  if [[ "$phase" == SAVE ]]; then write=true; fi
  printf 'port = %s\nserver_announce = false\nbind_address = 127.0.0.1\nluanttd_oneway_init = %s\n' "$port" "$write" > "$tmp/server.conf"
  if ! timeout 25 "$server" --config "$tmp/server.conf" --world "$tmp/world" --gameid onewayprobe --logfile '' > "$tmp/$phase.log" 2>&1; then
    cat "$tmp/$phase.log";exit 1
  fi
  grep "ONEWAY SQLITE $phase" "$tmp/$phase.log" || { cat "$tmp/$phase.log";exit 1; }
  if grep -E 'ERROR\[' "$tmp/$phase.log"; then exit 1; fi
  [[ -s "$tmp/world/mod_storage.sqlite" ]]
done
