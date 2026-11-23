-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD 16.0-RC1 src/order_type.h and src/order_cmd.cpp CmdModifyOrder
-- MOF_LOAD/MOF_UNLOAD. This adapter handles station orders of passenger
-- trains, which have exactly one cargo type even with several coaches.
local M={}
M.load={
  {value=0,label="Load if available"}, {value=2,label="Full load all"},
  {value=3,label="Full load any"}, {value=4,label="No loading"},
}
M.unload={
  {value=0,label="Unload if accepted"}, {value=1,label="Unload all"},
  {value=2,label="Transfer"}, {value=4,label="No unloading"},
}
function M.change(order,kind,value,unbunching)
  if order.kind~="station" or math.floor((order.nonstop or 0)/2)%2~=0 then return false end
  local choices=M[kind]
  if not choices or value==(order[kind.."_type"] or 0) then return false end
  for _,item in ipairs(choices) do
    if item.value==value then
      if kind=="load" and unbunching and (value==2 or value==3) then return false end
      order[kind.."_type"]=value
      if kind=="load" and value==4 then order.refit=nil end
      return true
    end
  end
  return false
end
function M.load_flags(value)
  return value==2 or value==3,value==4
end
function M.arrival(order,opts)
  opts.full,opts.no_load=M.load_flags(order.load_type)
  opts.force_unload=order.unload_type==1
  opts.transfer=order.unload_type==2
  opts.no_unload=order.unload_type==4
  return opts
end
function M.summary(order)
  local a={}
  for _,k in ipairs({"load","unload"}) do
    for _,option in ipairs(M[k]) do
      if option.value~=0 and option.value==order[k.."_type"] then a[#a+1]=option.label end
    end
  end
  if #a>0 then return "  ·  "..table.concat(a," / ") end
  return ""
end
return M
