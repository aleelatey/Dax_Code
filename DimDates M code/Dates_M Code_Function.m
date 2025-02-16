= (StartDate as date, EndDate as date, optional FYStartMonth as number, optional Holidays as list, optional WDStartNum as number ) as table =>
  let
    FYStartMonth = if List.Contains( {1..12}, FYStartMonth ) then FYStartMonth else 1,
    //the WDStartNum parameter allows you to set Weekday numbering running from 0-6 or 1-7 but first day of the week will remain Monday
    WDStart = if List.Contains( {0, 1}, WDStartNum ) then WDStartNum else 0,
    CurrentDate = Date.From(DateTime.FixedLocalNow()),
    DayCount = Duration.Days(Duration.From(EndDate - StartDate))+1,
    Source = List.Dates(StartDate,DayCount,#duration(1,0,0,0)),
    AddToday = if EndDate < CurrentDate then List.Combine( {Source, {CurrentDate}}) else Source,
    TableFromList = Table.FromList(AddToday, Splitter.SplitByNothing()),
    ChangedType = Table.TransformColumnTypes(TableFromList,{{"Column1", type date}}),
    RenamedColumns = Table.RenameColumns(ChangedType,{{"Column1", "Date"}}),
    InsertYear = Table.AddColumn(RenamedColumns, "Year", each Date.Year([Date]), type number),
    InsertQuarter = Table.AddColumn(InsertYear, "QuarterOfYear", each Date.QuarterOfYear([Date]), type number),
    InsertMonth = Table.AddColumn(InsertQuarter, "MonthOfYear", each Date.Month([Date]), type number),
    InsertDay = Table.AddColumn(InsertMonth, "DayOfMonth", each Date.Day([Date]), type number),
    InsertDayInt = Table.AddColumn(InsertDay, "DateInt", each [Year] * 10000 + [MonthOfYear] * 100 + [DayOfMonth], type number),
    InsertMonthName = Table.AddColumn(InsertDayInt, "Month Name", each Date.ToText([Date], "MMMM"), type text),
    InsertCalendarMonth = Table.AddColumn(InsertMonthName, "Month & Year", each (try(Text.Range([Month Name],0,3)) otherwise [Month Name]) & " " & Number.ToText([Year]), type text),
    InsertCalendarQtr = Table.AddColumn(InsertCalendarMonth, "Quarter & Year", each "Q" & Number.ToText([QuarterOfYear]) & " " & Number.ToText([Year]), type text),
    InsertDayWeek = Table.AddColumn(InsertCalendarQtr, "DayOfWeek", each Date.DayOfWeek([Date]) + WDStart, Int64.Type),
    InsertDayName = Table.AddColumn(InsertDayWeek, "DayOfWeekName", each Date.ToText([Date], "dddd", "en-US"), type text),
    InsertWeekEnding = Table.AddColumn(InsertDayName, "WeekEnding", each Date.EndOfWeek( [Date], Day.Monday), type date),
    InsertMonthEnding = Table.AddColumn(InsertWeekEnding, "MonthEnding", each Date.EndOfMonth([Date]), type date),
    InsertWeekNumber= Table.AddColumn(InsertMonthEnding, "ISO Weeknumber", each
      if Number.RoundDown((Date.DayOfYear([Date])-(Date.DayOfWeek([Date], Day.Monday)+1)+10)/7)=0
      then Number.RoundDown((Date.DayOfYear(#date(Date.Year([Date])-1,12,31))-(Date.DayOfWeek(#date(Date.Year([Date])-1,12,31), Day.Monday)+1)+10)/7)
      else if (Number.RoundDown((Date.DayOfYear([Date])-(Date.DayOfWeek([Date], Day.Monday)+1)+10)/7)=53 and (Date.DayOfWeek(#date(Date.Year([Date]),12,31), Day.Monday)+1<4))
      then 1 else Number.RoundDown((Date.DayOfYear([Date])-(Date.DayOfWeek([Date], Day.Monday)+1)+10)/7), type number),
    InsertISOyear = Table.AddColumn(InsertWeekNumber, "ISO Year", each Date.Year( Date.AddDays( Date.StartOfWeek([Date], Day.Monday), 3 )),  Int64.Type),
    BufferTable = Table.Buffer(Table.Distinct( InsertISOyear[[ISO Year], [DateInt]])),
    InsertISOday = Table.AddColumn(InsertISOyear, "ISO Day of Year", (OT) => Table.RowCount( Table.SelectRows( BufferTable, (IT) => IT[DateInt] <= OT[DateInt] and IT[ISO Year] = OT[ISO Year])),  Int64.Type),
    InsertCalendarWk = Table.AddColumn(InsertISOday, "Week & Year", each Text.From([ISO Year]) & "-" & Text.PadStart( Text.From( [ISO Weeknumber] ), 2, "0"), type text ),
    InsertWeeknYear = Table.AddColumn(InsertCalendarWk, "WeeknYear", each [ISO Year] * 10000 + [ISO Weeknumber] * 100,  Int64.Type),

    InsertMonthnYear = Table.AddColumn(InsertWeeknYear , "MonthnYear", each [Year] * 10000 + [MonthOfYear] * 100, type number),
    InsertQuarternYear = Table.AddColumn(InsertMonthnYear, "QuarternYear", each [Year] * 10000 + [QuarterOfYear] * 100, type number),
    AddFY = Table.AddColumn(InsertQuarternYear, "Fiscal Year", each "FY" & (if [MonthOfYear] >= FYStartMonth then Text.PadEnd( Text.End( Text.From([Year] +1), 2), 2, "0") else Text.End( Text.From([Year]), 2)), type text),
    AddFQ = Table.AddColumn(AddFY, "Fiscal Quarter", each "FQ" & Text.From( Number.RoundUp( Date.Month( Date.AddMonths( [Date], - (FYStartMonth -1) )) / 3 )), type text),
    AddFM = Table.AddColumn(AddFQ, "Fiscal Period", each if [MonthOfYear] >= FYStartMonth then [MonthOfYear] - (FYStartMonth-1) else [MonthOfYear] + (12-FYStartMonth+1), type text),

    InsertIsAfterToday = Table.AddColumn(AddFM, "IsAfterToday", each not ([Date] <= Date.From(CurrentDate)), type logical),
    InsertIsWorkingDay = Table.AddColumn(InsertIsAfterToday, "IsWorkingDay", each if Date.DayOfWeek([Date], Day.Monday) > 4 then false else true, type logical),
    InsertIsHoliday = Table.AddColumn(InsertIsWorkingDay, "IsHoliday", each if Holidays = null then "Unknown" else List.Contains( Holidays, [Date] ), if Holidays = null then type text else type logical),
    InsertIsBusinessDay = Table.AddColumn(InsertIsHoliday, "IsBusinessDay", each if [IsWorkingDay] = true and [IsHoliday] <> true then true else false, type logical),
    InsertDayType = Table.AddColumn(InsertIsBusinessDay, "Day Type", each if [IsHoliday] = true then "Holiday" else if [IsWorkingDay] = false then "Weekend" else if [IsWorkingDay] = true then "Weekday" else null, type text),

    //InsertDayOffset = Table.AddColumn(InsertDayType, "DayOffset", each Number.From([Date] - CurrentDate), type number),  //if you enable DayOffset, don't forget to adjust the PreviousStepName in the next line of code.
    InsertWeekOffset = Table.AddColumn(InsertDayType, "WeekOffset", each (Number.From(Date.StartOfWeek([Date], Day.Monday))-Number.From(Date.StartOfWeek(CurrentDate, Day.Monday)))/7, type number),
    InsertMonthOffset = Table.AddColumn(InsertWeekOffset, "MonthOffset", each ((12 * Date.Year([Date])) +  Date.Month([Date])) - ((12 * Date.Year(Date.From(CurrentDate))) +  Date.Month(Date.From(CurrentDate))), type number),
    InsertQuarterOffset = Table.AddColumn(InsertMonthOffset, "QuarterOffset", each ((4 * Date.Year([Date])) +  Date.QuarterOfYear([Date])) - ((4 * Date.Year(Date.From(CurrentDate))) +  Date.QuarterOfYear(Date.From(CurrentDate))), type number),
    InsertYearOffset = Table.AddColumn(InsertQuarterOffset, "YearOffset", each Date.Year([Date]) - Date.Year(Date.From(CurrentDate)), type number),

    IdentifyCurrentDate = Table.SelectRows(InsertYearOffset, each ([Date] = CurrentDate)),
    CurrentYear = IdentifyCurrentDate{0}[Year],
    CurrentMonth = IdentifyCurrentDate{0}[MonthOfYear],
    InsertFYoffset = Table.AddColumn(InsertYearOffset, "FiscalYearOffset", each try (if [MonthOfYear] >= FYStartMonth then [Year]+1 else [Year]) - 
      (if CurrentMonth >= FYStartMonth then CurrentYear+1 else CurrentYear) otherwise null, type number),
    RemoveToday = if EndDate < CurrentDate then Table.SelectRows(InsertFYoffset, each ([Date] <> CurrentDate)) else InsertFYoffset,
    InsertCompletedWeek = Table.AddColumn(RemoveToday, "WeekCompleted", each [WeekEnding] < Date.From(Date.EndOfWeek(CurrentDate)), type logical),
    InsertCompletedMonth = Table.AddColumn(InsertCompletedWeek, "MonthCompleted", each [MonthEnding] < Date.From(Date.EndOfMonth(CurrentDate)), type logical),
    InsertCompletedQuarter = Table.AddColumn(InsertCompletedMonth, "QuarterCompleted", each Date.EndOfQuarter([Date]) < Date.From(Date.EndOfQuarter(CurrentDate)), type logical),
    InsertChangedType = Table.TransformColumnTypes(InsertCompletedQuarter,{{"Year", Int64.Type}, {"QuarterOfYear", Int64.Type}, {"MonthOfYear", Int64.Type}, {"DayOfMonth", Int64.Type}, {"DateInt", Int64.Type}, {"DayOfWeek", Int64.Type}, {"ISO Weeknumber", Int64.Type}, {"WeeknYear", Int64.Type}, {"MonthnYear", Int64.Type}, {"QuarternYear", Int64.Type}, {"Fiscal Period", Int64.Type}, {"WeekOffset", Int64.Type}, {"MonthOffset", Int64.Type}, {"QuarterOffset", Int64.Type}, {"YearOffset", Int64.Type}, {"FiscalYearOffset", Int64.Type}})
  in
  InsertChangedType
  