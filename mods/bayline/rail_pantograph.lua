-- Pure native 3D presentation geometry. OpenTTD supplies stock height,
-- vehicle pose and bridge state; this never changes power or motion.
local P={heel={x=0,y=.580,z=.053}, shoe_run=-.022, nominal_extension=.204, half_contact=.074}
local epsilon=1e-8
local function number(x)
  return type(x)=="number" and x==x and math.abs(x)<math.huge
end

-- Find the shoe's contact with an already-qualified wire centerline.
-- Measure u along the horizontal track axis; y is world height.
-- a=(u,y) is the contact point at zero extension of the moving art,
-- and d=(du,dy) is its displacement per unit of collector extension,
-- in those same world coordinates. The three values returned are the
-- extension and the exact shoe contact u/y; the entire vehicle is not
-- translated or rescaled. Segment rows are {u0,y0,u1,y1} and ordered.
function P.contact(segments,u,y,du,dy,min_extension,max_extension)
  if type(segments)~="table" or #segments==0 or #segments>8 or
      not number(u) or not number(y) or not number(du) or not number(dy) or dy<=0 or
      not number(min_extension) or not number(max_extension) or
      min_extension<0 or max_extension<=min_extension then return nil,"INVALID_CONTACT_INPUT" end
  local previous,extension,out_u,out_y
  for _,s in ipairs(segments) do
    if type(s)~="table" or not number(s[1]) or not number(s[2]) or not number(s[3]) or
        not number(s[4]) or s[3]<=s[1] or previous and
            (math.abs(s[1]-previous[3])>epsilon or math.abs(s[2]-previous[4])>epsilon) then
      return nil,"DISCONTINUOUS_WIRE"
    end
    local pitch=(s[4]-s[2])/(s[3]-s[1])
    local rise=dy-pitch*du
    -- No behavior is inferred for a pantograph axis parallel to a wire;
    -- outside a locally monotone fit the geometric mount is unsupported.
    if rise<=epsilon then return nil,"UNSUPPORTED_WIRE_ANGLE" end
    local reach=(s[2]+pitch*(u-s[1])-y)/rise
    local at=u+reach*du
    if at>=s[1]-epsilon and at<=s[3]+epsilon and
        reach>=min_extension-epsilon and reach<=max_extension+epsilon then
      if extension and math.abs(extension-reach)>epsilon then return nil,"AMBIGUOUS_CONTACT" end
      extension=math.max(min_extension,math.min(max_extension,reach))
      out_u,out_y=u+extension*du,y+extension*dy
    end
    previous=s
  end
  if extension then return extension,out_u,out_y end
  return nil,"NO_WIRE_CONTACT"
end

-- rotate must be Luanti vector.rotate, the same local/world convention
-- used by ObjectRef:set_rotation. Wire profile is in the principal
-- world coordinate named by axis; side is its perpendicular position.
-- A curved contact is not inferred from this straight-axis adapter.
function P.mount(segments,axis,side,body,rotation,rotate,min_extension,max_extension)
  if axis~="x" and axis~="z" or not number(side) or type(body)~="table" or
      not number(body.x) or not number(body.y) or not number(body.z) or type(rotation)~="table" or
      not number(rotation.x) or not number(rotation.y) or not number(rotation.z) or type(rotate)~="function" then
    return nil,"INVALID_CONTACT_INPUT"
  end
  local across=axis=="x" and "z" or "x"
  local foot=rotate(P.heel,rotation)
  local inset=rotate({x=0,y=0,z=P.shoe_run},rotation)
  local normal=rotate({x=0,y=1,z=0},rotation)
  local reach,u,y=P.contact(segments,body[axis]+foot[axis]+inset[axis],
    body.y+foot.y+inset.y,normal[axis],normal.y,min_extension,max_extension)
  if not reach then return nil,u end
  local v=body[across]+foot[across]+inset[across]+reach*normal[across]
  if math.abs(v-side)>P.half_contact then return nil,"CONTACT_OUTSIDE_SHOE" end
  local touching={y=y,[axis]=u,[across]=v}
  return {extension=reach,scale_y=reach/P.nominal_extension,
    heel={x=body.x+foot.x,y=body.y+foot.y,z=body.z+foot.z},world_contact=touching}
end
return P
