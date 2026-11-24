-- Authoritative bridge-free standard track: the native adapter must
-- not narrow the pinned CmdBuildSingleRail shoreline kernel.
local function load(n) return dofile("mods/luanttd_core/"..n..".lua") end
local Sim,T,Sl=load("sim"),load("openttd/rail_track"),load("openttd/slope")
local Q=load("openttd/rail_construction")(T)
local S=Sim.new(1751)
local owner="Coast rail"
local c=Sim.company(S,owner)
c.cash=100000
local id=assert(Sim.id(10,10))
local slope=0
local function shape() return slope,0 end
local Follow=load("openttd/rail_follow")(T)
local Lab=load("trackworks")(Sim,T,Follow,Sl,nil,nil,shape)
local B=load("rail_construction_tools")({Sim=Sim,s=S,terrain={tile=shape},
  render={update=function()end,raise_bound=function()end},save=function()end},Lab,T,nil,{
  track=function(tile,p,o)
    local q,why=Q.piece(tile,p.track,o)
    return q and q.cost,why,q
  end,
})
local wet,dry,denied=0,0,0
for _,mask in ipairs({0,1,2,3,4,6,7,8,9,11,12,13,14,23,27,29,30}) do
  slope=mask
  for tr=0,5 do
    local variant=tr%2
    local tile={h=0,terrain="water",water_class="sea",coastal_water=mask~=0 or nil,
      stock_water_rocks=mask~=0 or nil,variant=variant}
    S.tiles[id]=tile
    local q=Q.piece({slope=mask,kind="water",coast=mask~=0,base_level=0},tr,{owner=owner})
    local p,why=B.quote_track(owner,id,id,tr,false)
    if q then
      assert(p,("shape %d track %d: %s"):format(mask,tr,tostring(why)))
      assert(p.price==q.cost and p.pieces[1].water_ground==q.water_ground)
      assert(tile.terrain=="water" and not tile.build)
      local balance=c.cash
      assert(B.build(owner,p))
      assert(c.cash==balance-q.cost and tile.rail_tracks==2^tr and tile.h==0 and tile.variant==variant)
      assert(tile.terrain=="grass" and not tile.coastal_water and not tile.stock_water_rocks)
      if q.water_ground then assert(tile.rail_ground==13);wet=wet+1
      else assert(tile.rail_ground==0);dry=dry+1 end
    else
      assert(not p and tile.terrain=="water" and not tile.build)
      denied=denied+1
    end
  end
end
assert(wet>=4 and dry>=12 and denied>=12,("counts %d/%d/%d"):format(wet,dry,denied))
print(("PASS all 102 RC1 coast/open-water shapes×pieces: %d dry tracks, %d flooded halves, %d refused; no changed corners")
  :format(dry,wet,denied))
