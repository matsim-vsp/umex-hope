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

    # same palette as distribution_time_at_activities_stacked, extended by 5 Tableau 20 tints so all 20 agents get distinct colors
    agent_colors = [ACTIVITY_COLORS; ["#B6992D", "#86BCB6", "#D37295", "#79706E", "#D7B5A6"]]
    n_agents = length(unique(sub.agentid))

    @df sub StatsPlots.plot(:timer, :heatdosis, group = :agentid,
        color          = permutedims(agent_colors[mod1.(1:n_agents, length(agent_colors))]),
        linewidth      = 3,
        xlabel         = "Time",
        ylabel         = "Heat dosis",
        title          = "Heat dosis for 20 exemplary agents",
        legend         = :outerbottom,
        legend_columns = 5,
        foreground_color_legend = nothing,
        grid           = :y,
        gridalpha      = 0.3,
        framestyle     = :box,
        bottom_margin  = 12mm,
        left_margin    = 10mm,
        right_margin   = 15mm,   # keep the last date tick from being cut off
        guidefontsize  = 36,
        tickfontsize   = 28,
        legendfontsize = 28,
        titlefontsize  = 36,
        size           = (1800, 1600),
        dpi            = 300
    )
    savefig(string(output_path, "/dosis_over_time.pdf"))
    savefig(string(output_path, "/dosis_over_time.png"))

    #CUMULATIVE DOSIS OVER THE COURSE OF TWO DAYS FOR 5 RANDOMLY CHOSEN AGENTS, INCL. NIGHTTIME RECOVERY
    plot_dosis_over_days(params, model, [Date(2026, 6, 26), Date(2026, 6, 27)], string(output_path, "/dosis_over_days_2026-06-20_to_2026-06-21"))

end

"""
    plot_dosis_over_days(params, model, days, basepath; n_agents = 5)

    Line plot of the heat dosis of n_agents randomly chosen agents over the course of consecutive days; writes <basepath>.pdf and <basepath>.png.
    Each day starts with the remainder of the previous day's dosis, which decays between 00:00 and 05:00 (see nighttime_recovery),
    and the hourly dosis of that day is added on top. The value at 24:00 equals the agent's dosis for that day in dosis_accumulation_df.csv.
    Only agents that were susceptible on all days (i.e. have a dosis for each day) are sampled.
"""
function plot_dosis_over_days(params, model, days, basepath; n_agents = 5)
    total_dosis = Dict((row.agentid, Date(row.timer)) => row.heatdosis for row in eachrow(model.dosis_accumulation_DF))
    recovery_efficiency = Dict(zip(model.recovery_efficiency_DF.date, model.recovery_efficiency_DF.recovery_efficiency))
    candidates = [id for id in unique(model.dosis_accumulation_DF.agentid) if all(haskey(total_dosis, (id, day)) for day in days)]
    n_agents = min(n_agents, length(candidates))
    sample_ids = sample(candidates, n_agents; replace = false)

    # x = hours since 00:00 of the first day; entry h+1 of each day is the value at h:00
    dosis_curves = map(sample_ids) do id
        curve = Float64[]
        for (i, day) in enumerate(days)
            hourly_dosis = compute_hourly_dosis(params, model, id, day)
            decay_rate = model.max_night_recovery_rate * recovery_efficiency[day]
            # remainder at 05:00 (after recovery) = total dosis of the day minus the newly accumulated dosis
            remainder = total_dosis[(id, day)] - sum(hourly_dosis)
            night_dosis = [remainder * exp(decay_rate * (5 - min(h, 5))) for h in 0:24]
            day_curve = night_dosis .+ [0.0; cumsum(hourly_dosis)]
            # 24:00 of the previous day is 00:00 of this day
            append!(curve, i == 1 ? day_curve : day_curve[2:end])
        end
        curve
    end
    n_hours = 24 * length(days)
    # tick every 6 hours, the first tick of each day also shows the date; the last tick is 24:00 of the last day
    tick_labels = [(h % 24 == 0 && h < n_hours ? Dates.format(days[h ÷ 24 + 1], "dd.mm.") * "\n" : "") *
                   lpad(h == n_hours ? 24 : h % 24, 2, "0") * ":00" for h in 0:6:n_hours]

    StatsPlots.plot(
        0:n_hours,
        dosis_curves,
        label          = permutedims(sample_ids),
        color          = permutedims(ACTIVITY_COLORS[1:n_agents]),
        linewidth      = 4,
        xlabel         = "Time",
        ylabel         = "Heat dosis",
        title          = "Heat dosis from $(first(days)) to $(last(days))",
        xticks         = (0:6:n_hours, tick_labels),
        xlims          = (0, n_hours),
        legend         = :outerbottom,
        legend_columns = n_agents,
        foreground_color_legend = nothing,
        grid           = :y,
        gridalpha      = 0.3,
        framestyle     = :box,
        bottom_margin  = 12mm,
        left_margin    = 20mm,
        top_margin     = 15mm,
        right_margin   = 15mm,   # room for the "24:00" tick label
        guidefontsize  = 36,
        tickfontsize   = 28,
        legendfontsize = 28,
        titlefontsize  = 36,
        size           = (1800 + 900 * (length(days) - 1), 1600),
        dpi            = 300
    )
    # nighttime recovery window (00:00 - 05:00) of each day
    StatsPlots.vspan!(vcat([[24 * (i - 1), 24 * (i - 1) + 5] for i in eachindex(days)]...),
        color = :gray, alpha = 0.15, label = "")

    savefig(string(basepath, ".pdf"))
    savefig(string(basepath, ".png"))
end
