# In-world place names

Place names and stop labels follow the local ground and the object's
roof height, including hillside construction. A terrain change moves an
existing label instead of leaving it at the height it had when it first
appeared.

Towns and industries are visible up to 384 Luanti nodes away (192 game
tiles). Stops stay local so they don't flood the view. The simulation
worker sends at most 64 nearby place records, independent of loaded
terrain chunks. This read-only observation doesn't load remote geometry
or change the simulation.

Native tests cover a distant place with no subscribed terrain, rejected
out-of-range coordinates, and a visible in-client label above a ridge
that follows a height change without changing its HUD ID.
