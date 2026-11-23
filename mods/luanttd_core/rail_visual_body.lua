-- Shared projected body pose for the native dispatcher and worker
-- snapshots. Travel-order indices are distinct from physical body IDs.
return function(Sim,models,diagonal,stock,surface,fallback)
  return function(train,sample,i,engine,wagon)
    local id,td,f=sample.id,sample.td,sample.progress
    local count=#train.consist.parts
    local push_pull=(train.dual_head or train.stock_engine==11) and count>1
    local backing=push_pull and sample.reversed==true
    local body_index=backing and count-i+1 or i
    local rear=push_pull and body_index==count
    local kind=(body_index==1 or rear) and engine or (type(wagon)=="table" and wagon[body_index] or wagon)
    local flip
    if not push_pull then flip=sample.reversed==true end
    local tx,tz=Sim.xy(id)
    local x,z,dx,dz
    if sample.x then x,z,dx,dz=sample.x-2*tx,sample.z-2*tz,sample.dx,sample.dz
    elseif not sample.wormhole then x,z,dx,dz=diagonal(id,td,f) end
    if x==nil then x,z,dx,dz=stock(td,f) end
    local level,tilt
    if surface then level,tilt=surface(id,td,f,{wormhole=sample.wormhole}) end
    local flipped=rear~=backing
    return {x=2*tx+.5+x,y=(level or fallback(id))+models[kind].offset,z=2*tz+.5+z},
      {x=(tilt or 0)*(flipped and 1 or -1),y=math.pi-math.atan2(dx,dz)+(flipped and math.pi or 0),z=0},
      kind,body_index,flip
  end
end
