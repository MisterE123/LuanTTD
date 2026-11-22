#!/usr/bin/env bash
# Real default generated world, vanilla configuration, two server launches.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -n ${BAYLINE_NATIVE_TOOLS:-} ]]; then
  tools=$(realpath "$BAYLINE_NATIVE_TOOLS")
  export PATH="$tools/run/bin:$tools/usr/bin:$PATH"
  export LD_LIBRARY_PATH="$tools/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
out=$(mktemp -d "${TMPDIR:-/tmp}/luanttd-default-tram.XXXXXX")
echo "Native default tram evidence: $out"
game="$out/games/bayline"
mkdir -p "$game" "$out/world" "$out/home" "$out/cache"
cp game.conf "$game/"
cp -a -l mods "$game/" 2>/dev/null || { mkdir -p "$game/mods"; cp -a mods/. "$game/mods/"; }
if [[ -n ${BAYLINE_NATIVE_ASSET_MOD:-} ]]; then
  # Child worktree can be sparse. Preserve its new icons and link the
  # unchanged game assets; never write into a linked file.
  for folder in models textures; do
    mkdir -p "$game/mods/bayline/$folder"
    for file in "$BAYLINE_NATIVE_ASSET_MOD/$folder/"*; do
      if [[ ! -e "$game/mods/bayline/$folder/${file##*/}" ]]; then
        cp -al "$file" "$game/mods/bayline/$folder/" 2>/dev/null || cp -a "$file" "$game/mods/bayline/$folder/"
      fi
    done
  done
fi
cp mods/bayline/init.lua "$out/init.lua"
mv -f "$out/init.lua" "$game/mods/bayline/init.lua"
printf '\n' >> "$game/mods/bayline/init.lua"
cat tests/default_tram_native.lua >> "$game/mods/bayline/init.lua"
printf 'gameid = bayline\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' > "$out/world/world.mt"
printf 'port = %s\nbind_address = 127.0.0.1\nserver_announce = false\n' "${BAYLINE_NATIVE_PORT:-39759}" > "$out/default.conf"
export HOME="$out/home" XDG_CACHE_HOME="$out/cache"
export LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games"
run() {
  local stage=$1 message=$2
  if ! timeout 30 luantiserver --world "$out/world" --config "$out/default.conf" --gameid bayline --logfile "" > "$out/$stage.log" 2>&1 ||
     ! grep -q "$message" "$out/$stage.log"; then cat "$out/$stage.log"; exit 1; fi
  grep "$message" "$out/$stage.log"
}
run before DEFAULT_TRAM_NATIVE_SAVED
grep DEFAULT_RAIL_STATION_DIRECT_PASS "$out/before.log"
run after DEFAULT_TRAM_NATIVE_PASS
