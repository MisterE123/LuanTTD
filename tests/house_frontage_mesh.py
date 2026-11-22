"""Check the shipped porch/door models stay on the same parcel after rotation."""
from pathlib import Path

root = Path(__file__).resolve().parents[1] / "mods/bayline/models"
names = (
    *(f"scenery_house_{n}" for n in range(4)),
    "town_shop",
    *(f"house_build_stage_{n}" for n in range(3)),
)
offsets = ((0, 0), (0, 1), (1, 1), (1, 0))

def rotate(x, z, n):
    for _ in range(n):
        x, z = z, -x
    return x, z


for name in names:
    vertices = []
    doors = []
    group = ""
    for line in (root / f"bl_{name}.obj").read_text().splitlines():
        a = line.split()
        if not a:
            continue
        if a[0] == "o":
            group = a[1].lower()
        elif a[0] == "v":
            x,y,z = map(float,a[1:])
            vertices.append((-x,y,z))  # Luanti reflects the OBJ X axis.
            if "temporary_footpath" in group:
                doors.append(z)
    assert len(vertices) > 400, name
    if "stage" in name:
        assert doors and max(doors) < .10, "stock worksite entry uses -Z"
    else:
        # Joined Blender export has one object. Its paving reaches close
        # to +Z, much farther than the opposite rear garden edge.
        assert max(z for _,_,z in vertices) > 1.4
    for n,(dx,dz) in enumerate(offsets):
        x,z=rotate(.5,.5,n)
        assert (x+dx,z+dz)==(.5,.5), (name,n,"parcel center")
        for x,y,z in vertices:
            u,v=rotate(x,z,n)
            assert -.5001 <= u+dx <= 1.5001 and -.5001 <= v+dz <= 1.5001, (name,n,u,v)
print("PASS: all 8 shipped directional buildings fit the same 2×2 parcel at every facing")
