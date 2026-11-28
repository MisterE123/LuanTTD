-- OpenTTD 16.0-RC1 native seed 1751: Normal terrain, town, river and
-- industry settings, from the paid bus / Wood / Goods corridor. At the
-- end of source tick 12602, Company 0 builds Country airports at (43,52)
-- and (47,93), purchases Coleman Count, adds both stop orders (origin
-- first), and starts the aircraft. Read after the normal landscape
-- callback. The suffix ends on the first touchdown, before Brake risk.
return {
  first=12598,build=12602,last=14166,rng=572996178,motion=1423277238,
  sample={
    [12603]={741,835,33,6,4,1,3,2,1,0,5,0},
    [12607]={741,835,33,54,36,65,3,2,1,0,5,0},
    [12735]={720,855,33,0,28,1,7,2,2,2,5,1},
    [12736]={720,855,33,0,28,1,7,10,1,2,5,0},
    [12806]={734,859,33,200,76,16,5,10,1,2,5,0},
    [12969]={695,872,33,473,80,2,1,12,8,8,5,0},
    [13059]={613,872,197,473,24,14,1,14,17,17,6,0},
    [14165]={813,1528,34,473,156,144,1,15,11,10,6,0},
    [14166]={812,1528,33,473,160,6,1,16,11,11,6,0},
  },
  economy={tick=12607,id=5,reliability=63946,chance=1,counter=0},
  new_mail={tick=12806,station=5,rng={468944850,2013082287}},
}
