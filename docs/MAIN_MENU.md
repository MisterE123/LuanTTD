# LuanTTD main menu

Select LuanTTD in Luanti's **Start Game** tab. Start Game keeps the
engine's normal world picker, so selecting and creating worlds works as before.
The game icon and header appear with a native LuanTTD screenshot behind it.
When the engine applies the theme (for example on launch or when switching
back to LuanTTD), it chooses one of four backgrounds. This is a choice on
theme load, not an animated slideshow.

| File | Scene |
| --- | --- |
| `menu/background.png` | The street grid and town square on the Temperate coast |
| `menu/background.1.png` | Red-girder rail and road bridges across a river |
| `menu/background.2.png` | An active-world steel mill beside cultivated fields |
| `menu/background.3.png` | A compact town center and its streets |

The original square locomotive icon and LuanTTD wordmark are built by
`tools/build_main_menu_art.py`. The backgrounds are real Linux Luanti
captures from the playable game in cinematic mode, fitted and shaded for menu
legibility. To rebuild, pass four full-frame screenshot paths in the order
above. The same tool also creates the root `screenshot.png` thumbnail seen in
Luanti's installed-content tab.

The menu music uses Luanti's standard `menu/theme.ogg` hook. Main-menu
audio respects the engine's sound/music volume and mute settings.

## Verification

`bash tests/main_menu_native.sh` opens the stock Luanti client under
Xvfb with sound enabled on an OpenAL null output. It captures the real
menu and verifies Vorbis decoding of the themed track when bundled.
