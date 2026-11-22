-- Both test clients compile real stock road paths from the production port.
return function(root)
  local F=dofile(root.."openttd/yapf_road_follow.lua")
  local Motion=dofile(root.."openttd/road_motion.lua")(dofile(root.."openttd/road_motion_data.lua"))
  local Paint=dofile(root.."road_motion_presentation.lua")(dofile(root.."road_lanes.lua"))
  local delta={[0]={-1,0},{0,1},{1,0},{0,-1}}
  local bits={[0]=8,4,2,1}
  local function reverse(a)return (a+2)%4 end
  local W=64
  local function id(x,z) return z*W+x end
  local function xy(n) return n%W,math.floor(n/W) end
  local function adjacent(n,d)return n+delta[d][1]+delta[d][2]*W end
  local R={}
  function R.compile(a,b,cx,cz)
    assert(b~=reverse(a))
    local piv=id(cx,cz)
    local st1=adjacent(piv,reverse(a))
    local st2=adjacent(piv,b)
    local ids={adjacent(st1,reverse(a)),st1,piv,st2,adjacent(st2,b)}
    local board={xy=xy,adjacent=adjacent}
    local T={}
    function board.tile(n)return T[n] end
    local points={}
    for i,n in ipairs(ids) do
      local u=i<=3 and a or b
      local v=i<3 and a or b
      local mask=bits[reverse(u)]+bits[v]
      local p={kind=(i==1 or i==5) and "drive_stop" or "road",roadtype=0,road_bits=mask,dir=v}
      local dirs=F.trackdirs(F.origin_trackdirs(p,false,u))
      local td
      for _,e in ipairs(dirs) do
        if F.exit_direction(e)==v then td=e end
      end
      assert(td,("stock curve %d %d has no valid trackdir"):format(a,b))
      T[n]=p
      local x,z=xy(n)
      points[i]={x=x,z=z,mask=mask,id=n}
      ids[i]={tile=n,td=td}
    end
    local A=dofile(root.."road_motion_leg.lua")(Motion,F,board)
    local frames=assert(A.compile(ids))
    local function motion(k,f)
      assert(k>=1 and k<#frames and f>=0 and f<=1)
      local x,z,angle=Paint.pose(frames[k],frames[k+1],f)
      return x,z,angle,frames[k][4]
    end
    return {frames=frames,pose=motion,points=points,id=piv}
  end
  return R
end
