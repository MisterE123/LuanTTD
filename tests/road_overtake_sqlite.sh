#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
server="${1:-luantiserver}"
if [[ "$server" == */* ]]; then server=$(realpath "$server"); fi
port="${2:-39289}"
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
game="$tmp/games/overtakeprobe"
mod="$game/mods/overtakeprobe"
mkdir -p "$mod/openttd" "$tmp/world" "$tmp/home"
printf 'title = Road overtaking SQLite probe\n' > "$game/game.conf"
printf 'name = overtakeprobe\n' > "$mod/mod.conf"
cp mods/bayline/*.lua "$mod/"
cp mods/bayline/openttd/*.lua "$mod/openttd/"
cp tests/road_overtake_fixture.lua "$mod/"
cp tests/road_overtake_sqlite.lua "$mod/init.lua"
printf 'gameid = overtakeprobe\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' > "$tmp/world/world.mt"
export HOME="$tmp/home" LUANTI_GAME_PATH="$tmp/games" MINETEST_GAME_PATH="$tmp/games"
for phase in CHECKPOINT RESTORE; do
  write=false
  if [[ "$phase" == CHECKPOINT ]]; then write=true; fi
  printf 'port = %s\nserver_announce = false\nbind_address = 127.0.0.1\nluanttd_overtake_write = %s\n' "$port" "$write" > "$tmp/server.conf"
  if ! timeout 25 "$server" --config "$tmp/server.conf" --world "$tmp/world" --gameid overtakeprobe --logfile '' > "$tmp/$phase.log" 2>&1; then
    cat "$tmp/$phase.log"
    exit 1
  fi
  for kind in stopped moving; do
    grep "OVERTAKE SQLITE $phase $kind" "$tmp/$phase.log" || { cat "$tmp/$phase.log"; exit 1; }
  done
  if grep -E 'ERROR\[' "$tmp/$phase.log"; then exit 1; fi
  [[ -s "$tmp/world/mod_storage.sqlite" ]]
done
