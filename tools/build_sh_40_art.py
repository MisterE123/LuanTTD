#!/usr/bin/env python3
"""Stock SH '40': original Class 87-based variant of the shared image 20 body."""
import os
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_sh_30_art as base

# OpenTTD gives the two heads the same silhouette/sprite. The documented
# launch Rail Blue and full yellow ends permit identifying the two natively
# without changing wheelbase, loading gauge, couplers or pantograph geometry.
PALETTE = dict(base.PAL, **{
    "Electric enamel blue": "326b98",
    "Blue sunward edge": "518eb6",
    "Blue shadow coachwork": "274761",
    "Cab lower vent blue": "325c7d",
    "Grey blue lower band": "7d8b91",
    "Ochron yellow warning apron": "e8ba42",
    "Yellow shoulder highlight": "f0c759",
    "Cream machine numerals": "f6eac5",
})

# A purpose-drawn geometric badge, not sampled lettering or stock pixels.
GLYPHS = (
    ("111", "100", "111", "001", "111"),  # S
    ("101", "101", "111", "101", "101"),  # H
    ("101", "101", "111", "001", "001"),  # 4
    ("111", "101", "101", "101", "111"),  # 0
)
OMITTED = (
    "Period rounded lower cab center company plate",
    "Original narrow cream fleet plate characters",
    "Inset contrasting small original SH30 side number plate",
    "Original cream miniature square AL6 stencil strokes",
)


def body(m):
    base.locomotive_shell(m)
    base.cab(m)
    base.drive_and_vents(m)
    for key in OMITTED:
        # Keep flush uninterrupted Class 87 end sheet: unlike its predecessor,
        # this class had no cab-end route-indicator box. Vehicle ID is on sides.
        for mapping in (m.parts, m.vertices, m.lookup):
            del mapping[key]
    for side in (-1, 1):
        base.B(m, "Original raised SH40 fleet identity panel on each side",
               "Readably black headcode", side*.222, 0, .012, .107, .272, .314, .003)
        p = .00575
        for i, (letter, glyph) in enumerate(zip("SH40", GLYPHS)):
            for r, row in enumerate(glyph):
                c = 0
                while c < len(row):
                    if row[c] == "0":
                        c += 1
                        continue
                    end = c + 1
                    while end < len(row) and row[end] == "1":
                        end += 1
                    # Reverse horizontal array direction on opposite sides,
                    # so lettering reads SH40 from either external view.
                    runs_mid = (c+end-1)/2
                    z = side*(i*4+runs_mid-7)*p
                    h = .293+(2-r)*p
                    base.B(m, f"Original raised SH40 badge letter {letter}",
                           "Cream machine numerals", side*.229, z, .002,
                           (end-c-.05)*p, h-p/2, h+p/2, .00015)
                    c = end


def main():
    base.write_assets(
        name="bl_rail_sh_40", filename="rail_sh_40",
        model_name="SH '40' electric / original Class 87",
        stock="14.1 global engine #24, image20, normal rigid one-part electric.",
        provenance="Original Class 86 body variant; Class 87 history and OpenGFX cue only; art/rail_sh_40.md.",
        credit="# Original stock SH '40' Class 87 · tools/build_sh_40_art.py",
        palette=PALETTE, body=body, review=os.getenv("SH_40_REVIEW"),
    )


if __name__ == "__main__":
    main()
