= Query1(#date(2019, 1, 1), #date(2022, 12, 31), null, null, null)


// Add column
  = Table.AddColumn(Source, "Odd-/Even Week", each if Number.IsOdd([ISO Weeknumber]) then "Odd" else "Even")


  // example of code to select specific columns in new table.
  = Table.Buffer( Dates[[Date], [DayOfWeekName], [#"Odd-/Even Week"]] )
