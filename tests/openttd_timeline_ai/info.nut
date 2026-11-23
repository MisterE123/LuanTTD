class TimelineInfo extends AIInfo {
    function GetAuthor()      { return "LuanTTD test suite"; }
    function GetName()        { return "TimelineProbe"; }
    function GetDescription() { return "Read the stock catalogue without building or spending."; }
    function GetVersion()     { return 1; }
    function GetDate()        { return "2026-11-23"; }
    function CreateInstance() { return "TimelineProbe"; }
    function GetShortName()   { return "TLQA"; }
    function GetAPIVersion()  { return "16"; }
}
RegisterAI(TimelineInfo());
