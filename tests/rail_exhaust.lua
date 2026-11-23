local path="mods/luanttd_core/"
local M=dofile(path.."rail_exhaust_model.lua")
local train={phase="running",speed=20,max_track_speed=100,consist={parts={{},{},{}}}}
assert(M.work(train,"steam",1,{})==.2)
assert(not M.work(train,"steam",3,{}))
assert(M.work(train,"sh_125",1,{})==.2)
train.dual_head=true
assert(M.work(train,"sh_125",3,{})==.2 and not M.work(train,"sh_125",2,{}))
assert(not M.work(train,"wagon",1,{}) and not M.work(train,"sh_40",1,{}))
assert(not M.work(train,"steam",1,{rail_depot_dir=0}))
assert(not M.work(train,"steam",1,{}, {kind="tunnel"}))
assert(M.work(train,"steam",1,{}, {kind="bridge"})==.2)
assert(not M.work(train,"steam",1,{},nil,true))
train.speed=60
assert(not M.work(train,"sh_125",1,{}) and M.work(train,"steam",1,{})==.6)
train.phase="dwell"
assert(not M.work(train,"steam",1,{}))
train.phase,train.slowing="running",true
assert(not M.work(train,"steam",1,{}))
train.slowing,train.crashed=false,true
assert(not M.work(train,"steam",1,{}))

local particles,near,far={},nil,nil
local function viewer(name,pos)
  return {get_player_name=function()return name end,get_pos=function()return pos end}
end
near=viewer("near",{x=1,y=1,z=1})
far=viewer("far",{x=100,y=1,z=100})
local function fixture()
  particles={}
  return dofile(path.."rail_exhaust_view.lua")({
    add_particle=function(p) particles[#particles+1]=p end,
    get_connected_players=function()return {near,far} end
  },M,function(a,r)
    return {x=r.y==math.pi and -a.x or a.x,y=a.y,z=r.y==math.pi and -a.z or a.z}
  end)
end
local v=fixture()
local body={kind="ginzu",body_index=1,exhaust=.1,flip=false,rotation={x=0,y=0,z=0}}
local coach={kind="wagon",body_index=2,exhaust=.1,flip=false,rotation=body.rotation}
local electric={kind="sh_30",body_index=3,exhaust=.1,flip=false,rotation=body.rotation}
local rows={train={mode="rail",parts={body,body,coach,electric}}}
local x=0
local function step(count,dx)
  for _=1,count do
    x=x+dx
    body.pos={x=x,y=3,z=7};coach.pos=body.pos;electric.pos=body.pos
    v.render(rows,.05)
  end
end
step(16,.05)
assert(#particles==3,"one clock per physical engine even with duplicate rows/outlets")
assert(particles[1].playername=="near" and particles[1].texture.name=="bl_rail_steam.png")
assert(math.abs(particles[1].pos.y-3.594)<.0001 and math.abs(particles[1].pos.z-6.645)<.0001)
assert(math.abs(particles[2].pos.z-6.684)<.0001 and particles[1].velocity.x<0)
local n=#particles
step(15,0);assert(#particles==n,"must not exhaust at standstill")
step(1,10);assert(#particles==n,"a route snap must not create smoke")
body.rotation.y,body.flip=math.pi,true
step(1,-.05);assert(#particles==n,"a reverse snap must not create smoke")
step(8,-.05);assert(#particles==n+2 and particles[n+1].pos.z>7.31,"track the turned physical chimney")
v.render({},.1)
n=#particles;step(1,.1);assert(#particles==n,"do not create a puff when reculling")
v=fixture();body.kind,body.exhaust="hendry",.2
step(60,-.04)
assert(#particles==3 and particles[1].texture.name:find("535258"))
print("Rail exhaust: stock movement gates, chimney transforms and multiple outlets, bounded local plumes, no wagon/electric/duplicate/idle smoke")
