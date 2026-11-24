#!/usr/bin/env python3
"""Build the native Luanti title theme from four actual LuanTTD captures.

Usage: python3 tools/build_main_menu_art.py town.png railway.png industry.png city.png
Inputs are borderless in-game captures taken in cinematic mode. The art in
this tool is original. Pillow + the standard DejaVu fonts are required.
"""
from argparse import ArgumentParser
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageOps

ROOT = Path(__file__).resolve().parents[1]
BLUE, DEEP, DARK = "#183d4b", "#102634", "#091923"
MINT, CREAM, GOLD = "#6ac7b4", "#f5edce", "#f7c276"

def icon(size):
    img = Image.new("RGBA", (size, size))
    d = ImageDraw.Draw(img)
    def coord(vals):
        return tuple(round(v * size / 128) for v in vals)
    def rect(box, radius, color, outline=None, width=1):
        d.rounded_rectangle(coord(box), radius=round(radius*size/128), fill=color, outline=outline, width=round(width*size/128))
    def poly(points, color):
        d.polygon([coord(p) for p in points], fill=color)
    rect((5, 5, 122, 122), 23, DARK)
    rect((5, 3, 122, 119), 23, BLUE, MINT, 3)
    # The rails and ties establish perspective; a front-on locomotive
    # remains legible even on the square button at narrow mobile widths.
    poly([(53,85),(75,85),(100,113),(28,113)], DEEP)
    poly([(46,86),(53,86),(36,112),(25,112)], GOLD)
    poly([(75,86),(82,86),(103,112),(92,112)], GOLD)
    d.line(coord((33,105,95,105)),fill=MINT,width=round(4*size/128))
    rect((51,20,76,29),4,GOLD)
    rect((55,24,72,43),2,GOLD)
    rect((37,34,90,86),10,MINT)
    rect((42,40,85,64),7,DEEP)
    rect((47,45,60,58),3,CREAM)
    rect((67,45,80,58),3,CREAM)
    d.ellipse(coord((58,66,70,78)),fill=GOLD)
    rect((32,81,95,92),4,GOLD)
    rect((46,90,82,98),3,DARK)
    return img

def header():
    img = Image.new("RGBA", (768, 156))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((34,24,746,147), radius=28, fill=(3,12,21,166))
    d.rounded_rectangle((30,17,742,137), radius=24, fill=(13,32,42,245), outline=MINT, width=3)
    img.alpha_composite(icon(104), (52,25))
    word = ImageFont.truetype("DejaVuSans-Bold.ttf", 60)
    sub = ImageFont.truetype("DejaVuSans.ttf", 17)
    x, y = 181, 70
    d.text((x,y),"Luan",font=word,fill=CREAM,anchor="lm",stroke_width=0)
    d.text((x+d.textlength("Luan",font=word),y),"TTD",font=word,fill=GOLD,anchor="lm",stroke_width=0)
    d.text((x+3,116),"T R A N S P O R T   T Y C O O N   I N   3 D",font=sub,fill=MINT,anchor="lm")
    # Fine track motif repeats the icon rails without stealing focus.
    for y in (64,78):
        d.line((577,y,700,y), fill=(72,115,119,255), width=2)
    for x in range(585,700,18):
        d.line((x,60,x-8,83), fill=(54,91,96,255), width=3)
    return img

def background(frame):
    img = ImageOps.fit(frame, (1280,720), Image.Resampling.LANCZOS)
    shade = Image.new("RGB", img.size, (9,24,34))
    fade = Image.new("L", img.size)
    # Keep the actual scenery recognizable around the world picker,
    # while protecting the pale Luanti tab labels at the edge of the frame.
    px = fade.load()
    for y in range(img.height):
        for x in range(img.width):
            n = ((x/1279-.5)**2*2+(y/719-.47)**2*1.5)*.22
            px[x,y] = round(255*(.09+n))
    return Image.composite(shade, img, fade).quantize(colors=256)

def write(img, path):
    tmp = path.with_suffix(".next.png")
    img.save(tmp, format="PNG", optimize=True)
    tmp.replace(path)

def main():
    p = ArgumentParser(description=__doc__)
    p.add_argument("captures", nargs=4, type=Path)
    args = p.parse_args()
    menu = ROOT/"menu"
    menu.mkdir(exist_ok=True)
    for i,path in enumerate(args.captures):
        frame = Image.open(path).convert("RGB")
        suffix = f".{i}" if i else ""
        write(background(frame), menu/f"background{suffix}.png")
        if not i:
            write(ImageOps.fit(frame,(640,360),Image.Resampling.LANCZOS).quantize(colors=256),ROOT/"screenshot.png")
    write(icon(384).resize((128,128), Image.Resampling.LANCZOS),menu/"icon.png")
    write(header(),menu/"header.png")

if __name__ == "__main__":
    main()
