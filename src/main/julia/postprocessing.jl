using CSV, DataFrames, StatsPlots, Colors, StatsBase, Measures

function postprocessing(output_path, params, model)

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

    #CUMULATIVE DOSIS OVER THE COURSE OF ONE DAY FOR 5 RANDOMLY CHOSEN AGENTS
    plot_dosis_over_day(params, model, Date(2026, 6, 20), string(output_path, "/dosis_over_day_2026-06-20"))

end

"""
    plot_dosis_over_day(params, model, day, basepath; n_agents = 5)

    Line plot of the cumulative heat dosis of n_agents randomly chosen agents over the course of one day; writes <basepath>.pdf and <basepath>.png.
    The hourly dosis is recomputed from the model, the value at 24:00 equals the agent's dosis for that day in dosis_accumulation_df.csv.
"""
function plot_dosis_over_day(params, model, day, basepath; n_agents = 5)
    sample_ids = sample(collect(keys(model.hourly_activity_seconds)), n_agents; replace = false)
    # x = end of each hour, starting with 0 dosis at 00:00
    cumulative_dosis = [[0.0; cumsum(compute_hourly_dosis(params, model, id, day))] for id in sample_ids]

    StatsPlots.plot(
        0:24,
        cumulative_dosis,
        label          = permutedims(sample_ids),
        color          = permutedims(ACTIVITY_COLORS[1:n_agents]),
        linewidth      = 4,
        xlabel         = "Time of day",
        ylabel         = "Cumulative heat dosis",
        title          = "Heat dosis on $(day)",
        xticks         = (0:3:24, [lpad(h, 2, "0") * ":00" for h in 0:3:24]),
        xlims          = (0, 24),
        legend         = :outerbottom,
        legend_columns = n_agents,
        foreground_color_legend = nothing,
        grid           = :y,
        gridalpha      = 0.3,
        framestyle     = :box,
        bottom_margin  = 12mm,
        left_margin    = 10mm,
        right_margin   = 15mm,   # room for the "24:00" tick label
        guidefontsize  = 36,
        tickfontsize   = 28,
        legendfontsize = 28,
        titlefontsize  = 36,
        size           = (1800, 1600),
        dpi            = 300
    )

    savefig(string(basepath, ".pdf"))
    savefig(string(basepath, ".png"))
end
