// This file contains your Data Connector logic
section CBSOpenData;

//base settings
CBSBaseURL = "http://opendata.cbs.nl";
ODataApi = CBSBaseURL&"/ODataApi/OData/";
ODataFeed=CBSBaseURL&"/ODataFeed/OData/";
ODataCatalog=CBSBaseURL&"/ODataCatalog/";

//Exported functions
[DataSource.Kind="CBSOpenData", Publish="CBSOpenData.Publish"]
//shared CBSOpenData.Contents = Value.ReplaceType(GetTableData,type function(tableID as Text.Type) as any);
shared CBSOpenData.OpenData = Value.ReplaceType(BuildNavigationTable, type function(thema as Text.Type) as any);

//sample input: arbeid
BuildNavigationTable = (themeInput as text) as table =>
    let
        themes = GetTheme(themeInput)
        ,addTables = Table.AddColumn(themes,"Data", each CreateTableNavigationTableForTheme([ThemeID]))
        ,addItemKind = Table.AddColumn(addTables,"ItemKind", each "Folder")
        ,addItemKind2 = Table.AddColumn(addItemKind,"ItemName",each "Folder")
       ,addIsLeaf = Table.AddColumn(addItemKind2,"IsLeaf", each "false")
        ,changeKey = Table.AddColumn(addIsLeaf, "ThemeID2", each "T"&Text.From([ThemeID]))
        ,removeThemeID = Table.RemoveColumns(changeKey,{"ThemeID"})
        ,NavTable = Table.ToNavigationTable(removeThemeID,{"ThemeID2"},"ThemeTitle","Data","ItemKind","ItemName","IsLeaf")
    in
        NavTable;

//sample input: 15
CreateTableNavigationTableForTheme = (themeID as number) as table =>
    let
        
        tables = GetTablesForTheme(themeID)
        ,nestedjoin1 = Table.NestedJoin(tables,"TableID",GetTables,{"ID"},"NewColumn",JoinKind.LeftOuter)
        ,expanded1 = Table.ExpandTableColumn(nestedjoin1,"NewColumn",{"Identifier","Title"},{"Identifier","Title.1"})
        ,rename1 = Table.RenameColumns(expanded1,{{"Identifier","TableIdentifier2"}})
        ,rename2 = Table.RenameColumns(rename1,{{"Title.1","TableTitle"}})
        ,removeduplicates1 = Table.Distinct(rename2,{"TableIdentifier"})
        ,addItemKind = Table.AddColumn(removeduplicates1,"ItemKind",each "Table")
        ,addIsLeaf = Table.AddColumn(addItemKind,"IsLeaf",each "false")       
        ,addData = Table.AddColumn(addIsLeaf,"Data", each GetTableData([TableIdentifier]))
        ,removedcols = Table.RemoveColumns(addData,{"ID","ThemeID","TableID"})
        ,NavTable = Table.ToNavigationTable(addData,{"TableIdentifier"},"TableTitle","Data","ItemKind","ItemKind","IsLeaf")
        in NavTable;

GetTheme = (themeInput as text) =>
    let
    Source = OData.Feed(ODataCatalog &"Themes")
    ,removed1 = Table.RemoveColumns(Source,{"Language", "Catalog", "Number", "ParentID"})
    ,filtered = Table.SelectRows(removed1, each Text.Contains([Title], themeInput))
    ,renamed1 = Table.RenameColumns(filtered,{{"ID","ThemeID"},{"Title","ThemeTitle"}})
in
    renamed1;

GetTablesForTheme = (themeID as number) =>
    let
        S = GetTables_Themes()
        ,R = Table.SelectRows(S,each [ThemeID] = themeID)
    in R;

GetTables_Themes= ()=>
    let
    Source = OData.Feed(ODataCatalog&"Tables_Themes")
in
    Source;

GetTables = () =>
    let
    Source = OData.Feed(ODataCatalog&"Tables")
in
    Source;

//sample input: 83294NED
GetTableData = (tableID as text) =>
    let
        Source = OData.Feed(ODataFeed&tableID)
        ,my_table = Source{[Name="TypedDataSet",Signature="table"]}[Data]
        ,unpivoted = Table.Unpivot(my_table, List.Distinct(GetDimensions(tableID)[Key]), "Attribute", "Value")
        ,merged = Table.NestedJoin(unpivoted,{"Attribute", "Value"},GetDimensions(tableID),{"Key", "Dimension.Key"},"NewColumn",JoinKind.LeftOuter)
        ,expanded = Table.ExpandTableColumn(merged, "NewColumn", {"Dimension.Title"}, {"Dimension.Title"})
        ,removed = Table.RemoveColumns(expanded,{"Value"})
        ,pivoted = Table.Pivot(removed, List.Distinct(removed[Attribute]), "Attribute", "Dimension.Title")
    in
       pivoted;

GetDimensions = (tableID as text) =>
    let
        Source = OData.Feed(ODataApi&tableID),
        DataProperties_table = Source{[Name="DataProperties",Signature="table"]}[Data],
        filtered = Table.SelectRows(DataProperties_table, each ([Type] = "Dimension" or [Type] = "TimeDimension")),
        removed= Table.SelectColumns(filtered,{"Key"}),
        inv = Table.AddColumn(removed, "Dimension", each GetDimension(tableID, [Key])),
        exp = Table.ExpandTableColumn(inv, "Dimension", {"Key", "Title"}, {"Dimension.Key", "Dimension.Title"})
    in 
         exp;
         
GetDimension = (tableID,b) =>
   let
    
        Source = OData.Feed(ODataApi&tableID),
        TypedDataSet_table = Source{[Name=b,Signature="table"]}[Data],
        result = Table.SelectColumns(TypedDataSet_table,{"Key", "Title"})
    in
        result;


// Data Source Kind description
CBSOpenData = [
    Authentication = [
        Implicit = []
    ],
    Label = "CBS Open Data"
];

// Data Source UI publishing description
CBSOpenData.Publish = [
    Beta = false,
    Category = "Other",
    ButtonText = { Extension.LoadString("ButtonTitle"), Extension.LoadString("ButtonHelp") },
    SourceImage = CBSOpenData.Icons,
    SourceTypeImage = CBSOpenData.Icons
];

CBSOpenData.Icons = [
    Icon16 = { Extension.Contents("CBSOpenData16.png"), Extension.Contents("CBSOpenData20.png"), Extension.Contents("CBSOpenData24.png"), Extension.Contents("CBSOpenData32.png") },
    Icon32 = { Extension.Contents("CBSOpenData32.png"), Extension.Contents("CBSOpenData40.png"), Extension.Contents("CBSOpenData48.png"), Extension.Contents("CBSOpenData64.png") }
];
//Helper function converting Table to NavigationTable
Table.ToNavigationTable = (
    table as table,
    keyColumns as list,
    nameColumn as text,
    dataColumn as text,
    itemKindColumn as text,
    itemNameColumn as text,
    isLeafColumn as text
) as table =>
    let
        
        tableType = Value.Type(table),
        newTableType = Type.AddTableKey(tableType, keyColumns, true) meta 
        [
            NavigationTable.NameColumn = nameColumn, 
            NavigationTable.DataColumn = dataColumn,
            NavigationTable.ItemKindColumn = itemKindColumn, 
            Preview.DelayColumn = itemNameColumn, 
            NavigationTable.IsLeafColumn = isLeafColumn
        ],
        navigationTable = Value.ReplaceType(table, newTableType)
    in
        navigationTable;