-- SPDX-License-Identifier: GPL-2.0-only
-- Verify a single native stock north-corner Raise, not a generic writer.
local path=core.get_modpath(core.get_current_modname())
local function load(n) return dofile(path.."/"..n..".lua") end
local file=assert(io.open(path.."/input.json","rb"))
local q=assert(core.parse_json(file:read("*a")));file:close()
local T=load("terrain")
local L=load("landscaping")(T)
local I=load("openttd_map")(T)
local width=256
local expected={[44902]=2,[44903]=4,[45158]=1,[45159]=8}

local function compute(spec)
  assert(spec.schema=="luanttd-stock-terraform-quote-input/1" and spec.tile==45159
    and spec.direction=="raise" and spec.mask==8 and spec.company==0
    and spec.snapshot.width==width and spec.snapshot.height==256
    and spec.source_sha256==spec.snapshot.source.sha256 and spec.inflation==65536)
  local land={}
  for _,rec in ipairs(spec.incident) do
    assert(expected[rec.tile] and rec.slope==expected[rec.tile] and rec.owner==16 and rec.kind=="grass"
      and rec.base==1 and rec.density==3 and not land[rec.tile],"unsupported terrain footprint")
    land[rec.tile]=rec
  end
  assert(#spec.incident==4)
  local board=I.prepare(spec.snapshot)
  local world=board.corner_grid
  local x,z=spec.tile%width+1,math.floor(spec.tile/width)+1
  local factor=assert(({[0]=6,8,9})[spec.construction_difficulty])
  local costs={grass=math.floor(20*factor/8)}
  local unit=math.floor(L.base_terraform_cost*factor/8)
  assert(T.corner(world,x,z)==1 and board.source_tile_id(x,z)==spec.tile)
  local checked={}
  local opts={unit_cost=unit,max_height=spec.max_height,allowance=spec.terraform_quota,cash=spec.cash,
    validate_tile=function(pass,tx,tz,mask,lo,hi)
      local id=board.source_tile_id(tx,tz)
      local valid=land[id]
      if not valid or board.tile_type(tx,tz)~=0 or T.tile(world,tx,tz)~=0
        or mask~=valid.slope or lo~=valid.base or hi~=lo+1 then return nil,"UNQUALIFIED_TERRAIN" end
      if pass==1 then checked[#checked+1]={tile=id,mask=mask,low=lo,high=hi} end
      return L.clear_ground_cost(valid.kind,valid.density,costs)
    end}
  local p=assert(L.corner(world,x,z,true,opts))
  assert(#p.changes==1 and #p.dirty==4 and #checked==4
    and p.changes[1].x==x and p.changes[1].z==z and p.changes[1].height==2
    and p.cost==unit+4*costs.grass and p.spent_allowance==65536
    and p.allowance_after==spec.terraform_quota-65536 and p.cash_after==spec.cash-p.cost
    and T.corner(world,x,z)==1,"unexpected quote/impure preview")
  assert(L.apply(world,p) and T.corner(world,x,z)==2)
  for _,r in ipairs(checked) do
    local mask,low,high=T.tile(world,r.tile%width+1,math.floor(r.tile/width)+1)
    assert(mask==r.mask and low==r.low and high==r.high)
  end
  assert(not L.apply(world,p),"the same shared-corner plan must not execute twice")
  return {schema="luanttd-stock-terraform-quote/1",source_sha256=spec.source_sha256,original_tick=spec.original_tick,
    tile=spec.tile,mask=spec.mask,old_height=1,height=2,unit=unit,clear_each=costs.grass,cost=p.cost,
    company=spec.company,new_slopes=checked,terraform_quota_debit=p.spent_allowance}
end

local result=compute(q)
local function copy(t)
  if type(t)~="table" then return t end
  local r={}
  for k,v in pairs(t) do r[k]=copy(v) end
  return r
end
local n=0
for _,mutate in ipairs({
  function(a) a.tile=45160 end,
  function(a) a.direction="lower" end,
  function(a) a.mask=9 end,
  function(a) a.company=1 end,
  function(a) a.incident[1].owner=0 end,
  function(a) a.incident[1].kind="field" end,
  function(a) a.terraform_quota=0 end,
  function(a) a.cash=1 end,
  function(a) a.max_height=1 end,
}) do
  local p=copy(q);mutate(p);assert(not pcall(compute,p),"unsupported quote accepted");n=n+1
end
result.rejected_lab_inputs=n
local body=assert(core.write_json(result))
core.log("action","LuanTTD stock terraform quote "..assert(core.write_json({body=body,sha256=core.sha256(body)})))
core.register_on_mods_loaded(function()
  core.after(.05,function() core.request_shutdown("stock terraforming quote complete",false,0) end)
end)
