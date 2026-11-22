class YAPFProbe extends AIController {
    function Require(ok, message) {
        if (!ok) throw message + ": " + AIError.GetLastErrorString();
    }

    function FindFlat(in_y) {
        for (local y=in_y; y<in_y+24; y++) {
            for (local x=5; x<AIMap.GetMapSizeX()-10; x++) {
                local ok=true;
                local h=AITile.GetMinHeight(AIMap.GetTileIndex(x,y));
                for (local dy=-1; dy<=2 && ok; dy++) {
                    for (local dx=0; dx<=7 && ok; dx++) {
                        local tile=AIMap.GetTileIndex(x+dx,y+dy);
                        ok=AITile.IsBuildable(tile) && AITile.GetSlope(tile)==AITile.SLOPE_FLAT
                           && AITile.GetMinHeight(tile)==h;
                    }
                }
                if (ok) return [x,y];
            }
        }
        throw "No flat construction area in seeded map";
    }
    function At(origin,x,y) {
        return AIMap.GetTileIndex(origin[0]+x,origin[1]+y);
    }
    function Build(origin,with_stop) {
        local a=At(origin,0,0), j1=At(origin,1,0), j2=At(origin,5,0);
        local start=At(origin,0,-1), dest=At(origin,6,0);
        local bend1=At(origin,1,1), bend2=At(origin,5,1), mid=At(origin,3,0);
        Require(AIRoad.BuildRoadFull(a,j2),"Build main road");
        Require(AIRoad.BuildRoad(j1,bend1),"Build first turn");
        Require(AIRoad.BuildRoad(bend1,bend2),"Build alternate road");
        Require(AIRoad.BuildRoad(bend2,j2),"Build last turn");
        Require(AIRoad.BuildRoadDepot(start,a),"Build depot");
        Require(AIRoad.BuildRoadFull(a,At(origin,0,1)),"Connect depot curb");
        Require(AIRoad.AreRoadTilesConnected(start,a),"Connect depot approach");
        Require(AIRoad.BuildRoadStation(dest,j2,AIRoad.ROADVEHTYPE_BUS,AIStation.STATION_NEW),
                "Build ordered bay stop");
        if (with_stop) {
            Require(AIRoad.BuildDriveThroughRoadStation(mid,At(origin,4,0),
                AIRoad.ROADVEHTYPE_BUS,AIStation.STATION_NEW),"Build unordered through stop");
        }

        local engines=AIEngineList(AIVehicle.VT_ROAD);
        local engine=-1;
        for (local e=engines.Begin();!engines.IsEnd();e=engines.Next()) {
            local cargo=AIEngine.GetCargoType(e);
            if (AICargo.HasCargoClass(cargo,AICargo.CC_PASSENGERS)) { engine=e;break; }
        }
        Require(engine>=0,"Find a stock bus");
        local v=AIVehicle.BuildVehicle(start,engine);
        Require(AIVehicle.IsValidVehicle(v),"Buy bus");
        Require(AIOrder.AppendOrder(v,dest,AIOrder.OF_NON_STOP_INTERMEDIATE),"Order to destination");
        Require(AIVehicle.StartStopVehicle(v),"Dispatch");
        AILog.Info("YAPF_DISPATCH "+(with_stop?"stop":"plain"));
        local observed=null, previous=-1, path="";
        for (local tick=0;tick<2600;tick++) {
            this.Sleep(1);
            local tile=AIVehicle.GetLocation(v);
            if (tile!=previous) {
                local x=AIMap.GetTileX(tile)-origin[0], y=AIMap.GetTileY(tile)-origin[1];
                path+=x+","+y+" ";
                previous=tile;
            }
            if (tile==mid) observed="straight";
            if (tile==At(origin,3,1)) observed="detour";
            if (tile==dest) {
                Require(observed!=null,"Arrived without crossing either branch");
                AILog.Info("YAPF_RESULT "+(with_stop?"stop":"plain")+" "+observed+" "+path);
                return;
            }
        }
        throw "Stock bus never arrived; last path "+path;
    }
    function Start() {
        this.SetCommandDelay(1);
        AIRoad.SetCurrentRoadType(AIRoad.ROADTYPE_ROAD);
        Build(FindFlat(5),false);
        Build(FindFlat(34),true);
        AILog.Info("YAPF_DONE");
        while (true) this.Sleep(1000);
    }
}
