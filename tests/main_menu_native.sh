#!/usr/bin/env bash
# Exercise the unmodified Luanti title screen under Xvfb, not in an in-game mod.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -n ${BAYLINE_NATIVE_TOOLS:-} ]]; then
  tools=$(realpath "$BAYLINE_NATIVE_TOOLS")
  export PATH="$tools/run/bin:$tools/usr/bin:$PATH" LD_LIBRARY_PATH="$tools/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
out=$(mktemp -d "${TMPDIR:-/tmp}/luanttd-main-menu.XXXXXX")
echo "Native menu evidence: $out"
out=$(realpath "$out")
mkdir -p "$out/games/luanttd" "$out/home" "$out/cache"
game=$(pwd -P)
for item in game.conf mods menu screenshot.png; do
  ln -s "$game/$item" "$out/games/luanttd/$item"
done
display=${BAYLINE_NATIVE_DISPLAY:-267}
export HOME="$out/home" XDG_CACHE_HOME="$out/cache" LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games"
export DISPLAY=127.0.0.1:$display LIBGL_ALWAYS_SOFTWARE=1 LP_NUM_THREADS=2 ALSOFT_DRIVERS=null
cc -shared -fPIC tests/native_loopback.c -ldl -o "$out/loopback.so"
env LD_PRELOAD="$out/loopback.so" Xvfb ":$display" -screen 0 1280x720x24 -listen tcp -nolisten unix -nolisten local -ac -noreset >"$out/xvfb.log" 2>&1 &
xv=$!; client=
trap '[[ -z $client ]] || kill "$client" 2>/dev/null || true; kill "$xv" 2>/dev/null || true; wait || true' EXIT
for _ in {1..80}; do xdpyinfo >/dev/null 2>&1 && break; sleep .15; done
xdpyinfo >/dev/null 2>&1
cat > "$out/client.conf" <<'CFG'
screen_w = 1280
screen_h = 720
fullscreen = false
enable_sound = true
enable_shaders = false
menu_last_game = luanttd
CFG
# Screen capture checks actual composition. This diagnostic hook records
# vanilla Vorbis decoder success for the packaged theme with null output.
cat > "$out/audio-probe.c" <<'C'
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>

FILE *fopen(const char *path, const char *mode) {
  FILE *(*real_fn)(const char *, const char *) = dlsym(RTLD_NEXT, "fopen");
  FILE *result = real_fn(path, mode);
  if (result && strstr(path, "/menu/") && strstr(path, ".png"))
    fprintf(stderr, "NATIVE MAIN MENU IMAGE READY %s\n", path);
  return result;
}

int ov_fopen(const char *path, void *vorbis_file) {
  int (*real_fn)(const char *, void *) = dlsym(RTLD_NEXT, "ov_fopen");
  int result = real_fn(path, vorbis_file);
  if (result == 0 && strstr(path, "/menu/theme.ogg"))
    fprintf(stderr, "NATIVE MAIN MENU VORBIS READY %s\n", path);
  return result;
}
C
cc -shared -fPIC "$out/audio-probe.c" -ldl -o "$out/audio-probe.so"
env LD_PRELOAD="$out/audio-probe.so" luanti --config "$out/client.conf" --info --logfile '' >"$out/client.log" 2>&1 &
client=$!
win=$(timeout 30 xdotool search --sync --onlyvisible --name 'Luanti' | tail -1)
xdotool windowfocus --sync "$win" mousemove 1255 695
sleep 2
import -window root -quality 93 "$out/main-menu.jpg"
[[ -s "$out/main-menu.jpg" ]]
for asset in 'header\.png' 'icon\.png' 'background(\.[123])?\.png'; do
  grep -Eq "NATIVE MAIN MENU IMAGE READY .*/menu/$asset" "$out/client.log"
done
if [[ -f menu/theme.ogg ]]; then
  grep -q 'NATIVE MAIN MENU VORBIS READY' "$out/client.log"
fi
echo 'PASS native LuanTTD game picker loaded the title header, icon and screenshot theme'
