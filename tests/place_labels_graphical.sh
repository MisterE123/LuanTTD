#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d "${TMPDIR:-/tmp}/luanttd-place-labels-view.XXXXXX")
echo "Evidence: $out"
game="$out/games/luanttd"
mkdir -p "$game" "$out/world" "$out/home"
cp game.conf "$game/"
cp -al mods "$game/"
mod="$game/mods/luanttd_core"
cp tests/qa_layout.lua "$mod/qa_layout.lua"
(cat "$mod/init.lua";printf '\n';cat tests/place_labels_graphical.lua) > "$out/init.lua"
mv "$out/init.lua" "$mod/init.lua"
printf 'gameid = luanttd\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' > "$out/world/world.mt"
printf 'luanttd_qa_plain_layout = true\nscreen_w = 1180\nscreen_h = 760\nenable_sound = false\nviewing_range = 64\n' > "$out/native.conf"
printf 'luanttd_qa_bridge_style = %s\n' "${BAYLINE_TEST_BRIDGE_STYLE:-9}" >> "$out/native.conf"
export HOME="$out/home" XDG_CACHE_HOME="${LUANTTD_NATIVE_MEDIA_CACHE:-$out/cache}" LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games"
export LIBGL_ALWAYS_SOFTWARE=1 LP_NUM_THREADS=1 ALSOFT_DRIVERS=null
python3 tests/cache_luanti_game_media.py "$game" "$XDG_CACHE_HOME" >/dev/null
display=${BAYLINE_NATIVE_DISPLAY:-493}
export DISPLAY="127.0.0.1:$display"
cc -shared -fPIC tests/native_loopback.c -ldl -o "$out/loopback.so"
env LD_PRELOAD="$out/loopback.so" Xvfb ":$display" -screen 0 1180x760x24 -listen tcp -nolisten local -nolisten unix -ac -noreset >"$out/xvfb.log" 2>&1 &
xv=$!; client=
trap '[[ -z "$client" ]] || kill "$client" 2>/dev/null || true; kill "$xv" 2>/dev/null || true;wait 2>/dev/null || true' EXIT
for _ in {1..40}; do xdpyinfo >/dev/null 2>&1 && break; sleep .25; done
xdpyinfo >/dev/null
luanti --world "$out/world" --go --gameid luanttd --config "$out/native.conf" --logfile '' >"$out/client.log" 2>&1 &
client=$!
win=$(timeout 20 xdotool search --onlyvisible --sync --pid "$client" | tail -n 1)
xdotool windowfocus --sync "$win"
for _ in {1..200}; do
  if grep -q PLACE_LABELS_NATIVE_SCENE_READY "$out/client.log"; then break; fi
  kill -0 "$client" 2>/dev/null || break
  sleep .25
done
grep PLACE_LABELS_NATIVE_SCENE_READY "$out/client.log" || { cat "$out/client.log";exit 1; }
sleep 3
import -window root "$out/place-labels.png"
! grep -Ei 'could not load|ERROR\[' "$out/client.log"
