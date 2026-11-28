-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD contributors, OpenTTD 16.0-RC1 (07b339c) src/tgp.cpp (TerraGenesis Perlin),
-- core/random_func.cpp; 14.1 coast path retained only for its differential fixture.
-- heightmap.cpp FixSlopes and water_cmd.cpp ConvertGroundTilesIntoWaterTiles.
-- See COPYING.OpenTTD.md. No external height maps or original graphics needed.
return function(Slope)
  local G={}
  local floor,ceil,min,max,abs,sin,sqrt=math.floor,math.ceil,math.min,math.max,math.abs,math.sin,math.sqrt
  local char,byte=string.char,string.byte
  local U32,U31,U16=4294967296,2147483648,65536
  local pi2=math.pi/2
  local function int(n,lo,hi)
    return type(n)=="number" and n>=lo and n<=hi and floor(n)==n
  end
  local function trunc(n) return n<0 and ceil(n) or floor(n) end
  local function clamp(n,lo,hi) return max(lo,min(hi,n)) end
  local function bit(n,i) return floor(n/2^i)%2~=0 end
  local function rot(n,k,m) return floor(n/m)+n%m*k end
  local bx={}
  for a=0,15 do
    for b=0,15 do
      local m,q,t,u=1,0,a,b
      for _=1,4 do
        if t%2~=u%2 then q=q+m end
        t,u,m=floor(t/2),floor(u/2),m*2
      end
      bx[a*16+b]=q
    end
  end
  local function xor(a,b)
    local out,p=0,1
    for _=1,8 do
      out=out+p*bx[a%16*16+b%16]
      a,b,p=floor(a/16),floor(b/16),p*16
    end
    return out
  end
  local xorseed={}
  for i=0,3 do
    local b=floor(0x1234567f/256^i)%256
    local t={}
    xorseed[i]=t
    for a=0,255 do
      t[a]=256^i*(bx[(a%16)*16+b%16]+16*bx[floor(a/16)*16+floor(b/16)])
    end
  end
  function G.next_random(s)
    local a,b=s[1],s[2]
    local x=xorseed[0][b%256]+xorseed[1][floor(b/256)%256]+xorseed[2][floor(b/65536)%256]
      +xorseed[3][floor(b/16777216)]
    s[1]=(a+rot(x,33554432,128)+1)%U32
    s[2]=(rot(a,536870912,8)-1)%U32
    return s[2]
  end
  -- New temperate game startup before GenerateLandscape: StartupEconomy
  -- draws once to initialize fluctuation. Script randomizers seed from a copy.
  function G.startup_rng(seed)
    assert(int(seed,0,U32-1),"TerraGenesis requires an explicit uint32 seed")
    local state={seed,seed}
    G.next_random(state)
    return state
  end
  local function random_height(s,a)
    -- RandomRange uses the high half of an unsigned 64-bit product. This
    -- legal range never exceeds 2^53, and logical >>6 narrowed to int16
    -- equals signed floor /64 for the amplitude range in stock TGP.
    return floor((floor(G.next_random(s)*(2*a+1)/U32)-a)/64)
  end
  local row_enc={}
  for i=0,255 do row_enc[i]=char(i) end
  local function pack16(a,n,out)
    for i=1,n do
      local v=a[i]%U16
      out[i]=row_enc[v%256]..row_enc[floor(v/256)]
    end
    return table.concat(out,"",1,n)
  end
  local function get16(row,x)
    local lo,hi=byte(row,x*2-1,x*2)
    local v=lo+256*hi
    return v<32768 and v or v-U16
  end
  local max_heights={
    {3,3,3,3,4,5,7},{5,7,8,9,14,19,31},{8,9,10,15,23,37,61},
    {10,11,17,19,49,63,73},{12,19,25,31,67,75,87},
  }
  local amps={
    {16000,5600,1968,688,240,16,16},{24000,12800,6400,2700,1024,128,16},
    {32000,19200,12800,8000,3200,256,64},{48000,24000,19200,16000,8000,512,320},
  }
  local extr={3.3,2.8,2.3,1.8}
  local function get_max_height(p)
    if p.terrain_type==5 then return 16*(p.custom_terrain_type+1)-1 end
    local h=max_heights[p.terrain_type+1][min(p.lx,p.lz)-5]
    if p.map_height_limit~=0 then h=min(h,p.map_height_limit) end
    return 16*h
  end
  local function amplitude(frequency,p,maxh)
    local ix=frequency-3
    local a=amps[p.tgen_smoothness+1][max(0,ix)+1]
    if ix>=0 then return a end
    local hr=256
    repeat
      a=trunc(extr[p.tgen_smoothness+1]*a)
      hr,ix=hr*2,ix+1
    until ix==0
    return clamp(trunc((maxh-hr)/hr),0,1)*a
  end
  local function raw_perlin(p,maxh,state)
    local rows,pack=nil,{}
    local a,b,scratch={},{},{}
    for f=max(10-min(p.lx,p.lz),0),9 do
      local amp=amplitude(f,p,maxh)
      if amp~=0 then
        local step=2^(9-f)
        local nx,nz=p.width/step+1,p.depth/step+1
        local next_rows={}
        if not rows then
          for z=1,nz do
        if p.pulse and z%16==0 then p.pulse() end
            for x=1,nx do scratch[x]=random_height(state,amp) end
            next_rows[z]=pack16(scratch,nx,pack)
          end
        else
          local function interp(row,out)
            for x=1,nx,2 do out[x]=get16(row,(x+1)/2) end
            for x=2,nx-1,2 do out[x]=trunc((out[x-1]+out[x+1])/2) end
          end
          interp(rows[1],a)
          for z=1,nz do
        if p.pulse and z%16==0 then p.pulse() end
            -- In source, horizontal and vertical interpolation both complete
            -- before noise is added. Keep two unperturbed even lattice rows.
            if z%2==0 then
              interp(rows[z/2+1],b)
              for x=1,nx do scratch[x]=trunc((a[x]+b[x])/2)+random_height(state,amp) end
              a,b=b,a
            else
              for x=1,nx do scratch[x]=a[x]+random_height(state,amp) end
            end
            next_rows[z]=pack16(scratch,nx,pack)
          end
        end
        rows=next_rows
      end
    end
    return rows
  end
  local function each_row(rows,p,transform)
    local n,a,buf=p.width+1,{},{}
    for z=1,p.depth+1 do
        if p.pulse and z%16==0 then p.pulse() end
      local row=rows[z]
      for x=1,n do a[x]=transform(get16(row,x),x,z) end
      rows[z]=pack16(a,n,buf)
    end
  end
  local water_fractions={70,170,270,420}
  local function adjust_water(rows,p,maxh)
    local hist,lo,hi={},32767,-32768
    for z=1,p.depth+1 do
        if p.pulse and z%16==0 then p.pulse() end
      local row=rows[z]
      for x=1,p.width+1 do
        local h=get16(row,x)
        hist[h]=(hist[h] or 0)+1
        lo,hi=min(lo,h),max(hi,h)
      end
    end
    local percent=water_fractions[p.quantity_sea_lakes+1] or floor(p.custom_sea_level*1024/100)
    local desired=floor(percent*p.width*p.depth/1024)
    local water,sea=0,lo
    while sea<hi do
      water=water+(hist[sea] or 0)
      if water>=desired then break end
      sea=sea+1
    end
    assert(hi>sea,"TerraGenesis source normalization requires nonconstant heights")
    each_row(rows,p,function(v)
      return clamp(trunc(maxh*(v-sea)/(hi-sea))+16,0,maxh-1)
    end)
  end
  -- Low 31 bits of the stock signed-long coast polynomial. Split products
  -- into 16-bit pieces so Lua doubles cannot lose low bits to rounding.
  local function mul31(a,b)
    local al,bl=a%U16,b%U16
    return (al*bl+((floor(a/U16)*bl+floor(b/U16)*al)%32768)*U16)%U31
  end
  local function coast_noise(seed,x,z,primes,normalize)
    local function integer_noise(i,j,prime)
      local n=(i+j*prime+seed)%U31
      n=xor(n,(n*8192)%U31)
      local result=(mul31(n,(mul31(mul31(n,n),15731)+789221)%U31)+1376312589)%U31
      return 1-result/1073741824
    end
    local total,frequency,amplitude,weight=0,1,1,0
    for i=0,5 do
      local fx,fz=x*frequency/64,z*frequency/64
      local u,v=trunc(fx),trunc(fz)
      local ax,az=fx-u,fz-v
      local a,b=integer_noise(u,v,primes[2]),integer_noise(u+1,v,primes[2])
      local c,d=integer_noise(u,v+1,primes[2]),integer_noise(u+1,v+1,primes[2])
      local ab,cd=a+ax*(b-a),c+ax*(d-c)
      total=total+(ab+az*(cd-ab))*(normalize and amplitude or primes[1]^i)
      weight=weight+amplitude
      frequency,amplitude=frequency*2,amplitude*primes[1]
    end
    return normalize and total/weight or total
  end
  local slopes_coast={
    {{.9,53}, .25,5,{.35,179},1,12},
    {{.85,71},.25,6,{.35,193},.75,12},
    {{.85,101},.3,6,{.45,67},.75,8},
    {{.9,167},.4,5,{.4,211},.7,9},
  }
  local function coast_lines(rows,p,borders)
    if borders==0 then return end
    local w,h=p.width,p.depth
    local smallest=min(w,h)
    local jagged=min(12+floor(smallest*smallest/4096)+min(max(w,h)/smallest,16),64)
    local smooth=min(floor(smallest/32),32)
    -- BorderFlag order: NE at x=0, SE at z=h, SW at x=w, NW at z=0.
    local primes={{67,179,53},{101,193,71},{199,67,101},{179,211,167}}
    local function depth(i,t)
      local c=primes[i]
      return 2+smooth*(1+coast_noise(p.seed,t,t,{.2,c[1]},true))
        +jagged*abs(coast_noise(p.seed,t,t,{.5,c[2]},true))
        +8*abs(coast_noise(p.seed,t,t,{.8,c[3]},true))
    end
    local function cutoff(i,x,z,y,q)
      local c=slopes_coast[i]
      local v=abs((coast_noise(p.seed,x,z,c[1])+c[2])*c[3]+(coast_noise(p.seed,y,q,c[4])+c[5])*c[6])
      local small=min(p.lx,p.lz)
      local base=floor(small*small/64)
      v=max(base+v,base+4-v)
      return small<8 and v>5 and v/1.5 or v
    end
    local z2,z3=floor(h/2),floor(h/3)
    local north,south={},{}
    for x=0,w do
      north[x]=bit(borders,3) and (p.legacy and cutoff(4,x,z2,x,z3) or depth(4,x)) or 0
      south[x]=bit(borders,1) and h-1-(p.legacy and cutoff(2,x,z3,x,z3) or depth(2,x)) or h
    end
    local a,buf={},{}
    for z=0,h do
        if p.pulse and z%16==0 then p.pulse() end
      local left=bit(borders,0) and (p.legacy and cutoff(1,h-z,z,z,z) or depth(1,z)) or 0
      local right=bit(borders,2) and w-1-(p.legacy and cutoff(3,h-z,z,z,z) or depth(3,z)) or w
      local row=rows[z+1]
      for x=0,w do
        a[x+1]=(x<left or x>right or z<north[x] or z>south[x]) and 0 or get16(row,x+1)
      end
      rows[z+1]=pack16(a,w+1,buf)
    end
  end
  local function smooth_slopes(rows,p,step)
    local w,h=p.width+1,p.depth+1
    local a,buf={},{}
    local function sweep(z1,z2,x1,x2,d)
      local neighbor
      for z=z1,z2,d do
        if p.pulse and z%16==0 then p.pulse() end
        local row,prev=rows[z],32767
        for x=x1,x2,d do
          local current=get16(row,x)
          local side=neighbor and get16(neighbor,x) or current
          local v=min(current,min(prev,side)+step)
          a[x],prev=v,v
        end
        neighbor=pack16(a,w,buf)
        rows[z]=neighbor
      end
    end
    sweep(1,h,1,w,1)
    sweep(h,1,w,1,-1)
  end
  local function smooth_coasts(rows,p,borders)
    if borders==0 then return end
    local w,h=p.width,p.depth
    -- Changes are confined to the coast search plus smoothing depth. A sparse
    -- overlay keeps exact read-after-write order along perpendicular shores.
    local edits={}
    local function valid(x,z) return x>=0 and x<w and z>=0 and z<h end
    local function read(x,z)
      local row=edits[z]
      return (row and row[x]) or get16(rows[z+1],x+1)
    end
    local function soften(x,z,dx,dz)
      for _=1,p.legacy and 35 or 100 do
        if not valid(x,z) or read(x,z)>=16
          or valid(x+dz,z+dx) and read(x+dz,z+dx)>0
          or valid(x-dz,z-dx) and read(x-dz,z-dx)>0 then break end
        x,z=x+dx,z+dz
      end
      local prev=16
      for depth=0,35 do
        if not valid(x,z) then break end
        local h0=read(x,z)
        local v=min(h0,prev+4+depth)
        if v~=h0 then
          local row=edits[z] or {}
          row[x],edits[z]=v,row
        end
        prev,x,z=v,x+dx,z+dz
      end
    end
    for x=0,w-1 do
      if bit(borders,3) then soften(x,0,0,1) end
      if bit(borders,1) then soften(x,h-1,0,-1) end
    end
    for z=0,h-1 do
      if bit(borders,0) then soften(0,z,1,0) end
      if bit(borders,2) then soften(w-1,z,-1,0) end
    end
    local a,buf={},{}
    for z,changes in pairs(edits) do
      local row=rows[z+1]
      for x=0,w do a[x+1]=changes[x] or get16(row,x+1) end
      rows[z+1]=pack16(a,w+1,buf)
    end
  end
  local function sine_transform(rows,p,maxh)
    local lut={}
    for h=0,maxh-1 do
      if h<16 then lut[h]=h
      else
        local t=(h-16)/(maxh-16)
        t=.5*(sin((2*t-1)*pi2)+1)
        lut[h]=clamp(trunc(t*(maxh-16)+16),0,maxh-1)
      end
    end
    each_row(rows,p,function(h) return lut[h] end)
  end
  -- C++ HeightMapCurves intentionally uses IEEE single precision in the
  -- weights/blends. Lua 5.1 has no float pack; emulate normal float values
  -- with one nearest-even mantissa rounding at each source operation.
  local function f32(n)
    if n==0 then return n end
    local m,e=math.frexp(n)
    local y=m*16777216
    local a=floor(y)
    local d=y-a
    if d>.5 or d==.5 and a%2==1 then a=a+1 end
    return math.ldexp(a,e-24)
  end
  local curve_control={
    {0,0,.8,.13,1,.4},
    {0,0,.53,.13,.8,.27,1,.6},
    {0,0,.53,.27,.8,.57,1,.8},
    {0,0,.4,.3,.7,.8,.92,.99,1,.99},
  }
  local function curves(rows,p,maxh,state)
    if p.variety==0 then return end
    local n=2^p.variety
    local factor=f32(sqrt(f32(p.width/p.depth)))
    local sx=clamp(trunc(f32(n*factor)+.5),1,128)
    local sz=clamp(trunc(f32(n/factor)+.5),1,128)
    local c={}
    for i=0,sx*sz-1 do
      local r=G.next_random(state)
      c[i]=(p.legacy and r%4 or floor(r/1073741824))+1
    end
    local mh=maxh-16
    local lookup={}
    for t=1,4 do
      local a,control={},curve_control[t]
      for i=1,#control-2,2 do
        local x1,y1,x2,y2=trunc(control[i]*mh),trunc(control[i+1]*mh),
          trunc(control[i+2]*mh),trunc(control[i+3]*mh)
        for v=x1,x2-1 do a[v]=y1+trunc((v-x1)*(y2-y1)/(x2-x1)) end
      end
      lookup[t]=a
    end
    local function axis(size,sections)
      local a={}
      for i=0,size-1 do
        local f=f32(f32(sections*i/size)+1)
        local u=floor(f)
        local w=f32(2*f32(f-u)-1)
        w=f32(sin(w*pi2))
        w=f32(sin(w*pi2))
        w=f32(.5*f32(w+1))
        a[i+1]={u-1,min(u,sections-1),w,f32(1-w)}
      end
      return a
    end
    local x_axis,z_axis=axis(p.width,sx),axis(p.depth,sz)
    each_row(rows,p,function(h,x,z)
      if h<16 or not x_axis[x] or not z_axis[z] then return h end
      h=h-16
      local X,Z=x_axis[x],z_axis[z]
      local z1,z2=sx*Z[1],sx*Z[2]
      local a,b=lookup[c[X[1]+z1]][h],lookup[c[X[1]+z2]][h]
      local d,e=lookup[c[X[2]+z1]][h],lookup[c[X[2]+z2]][h]
      local first=f32(f32(a*Z[4])+f32(b*Z[3]))
      local second=f32(f32(d*Z[4])+f32(e*Z[3]))
      return 16+trunc(f32(f32(first*X[4])+f32(second*X[3])))
    end)
  end
  local function integer_rows(rows,p,maxh,state)
    local buf,rock_rows={},{}
    local height=floor(maxh/16)
    -- GenerateWorld resolves the automatic construction ceiling before FixSlopes.
    local cap=p.map_height_limit==0 and max(30,min(255,height+15)) or p.map_height_limit
    local function inner(x,z)
      return x<p.width and z<p.depth and (not p.freeform_edges or x>1 and z>1)
    end
    -- The extra interpolation fringe is not transferred into OpenTTD's
    -- map. WorldStorage uses the repeated far-edge corner for its fringe.
    rows[p.depth+1]=nil
    for z=1,p.depth do
        if p.pulse and z%16==0 then p.pulse() end
      local row=rows[z]
      for x=1,p.width do buf[x]=row_enc[clamp(floor(get16(row,x)/16),0,height)] end
      rows[z]=table.concat(buf)
    end
    -- GenerateLandscape::FixSlopes after the integer height transfer.
    local function sweep(z1,z2,x1,x2,d)
      local row_new,rock_bits,rock_bytes={},{},{}
      local nbytes=ceil(p.width/8)
      local neighbor
      for z=z1,z2,d do
        if p.pulse and z%16==0 then p.pulse() end
        local row,prev=rows[z],255
        local rock_row=rock_rows[z]
        local changed=false
        for x=x1,x2,d do
          local a=byte(row,x)
          local b=neighbor and byte(neighbor,x) or 255
          local low=min(prev,b)
          local v=min(a,low+1)
          -- RC1 heightmap.cpp FixSlopes draws even on a failed rock chance;
          -- only physical lowered inner tiles consume a draw, in sweep order.
          if not p.legacy and v~=a and inner(x,z)
              and floor(G.next_random(state)*cap/U32)<=low then
            local i,k=floor((x-1)/8)+1,(x-1)%8
            local bits=rock_bits[i] or (rock_row and byte(rock_row,i)) or 0
            rock_bits[i]=bit(bits,k) and bits or bits+2^k
            changed=true
          end
          row_new[x],prev=row_enc[v],v
        end
        if changed then
          for i=1,nbytes do
            rock_bytes[i]=row_enc[rock_bits[i] or (rock_row and byte(rock_row,i)) or 0]
            rock_bits[i]=nil
          end
          rock_rows[z]=table.concat(rock_bytes)
        end
        neighbor=table.concat(row_new)
        rows[z]=neighbor
      end
    end
    sweep(1,p.depth,1,p.width,1)
    sweep(p.depth,1,p.width,1,-1)
    return rows,rock_rows
  end
  local CLEAR,WATER,VOID=0,6,7
  local flood={[0]=170,10,130,2,160,0,128,131,40,8,0,14,32,56,224}
  local dx,dz={[0]=-1,-1,-1,0,1,1,1,0},{[0]=-1,0,1,1,1,0,-1,-1}
  local raised={[1]=true,[2]=true,[4]=true,[8]=true}
  function G.describe(word) return word%16,floor(word/16)%16 end
  local sizes={}
  for i=6,12 do sizes[2^i]=i end
  local defaults={terrain_type=1,quantity_sea_lakes=0,tgen_smoothness=1,
    water_borders=15,variety=0,custom_terrain_type=15,custom_sea_level=1,map_height_limit=0}
  local fields={"terrain_type","quantity_sea_lakes","tgen_smoothness","water_borders","variety",
    "custom_terrain_type","custom_sea_level","map_height_limit"}
  local function options(opts)
    assert(type(opts)=="table","TerraGenesis options required")
    local p={width=opts.width,depth=opts.depth,seed=opts.seed,freeform_edges=opts.freeform_edges~=false,
      legacy=opts.differential_version=="14.1"}
    p.lx,p.lz=sizes[p.width],sizes[p.depth]
    assert(p.lx and p.lz,"TerraGenesis stock axes are powers of two, 64–4096")
    assert(int(p.seed,0,U32-1),"TerraGenesis requires an explicit uint32 seed")
    assert(opts.freeform_edges==nil or type(opts.freeform_edges)=="boolean","Invalid freeform edges flag")
    assert(opts.landscape==nil or opts.landscape=="temperate","Only the temperate GenerateLandscape stage is mounted")
    for _,k in ipairs(fields) do p[k]=opts[k]==nil and defaults[k] or opts[k] end
    assert(int(p.terrain_type,0,5) and int(p.quantity_sea_lakes,0,4)
      and int(p.tgen_smoothness,0,3) and int(p.water_borders,0,16) and int(p.variety,0,5)
      and int(p.custom_terrain_type,1,255) and int(p.custom_sea_level,1,90)
      and (p.map_height_limit==0 or int(p.map_height_limit,15,255)),"TerraGenesis settings out of range")
    return p
  end
  function G.generate(opts)
    local p=options(opts)
    local work,label=0,"Shaping the landscape"
    local function mark(f,name)
      work,label=f,name or label
      if opts.progress then opts.progress(work,label) end
    end
    if opts.progress then p.pulse=function() opts.progress(work,label) end end
    local w,h=p.width,p.depth
    local starting=opts.rng_state
    assert(starting==nil or (type(starting)=="table" and int(starting[1],0,U32-1)
      and int(starting[2],0,U32-1)),"Invalid OpenTTD RNG state")
    local state={p.seed,p.seed}
    if starting then state[1],state[2]=starting[1],starting[2] end
    local start_a,start_b=state[1],state[2]
    local maxh=get_max_height(p)
    local raw=raw_perlin(p,maxh,state)
    mark(.25,"Sculpting coastlines")
    local borders=p.freeform_edges and p.water_borders or 15
    adjust_water(raw,p,maxh)
    if borders==16 then borders=G.next_random(state)%16 end
    local roughness=7+3*p.tgen_smoothness
    coast_lines(raw,p,borders)
    smooth_slopes(raw,p,roughness)
    mark(.55,"Smoothing slopes and coasts")
    smooth_coasts(raw,p,borders)
    smooth_slopes(raw,p,roughness)
    mark(.74,"Finishing elevation")
    sine_transform(raw,p,maxh)
    curves(raw,p,maxh,state)
    if p.legacy then smooth_slopes(raw,p,16) end
    mark(.90,"Finishing shared corners")
    local rows,rock_rows=integer_rows(raw,p,maxh,state)
    local id={p.legacy and "ott14.1-tgp-temperate-v1" or "ott16.0-RC1-tgp-temperate-v1",w.."x"..h,("%08x"):format(p.seed),p.freeform_edges and 1 or 0,("%08x%08x"):format(start_a,start_b)}
    for _,field in ipairs(fields) do id[#id+1]=p[field] end
    id=table.concat(id,"/")
    local function is_void(x,z) return x==w or z==h or p.freeform_edges and (x==1 or z==1) end
    local function corners(x,z)
      local v=min(z+1,h)
      local u=min(x+1,w)
      local r,s=rows[z],rows[v]
      return byte(r,x),byte(r,u),byte(s,x),byte(s,u)
    end
    local V={width=w,depth=h,seed=p.seed,freeform=p.freeform_edges,water_borders=borders,
      estimated_max_height=floor(maxh/16),rng_after=state,base_id=id}
    function V.corner(x,z)
      if int(x,1,w+1) and int(z,1,h+1) then return byte(rows[min(z,h)],min(x,w)) end
    end
    function V.tile(x,z)
      if not int(x,1,w) or not int(z,1,h) then return nil end
      if is_void(x,z) then return VOID end
      local s,b=Slope.classify(corners(x,z))
      local r=rock_rows[z]
      local ground=r and bit(byte(r,floor((x-1)/8)+1),(x-1)%8) and 512 or CLEAR
      if b~=0 then return ground end
      if s==0 then return WATER+16 end
      if raised[s] then return WATER+32 end
      local directions=flood[s%16]
      for d=0,7 do
        if directions%2~=0 then
          local idx=((z-1+dz[d])*w+x-1+dx[d])%(w*h)
          local u,v=idx%w+1,floor(idx/w)+1
          local other=Slope.classify(corners(u,v))%16
          if other==0 or raised[other] or is_void(u,v) then return WATER+32 end
        end
        directions=floor(directions/2)
      end
      return ground
    end
    function V.storage_options()
      return {seed=p.seed,base_id=id,corner=function(_,x,z)return V.corner(x,z) end,
        tile=function(_,x,z)return V.tile(x,z) end}
    end
    function V.generation_footprint()
      return {height_bytes=w*h, octave_scratch_rows=3,sweep_scratch_rows=1,
        packed_fixed_bytes=(w+1)*(h+1)*2,coast_edit_rim=p.legacy and 71 or 136}
    end
    return V
  end
  return G
end
