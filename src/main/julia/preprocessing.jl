using Plots, Dates, HTTP, CSV, DataFrames, Statistics, Random

function preprocessing(df_merged, output_path)
    df_merged = filter(r -> r.timestamp < DateTime("2026-03-22T12:00:00"), df_merged)

    df_merged.air_temperature_c = coalesce.(df_merged.air_temperature_c, 0.0)
    df_merged.relative_humidity_pct = coalesce.(df_merged.relative_humidity_pct, 0.0)
    df_merged.wind_speed_ms = coalesce.(df_merged.wind_speed_ms, 0.0)
    df_merged.Tmrt_C    = coalesce.(df_merged.Tmrt_C, 0.0)

    vars   = [:air_temperature_c, :relative_humidity_pct, :wind_speed_ms, :Tmrt_C]
    labels = ["Air Temperature (°C)", "Relative Humidity (%)", "Wind Speed (m/s)", "Tmrt (°C)"]

    plots = [
        Plots.plot(df_merged.timestamp, df_merged[!, v];
            label     = nothing,
            ylabel    = l,
            linewidth = 2,
            color     = :steelblue,
            guidefontsize = 16,
            tickfontsize  = 12)
        for (v, l) in zip(vars, labels)
    ]

    Plots.plot(plots...;
        layout  = (2, 2),
        xlabel  = ["Date" "Date" "Date" "Date"],   # only label the bottom panel
        size    = (1200, 800),
        plot_title = "UTCI input variables",
        guidefontsize = 16,
        tickfontsize  = 12
    )

    savefig(string(output_path,"/UTCI_input_variables.pdf"))
    savefig(string(output_path,"/UTCI_input_variables.png"))

    #DISTRIBUTIONS FOR TIME SPENT AT ACTIVITIES
    cols = ["home", "educ", "errands", "pt", "bike", "visit", "shop", "work", "business", "walk", "leisure", "car", "accomp", "ride", "other"]

    agent_attr_DF = CSV.read(string(output_path, "/input_agent_attributes.csv"), DataFrame)
    agent_attr_DF = filter(row -> !all(row[col] == 0 for col in cols) && !any(row[col] < 0 for col in cols), agent_attr_DF)
    plots = map(cols) do col
        counts = StatsBase.countmap(agent_attr_DF[!, col] ./ 3600)
        StatsPlots.bar(collect(keys(counts)), collect(values(counts)),
            title = col,
            legend = false,
            xlabel = "",
            ylabel = "Count"
        )
    end
    StatsPlots.plot(plots..., layout = (3, 5), size = (1000, 600))
    savefig(string(output_path, "/distribution_time_at_activities.pdf"))

    # STACKED BAR CHART FOR SUBSET OF AGENTS
    # pick a manageable number of agents (e.g. 20 random ones)
    unique_ids = unique(agent_attr_DF.person)
    sample_ids = StatsBase.sample(unique_ids, min(20, length(unique_ids)); replace = false)

    sub = agent_attr_DF[in.(agent_attr_DF.person, Ref(sample_ids)), :]

    # matrix of values: rows = agents, columns = activities
    values_matrix = Matrix(sub[:, cols]) ./ 3600

    StatsPlots.groupedbar(
        string.(sub.person),
        values_matrix,
        bar_position = :stack,
        label = permutedims(cols),
        xlabel = "Agent ID",
        ylabel = "Time (hours)",
        title = "Time at Activities by Agent",
        legend = :outertopright,
        xrotation = 45,
        bottom_margin = 12mm,
        left_margin = 10mm,
        guidefontsize = 36,
        tickfontsize  = 28,
        legendfontsize = 28,
        titlefontsize = 36,
        size          = (1800, 1400),   # 2x the typical (900, 700) — higher pixel density
        dpi           = 300   
    )
    
    savefig(string(output_path, "/distribution_time_at_activities_stacked.pdf"))
    savefig(string(output_path, "/distribution_time_at_activities_stacked.png"))


    # STACKED BAR CHART FOR SUBSET OF AGENTS (TOO SHORT)
    agent_attr_toosmall_DF = CSV.read(string(output_path, "/input_agent_attributes_toosmall.csv"), DataFrame)
    # pick a manageable number of agents (e.g. 20 random ones)
    unique_ids = unique(agent_attr_toosmall_DF.person)
    sample_ids = StatsBase.sample(unique_ids, min(20, length(unique_ids)); replace = false)

    sub_toosmall = agent_attr_DF[in.(agent_attr_toosmall_DF.person, Ref(sample_ids)), :]

    # matrix of values: rows = agents, columns = activities
    values_matrix = Matrix(sub[:, cols]) ./ 3600

    StatsPlots.groupedbar(
        string.(sub_toosmall.person),
        values_matrix,
        bar_position = :stack,
        label = permutedims(cols),
        xlabel = "Agent ID",
        ylabel = "Time (hours)",
        title = "Time at Activities by Agent",
        legend = :outertopright,
        xrotation = 45,
        bottom_margin = 12mm,
        left_margin = 10mm,
        guidefontsize = 36,
        tickfontsize  = 28,
        legendfontsize = 28,
        titlefontsize = 36,
        size          = (1800, 1400),   # 2x the typical (900, 700) — higher pixel density
        dpi           = 300   
    )
    
    savefig(string(output_path, "/distribution_time_at_activities_stacked_toosmall.pdf"))
    savefig(string(output_path, "/distribution_time_at_activities_stacked_toosmall.png"))

    return df_merged
end
