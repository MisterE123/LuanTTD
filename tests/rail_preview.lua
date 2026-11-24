-- Feed the placement renderer the real AutoRail quote, then compare
-- every ghost against the committed same-height diagonal presentation.
local root="mods/luanttd_core/"
local Track=dofile(root.."openttd/rail_track.lua")
local Slope=dofile(root.."openttd/slope.lua")
local Sim,S={}, {tiles={},companies={},topology=0}
function Sim.id(x,z) if x>=0 and x<100 and z>=0 and z<100 then return z*100+x+1 end end
function Sim.xy(id) return (id-1)%100,math.floor((id-1)/100) end
for i=1,10000 do S.tiles[i]={h=2,terrain="grass"} end
function Sim.company(s,n)
  s.companies[n]=s.companies[n] or {cash=100000,expense=0,month_exp=0}
  return s.companies[n]
end
local function terrain(id) local t=S.tiles[id];return t.slope or 0,t.h end
local Lab=dofile(root.."trackworks.lua")(Sim,Track,nil,Slope,nil,nil,terrain)
local api={Sim=Sim,s=S,terrain={tile=terrain},trackworks=Lab,render={update=function() end},save=function() end}
local Build=dofile(root.."rail_construction_tools.lua")(api,Lab,Track,nil,{track=function() return 2 end})
local Ghost=dofile(root.."rail_preview.lua")(api,root)
local Diagonal=dofile(root.."rail_diagonal.lua")(Sim,Track,api.terrain,Lab.surface)
local function aim(x,z) return {x=16*x+8,z=16*z+8} end
local p=assert(Build.quote_autotrack("QA",aim(5,5),aim(15,15)))
assert(#p.pieces>10)
local g=Ghost(p.pieces,"QA",{x=15,z=15})
assert(#g==#p.pieces and g[1].mesh:match("eased_.*_[12]%.obj$")
  and g[#g].mesh:match("eased_.*_[12]%.obj$"))
for i=2,#g-1 do assert(g[i].mesh:match("eased_.*_3%.obj$"),g[i].mesh) end
for _,q in ipairs(g) do assert(not S.tiles[q.id].rail_tracks and q.pos.y==3.038) end
assert(Build.build("QA",p))
for i,q in ipairs(g) do
  local mode=Diagonal.mode(S,q.id)
  assert(q.mesh==("bl_rail_eased_%d_%d.obj"):format(p.pieces[i].tracks,mode))
end
-- A neighboring piece that already exists participates in placement.
-- A connection to a turnout or another railhead elevation is not eased.
local a,b=Sim.id(50,50),Sim.id(50,51)
local r={id=a,tracks=8}
S.tiles[b].rail_tracks,S.tiles[b].owner=4,"QA"
assert(Ghost({r},"QA")[1].mesh=="bl_rail_eased_8_2.obj")
S.tiles[b].owner="Other"
assert(Ghost({r},"QA")[1].mesh=="bl_rail_track_8.obj")
S.tiles[b].owner,S.tiles[b].rail_tracks="QA",5
assert(Ghost({r},"QA")[1].mesh=="bl_rail_track_8.obj")
S.tiles[b].rail_tracks,S.tiles[b].h=4,3
assert(Ghost({r},"QA")[1].mesh=="bl_rail_track_8.obj")
S.tiles[b].h,S.tiles[b].rail_type=2,1
assert(Ghost({r},"QA")[1].mesh=="bl_rail_track_8.obj")
S.tiles[b].rail_type=nil
assert(Ghost({{id=a,tracks=9}},"QA")[1].mesh=="bl_rail_track_9.obj")
S.tiles[a].slope=3
local grade=Ghost({{id=a,tracks=1}},"QA")[1]
assert(grade.mesh=="bl_rail_grade_1.obj" and grade.pos.y==4.038)
-- A valid very long diagonal must never skip every other quoted tile.
local long=assert(Build.quote_autotrack("QA",aim(1,20),aim(73,92)))
assert(#long.pieces>96)
local window=Ghost(long.pieces,"QA",{x=100,z=130})
assert(#window==96 and window[1].mesh:match("_3%.obj$"))
local indices={}
for i,item in ipairs(long.pieces) do indices[item.id]=i end
for i=2,#window do assert(indices[window[i].id]==indices[window[i-1].id]+1) end
print("PASS: AutoRail placement ghosts exactly match built diagonals; preview is read-only, handles adjoining tracks, turnouts and grades; long ghosts stay connected")
S.tiles[a].slope=0
S.tiles[b].rail_type=2
local advanced=Ghost({{id=a,tracks=8,result_railtype=2}},"QA")[1]
assert(advanced.mesh=="bl_guideway_mono_eased_8_2.obj" and advanced.atlas=="bl_guideway_mono_atlas.png")
assert(not S.tiles[a].rail_type,"previews must not retag the authority's tile")
local incompatible=Ghost({{id=a,tracks=8,result_railtype=3}},"QA")[1]
assert(incompatible.mesh=="bl_guideway_maglev_flat_8.obj" and incompatible.atlas=="bl_guideway_maglev_atlas.png")
S.tiles[a].slope=3
advanced=Ghost({{id=a,tracks=1,result_railtype=2}},"QA")[1]
assert(advanced.mesh=="bl_guideway_mono_grade_1.obj" and advanced.pos.y==4.038)
print("PASS monorail and maglev previews show their own guideway profiles without foreign-gauge easing")

S.tiles[a].slope=8
local split=Ghost({{id=a,tracks=12}},"QA")
assert(#split==2 and split[1].mesh=="bl_rail_track_8.obj" and split[2].mesh=="bl_rail_track_4.obj")
assert(math.abs(split[1].pos.y-3.038)<1e-9 and math.abs(split[2].pos.y-4.038)<1e-9 and not S.tiles[a].rail_tracks)
print("PASS split-level preview shows both individual opposed railheads")

-- Actual shared corners, not arbitrary per-tile masks: each drag
-- alternates a single-corner split railhead with a leveled neighbor.
-- Reverse the same two hillside courses to cover both track families
-- and all four drag directions.
local Stock=dofile(root.."openttd/rail_construction.lua")(Track)
api.company_can_build_stock_railtype=function() return true end
local native=dofile(root.."rail_construction_tools.lua")(api,Lab,Track,nil,{track=function(tile,plan,opts)
  local q,why=Stock.piece(tile,plan.track,opts)
  if q then return q.cost,nil,q end
  return nil,why
end})
local projection=dofile(root.."rail_diagonal.lua")(Sim,Track,api.terrain,Lab.surface,Lab.split_surface)
local shipped={[0]="bl_rail_eased_",[1]="bl_rail_eased_",[2]="bl_guideway_mono_eased_",[3]="bl_guideway_maglev_eased_"}
for sign=1,-1,-2 do
  for direction=1,-1,-2 do
    local x,z=23,35
    local stopx,stopz=x+direction*7,z+direction*7*sign
    local anchor=x-sign*z
    local offset=sign==1 and 0 or 1
    local function h(u,v)
      return u-sign*v-anchor>=offset and 5 or 4
    end
    for gx=13,33 do for gz=25,45 do
      local slope,base=Slope.classify(h(gx,gz),h(gx+1,gz),h(gx,gz+1),h(gx+1,gz+1))
      S.tiles[Sim.id(gx,gz)]={terrain="grass",h=base,slope=slope}
    end end
    local q=assert(native.quote_autotrack("QA",aim(x,z),aim(stopx,stopz),0))
    local ghost=Ghost(q.pieces,"QA")
    assert(#ghost==15 and #q.ids==15)
    local split_count=0
    for i,r in ipairs(ghost) do
      local piece=q.pieces[i]
      local shape,base=terrain(r.id)
      if Lab.split_surface(shape,base,piece.tracks) then split_count=split_count+1 end
      assert((i==1 or i==15) and r.mesh:match("^bl_rail_eased_")
        or r.mesh==shipped[0]..piece.tracks.."_3.obj",
        ("wrong hillside ghost %d: %s"):format(i,r.mesh))
      assert(math.abs(r.pos.y-6.038)<1e-8,r.pos.y)
      assert(S.tiles[r.id].rail_tracks==nil)
    end
    assert(split_count>=7)
    assert(native.build("QA",q))
    for i,piece in ipairs(q.pieces) do
      local mode=projection.mode(S,piece.id,piece.tracks)
      assert(mode>0 and (i==1 or i==15 or mode==3))
      assert(ghost[i].mesh==shipped[0]..piece.tracks.."_"..mode..".obj")
      if i>1 and i<15 then
        local x,z,dx,dz=projection.sample(piece.track,.25,mode)
        local w,y,ux,uz=projection.sample(piece.track,.75,mode)
        assert(math.abs(w-x-.5*math.sqrt(2)*dx)<1e-7 and math.abs(y-z-.5*math.sqrt(2)*dz)<1e-7)
        assert(dx==ux and dz==uz and math.abs(math.abs(dx)-math.sqrt(.5))<1e-7)
      end
    end
  end
end
for gauge=0,3 do
  local x,z=60,20+gauge*17
  for u=x-2,x+9 do for v=z-2,z+9 do
    S.tiles[Sim.id(u,v)]={terrain="grass",h=4}
  end end
  local q=assert(native.quote_autotrack("QA",aim(x,z),aim(x+7,z+7),gauge))
  local g=Ghost(q.pieces,"QA")
  assert(#g==15 and g[2].mesh==shipped[gauge]..q.pieces[2].tracks.."_3.obj")
  assert(native.build("QA",q))
  assert(projection.mode(S,q.pieces[2].id)==3)
end
print("PASS: four uphill-facing AutoRail drags across alternating raw slopes; matching ghost heights, track, and train vectors. All four gauges on level terrain.")

-- A second drag one tile east of the first builds opposing half tracks
-- in a common tile. Assert both independent railway lanes survive quote,
-- commit, mesh choice and train-curve sampling without a crossover.
for sign=1,-1,-2 do
  for x=65,83 do for z=59,81 do
    S.tiles[Sim.id(x,z)]={terrain="grass",h=4,slope=0}
  end end
  local a,b,c,d=71,70,78,70+7*sign
  local first=assert(native.quote_autotrack("QA",aim(a,b),aim(c,d),0))
  assert(native.build("QA",first))
  local next=assert(native.quote_autotrack("QA",aim(a+1,b),aim(c+1,d),0))
  local g=Ghost(next.pieces,"QA")
  assert(native.build("QA",next))
  local count=0
  for i,piece in ipairs(next.pieces) do
    local bits=piece.tracks
    local lower=bits==12 and 4 or bits==48 and 16
    if lower then
      count=count+1
      assert(g[i].mesh:match("^bl_rail_dual_"))
      assert(g[i].mesh=="bl_rail_dual_"..projection.dual_variant(S,piece.id,bits)..".obj")
      local f=assert(io.open(root.."models/"..g[i].mesh,"rb"));f:close()
      local firstmask,secondmask=lower,lower*2
      local mode=projection.mode(S,piece.id,firstmask)
      local across=projection.mode(S,piece.id,secondmask)
      assert(mode>0 and across>0)
      local routes={}
      for _,mask in ipairs({firstmask,secondmask}) do
        local idx=math.floor(math.log(mask)/math.log(2)+.5)
        for side=0,3 do
          if Track.trackdir_for_entry(idx,side) then
            assert(not routes[side])
            routes[side]=idx
          end
        end
        local selected=projection.mode(S,piece.id,mask)
        if count>1 and count<7 then
          assert(selected==3)
          local x,z,dx,dz=projection.sample(idx,.5,selected)
          assert(x~=0 and z~=0 and math.abs(math.abs(dx)-math.sqrt(.5))<1e-8)
          assert(math.abs(math.abs(dz)-math.sqrt(.5))<1e-8)
        end
      end
    end
  end
  assert(count==7,count)
end
print("PASS both stock parallel diagonal track pairs: quotes, commits, independent topology, native mesh assets, and train centerline")
