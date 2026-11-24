# In-world place names

Place names and stop labels follow the local ground and the object's
roof height, including hillside construction. A terrain change moves an
existing label instead of leaving it at the height it had when it first
appeared.

Town and industry names extend just past the view distance. With a
64-node view, the cutoff is 70 nodes, measured from the camera rather
than ignoring height. The margin is about 10%, bounded to 4–16 nodes.
Single-player uses Luanti's viewing-range setting, capped by game fog
and map sending distance. A multiplayer server uses its configured
limits: Luanti's server Lua API does not report each remote client's
graphics setting. Stops still stay local.

The simulation worker sends at most 64 eligible places. Fetching names
doesn't load remote geometry or change simulation state.

Native tests cover a distant place with no subscribed terrain, a
shorter cutoff excluding that same place, and a label 69.5 nodes away
in a 64-node client view. The ridge label still moves after a height
change without changing its HUD ID.
