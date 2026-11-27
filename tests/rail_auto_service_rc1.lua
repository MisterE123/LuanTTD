-- Boundaries from OpenTTD 16.0-RC1 VehicleEnterTile_Rail and servicing.
local D=dofile("mods/luanttd_core/openttd/rail_depot_entry_rc1.lua")
local S=dofile("mods/luanttd_core/openttd/rail_auto_service_rc1.lua")
local pose={
  {10,8,15,8,-1,0},
  {8,4,8,0,0,1},
  {4,8,0,8,1,0},
  {8,10,8,15,0,-1},
}
local checked=0
for d=0,3 do
  local ex,ey,bx,by,dx,dy=unpack(pose[d+1])
  for x=0,15 do for y=0,15 do
    local inbound=D.tile_event(d,((d+2)%4)*2+1,x+32,y+16,8,true)
    local block=x==bx and y==by and "blocked" or nil
    assert(inbound==(block or x==ex and y==ey and "hide" or nil))
    for offset=1,8 do
      local n=offset+1
      local reveal=x==ex+n*dx and y==ey+n*dy and "reveal" or nil
      assert(D.tile_event(d,d*2+1,x,y,offset,true)==(block or reveal))
      assert(D.tile_event(d,d*2+1,x,y,offset,false)==block)
      if reveal then assert(D.ticks_to_leave(d,x,y,offset)==0) end
      checked=checked+1
    end
  end end
end
local opts={interval=150,breakdowns=1,no_servicing_if_no_breakdowns=true}
local v={reliability=20000,date_of_last_service=700000}
assert(not S.due(v,opts,50000,700150))
assert(S.due(v,opts,50000,700151))
for _,flag in ipairs({"stopped","crashed","has_depot_order","loading"}) do
  v[flag]=true;assert(not S.due(v,opts,50000,700151));v[flag]=nil
end
opts.percent=true;opts.interval=20
v.reliability=40000;assert(not S.due(v,opts,50000,700999))
v.reliability=39999;assert(S.due(v,opts,50000,700999))
opts.breakdowns=0;assert(not S.due(v,opts,50000,700999))
opts.can_autoreplace=function() return true end;assert(S.due(v,opts,50000,700999))
opts.interval=0;assert(not S.due(v,opts,50000,700999))
local function fail() error("No draw/search expected") end
v.all_in_depot=true;assert(S.decision(v,opts,fail,fail).kind=="service_here");v.all_in_depot=nil
local function found(cap,penalty)
  assert(cap==2000 and penalty==100000)
  return {cost=1700,tile=10,route={8,9,10}}
end
assert(S.decision(v,opts,found,fail).tile==10)
v.depot_target=10;assert(S.decision(v,opts,found,fail).kind=="go_to_depot")
v.depot_target=20
assert(not S.decision(v,opts,found,function() return 0xFFFF end))
assert(S.decision(v,opts,found,function() return 0x0000 end).tile==10)
assert(S.decision(v,opts,function() return nil end,fail).kind=="cancel_depot")
print(("PASS RC1 train service guards and %d four-facing depot pixel/formation cases"):format(checked))

-- Actual atomic movement and reservation adapter. Match the stock
-- inbound NE depot: head enters dead-end tile first, stops at x=10,
-- and is hidden while the coach advances. No release until the tail.
local root="mods/luanttd_core/"
local function port(name,...)return dofile(root.."openttd/"..name..".lua")(...)end
local T=dofile(root.."openttd/rail_track.lua")
local F=port("rail_follow",T)
local C=port("rail_yapf_cost",T,F)
local P=port("rail_reservation",T,F,C)
local L=port("rail_consist_reservation",T,F,P)
local K=port("rail_consist_motion",T,port("rail_motion",T),F,L)
local Driver=dofile(root.."rail_consist_dispatch.lua")(K,L)
local function id(x,y)return x+32*y end
local rows={}
for x=2,10 do rows[id(x,5)]={kind="rail",trackbits=1,owner=1,railtype=0} end
local depot=id(11,5)
rows[depot]={kind="depot",dir=T.NE,owner=1,railtype=0}
local off={[0]=-1,32,1,-32}
local board={tile=function(i)return rows[i] end,adjacent=function(i,d)return i+off[d] end,
  xy=function(i)return i%32,math.floor(i/32) end,tile_at=id}
local function part(pixel)
  local x=math.floor(pixel/16)
  return {tile=id(x,5),length=8,pose={x=pixel,y=88,tx=x,ty=5,td=8,direction=5}}
end
local a,b=part(175),part(167)
local consist=assert(K.place(board,1,{a,b}))
local life=L.new()
assert(Driver.register(board,life,17,consist))
local forward=function()return 8 end
local ignored,why=Driver.step(board,life,17,consist,forward,{})
assert(not ignored and why=="unsupported_track" and consist.parts[1].pose.x==175)
local saw_mask=0
for n=1,19 do
  local result,err=Driver.step(board,life,17,consist,forward,{inbound_depot=depot})
  assert(result,err)
  if n>=11 then
    assert(consist.parts[1].hidden and consist.parts[1].pose.x==186)
    assert(life.trains[17].parts[1].in_depot)
    if n<19 then assert(not Driver.stow_return(board,life,17,consist,depot)) end
  end
  assert(L.claim_owner(life,depot,T.X)==17 and L.valid_state(board,life))
  saw_mask=saw_mask+#(result.depot_hides or {})
end
assert(saw_mask==2)
assert(Driver.stow_return(board,life,17,consist,depot))
assert(L.claim_owner(life,depot,T.X)==nil and next(life.claims)==nil and L.valid_state(board,life))
for _,p in ipairs(consist.parts) do assert(p.hidden and p.pose.x==186 and p.pose.direction==1 and p.pose.td==0) end
print("PASS RC1 engine then coach converge to the depot and release the reservation only after the tail")
