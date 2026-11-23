local path="mods/luanttd_core/"
local Track=dofile(path.."openttd/rail_track.lua")
local stock=dofile(path.."rail_pose.lua")(Track).sample
local Sim,S={}, {tiles={}}
function Sim.id(x,z) return z*100+x end
function Sim.xy(id) return id%100,math.floor(id/100) end
local D=dofile(path.."rail_diagonal.lua")(Sim,Track)
local function diagonal(id,td,f) return D.sample(td,f,D.mode(S,id)) end
local Fit=dofile(path.."rail_body_spacing.lua")(Sim,Track,diagonal,stock)
local poses={}
-- Complete observed route on actual renderer paths: straight, entry
-- easement, the thin 45-degree diagonal, exit easement, straight.
local x,z=20,12
local function rail(td)
  local id=Sim.id(x,z)
  local track=Track.track(td)
  S.tiles[id]={rail_tracks=2^track,owner="QA",h=0}
  local n=track<2 and 16 or 8
  for i=0,n-1 do poses[#poses+1]={id=id,td=td,progress=i/n,reversed=false} end
  local exit=Track.exit_side(td)
  local move=({[0]={-1,0},{0,1},{1,0},{0,-1}})[exit]
  x,z=x+move[1],z+move[2]
end
rail(0);rail(0)
for i=1,5 do rail(3);rail(2) end
rail(0);rail(0)
local function coords(p)
  if p.x then return p.x,p.z,p.dx,p.dz end
  local x,z=Sim.xy(p.id)
  local sx,sz,dx,dz=diagonal(p.id,p.td,p.progress)
  if not sx then sx,sz,dx,dz=stock(p.td,p.progress) end
  return x*2+sx,z*2+sz,dx,dz
end
local function dist(a,b)
  local x,z=coords(a)
  local bx,bz=coords(b)
  return math.sqrt((x-bx)^2+(z-bz)^2)
end
local function coupler_gap(a,b)
  local x,z,dx,dz=coords(a)
  local bx,bz,ux,uz=coords(b)
  -- Fore/aft couplers are +/-4.99 OBJ units on the shipped rolling
  -- stock, i.e. 0.499 Luanti nodes either side of the body center.
  return math.sqrt((bx+.499*ux-(x-.499*dx))^2+(bz+.499*uz-(z-.499*dz))^2)
end
local parts={{length=8},{length=8},{length=8}}
local best,raw_max,did_n,did_c,max_body_displacement=0,0,0,0,0
for i=17,#poses do
  local raw={poses[i],poses[i-8],poses[i-16]}
  local f=Fit(raw,parts)
  if f then
    did_n=did_n+1
    assert(f[1].id==raw[1].id and f[1].progress==raw[1].progress,"steam locomotive keeps its sampled travel coordinate")
    max_body_displacement=math.max(max_body_displacement,dist(f[1],raw[1]))
    for p=2,#parts do
      local delta=coupler_gap(f[p-1],f[p])
      best=math.max(best,delta)
      raw_max=math.max(raw_max,coupler_gap(raw[p-1],raw[p]))
    end
    local forward=assert(Fit(raw,parts,true))
    local reverse={}
    for p=1,#parts do
      local a=raw[#parts-p+1]
      reverse[p]={id=a.id,td=Track.reverse_trackdir(a.td),progress=1-a.progress,reversed=true}
    end
    local backward=assert(Fit(reverse,parts,true))
    for p=1,#parts do
      assert(dist(forward[p],backward[#parts-p+1])<.003,"bidirectional bodies move on a cab change")
    end
    if i%8==0 then did_c=did_c+1 end
  end
end
assert(did_n>70 and did_c>8 and raw_max>.65 and best<.06 and max_body_displacement<.20)
local head=poses[67]
local car=poses[59]
assert(Fit({head,car},{{},{}}))
local bad={id=car.id,td=Track.reverse_trackdir(car.td),progress=.5,reversed=false}
assert(Fit({head,bad},{{},{}})==nil,"never guess an unproven switch path")
bad={id=car.id,td=car.td,progress=car.progress,reversed=true}
assert(Fit({head,bad},{{},{}})==nil,"never stretch over the reversal epoch")
bad.wormhole=true
assert(Fit({head,bad},{{},{}})==nil,"no re-spacing inside a bridge or tunnel")
assert(Fit({head},{{},{}})==nil,"hidden tail gets no pose")
print(("PASS: %d fixed couplings comparing stock gap %.3f with compensated %.3f; centered push-pull reversal is invariant"):
  format(did_n,raw_max,best))
