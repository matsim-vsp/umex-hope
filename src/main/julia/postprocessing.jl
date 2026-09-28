using CSV, DataFrames, StatsPlots, Colors, StatsBase, Measures

function postprocessing(output_path)

    output_path = string("./", output_path)

    # SUSCEPTIBLE, EXPOSED, AFFECTED OVER TIME
    # Read the CSV of Susceptible, Exposed, Affected
    df = CSV.read(string(output_path, "/SusceptibleExposedAffected.csv"), DataFrame)
    # Create the line plot
    @df df StatsPlots.plot(:datetime, :count, group=:state,
        xlabel = "Date",
        ylabel = "Count",
        title  = "Agent States Over Time",
        legend = :topright
    )
    savefig(string(output_path, "/output-SusceptibleExposedAffected.pdf"))
    savefig(string(output_path, "/output-SusceptibleExposedAffected.png"))

    #AFFECTED OVER TIME (INCIDENCE), LEITSTELLENDATEN
    df_controlcenter = CSV.read("/Users/sydney/git/umex-hope/daily_counts_incidence_control_center.csv", DataFrame)
    df_controlcenter.Datum = Date.(df_controlcenter.Datum)
    #Only keep newly affected (new cases per day, comparable to daily incidence)
    df = df[df.state .== "newlyaffected", :]
    df.Incidence = df.count ./ 7687 .* 100000 
    df.datetime = Date.(df.datetime)
    df = df[df.datetime .> Date(2026, 1, 1), :]

    @df df_controlcenter StatsPlots.plot(:Datum, :heatwave_incidence,
    xlabel = "Date",
    ylabel = "Affected",
    legend = false,
    linewidth = 2)

    @df df StatsPlots.plot!(:datetime, :Incidence,
    linewidth = 2)

    savefig(string(output_path, "/output-AffectedvsData.pdf"))
    savefig(string(output_path, "/output-AffectedvsData.png"))


    # AFFECTED BY AGE OVER TIME
    # Read the CSV of Susceptible, Exposed, Affected by age
    df_byage = CSV.read(string(output_path, "/SusceptibleExposedAffected_diffbyage.csv"), DataFrame)
    # Create the line plot
    df_byage.age_label = string.(df_byage.age_low) .* "-" .* string.(df_byage.age_high)

    sub = filter(r -> r.state == "affected", df_byage)

    @df sub StatsPlots.plot(:datetime, :count, group=:age_label,
            xlabel = "Date",
            ylabel = "Count",
            title  = "Affected by Age Group",
            legend = :topright,
            color  = :steelblue
    )
    savefig(string(output_path, "/output-SusceptibleExposedAffected_diffbyage.pdf"))

    #DOSIS OVER TIME FOR 20 RANDOMLY CHOSEN AGENTS
    dosis_df = CSV.read(string(output_path, "/dosis_accumulation_df.csv"), DataFrame)
    # pick 20 random unique agent ids
    unique_ids = unique(dosis_df.agentid)
    sample_ids = sample(unique_ids, min(20, length(unique_ids)); replace = false)

    # filter down to just those agents
    sub = dosis_df[in.(dosis_df.agentid, Ref(sample_ids)), :]
    sort!(sub, [:agentid, :timer])

    @df sub StatsPlots.plot(:timer, :heatdosis, group = :agentid,
        xlabel = "Time",
        ylabel = "Heat dosis",
        title  = "Heat dosis by Agent",
        legend = :outertopright
    )
    savefig(string(output_path, "/dosis_over_time.pdf"))
    savefig(string(output_path, "/dosis_over_time.png"))
    
end
