"""Compile the original OpenTTD 16.0-RC1 vehicle order index methods."""
from hashlib import sha256
from itertools import product
from pathlib import Path
import re
import subprocess
import sys
from tempfile import TemporaryDirectory

ROOT = Path(__file__).resolve().parents[1]
EXPECTED = "618e3cbb81fcc9919f013d3f226a89787a340ea5d6b247feb5b9fbbf9a43aaae"
FUNCTIONS = ("SkipToNextRealOrderIndex", "IncrementImplicitOrderIndex",
             "IncrementRealOrderIndex", "UpdateRealOrderIndex")


def extract(text, name):
    begin = re.search(rf"\bvoid {name}\(\)\s*\{{", text).start()
    start = text.index("{", begin)
    depth = 0
    for i in range(start, len(text)):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if not depth:
                return text[begin:i + 1]
    raise ValueError(name)


PREFIX = """
#include <cassert>
#include <iostream>
#include <vector>
constexpr bool OT_IMPLICIT = true;
struct Order {
    bool implicit;
    bool IsType(bool t) const { return implicit == t; }
};
void InvalidateVehicleOrder(void *, int) {}
struct Vehicle {
    unsigned cur_real_order_index = 0, cur_implicit_order_index = 0;
    std::vector<Order> orders;
    unsigned GetNumOrders() const { return orders.size(); }
    unsigned GetNumManualOrders() const { unsigned n=0; for (auto &o: orders) n+=!o.implicit; return n; }
    const Order *GetOrder(unsigned i) const {return &orders.at(i);}
"""
SUFFIX = """
};
int main() {
    unsigned op,n,pos,imp,flag;
    while (std::cin>>op>>n>>pos>>imp) {
        Vehicle v;
        v.cur_real_order_index=pos;
        v.cur_implicit_order_index=imp;
        for (unsigned j=0;j<n;++j) { std::cin>>flag; v.orders.push_back({bool(flag)}); }
        if (op==0) v.UpdateRealOrderIndex();
        else if (op==1) v.IncrementRealOrderIndex();
        else v.IncrementImplicitOrderIndex();
        std::cout<<v.cur_real_order_index<<" "<<v.cur_implicit_order_index<<"\\n";
    }
}
"""
LUA = """
local O=dofile("mods/luanttd_core/openttd/rail_order_list.lua")
local function num() return io.read("*n") end
while true do
  local op=num();if op==nil then break end
  local n,idx,i=num(),num(),num()
  local v={real=idx,implicit=i}
  local orders={}
  for j=1,n do orders[j]={kind=num()==1 and "implicit" or "station"} end
  if op==0 then O.update_real(orders,v)
  elseif op==1 then O.increment_real(orders,v)
  else O.increment_implicit(orders,v) end
  print(v.real.." "..v.implicit)
end
"""


def main():
    src = Path(sys.argv[1])
    lua = sys.argv[2] if len(sys.argv) > 2 else "lua5.1"
    cache = src.read_bytes()
    assert sha256(cache).hexdigest() == EXPECTED, "not the pinned 16.0-RC1 vehicle_base.h"
    data = []
    for count in range(8):
        for flags in product((0, 1), repeat=count):
            real = [i for i, f in enumerate(flags) if f == 0] or [0]
            for op in range(3):
                for r in (range(count + 2) if op == 0 else real):
                    for i in range(max(1, count)):
                        data.append((op, count, r, i, *flags))
    payload = "".join(" ".join(map(str, line)) + "\n" for line in data)
    cpp = PREFIX + "\n".join(extract(cache.decode(), f) for f in FUNCTIONS) + SUFFIX
    with TemporaryDirectory(prefix="luanttd-order-oracle-") as tmp:
        test = Path(tmp) / "test"
        test.with_suffix(".cpp").write_text(cpp)
        subprocess.run(["g++", "-std=c++20", "-O2", str(test.with_suffix(".cpp")), "-o", str(test)], check=True)
        native = subprocess.check_output([test], text=True, input=payload).splitlines()
        test.with_suffix(".lua").write_text(LUA)
        port = subprocess.check_output([lua, test.with_suffix(".lua")], cwd=ROOT, text=True, input=payload).splitlines()
    assert len(port) == len(native) == len(data)
    for i, (stock, got) in enumerate(zip(native, port)):
        assert stock == got, (data[i], stock, got)
    print(f"PASS OpenTTD 16.0-RC1 original C++ agrees on {len(data)} order index cases")


if __name__ == "__main__":
    main()
