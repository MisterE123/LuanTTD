#!/usr/bin/env python3
"""Compare ordinary company object autoslope with OpenTTD 16.0-RC1."""
from argparse import ArgumentParser
from itertools import product
from pathlib import Path
from subprocess import check_output, run
from tempfile import TemporaryDirectory

from scenery_object_rc1_upstream import extract

p = ArgumentParser(description=__doc__)
p.add_argument("source", type=Path)
p.add_argument("--lua", default="lua5.1")
a = p.parse_args()
src = a.source / "src"
objects = (src / "object_cmd.cpp").read_text()
slopes = (src / "slope_func.h").read_text()
autoslope = (src / "autoslope.h").read_text()
cpp = r"""
#include <iostream>
#include <cstdint>
using TileIndex=int;
using Slope=int;
using DoCommandFlags=int;
constexpr int SLOPE_FLAT=0, SLOPE_STEEP=16;
enum ObjectType { OBJECT_TRANSMITTER, OBJECT_LIGHTHOUSE, OBJECT_STATUE,
                  OBJECT_OWNED_LAND, OBJECT_HQ };
enum class Price { BuildFoundation };
enum class ExpensesType { Construction };
enum class Commands { LandscapeClear };
enum class GameMode { Normal, Editor };
enum ObjectCallbackMask { Autoslope };
constexpr int MAX_COMPANIES=15, OWNER_NONE=16;
constexpr int CBID_OBJECT_AUTOSLOPE=1, CALLBACK_FAILED=65535;
struct CommandCost {
    int cost;
    CommandCost() : cost(0) {}
    explicit CommandCost(int c) : cost(c) {}
    CommandCost(ExpensesType, int c) : cost(c) {}
    bool Succeeded() const { return cost >= 0; }
};
template<Commands> struct Command {
    static CommandCost Do(DoCommandFlags, TileIndex) { return CommandCost(-1); }
};
int _price_dummy=137;
struct Prices { int operator[](Price) const {return _price_dummy;} } _price;
struct {struct {bool autoslope;} construction;} _settings_game;
GameMode _game_mode=GameMode::Normal;
int _current_company=0;
bool owns;
int base, shape, kind;
struct ObjectSpec {
    struct Mask { bool Test(ObjectCallbackMask) const {return false;} } callback_mask;
    struct Prop { int grffile; } grf_prop;
    bool IsEnabled() const {return true;}
    static const ObjectSpec *Get(ObjectType) {static ObjectSpec s{}; return &s;}
};
struct Object { static int GetByTile(TileIndex){return 0;} };
uint16_t GetObjectCallback(int,int,int,const ObjectSpec*,int,int) {return CALLBACK_FAILED;}
bool ConvertBooleanCallback(int,int,uint16_t) {return false;}
ObjectType GetObjectType(TileIndex) { return static_cast<ObjectType>(kind); }
CommandCost CheckTileOwnership(TileIndex) { return CommandCost(owns ? 0 : -2); }
Slope GetTileSlope(TileIndex) { return shape; }
"""
cpp += extract(slopes, "static constexpr bool IsSteepSlope(") + "\n"
cpp += extract(slopes, "static constexpr int GetSlopeMaxZ(") + "\n"
cpp += extract(autoslope, "inline bool AutoslopeEnabled()") + "\n"
cpp += "int GetTileMaxZ(TileIndex) { return base + GetSlopeMaxZ(shape); }\n"
cpp += extract(objects, "static CommandCost TerraformTile_Object(") + "\n"
cpp += r"""
int main() {
  int count, autoenabled, newshape, newbase;
  std::cin >> count;
  while(count--) {
    std::cin >> kind >> owns >> autoenabled >> shape >> base >> newshape >> newbase;
    _settings_game.construction.autoslope=autoenabled;
    std::cout << TerraformTile_Object(0,0,newbase,newshape).cost << '\n';
  }
}
"""
# 0..14 cover every ordinary natural corner shape except all raised,
# which the map stores as flat at the next level. 23/27/29/30 are steep.
shapes = [*range(15), 23, 27, 29, 30]
cases = list(product(range(5), (0, 1), (0, 1), shapes, (4, 5), shapes, (4, 5)))
fixture = f"{len(cases)}\n" + "\n".join(" ".join(map(str, row)) for row in cases) + "\n"
lua = r"""
local read=function() return io.read("*number") end
local test=dofile("mods/luanttd_core/openttd/object_autoslope.lua")
local kinds={[0]="transmitter","lighthouse","statue","owned_land","headquarters"}
for i=1,read() do
  local kind,owns,enabled,old_shape,old_base,new_shape,new_base=read(),read(),read(),read(),read(),read(),read()
  local cost=test.quote(kinds[kind],owns==1,old_shape,old_base,new_shape,new_base,
    {autoslope=enabled==1,foundation_price=137})
  io.write(cost or -1,"\n")
end
"""
with TemporaryDirectory() as d:
    stem = Path(d)
    source = stem / "test.cpp"
    exe = stem / "test"
    source.write_text(cpp)
    run(["g++", "-std=c++20", "-O2", str(source), "-o", str(exe)], check=True)
    expected = check_output([str(exe)], input=fixture, text=True)
    actual = check_output([a.lua, "-e", lua], input=fixture, text=True)
assert set(expected.splitlines()) == {"-1", "0", "137"}
assert actual == expected
print(f"PASS {len(cases):,} ordinary RC1 object autoslope cost and guard cases")
