#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
from pathlib import Path
from PIL import Image, ImageDraw
a=Image.new("RGBA",(128,128))
d=ImageDraw.Draw(a)
d.rounded_rectangle((4,4,123,123),radius=20,fill="#202840",outline="#97add5",width=5)
d.polygon([(18,99),(70,27),(111,29),(65,105)],fill="#0e1931")
d.line([(18,99),(69,25)],fill="#b0eef0",width=11)
d.line([(64,104),(113,28)],fill="#b0eef0",width=11)
d.polygon([(33,92),(45,76),(65,77),(53,95)],fill="#edaf5d")
d.polygon([(48,69),(60,54),(80,55),(68,72)],fill="#edaf5d")
d.polygon([(64,46),(74,33),(96,34),(86,49)],fill="#edaf5d")
a.resize((32,32),Image.Resampling.LANCZOS).save(Path(__file__).resolve().parents[1]/"mods/luanttd_core/textures/bl_dispatch_gauge_maglev.png")
