#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -n ${BAYLINE_NATIVE_TOOLS:-} ]]; then
  tools=$(realpath "$BAYLINE_NATIVE_TOOLS")
  export PATH="$tools/run/bin:$tools/usr/bin:$PATH"
  export LD_LIBRARY_PATH="$tools/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
out=$(mktemp -d "${TMPDIR:-/tmp}/luanttd-generated-oil.XXXXXX")
echo "Native generated oil logs: $out"
game="$out/games/luanttd"
mkdir -p "$game" "$out/world" "$out/home" "$out/cache"
cp game.conf "$game"
cp -al mods "$game/" || cp -R mods "$game/"
cp mods/luanttd_core/init.lua "$out/copy-init.lua"
mv "$out/copy-init.lua" "$game/mods/luanttd_core/init.lua"
printf '\n' >> "$game/mods/luanttd_core/init.lua"
cat tests/generated_oil_freight_native.lua >> "$game/mods/luanttd_core/init.lua"
printf 'gameid = luanttd\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' > "$out/world/world.mt"
printf 'port = %s\nserver_announce = false\nbind_address = 127.0.0.1\n' "${BAYLINE_NATIVE_PORT:-42231}" > "$out/native.conf"
export HOME="$out/home" XDG_CACHE_HOME="$out/cache" LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games"
for phase in SAVED PASS; do
  timeout 35s luantiserver --world "$out/world" --config "$out/native.conf" --gameid luanttd --logfile "" >"$out/$phase.log" 2>&1 || {
    tail -45 "$out/$phase.log"; exit 1
  }
  grep "GENERATED_OIL_FREIGHT_${phase}" "$out/$phase.log" || { tail -45 "$out/$phase.log"; exit 1; }
done
