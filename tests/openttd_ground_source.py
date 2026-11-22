#!/usr/bin/env python3
"""Differential test against unmodified OpenTTD 14.1 water classifier bodies."""
from hashlib import sha256
from pathlib import Path
import argparse
import re
import subprocess
import sys
import tempfile

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO/"tools"))
from openttd_save_ground import water_kind, SaveError


def extract(text, name):
    start = re.search(name,text,re.MULTILINE).start()
    i = text.index("{",start)
    n = 1
    while n:
        i += 1
        n += (text[i]=="{")-(text[i]=="}")
    return text[start:i+1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    args = parser.parse_args()
    source = args.source/"src"/"water_map.h"
    if not source.is_file():
        source = args.source/"water_map.h"
    raw = source.read_bytes()
    assert sha256(raw).hexdigest()=="1b3cf332d0a0f61957c109710e68bc0869dca2038c8c0d05aec39b44f6e422a8"
    header = raw.decode()
    source = """
#include <cassert>
#include <cstdio>
#include <cstdlib>
using byte = unsigned char;
enum TileType {MP_TREES=4, MP_STATION=5, MP_WATER=6, MP_INDUSTRY=8, MP_OBJECT=10};
struct Tile {
  int type, a, b;
  int m1() const {return a;}
  int m5() const {return b;}
};
bool IsTileType(Tile t, TileType type) {return t.type==type;}
int GB(int value,int begin,int count) {return (value>>begin)&((1<<count)-1);}
bool HasBit(int value,int pos) {return (value & (1<<pos)) != 0;}
#define NOT_REACHED() std::abort()
"""
    for pattern in ("^enum WaterTileTypeBitLayout \\{", "^enum WaterTileType \\{", "^enum WaterClass : byte \\{"):
        source += extract(header,pattern)+";\n"
    for name in ("GetWaterTileType", "HasTileWaterClass", "GetWaterClass", "IsCoast", "IsCoastTile"):
        source += extract(header,rf"^inline \w+ {name}\(Tile t\)")+"\n"
    source += """
int main(){
  for(int cls = 0; cls <= 10; cls++) for(int a = 0; a < 256; a++) for(int b = 0; b < 256; b++) {
    Tile t{cls,a,b};
    if(cls==6 && b/16!=0 && b/16!=1 && b/16!=8) {
      std::putchar(255); // Outside the stock classifier's valid domain.
    } else if(IsCoastTile(t)) {
      std::putchar(cls==4 ? 3 : 2);
    } else if(cls==6) {
      switch (GetWaterTileType(t)) {
        case WATER_TILE_CLEAR: std::putchar(1); break;
        case WATER_TILE_LOCK: std::putchar(4); break;
        case WATER_TILE_DEPOT: std::putchar(5); break;
        default: std::abort();
      }
    } else std::putchar(0);
  }
}
"""
    with tempfile.TemporaryDirectory(prefix="luanttd-stock-ground-") as name:
        temp = Path(name)
        cpp = temp/"source.cc"
        cpp.write_text(source)
        binary = temp/"source"
        subprocess.run(["c++","-O2",cpp,"-o",binary], check=True)
        oracle = iter(subprocess.check_output([binary]))
        for cls in range(11):
            for a in range(256):
                for b in range(256):
                    expected = next(oracle)
                    try:
                        actual = water_kind(cls,a,b)
                    except SaveError:
                        actual = 255
                    assert expected == actual,(cls,a,b,expected,actual)
        assert next(oracle,None) is None
    print("PASS: 720,896 pinned stock ground classifier byte combinations")


if __name__=="__main__":
    main()
