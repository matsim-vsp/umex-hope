using CSV, DataFrames, StatsPlots, Colors

function postprocessing(output_path)

    output_path = string("./", output_path)

    # Read the CSV of Susceptible, Exposed, Affected
    df = CSV.read(string(output_path, "/SusceptibleExposedAffected.csv"), DataFrame)
    # Create the line plot

    StatsPlots.plot(df.timer, df.susceptible, label="Susceptible", seriestype=:line, linewidth=2, color =:steelblue, xlabel="Time", ylabel="Count", title="Susceptible, Exposed, and Affected over Time", legend_title = "")
    StatsPlots.plot!(df.timer, df.exposed,    label="Exposed",  seriestype=:line, linewidth=2, color =:orange)
    StatsPlots.plot!(df.timer, df.affected,   label="Affected",  seriestype=:line, linewidth=2, color =:crimson)
    savefig(string(output_path, "/SusceptibleExposedAffected.pdf"))

    # Read the CSV of Susceptible, Exposed, Affected by age
    df_byage = CSV.read(string(output_path, "/SusceptibleExposedAffected_diffbyage.csv"), DataFrame)
    # Create the line plot
    # TODO: Right now: counts, need incidence
    StatsPlots.plot(df_byage.timer, df_byage.affected0010/df_byage.susceptible0010[1]*100000, label="00-10", seriestype=:line, linewidth=2, color =:steelblue, xlabel="Date", ylabel="Affected/100,000", title="Affected over Time", yformatter=:plain)
    StatsPlots.plot!(df_byage.timer, df_byage.affected1120/df_byage.susceptible1120[1]*100000, label="11-20", seriestype=:line, linewidth=2, color =:orange)
    StatsPlots.plot!(df_byage.timer, df_byage.affected2130/df_byage.susceptible2130[1]*100000, label="21-30", seriestype=:line, linewidth=2, color =:crimson)
    StatsPlots.plot!(df_byage.timer, df_byage.affected3140/df_byage.susceptible3140[1]*100000, label="31-40", seriestype=:line, linewidth=2, color =:deepskyblue)
    StatsPlots.plot!(df_byage.timer, df_byage.affected4150/df_byage.susceptible4150[1]*100000, label="41-50", seriestype=:line, linewidth=2, color =:dodgerblue)
    StatsPlots.plot!(df_byage.timer, df_byage.affected5160/df_byage.susceptible5160[1]*100000, label="51-60", seriestype=:line, linewidth=2, color =:purple)
    StatsPlots.plot!(df_byage.timer, df_byage.affected6170/df_byage.susceptible6170[1]*100000, label="61-70", seriestype=:line, linewidth=2, color =:pink)
    StatsPlots.plot!(df_byage.timer, df_byage.affected7180/df_byage.susceptible7180[1]*100000, label="71-80", seriestype=:line, linewidth=2, color =:violet)
    StatsPlots.plot!(df_byage.timer, df_byage.affected8190/df_byage.susceptible8190[1]*100000, label="81-90", seriestype=:line, linewidth=2, color =:maroon)
    StatsPlots.plot!(df_byage.timer, df_byage.affected91inf/df_byage.susceptible91inf[1]*100000, label="91-inf", seriestype=:line, linewidth=2, color =:green)

    savefig(string(output_path, "/SusceptibleExposedAffected_diffbyage.pdf"))

end