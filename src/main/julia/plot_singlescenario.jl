using CSV, DataFrames, StatsPlots, Colors

function postprocessing(output_path)

    output_path = string("./", output_path)

    # SUSCEPTIBLE, EXPOSED, AFFECTED OVER TIME
    # Read the CSV of Susceptible, Exposed, Affected
    df = CSV.read(string(output_path, "/SusceptibleExposedAffected.csv"), DataFrame)
    # Create the line plot
    @df df StatsPlots.plot(:timer, :count, group=:state,
        xlabel = "Timer",
        ylabel = "Count",
        title  = "Agent States Over Time",
        legend = :topright
    )
    savefig(string(output_path, "/SusceptibleExposedAffected.pdf"))

    # AFFECTED BY AGE OVER TIME
    # Read the CSV of Susceptible, Exposed, Affected by age
    df_byage = CSV.read(string(output_path, "/SusceptibleExposedAffected_diffbyage.csv"), DataFrame)
    # Create the line plot
    df_byage.age_label = string.(df_byage.age_low) .* "-" .* string.(df_byage.age_high)

    sub = filter(r -> r.state == "affected", df_byage)

    @df sub StatsPlots.plot(:timer, :count, group=:age_label,
            xlabel = "Timer",
            ylabel = "Count",
            title  = "Newly Affected by Age Group",
            legend = :topright
    )

    savefig(string(output_path, "/SusceptibleExposedAffected_diffbyage.pdf"))

end