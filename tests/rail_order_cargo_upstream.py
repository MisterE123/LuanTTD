"""Compile the two stock RC1 CmdModifyOrder cargo validation and mutation branches."""
from hashlib import sha256
from itertools import product
from pathlib import Path
import re
import subprocess
import sys
from tempfile import TemporaryDirectory


def pinned(path, digest):
    data = path.read_bytes()
    assert sha256(data).hexdigest() == digest, path
    return data.decode()


def main():
    root = Path(sys.argv[1])
    lua = sys.argv[2] if len(sys.argv) > 2 else "lua5.1"
    cmd = pinned(root / "order_cmd.cpp", "d348cc12a6ad70d6deffc6ff1d97d02d0ae04440ae82cdbffeff28df096555e2")
    typ = pinned(root / "order_type.h", "f5df6a1dde2bc2e026d38348eea66197d8d1934a2a156a436bbfc9948349e5fb")
    cmd = cmd[cmd.index("CommandCost CmdModifyOrder"):cmd.index("static bool CheckAircraftOrderDistance")]
    checks = cmd[cmd.index("case MOF_UNLOAD: {"):cmd.index("case MOF_DEPOT_ACTION:", cmd.index("case MOF_LOAD: {"))]
    start = cmd.index("case MOF_UNLOAD:\n")
    execute = cmd[start:cmd.index("case MOF_DEPOT_ACTION: {", start)]
    enums = [re.search(rf"enum class {n} : uint8_t {{[^}}]+}};", typ)[0]
             for n in ("OrderUnloadType", "OrderLoadType", "OrderNonStopFlag")]
    cc = "#include <cstdint>\n#include <iostream>\n" + "\n".join(enums) + """
enum { MOF_LOAD, MOF_UNLOAD, CARGO_NO_REFIT = -1 };
constexpr bool CMD_ERROR=false;
constexpr int STR_ERROR_UNBUNCHING_NO_FULL_LOAD=0;
bool CommandCost(int) { return false; }
struct Flags {
    int raw;
    bool Test(OrderNonStopFlag flag) { return raw & (1<<int(flag)); }
};
struct Order {
    int load, unload, flags, refit=7;
    OrderLoadType GetLoadType() { return OrderLoadType(load); }
    OrderUnloadType GetUnloadType() { return OrderUnloadType(unload); }
    Flags GetNonStopType() { return {flags}; }
    void SetLoadType(OrderLoadType t) { load=int(t); }
    void SetUnloadType(OrderUnloadType t) { unload=int(t); }
    void SetRefit(int c) { refit=c; }
};
struct Vehicle { bool unbunch; bool HasUnbunchingOrder() { return unbunch; } };
bool edit(Order *order,Vehicle *v,int mof,uint16_t data) {
    switch (mof) {
""" + checks + """
    }
    switch (mof) {
""" + execute + """
    }
    return true;
}
int main() {
    int action,dest,load,unload,flags,unbunch;
    while (std::cin>>action>>dest>>load>>unload>>flags>>unbunch) {
        Order o{load,unload,flags}; Vehicle v{bool(unbunch)};
        bool changed=edit(&o,&v,action,dest);
        std::cout<<changed<<" "<<o.load<<" "<<o.unload<<" "<<o.refit<<"\\n";
    }
}
"""
    luatest = """
local C=dofile("mods/luanttd_core/openttd/rail_order_cargo.lua")
local function n() return io.read("*n") end
while true do
  local action=n()
  if action==nil then break end
  local target,l,u,flags,unbunch=n(),n(),n(),n(),n()
  local o={kind="station",load_type=l,unload_type=u,nonstop=flags,refit=7}
  local ok=C.change(o,action==0 and "load" or "unload",target,unbunch==1)
  print(("%d %d %d %d"):format(ok and 1 or 0,o.load_type,o.unload_type,o.refit or -1))
end
"""
    cases = list(product(range(2), range(12), range(5), range(5), range(4), range(2)))
    payload = "".join(" ".join(map(str, row)) + "\n" for row in cases)
    with TemporaryDirectory(prefix="rc1-cargo-oracle-") as t:
        src = Path(t) / "orig.cpp"
        out = src.with_suffix("")
        src.write_text(cc)
        script = src.with_suffix(".lua")
        script.write_text(luatest)
        subprocess.run(["g++", "-std=c++20", "-O2", src, "-o", out], check=True)
        expected = subprocess.check_output([out], text=True, input=payload).splitlines()
        actual = subprocess.check_output([lua, script], text=True, input=payload).splitlines()
    assert len(actual) == len(expected) == len(cases)
    for case, a, e in zip(cases, actual, expected):
        assert a == e, (case, a, e)
    print(f"PASS: {len(cases)} exact RC1 CmdModifyOrder station cargo cases")


if __name__ == "__main__":
    main()
