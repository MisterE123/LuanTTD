# LuanTTD

An OpenTTD port for Luanti, played in a native 3D world. The target is
[OpenTTD 16.0-RC1](https://github.com/OpenTTD/OpenTTD/releases/tag/16.0-RC1).
The [State of the Port](docs/PORTING.md) tracks what works, which behaviors
still use the 14.1 reference, and what is missing.

## Install and play

1. Install Luanti 5.10 or newer. No other game or mods are needed.
2. On GitHub choose **Code → Download ZIP** and extract it, or clone this
   repository. Put the folder containing `game.conf` and `mods/` under
   Luanti's user `games` folder and name it **`luanttd`**. Use **Open User
   Data Directory** in Luanti to find it. Typical locations are
   `~/.minetest/games/` on Linux and `%APPDATA%\Luanti\games` on Windows
   (older installations may use `%APPDATA%\Minetest\games`).
3. Select **LuanTTD** and create a fresh world. Choose **Generate a world**
   or a scenario, then **Save and return** and **Play** the same world again.
   Construction and vehicle features are available without editing settings.
   Transport still needs the right infrastructure, cargo and available vehicles.

## First routes

- **Roadworks (2):** build a road, two bus stops near houses, and a depot.
  Inspect the depot to buy a bus, then open its orders, select both stops
  and start it. For trucks, use Road Freight and match pickup and delivery
  to the cargo the industries produce and accept.
- **Rail Construction (8):** lay track between two stations, add a depot
  and inspect it to buy a train. Use its Orders card to pick the platforms.
  See the [first train recipe](docs/native-qa-2026-11-22.md#first-train-recipe).
- **Sea & Air (0):** build docks, a ship depot and a connected channel for a
  ferry, or two flat country airfields and a plane for a passenger route.
- **Scenarios:** try **Farm and Factory** for grain and livestock, **Oil and
  Refinery** for oil, or **South Coast Coal** for a coal shipping route with
  a tested channel. Generated maps place industries based on density and
  terrain; not every map contains every cargo chain.

Fly with **WASD** and the mouse, rise with **Space**, descend with **Shift**,
and hold **E** to move faster. The active hotbar shows the available tools.
Left-click to use one. Right-click to cancel a build, finish order selection,
or inspect. Escape closes menus. Open **Transport & World Guide** from Inventory for help in-game.
In **Survey**, the Jump Map displays named towns and lets you jump to an
area or zoom for a closer look. It still accepts exact tile coordinates.
Use [the Survey tools](docs/street-view.md) to explore at street level or
fly from a built airport. Read [the Transport Gazette](docs/newspaper.md)
under **Inventory → Newspaper**. Normal play does not require chat commands.
Choose **Inventory → Tutorials** for guided [road, train, and boat businesses](docs/business-tutorials.md).

## Guides and settings

- [Build in 3D](docs/build-in-3d.md), [hotbar layout](docs/hotbar-layout.md)
  and [Transport & World Guide](docs/workbench-index.md)
- [Generated worlds and first freight route](docs/generated-campaign.md)
- [Farm](docs/FARM_FACTORY_WORLD.md), [Oil](docs/OIL_FREIGHT_WORLD.md),
  [Coal ships](docs/SHIP_COAL_PORT.md), and [Original Terrain Survey](docs/original-terrain-exploration.md)
- [State of the Port](docs/PORTING.md), [test notes](docs/TESTING.md)
  and [release history](docs/CHANGELOG.md)

The game exposes only implemented [OpenTTD options](settingtypes.txt), such as
world generation, starting year, breakdown difficulty and road-vehicle
servicing. Choose the starting year in the world setup screen; it determines
which vehicles are on sale. Choose 1968 for the Hendry 25 and UU 37. Ordinary
Luanti engine settings, such as sound volume and shaders, are still Luanti's.

## Dedicated server

Put the game in the normal Luanti user games directory and run
`luantiserver --gameid luanttd --world /path/to/world`. A dedicated server
generates a fresh temperate map without the local setup screen; the
OpenTTD options in its config supply the generator defaults.

## License

LuanTTD's integrated game code is GPL-2.0-only. See [LICENSE](LICENSE),
[NOTICE](docs/NOTICE.md) and [asset credits](art/README.md).
It includes Lua ports of source logic, not the OpenTTD executable or
commercial graphics. It does not open OpenTTD saves yet.
