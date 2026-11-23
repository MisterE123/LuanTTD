-- Engine presentation only. Never advances a train, creates a persistent
-- spawner, or uses the authoritative random number stream.
return function(core,model,rotate)
  local V={}
  local clocks,now={},0
  local texture="bl_rail_steam.png"
  local steam_interval={.26,.34,.46,.54}
  local steam={name=texture,alpha_tween={.90,.72,0},scale_tween={.60,1.52}}
  local diesel={name=texture.."^[colorize:#535258:215",alpha_tween={.37,.24,0},scale_tween={.62,1.28}}
  function V.render(rows,dt)
    if not rotate then return end
    now=now+math.min(dt,.2) -- no plume bursts after a focus loss or stall
    local keep,players={},nil
    local budget={}
    for key,row in pairs(rows) do
      if row.mode=="rail" then
        for _,part in ipairs(row.parts) do
          local profile=model.profiles[part.kind]
          if part.exhaust and profile then
            local id=key..":"..part.body_index
            -- Complete-train projections may overlap vision sectors.
            -- A physical body has one clock, even with multiple outlets.
            if not keep[id] then
              local old=clocks[id] or {serial=0,due=now+.09}
              local p=part.pos
              local last=old.pos
              old.pos,keep[id],clocks[id]=p,true,old
              local flip=old.flip==part.flip
              old.flip=part.flip
              if last and flip and now>=old.due then
                local dx,dz=p.x-last.x,p.z-last.z
                local dist=math.sqrt(dx*dx+dz*dz)
                -- Do not emit around a paused train, teleport, sector
                -- re-entry, or simultaneous snapping of a reversing consist.
                if dist>.002 and dist<.30+18*dt then
                  local interval=profile.diesel and (.86+.85*part.exhaust) or
                    steam_interval[1+math.floor(3*part.exhaust)]
                  old.due,old.serial=now+interval,old.serial+1
                  local a=rotate(profile[1+(old.serial-1)%#profile],part.rotation)
                  local at={x=p.x+a.x,y=p.y+a.y,z=p.z+a.z}
                  local trail=profile.diesel and .115 or .205
                  local side=math.sin(old.serial*2.4)*.09
                  local speed=profile.diesel and .34 or .59
                  local puff={pos=at,velocity={x=.065-trail*dx/dist+side*dz/dist,y=speed,
                      z=.055-trail*dz/dist-side*dx/dist},
                    acceleration={x=.038,y=.19,z=.023},size=profile.diesel and 1.38 or 2.00,
                    expirationtime=profile.diesel and .72 or .98,collisiondetection=false,
                    texture=profile.diesel and diesel or steam}
                  if not players then
                    players={}
                    for _,p in ipairs(core.get_connected_players()) do
                      local q=p:get_pos()
                      if q then players[#players+1]={name=p:get_player_name(),pos=q} end
                    end
                  end
                  for _,v in ipairs(players) do
                    local q,n=v.pos,v.name
                    if (budget[n] or 0)<12 and (q.x-at.x)^2+(q.y-at.y)^2+(q.z-at.z)^2<=38^2 then
                      local emit={playername=n}
                      for k,value in pairs(puff) do emit[k]=value end
                      core.add_particle(emit)
                      budget[n]=(budget[n] or 0)+1
                    end
                  end
                end
              end
            end
          end
        end
      end
    end
    for id in pairs(clocks) do if not keep[id] then clocks[id]=nil end end
  end
  return V
end
