using CSV, DataFrames, StatsPlots, Dates

# Read the CSV file
df = CSV.read("./Taegliche_RTW_Counts_gesamt_2026-01-01_bis_2026-07-06.csv", DataFrame)

# Remove the date 2026-07-06 (it's equal to zero --> calls had probably not been recorded yet)
df = filter(row -> row.Datum != Date("2026-07-06"), df)
df.Incidence = df.Anzahl ./ 205000 .* 100000 #Helmstedt and Wolfsburg have a joint Leitstelle 

# Create the line plot (of daily data)
p1 = @df df StatsPlots.plot(:Datum, :Anzahl,
    xlabel = "Date",
    ylabel = "Counts",
    legend = false)

p2 = @df df StatsPlots.plot(:Datum, :Incidence,
    xlabel = "Date",
    ylabel = "Incidence",
    legend = false)

StatsPlots.plot(p1, p2, layout = (2, 1))

savefig(string(output_path, "/daily_counts_incidence_control_center.pdf"))
savefig(string(output_path, "/daily_counts_incidence_control_center.png"))

# Assign each date to the Monday of its week
df.Woche = firstdayofweek.(df.Datum)
# Aggregate: sum the counts per week
weekly = combine(groupby(df, :Woche), :Anzahl => sum => :Anzahl)
weekly.Incidence = weekly.Anzahl ./ 205000 .* 100000

# Sort by week
sort!(weekly, :Woche)

# Plot the weekly data
p1 = @df weekly StatsPlots.plot(:Woche, :Anzahl,
    xlabel = "Date",
    ylabel = "Counts (Weekly)",
    legend = false)

p2 = @df weekly StatsPlots.plot(:Woche, :Incidence,
    xlabel = "Date",
    ylabel = "Incidence (Weekly)",
    legend = false)

StatsPlots.plot(p1, p2, layout = (2, 1))

savefig(string(output_path, "/weekly_counts_incidence_control_center.pdf"))
savefig(string(output_path, "/weekly_counts_incidence_control_center.png"))
