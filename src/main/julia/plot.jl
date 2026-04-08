using CSV, DataFrames, StatsPlots, Colors

# Read the CSV of Susceptible, Exposed, Affected
df = CSV.read("PATH/SusceptibleExposedAffected.csv", DataFrame)
# Create the line plot
# TODO: Right now: counts, need incidence
StatsPlots.plot(df.timer, df.susceptible, label="Susceptible", seriestype=:line, linewidth=2, color =:steelblue, xlabel="Time", ylabel="Count", title="Susceptible, Exposed, and Affected over Time")
StatsPlots.plot!(df.timer, df.exposed,    label="Exposed",  seriestype=:line, linewidth=2, color =:orange)
StatsPlots.plot!(df.timer, df.affected,   label="Affected",  seriestype=:line, linewidth=2, color =:crimson)
savefig("PATH/SusceptibleExposedAffected.pdf")

# Read the CSV of Susceptible, Exposed, Affected by age
df_byage = CSV.read("PATH/SusceptibleExposedAffected_diffbyage.csv", DataFrame)
# Create the line plot
# TODO: Right now: counts, need incidence
StatsPlots.plot(df_byage.timer, df_byage.affected0010, label="00-10", seriestype=:line, linewidth=2, color =:steelblue, xlabel="Time", ylabel="Count", title="Affected over Time")
StatsPlots.plot!(df_byage.timer, df_byage.affected1120, label="11-20", seriestype=:line, linewidth=2, color =:orange)
StatsPlots.plot!(df_byage.timer, df_byage.affected2130, label="21-30", seriestype=:line, linewidth=2, color =:crimson)
StatsPlots.plot!(df_byage.timer, df_byage.affected3140, label="31-40", seriestype=:line, linewidth=2, color =:deepskyblue)
StatsPlots.plot!(df_byage.timer, df_byage.affected4150, label="41-50", seriestype=:line, linewidth=2, color =:dodgerblue)
StatsPlots.plot!(df_byage.timer, df_byage.affected5160, label="51-60", seriestype=:line, linewidth=2, color =:purple)
StatsPlots.plot!(df_byage.timer, df_byage.affected6170, label="61-70", seriestype=:line, linewidth=2, color =:pink)
StatsPlots.plot!(df_byage.timer, df_byage.affected7180, label="71-80", seriestype=:line, linewidth=2, color =:violet)
StatsPlots.plot!(df_byage.timer, df_byage.affected8190, label="81-90", seriestype=:line, linewidth=2, color =:maroon)
StatsPlots.plot!(df_byage.timer, df_byage.affected91inf, label="91-inf", seriestype=:line, linewidth=2, color =:green)

savefig("/Users/sydney/git/umex-hope/data/2026-04-08T154235/SusceptibleExposedAffected_diffbyage.pdf")