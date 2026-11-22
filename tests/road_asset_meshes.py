"""Check exported static mesh units, footprint and road clearance."""
from pathlib import Path
from math import isclose

assets = Path(__file__).resolve().parents[1] / "mods/bayline/models"

def model(stem):
    rows = (assets / f"bl_{stem}.obj").read_text().splitlines()
    # Luanti's mesh node uses node units; OBJ import flips X.
    points = [tuple(map(float,s.split()[1:])) for s in rows if s.startswith("v ")]
    native = [(-x,y,z) for x,y,z in points]
    assert len(native)>250
    assert all(len(s.split())==4 for s in rows if s.startswith("f "))
    assert isclose(min(v[1] for v in native), -.5, abs_tol=.001)
    assert max(v[1] for v in native) < .6
    return native

for i in range(4):
    points = model(f"road_depot_{i}")
    assert all(-.5 <= x <= 1.5 and -.5 <= z <= 1.5 for x,_,z in points)

for name, axis, high in [("bus_shelter",2,True),("bus_shelter_quarter",0,False),
                         ("bus_shelter_corner",2,True),("bus_shelter_corner",0,True)]:
    points = model(name)
    assert all(-.51 <= x <= 1.51 and -.51 <= z <= 1.51 for x,_,z in points)
    edge = .5+(.3125 if high else -.3125)
    assert all((v[axis]>=edge if high else v[axis]<=edge) for v in points), f"{name} clips the asphalt on axis {axis}"
print("PASS: 7 meshes at native node scale; station assets clear the road")
