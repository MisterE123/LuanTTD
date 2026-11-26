# Walk collision

The terrain simulation and each stock industry's footprint are unchanged.
Walk uses Luanti's normal player movement against mesh-aligned, fixed
collision boxes in the projected world. The same resulting nodes work on
both locally rendered and worker-streamed tiles; there are no invisible
entities to maintain after a player moves away.

The collider build tool uses the shipped art's actual vertices. Industrial
mesh exports name the building components. It fits connected parts of
solid walls, machinery, columns and load-bearing decks independently,
rather than filling the footprint or boxing the roof and all the pillars
together. Walls have 0.04 node of horizontal clearance, rounded out to
1/128 node; thin or decorative props do not get this clearance. Open
gantries and entrances, including the refinery exchanger aisle and
vehicle depot portals, remain usable. Highly detailed areas use at most
ten industry boxes per rendered part; deep submerged visual piling does
not expand world collision searches. The four sightseeing hangar portal
walls keep their existing separately authored boxes.

The native forest trees use only actual trunk geometry. The five
elevation offsets share the same hull data, shifted by half-node
increments; foliage and boughs do not block movement. The four legacy
forest models use their grounded stems; named, multipart growth-stage
meshes can use up to three boxes to follow the lean. The generator also
recognizes the art pack's 19 more detailed Temperate tree forms whenever
their meshes are present.

Regenerate and verify from the repository root:

    python3 tools/build_walk_colliders.py
    python3 tools/build_walk_colliders.py --check
    lua5.1 tests/walk_collision_art.lua
    LUANTTD_NATIVE_GROUND_FIXTURE=industry_walk bash tests/industry_alternate_native.sh

The native client test moves a pedestrian against a real projected power
station facade, through the clear refinery aisle and into a stock tree
trunk. These are decorative-world movement changes, not changes to
OpenTTD's terrain, industry, construction or cargo rules.

Flat conventional ballast, junctions and eased diagonals use the same
track centreline as the displayed meshes. Inclined rail uses eight shallow
ballast steps aligned to the drivable terrain underneath; their combined
height stays below the ordinary Walk step. Level crossings keep their
low road plates. Walk starts above the selected ballast or crossing rather
than inside it, and actual fences remain physical. The native graphical
fixture checks contact and movement across and along the rail:

    bash tests/rail_walk_native.sh
