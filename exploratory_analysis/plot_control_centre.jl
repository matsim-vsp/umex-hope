using CSV, DataFrames, StatsPlots, Dates, Statistics

#Read in temperature data for Hannover --> Timing of heat wave
include("../temperature.jl")
temperature_hannover = temperature_reader("TemperatureHannoverDWD.txt")
temperature_hannover = select(temperature_hannover, :DATE, :TX)

# Read the CSV file
df = CSV.read("./Taegliche_RTW_Counts_gesamt_2026-01-01_bis_2026-07-06.csv", DataFrame)
df = leftjoin(df, temperature_hannover, on = :Datum => :DATE)

# Remove the date 2026-07-06 (it's equal to zero --> calls had probably not been recorded yet)
df = filter(row -> row.Datum != Date("2026-07-06"), df)
df.Incidence = df.Anzahl ./ 205000 .* 100000 #Helmstedt and Wolfsburg have a joint Leitstelle 

# Add weekday column (e.g., "Monday", "Tuesday", ...)
df.weekday = dayname.(df.Datum)
# For each weekday, compute the mean of Anzahl and subtract it from each row's Anzahl
df = transform(groupby(df, :weekday),
    :Anzahl => (x -> x .- mean(x)) => :deviation_from_mean)

#Only keep deviation, if we are experiencing a heat wave
df.heatwave = ifelse.(df.TX .>= 25, df.deviation_from_mean, 0)
df.heatwave = max.(df.heatwave, 0)
#Convert heatwave to incidence for calibration
df.heatwave_incidence = df.heatwave ./205000 .* 100000

# Create the line plot (of daily data)
p1 = @df df StatsPlots.plot(:Datum, :Anzahl,
    xlabel = "Date",
    ylabel = "Counts",
    legend = false, 
    linewidth = 2)

p2 = @df df StatsPlots.plot(:Datum, :Incidence,
    xlabel = "Date",
    ylabel = "Incidence",
    legend = false,
    linewidth = 2)

p3 = @df df StatsPlots.plot(:Datum, :deviation_from_mean,
    xlabel = "Date",
    ylabel = "Deviation from\nMean",
    legend = false,
    linewidth = 2)

p4 = @df df StatsPlots.plot(:Datum, :TX,
    xlabel = "Date",
    ylabel = "Max Temperature\n(°C)",
    legend = false,
    linewidth = 2)

p5 = @df df StatsPlots.plot(:Datum, :heatwave,
    xlabel = "Date",
    ylabel = "Deviation from\nMean (summer days)",
    legend = false,
    linewidth = 2)

p6 = @df df StatsPlots.plot(:Datum, :heatwave_incidence,
    xlabel = "Date",
    ylabel = "Deviation from\nMean Incidence\n(summer days)",
    legend = false,
    linewidth = 2)

StatsPlots.plot(p1, p2, p3, p4, p5, p6, layout = (3, 2), size = (1200, 1000), dpi = 300)

savefig(string("daily_counts_incidence_control_center.pdf"))
savefig(string("daily_counts_incidence_control_center.png"))

CSV.write("daily_counts_incidence_control_center.csv", df)

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

#Differentiation by age bin
# Read the second CSV file
df2 = CSV.read("Taegliche_RTW_Counts_nach_Alter_2026-01-01_bis_2026-07-06.csv", DataFrame)

# Get all column names except Datum (these are the y-columns)
ycols = names(df2, Not([:Datum, :Anzahl_gesamt]))

# Plot all columns as lines
@df df2 StatsPlots.plot(:Datum, cols(Symbol.(ycols)),
    xlabel = "Date",
    ylabel = "Counts",
    labels = permutedims(ycols),
    legend = :outerright)

savefig(string(output_path, "/daily_counts_incidence_control_center_agebins.pdf"))
savefig(string(output_path, "/daily_counts_incidence_control_center_agebins.png"))

# Assign each date to the Monday of its week
df2.Woche = firstdayofweek.(df2.Datum)

# Columns to aggregate: everything except Datum, Woche, and Anzahl_gesamt
ycols = names(df2, Not([:Datum, :Woche, :Anzahl_gesamt]))

# Aggregate: sum each column per week
weekly2 = combine(groupby(df2, :Woche), ycols .=> sum .=> ycols)

# Sort by week
sort!(weekly2, :Woche)

# Plot the weekly data
@df weekly2 StatsPlots.plot(:Woche, cols(Symbol.(ycols)),
    xlabel = "Date",
    ylabel = "Counts",
    labels = permutedims(ycols),
    legend = :outerright)

savefig(string(output_path, "/weekly_counts_incidence_control_center_agebins.pdf"))
savefig(string(output_path, "/weekly_counts_incidence_control_center_agebins.png"))
