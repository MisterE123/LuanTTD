#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
server=${1:-luantiserver}
[[ "$server" != */* ]] || server=$(realpath "$server")
port=${2:-39421}
tmp=$(mktemp -d "${TMPDIR:-/tmp}/luanttd-town-growth.XXXXXX")
trap 'rm -rf -- "$tmp"' EXIT
game="$tmp/games/luanttd"
mkdir -p "$game/mods" "$tmp/home" "$tmp/world" "$tmp/default"
cp game.conf settingtypes.txt "$game/"
cp -r mods/luanttd_core "$game/mods/"
# Test only Luanti source and shipped art, not Git or development mods.
cp tests/town_growth_live_fixture.lua "$game/mods/luanttd_core/"
printf '\n' >> "$game/mods/luanttd_core/init.lua"
cat tests/town_growth_sqlite_append.lua >> "$game/mods/luanttd_core/init.lua"
for world in world default; do
cp tests/qa_layout.lua "$game/mods/luanttd_core/qa_layout.lua"
cp tests/coastal_corridor_fixture.lua "$game/mods/luanttd_core/qa_coastal_corridor.lua"
  printf 'gameid = luanttd\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' > "$tmp/$world/world.mt"
done
export HOME="$tmp/home" LUANTI_GAME_PATH="$tmp/games" MINETEST_GAME_PATH="$tmp/games"
for phase in DEFAULT SAVE RESTORE; do
  world=world; setting=""
  case "$phase" in
    DEFAULT) world=default; setting='bayline_stock_town_growth = false' ;;
    SAVE) setting='bayline_stock_town_growth = true' ;;
    RESTORE) setting='bayline_stock_town_growth = false' ;;
  esac
  printf 'port = %s\nserver_announce = false\nbind_address = 127.0.0.1\nprometheus_listener_address = 127.0.0.1:%s\nbayline_seed = 1751\nluanttd_qa_coastal_layout = true\nbayline_growth_fixture = %s\n%s\n' "$port" "$port" "$phase" "$setting" > "$tmp/server.conf"
  if ! timeout 35 "$server" --config "$tmp/server.conf" --world "$tmp/$world" --gameid luanttd --logfile '' > "$tmp/$phase.log" 2>&1; then
    cat "$tmp/$phase.log"; exit 1
  fi
  grep "TOWN GROWTH SQLITE $phase" "$tmp/$phase.log" || { cat "$tmp/$phase.log"; exit 1; }
  if grep -E 'ERROR\[' "$tmp/$phase.log"; then exit 1; fi
  [[ -s "$tmp/$world/mod_storage.sqlite" ]]
done
