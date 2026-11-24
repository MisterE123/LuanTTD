-- One optional static prop fits the unused side of a fixed-wing hangar.
-- These tile references follow the current country's and city's FTA only.
-- No airport traffic, reservations, cargo, or persistent aircraft are created.
return function(Small,City)
  local H={}
  local layouts={country=Small.hangar,city=City.hangar}
  H.name="luanttd_core:airport_hangar_ga"
  H.x,H.z=1,0 -- unused subtile beside the original overlay at (0,0)
  H.collision={{-.142,-.49,.044,.035,-.31,.768},
    {-.38,-.288,.318,.27,-.235,.522}}
  -- Fitted to the opaque wall panels and supporting footings on the
  -- two actual mesh tiles. Their +Z portal and the taxi lane stay open.
  H.walls={
    small_airport_2_0={{.87,-.5,-.438,1.034,.426,1.204}},
    small_airport_3_0={{1.30,-.5,-.438,1.461,.426,1.204}},
    city_airport_4_0={{.759,-.49,-.418,.937,.418,.495}},
    city_airport_5_0={{1.305,-.49,-.418,1.481,.418,1.30}},
  }
  function H.has(field)
    local loc=field and layouts[field.layout or "country"]
    return loc and field.airport and loc.x==field.x and loc.z==field.z
  end
  local boxes={
    {.80,.035,.024,1.09,.255,.777}, -- fuselage, spinner, tail surfaces
    {.615,.206,.309,1.275,.265,.531}, -- high wing
    {.807,0,.464,1.081,.083,.551}, -- wheels and struts
  }
  local function hit_box(eye,ray,b)
    local enter,leave=0,3
    for i,k in ipairs({"x","y","z"}) do
      local o,d=eye[k],ray[k]
      if math.abs(d)<1e-7 then
        if o<b[i] or o>b[i+3] then return end
      else
        local p,q=(b[i]-o)/d,(b[i+3]-o)/d
        enter,leave=math.max(enter,math.min(p,q)),math.min(leave,math.max(p,q))
        if enter>leave then return end
      end
    end
    return enter>0 and enter or nil
  end
  local function through_open_portal(eye,ray)
    -- +Z is the live apron/taxi lane entrance. A player outside the rear
    -- or flank may not interact through a wall.
    if eye.z<-.40 then return false end
    if eye.z<=1.28 then
      return eye.x>-.44 and eye.x<1.329 and eye.y>=0 and eye.y<.73
    end
    if ray.z>=-1e-7 then return false end
    local t=(1.28-eye.z)/ray.z
    local x,y=eye.x+t*ray.x,eye.y+t*ray.y
    return t<3 and x>-.43 and x<1.329 and y>=0 and y<.73
  end
  function H.hit(eye,ray)
    if not through_open_portal(eye,ray) then return end
    local t
    for _,b in ipairs(boxes) do
      local s=hit_box(eye,ray,b)
      if s and (not t or s<t) then t=s end
    end
    return t
  end
  function H.pick(p,Sim,get,visible)
    local eye=p:get_pos()
    if not eye then return end
    local props=p:get_properties()
    eye={x=eye.x,y=eye.y+(props.eye_height or 1.47),z=eye.z}
    local dir=p:get_look_dir()
    local x,z=math.floor((eye.x+.5)/2),math.floor((eye.z+.5)/2)
    local best,id,airport=3
    for dz=-2,2 do for dx=-2,2 do
      local tx,tz=x+dx,z+dz
      local tile=Sim.id(tx,tz)
      local t=tile and get(tile)
      if t and H.has(t.airfield) and visible(tx*2+H.x,t.h+1,tz*2+H.z) then
        local at=H.hit({x=eye.x-tx*2,y=eye.y-t.h-.509,z=eye.z-tz*2},dir)
        if at and at<best then best,id,airport=at,tile,t.airfield.airport end
      end
    end end
    return id,airport
  end
  return H
end
