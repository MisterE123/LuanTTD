local C=dofile("mods/luanttd_core/openttd/rail_order_cargo.lua")
local function eq(x,y) assert(x==y,tostring(x).." ~= "..tostring(y)) end
local valid={load={[0]=true,[2]=true,[3]=true,[4]=true},unload={[0]=true,[1]=true,[2]=true,[4]=true}}
for _,k in ipairs({"load","unload"}) do
  local other=k=="load" and "unload" or "load"
  for value=-1,8 do
    for old=0,4 do
      for non=0,3 do
        for _,unbunching in ipairs({false,true}) do
          local o={kind="station",nonstop=non,refit=7}
          o[k.."_type"]=old
          o[other.."_type"]=4
          local ok=C.change(o,k,value,unbunching)
          local expected=not not (non<2 and old~=value and valid[k][value] and
            not (k=="load" and unbunching and (value==2 or value==3)))
          eq(ok,expected)
          eq(o[k.."_type"],ok and value or old)
          eq(o[other.."_type"],4)
          if ok and k=="load" and value==4 then eq(o.refit,nil) else eq(o.refit,7) end
        end
      end
    end
  end
end
assert(not C.change({kind="depot"},"load",4))
local r=C.arrival({load_type=3,unload_type=2},{})
assert(r.full and r.transfer and not r.no_load and not r.force_unload and not r.no_unload)
r=C.arrival({load_type=4,unload_type=1},{})
assert(not r.full and not r.transfer and r.no_load and r.force_unload and not r.no_unload)
r=C.arrival({load_type=2,unload_type=4},{})
assert(r.full and r.no_unload)
print("PASS OpenTTD RC1 station cargo flag validation, independent load/unload, no refit on no loading, no full load with unbunching")
