#!/usr/bin/env python3
"""Make a self-contained Luanti game archive, with no prior preview required."""
import argparse
from hashlib import file_digest
import io
import lzma
from pathlib import Path
import subprocess
import tarfile

ALLOW = {
    "LICENSE", "NOTICE.md", "README.md", "PORTING.md", "COPYING.OpenTTD.md", "LEVEL_CROSSING_WORLD.md", "STOCK_AREA_DEMOLITION.md",
    "docs/build-in-3d.md", "docs/generated-campaign.md", "docs/hotbar-layout.md",
    "docs/electric-rail.md", "docs/autorail.md", "docs/coastal-landscaping.md",
    "docs/day-night.md", "docs/rail-waypoints.md", "docs/harbor-buoys.md", "docs/native-qa-2026-11-22.md",
    "game.conf", "settingtypes.txt",
}
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument("archive",type=Path)
parser.add_argument("start_here",type=Path)
parser.add_argument("--ref",default="HEAD")
args=parser.parse_args()
repo=Path(__file__).resolve().parents[1]
archive=args.archive.resolve()
expected={}
with subprocess.Popen(["git","archive","--prefix=bayline/",args.ref],cwd=repo,stdout=subprocess.PIPE) as git:
    with tarfile.open(fileobj=git.stdout,mode="r|") as src, lzma.open(archive,"wb",preset=6) as compressed, tarfile.open(fileobj=compressed,mode="w|") as dst:
        guide=args.start_here.read_bytes()
        member=tarfile.TarInfo("START-HERE.txt");member.size=len(guide);member.mode=0o644
        dst.addfile(member,io.BytesIO(guide))
        for item in src:
            relative=item.name.removeprefix("bayline/")
            if not item.isfile() or not (relative.startswith("mods/") or relative in ALLOW): continue
            with src.extractfile(item) as stream:
                data=stream.read()
            dst.addfile(item,io.BytesIO(data))
            expected[item.name]=file_digest(io.BytesIO(data),"sha256").digest()
    assert git.wait()==0
with tarfile.open(archive,"r:xz") as f:
    assert set(f.getnames())==set(expected)|{"START-HERE.txt"}
    for name,h in expected.items():
        with f.extractfile(name) as sf:
            assert file_digest(sf,"sha256").digest()==h,name
with archive.open("rb") as f: sha=file_digest(f,"sha256").hexdigest()
print(f"{archive.name}: {len(expected):,} files checked; {archive.stat().st_size:,} bytes; SHA-256 {sha}")
