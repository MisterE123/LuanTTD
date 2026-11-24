#!/usr/bin/env python3
"""Reject actual airframes intersecting any City Airport mesh along its FTA."""
from pathlib import Path
from sys import argv
from types import SimpleNamespace
from darwin_100_art import CORE, city_ground_art

p=CORE/"models"
data=SimpleNamespace(city_prefix="bl_city_airport_",city_model_dir=p,city_ground_poses=Path(argv[1]))
for name in ("airtaxi_a34_1000","dinger_1000"):
    print(name,flush=True)
    city_ground_art(data,None,p/f"bl_stock_{name}.obj")
