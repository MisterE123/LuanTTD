class TimelineProbe extends AIController {
    function Start() {
        AILog.Info("TIMELINE_YEAR " + AIDate.GetYear(AIDate.GetCurrentDate()));
        foreach (mode in [AIVehicle.VT_RAIL, AIVehicle.VT_ROAD, AIVehicle.VT_WATER, AIVehicle.VT_AIR]) {
            local list = AIEngineList(mode);
            for (local id = list.Begin(); !list.IsEnd(); id = list.Next()) {
                if (!AIEngine.IsBuildable(id)) continue;
                local name = AIEngine.GetName(id);
                AILog.Info("TIMELINE_ENGINE " + mode + " " + id + " " + AIEngine.GetCargoType(id) + " " + name);
            }
        }
        local cargo = AICargoList();
        for (local id = cargo.Begin(); !cargo.IsEnd(); id = cargo.Next())
            AILog.Info("TIMELINE_CARGO " + id + " " + AICargo.GetCargoLabel(id) + " " + AICargo.GetName(id));
        local types = AIIndustryTypeList();
        for (local id = types.Begin(); !types.IsEnd(); id = types.Next())
            AILog.Info("TIMELINE_INDUSTRY " + id + " " + AIIndustryType.GetName(id));
        local built = AIIndustryList();
        local seen = {};
        for (local id = built.Begin(); !built.IsEnd(); id = built.Next()) {
            local kind = AIIndustry.GetIndustryType(id);
            if (!(kind in seen)) { seen[kind] <- true; AILog.Info("TIMELINE_INITIAL_SITE " + kind); }
        }
        local rail = AIRailTypeList();
        for (local id = rail.Begin(); !rail.IsEnd(); id = rail.Next())
            AILog.Info("TIMELINE_RAILTYPE " + id + " " + AIRail.GetName(id));
        local roads = AIRoadTypeList(AIRoad.ROADTRAMTYPES_ROAD);
        for (local id = roads.Begin(); !roads.IsEnd(); id = roads.Next())
            AILog.Info("TIMELINE_ROADTYPE " + id + " " + AIRoad.GetName(id));
        local bridges = AIBridgeList();
        for (local id = bridges.Begin(); !bridges.IsEnd(); id = bridges.Next())
            AILog.Info("TIMELINE_BRIDGE " + id + " " + AIBridge.GetName(id, AIVehicle.VT_ROAD));
        foreach (type in [AIAirport.AT_SMALL, AIAirport.AT_LARGE, AIAirport.AT_HELIPORT,
                         AIAirport.AT_METROPOLITAN, AIAirport.AT_INTERNATIONAL, AIAirport.AT_COMMUTER,
                         AIAirport.AT_HELIDEPOT, AIAirport.AT_INTERCON, AIAirport.AT_HELISTATION]) {
            if (AIAirport.IsValidAirportType(type))
                AILog.Info("TIMELINE_AIRPORT " + type + " " + AIAirport.GetAirportWidth(type) + " " + AIAirport.GetAirportHeight(type));
        }
        AILog.Info("TIMELINE_DONE");
        while (true) this.Sleep(1000);
    }
}
