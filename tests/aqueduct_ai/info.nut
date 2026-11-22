class AqueductProbeInfo extends AIInfo {
    function GetAuthor()      { return "LuanTTD test suite"; }
    function GetName()        { return "AqueductProbe"; }
    function GetDescription() { return "Compare stock water bridge construction on seeded dry valleys."; }
    function GetVersion()     { return 1; }
    function GetDate()        { return "2026-11-22"; }
    function CreateInstance() { return "AqueductProbe"; }
    function GetShortName()   { return "AQQA"; }
    function GetAPIVersion()  { return "14"; }
}
RegisterAI(AqueductProbeInfo());
