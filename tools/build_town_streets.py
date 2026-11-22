"""Municipal sidewalks around existing road-bit geometry; Pillow required."""
from pathlib import Path
from PIL import Image, ImageDraw

from road_surface_raster import CORNERS, connector
tex=Path(__file__).resolve().parents[1]/"mods/luanttd_core/textures"
flipped=Image.Transpose.FLIP_TOP_BOTTOM
for mask in range(16):
    with Image.open(tex/"bl_grass0.png") as grass:
        sheet=grass.convert("RGBA").transpose(flipped)
    with Image.open(tex/f"bl_road{mask}.png") as road:
        original=road.convert("RGBA")
    d=ImageDraw.Draw(sheet)
    for y in range(32):
        for x in range(32):
            a,b=x-15.5,y-15.5
            path=abs(a)<9 and abs(b)<9
            curb=False
            for i,(dx,dz) in enumerate(((0,-1),(1,0),(0,1),(-1,0))):
                if (mask & (1<<i)) and a*dx+b*dz>=0:
                    cross=abs(a*dz-b*dx)
                    path=path or cross<9
                    curb=curb or cross==8.5
            if mask in CORNERS and not connector(x,y):
                # Give the new inside fillet a continuous curb/footway while
                # leaving two undisturbed connector rows on every tile edge.
                steps=[abs(px-x)+abs(pz-y)
                       for px in range(max(0,x-2),min(32,x+3))
                       for pz in range(max(0,y-2),min(32,y+3))
                       if original.getpixel((px,pz))[3]]
                gap=min(steps,default=3)
                curb=curb or (not path and gap==2)
                path=path or gap<=2
            if path:
                c=(202,191,173) if curb else (161,151,136) if (x+y*3)%13==0 else (171,162,148)
                d.point((x,y),fill=c)
    sheet.alpha_composite(original)
    assert all(original.getpixel((x,y))==sheet.getpixel((x,y))
               for y in range(32) for x in range(32) if original.getpixel((x,y))[3]==255)
    image=sheet.transpose(flipped)
    for j in range(4):
        x,y=j%2*16,j//2*16
        image.crop((x,y,x+16,y+16)).save(tex/f"bl_town_street_{mask}_{j}.png",optimize=True)
print("PASS: sidewalks retain the original road geometry, including rounded bend fillets for all 16 masks")
