# OpenTTD stock audio

- **OpenSFX 1.0.3:** 73 sounds, including stock reserved/unused slots. Source: [official OpenSFX release tag](https://github.com/OpenTTD/OpenSFX/tree/1.0.3). Edited audio produced by the OpenSFX team and individual authors; the per-sample authors, source titles, editing credits, and original terms are in [opensfx.psfo](../third_party/opensfx/opensfx.psfo). The shipped Vorbis copies are format conversions under [CC BY-SA 3.0 Unported](https://creativecommons.org/licenses/by-sa/3.0/). No commercial Transport Tycoon audio is used.
- **OpenMSX 0.4.2:** the title theme “OpenTTD journey” by -lucas-, and all 30 stock gameplay tracks. Original songs by the [OpenMSX authors](https://github.com/OpenTTD/OpenMSX/tree/0.4.2), under GNU GPL version 2. The exact MIDI corresponding sources are in [third_party/openmsx](../third_party/openmsx), with [individual credits and playlist order](../third_party/openmsx/themes.list) and the [full GPLv2 license](../third_party/openmsx/LICENSE.txt).
- The MIDI tracks use FluidSynth and the **TimGM6mb** instrument set by Tim Brechbill and David Bolton (GPLv2). The instrument source is the unmodified Debian `timgm6mb-soundfont` package, with [copyright and upstream source](../third_party/openmsx/TimGM6mb-debian-copyright.txt). The matching [original SoundFont source](https://github.com/musescore/musescore-old/commit/90c33ef9d87b3f5ff92efd3b07d89eb455fb1fef) remains available from the authors. The instrument data itself is not used by Luanti at run time.
- [OpenTTD 16.0-RC1 code](https://github.com/OpenTTD/OpenTTD/tree/16.0-RC1) is the source for the sound slot map, relative gains, stock vehicle sound assignments, and per-genre music program. Those Lua translations are GPLv2.

## Reproduce the game assets

The GitHub build verifies and renders the audio before committing compiled
assets to the game. The repository download includes the published media;
no add-on, chat command or optional download is needed.

Use Python 3, FFmpeg with libvorbis, libfluidsynth.so.3 and TimGM6mb. On Debian and Ubuntu: `sudo apt install ffmpeg libfluidsynth3 timgm6mb-soundfont`. Fetch the OpenSFX 1.0.3 source tag (it has the original WAVs, not a proprietary CAT file):

```bash
git clone --depth 1 --branch 1.0.3 https://github.com/OpenTTD/OpenSFX /tmp/luanttd-opensfx
(cd /tmp/luanttd-opensfx/src/wav && sha256sum -c /path/to/LuanTTD/third_party/opensfx/source-sha256.txt)
OMP_NUM_THREADS=2 python3 tools/build_stock_audio.py \
    --sfx /tmp/luanttd-opensfx/src --music third_party/openmsx
python3 tests/stock_audio_media.py
```

The conversions are mono 22.05 kHz for positional effects, stereo 22.05 kHz for gameplay music, and stereo 32 kHz for the title, encoded in Vorbis. The title is played by the Luanti game-selection menu. The stock jukebox uses personal volume, playback, shuffle, old style, modern, and Ezy Street choices. Engine master volume and sound output still apply.

Runtime coverage is distinct from having every source clip: event hooks for content that is not ported, including Toyland-only machines, are not yet present. A handful of LuanTTD-only sounds (such as sightseeing wind) intentionally remain original.
