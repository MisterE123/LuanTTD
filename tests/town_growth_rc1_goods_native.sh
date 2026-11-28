#!/usr/bin/env bash
# Luanti dedicated worker and a disposable SQLite world, reopened mid-service.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -n ${BAYLINE_NATIVE_TOOLS:-} ]]; then
  tools=$(realpath "$BAYLINE_NATIVE_TOOLS")
  export PATH="$tools/run/bin:$tools/usr/bin:$PATH"
  export LD_LIBRARY_PATH="$tools/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
out=$(mktemp -d "${TMPDIR:-/tmp}/luanttd-ordinary-goods.XXXXXX")
echo "Ordinary goods worker evidence: $out"
game="$out/games/luanttd"
mkdir -p "$game" "$out/world" "$out/home"
cp game.conf "$game/"
cp -al mods "$game/" 2>/dev/null || cp -R mods "$game/"
cp tests/town_growth_rc1_goods_native.lua "$out/init.lua"
mv "$out/init.lua" "$game/mods/luanttd_core/init.lua"
cp tests/fixtures/rc1-active-town-goods-year.lua "$game/mods/luanttd_core/qa_native_goods.lua"
printf 'gameid = luanttd\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' > "$out/world/world.mt"
export HOME="$out/home" LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games"
port=${BAYLINE_NATIVE_PORT:-40067}
printf 'port = %s\nserver_announce = false\nbind_address = 127.0.0.1\n' "$port" > "$out/server.conf"
for expected in SAVED PASS; do
  timeout 240 luantiserver --world "$out/world" --config "$out/server.conf" --gameid luanttd --logfile '' \
    > "$out/$expected.log" 2>&1 || { tail -80 "$out/$expected.log";exit 1; }
  grep "ORDINARY_GOODS_$expected" "$out/$expected.log"
done
