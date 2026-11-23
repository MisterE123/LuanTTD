-- Exact native mast poses and controller-owned aspects, shared by the
-- in-engine renderer and the worker's bounded viewport projection.
return function(Sim,Track,Art,signal_pixel,board_base)
  local directions={0,1,2,3,4,5,8,9,10,11,12,13}
  return function(id,r,mask,out)
    out=out or {}
    local x,z=Sim.xy(id)
    for _,td in ipairs(directions) do
      local signal=Track.signal_along(td)
      if Track.has(mask,Track.track(td)) and Track.intersect(r.present_signals,signal)~=0 then
        local secondary=Track.track(td)==3 or Track.track(td)==5
        local variant=secondary and r.lower_variant or r.upper_variant
        local model=variant==1 and "semaphore" or "light"
        local green=Track.intersect(r.green_signals,signal)~=0
        local u,v=Art.world_anchor(td,false,mask)
        if u~=nil then
          local pixel=signal_pixel and signal_pixel(id,u,v)
          local y=(pixel and pixel/8 or board_base(id))+.5
          local p,rotation=Art.pose(x,z,y,td,false,mask)
          out[#out+1]={key=id..":"..td,model=model.."_"..(green and "green" or "red"),
            pos=p,rotation=rotation}
        end
      end
    end
    return out
  end
end
