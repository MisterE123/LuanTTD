#!/usr/bin/env bash
# Isolated graphical test of the native HUD, history, paper and close controls.
# Requires Luanti/Luantiserver, Xvfb, xdotool, ImageMagick import and tesseract.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -n ${BAYLINE_NATIVE_TOOLS:-} ]]; then
  t=$(realpath "$BAYLINE_NATIVE_TOOLS")
  export PATH="$t/run/bin:$t/usr/bin:$PATH"
  export LD_LIBRARY_PATH="$t/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
out=$(mktemp -d "${TMPDIR:-/tmp}/luanttd-newspaper.XXXXXX")
echo "Native newspaper evidence: $out"
game="$out/games/newstest"
mod="$game/mods/luanttd_core"
mkdir -p "$mod" "$out/world" "$out/home" "$out/cache"
printf 'title = Newspaper test\nallowed_mapgens = singlenode\n' >"$game/game.conf"
printf 'name = luanttd_core\n' >"$mod/mod.conf"
mkdir -p "$mod/openttd" "$mod/textures"
cp mods/luanttd_core/campaign_news_ui.lua "$mod/"
cp mods/luanttd_core/openttd/news.lua "$mod/openttd/"
cp mods/luanttd_core/textures/bl_newspaper_bulletin.png "$mod/textures/"
cp tests/campaign_news_native.lua "$mod/init.lua"
printf 'gameid = newstest\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' >"$out/world/world.mt"
port=${BAYLINE_NATIVE_PORT:-39215}
printf 'port = %s\nbind_address = 127.0.0.1\nprometheus_listener_address = 127.0.0.1:%s\nmg_name = singlenode\nmax_block_send_distance = 2\nmax_block_generate_distance = 2\n' "$port" "$port" >"$out/server.conf"
printf 'screen_w = 1180\nscreen_h = 760\nfullscreen = false\nenable_sound = false\nfps_max = 30\nviewing_range = 32\n' >"$out/client.conf"
export HOME="$out/home" XDG_CACHE_HOME="$out/cache" LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games"
export LIBGL_ALWAYS_SOFTWARE=1 MESA_SHADER_CACHE_DISABLE=1 ALSOFT_DRIVERS=null
display=${BAYLINE_NATIVE_DISPLAY:-375}
export DISPLAY="127.0.0.1:$display"
cc -shared -fPIC tests/native_loopback.c -ldl -o "$out/loopback.so"
env LD_PRELOAD="$out/loopback.so" Xvfb ":$display" -screen 0 1180x760x24 -listen tcp -nolisten local -nolisten unix -ac -noreset >"$out/xvfb.log" 2>&1 &
xv=$!; server= client=
trap '[[ -z "$client" ]] || kill "$client" 2>/dev/null || true; [[ -z "$server" ]] || kill "$server" 2>/dev/null || true; kill "$xv" 2>/dev/null || true; wait 2>/dev/null || true' EXIT
for _ in {1..40}; do xdpyinfo >/dev/null 2>&1 && break; sleep .25; done
xdpyinfo >/dev/null || { cat "$out/xvfb.log"; exit 1; }
luantiserver --world "$out/world" --gameid newstest --config "$out/server.conf" --logfile '' >"$out/server.log" 2>&1 &
server=$!
mark(){ for _ in {1..160}; do grep -q "$1" "$out/server.log" && return; kill -0 "$server" 2>/dev/null || break; sleep .25; done; tail -70 "$out/server.log"; return 1; }
mark 'listening on'
luanti --go --address 127.0.0.1 --port "$port" --name NewsQA --password '' --config "$out/client.conf" --logfile '' >"$out/client.log" 2>&1 &
client=$!
window=$(timeout 18 xdotool search --onlyvisible --sync --pid "$client" | tail -n 1)
xdotool windowfocus --sync "$window"
mark 'NATIVE NEWSPAPER BULLETIN'
sleep 2
xdotool mousemove 65 90
import -window root "$out/bulletin.png"
import -window root -crop '326x103+829+100' -resize 200% "$out/bulletin-detail.png"
tesseract "$out/bulletin-detail.png" "$out/bulletin" --psm 6 2>/dev/null
grep -qi 'Transport Gazette' "$out/bulletin.txt"
grep -qi 'Leopard Bus' "$out/bulletin.txt"
sleep 15
import -window root "$out/after-duration.png"
import -window root -crop '326x103+829+100' -resize 200% "$out/expired.png"
! tesseract "$out/expired.png" stdout --psm 6 2>/dev/null | grep -qi 'Transport Gazette'
xdotool key i
sleep 1
# Screen and formspec scale are fixed above. Assert the server only receives
# these input fields after genuine X11 clicks, then separately OCR the paper.
import -window root "$out/control-desk.png"
xdotool mousemove 590 381 click 1
mark 'NATIVE NEWSPAPER HISTORY'
sleep 1.1
import -window root "$out/history.png"
xdotool mousemove 680 199 click 1
mark 'NATIVE NEWSPAPER ARTICLE'
sleep 1.1
import -window root "$out/article.png"
import -window root -crop '556x180+312+139' -resize 200% "$out/article-panel.png"
tesseract "$out/article-panel.png" "$out/article" --psm 6 2>/dev/null
grep -qi 'TRANSPORT GAZETTE' "$out/article.txt"
grep -qi 'Leopard Bus' "$out/article.txt"
xdotool mousemove 760 607 click 1
mark 'NATIVE NEWSPAPER CLOSED'
! grep -E 'ERROR\[' "$out/client.log" "$out/server.log"
echo 'PASS native newspaper: non-modal bulletin expired, Control Desk history opened, actual paper read and closed'
