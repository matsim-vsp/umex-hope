using Plots, Dates, HTTP, CSV, DataFrames, Statistics, Random

include("utci.jl")

# Distinct, muted categorical colors (Tableau 10 + 5 light tints), grey reserved for "other"
const ACTIVITY_COLORS = ["#4E79A7", "#F28E2B", "#E15759", "#76B7B2", "#59A14F",
                         "#EDC948", "#B07AA1", "#FF9DA7", "#9C755F", "#A0CBE8",
                         "#FFBE7D", "#8CD17D", "#D4A6C8", "#499894", "#BAB0AC"]

# Display order of activities: home first, other last, everything else alphabetical.
# Colors are assigned in this order, so all activity plots share the same activity → color mapping.
activity_order(cols) = [filter(==("home"), cols); sort(filter(c -> c ∉ ("home", "other"), cols)); filter(==("other"), cols)]

# Stacked bar chart of time per activity for a set of agents; writes <basepath>.pdf and <basepath>.png
function plot_stacked_activities(agent_ids, values_matrix, cols, basepath; legend_columns = 5)
    # legend (and stacking) order
    ordered = activity_order(cols)
    perm = [findfirst(==(c), cols) for c in ordered]

    StatsPlots.groupedbar(
        string.(agent_ids),
        values_matrix[:, perm],
        bar_position   = :stack,
        label          = permutedims(ordered),
        color          = permutedims(ACTIVITY_COLORS[1:length(cols)]),
        linecolor      = :white,
        linewidth      = 0.5,
        xlabel         = "Agent ID",
        ylabel         = "Time (hours)",
        title          = "Time at Activities by Agent",
        legend         = :outerbottom,
        legend_columns = legend_columns,   # rows follow from ceil(length(cols) / legend_columns)
        foreground_color_legend = nothing,
        xrotation      = 90,
        grid           = :y,
        gridalpha      = 0.3,
        framestyle     = :box,
        bottom_margin  = 12mm,
        left_margin    = 10mm,
        guidefontsize  = 36,
        tickfontsize   = 28,
        legendfontsize = 28,
        titlefontsize  = 36,
        size           = (1800, 1600),   # 2x the typical (900, 700) — higher pixel density
        dpi            = 300
    )

    savefig(string(basepath, ".pdf"))
    savefig(string(basepath, ".png"))
end

# Age groups available for the violin plot: filter on SNZ_age, title label, file name suffix
const VIOLIN_AGE_GROUPS = Dict(
    :all         => (filter_fn = age -> true,      label = "all agents", suffix = "all"),
    :age65plus   => (filter_fn = age -> age >= 65, label = "age >= 65",  suffix = "65plus"),
    :age18orless => (filter_fn = age -> age <= 18, label = "age <= 18",  suffix = "18orless")
)

# Violin plot of time per activity, all activities in one panel; writes <basepath>_<suffix>.pdf and <basepath>_<suffix>.png.
# age_group selects the agents to plot (see VIOLIN_AGE_GROUPS: :all, :age65plus, :age18orless).
# Only agents who actually spend time at an activity (> 0 h) enter that activity's violin.
function plot_violin_activities(df_agents, cols, basepath, age_group)
    haskey(VIOLIN_AGE_GROUPS, age_group) ||
        error("Unknown age group $(age_group). Choose one of $(collect(keys(VIOLIN_AGE_GROUPS))).")
    group = VIOLIN_AGE_GROUPS[age_group]
    df_agents = filter(row -> group.filter_fn(row.SNZ_age), df_agents)

    ordered = activity_order(cols)

    p = StatsPlots.plot(
        xlabel         = "Activity",
        ylabel         = "Time (hours)",
        title          = "Distributions of time spent at activities ($(group.label))",
        legend         = false,
        xrotation      = 90,
        grid           = :y,
        gridalpha      = 0.3,
        framestyle     = :box,
        bottom_margin  = 40mm,
        left_margin    = 20mm,
        guidefontsize  = 36,
        tickfontsize   = 28,
        titlefontsize  = 36,
        size           = (2400, 1600),
        dpi            = 300
    )

    for (i, col) in enumerate(ordered)
        hours = filter(>(0), df_agents[!, col] ./ 3600)
        isempty(hours) && continue
        x = fill(string(col, " (n = ", length(hours), ")"), length(hours))
        StatsPlots.violin!(p, x, hours, color = ACTIVITY_COLORS[i], linecolor = ACTIVITY_COLORS[i])
        StatsPlots.boxplot!(p, x, hours,
            fillalpha = 0, linecolor = :black, linewidth = 2, bar_width = 0.15, outliers = false)
    end

    savefig(p, string(basepath, "_", group.suffix, ".pdf"))
    savefig(p, string(basepath, "_", group.suffix, ".png"))
end

# Start date for all timeline plots
const PLOT_START = DateTime("2026-05-01T00:00:00")

function preprocessing(df_merged, output_path)
    df_merged = filter(r -> r.timestamp < DateTime("2026-09-01T00:00:00"), df_merged)

    df_merged.air_temperature_c = coalesce.(df_merged.air_temperature_c, 0.0)
    df_merged.relative_humidity_pct = coalesce.(df_merged.relative_humidity_pct, 0.0)
    any(ismissing, df_merged.wind_speed_ms) &&
        error("We are missing data on wind speed. Cannot compute UTCI")
    df_merged.wind_speed_ms = disallowmissing(df_merged.wind_speed_ms)
    df_merged.Tmrt_C    = coalesce.(df_merged.Tmrt_C, 0.0)

    # Plot of UTCI input variables
    vars   = [:air_temperature_c, :relative_humidity_pct, :wind_speed_ms, :Tmrt_C]
    labels = ["Air Temperature (°C)", "Relative Humidity (%)", "Wind Speed (m/s)", "Tmrt (°C)"]

    # one value per day: noon
    df_plot = filter(r -> r.timestamp >= PLOT_START && Time(r.timestamp) == Time(12, 0, 0), df_merged)
    sort!(df_plot, :timestamp)

    plots = [
        Plots.plot(df_plot.timestamp, df_plot[!, v];
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
        left_margin   = 10mm,   # keep y-axis labels from being cut off
        bottom_margin = 10mm,   # keep x-axis labels from being cut off
        guidefontsize = 16,
        tickfontsize  = 12
    )

    savefig(string(output_path,"/UTCI_input_variables.pdf"))
    savefig(string(output_path,"/UTCI_input_variables.png"))

    # UTCI

    df_merged.UTCI = utci.(df_merged.air_temperature_c, 
                df_merged.Tmrt_C,
                df_merged.wind_speed_ms,
                df_merged.relative_humidity_pct)
    
    # one value per day: UTCI at noon
    df_noon = filter(r -> r.timestamp >= PLOT_START && Time(r.timestamp) == Time(12, 0, 0), df_merged)
    df_noon.date = Date.(df_noon.timestamp)
    sort!(df_noon, :date)

    # x-ticks on the first of every month
    tick_dates = collect(Date(PLOT_START):Month(1):lastdayofmonth(maximum(df_noon.date)))

    Plots.plot(df_noon.date, df_noon.UTCI;
            label     = nothing,
            ylabel    = "Temperature (°C)",
            xlabel    = "Date",
            xticks    = (Dates.value.(tick_dates), Dates.format.(tick_dates, "yyyy-mm-dd")),
            linewidth = 2,
            color     = :steelblue,
            guidefontsize = 16,
            tickfontsize  = 12,
            size    = (1200, 400),
            left_margin   = 10mm,   # keep y-axis label from being cut off
            bottom_margin = 10mm,   # keep x-axis label from being cut off
            plot_title = "UTCI")
    
    savefig(string(output_path,"/UTCI.pdf"))
    savefig(string(output_path,"/UTCI.png"))
    

    #DISTRIBUTIONS FOR TIME SPENT AT ACTIVITIES
    cols = ["home", "educ", "errands", "pt", "bike", "visit", "shop", "work", "business", "walk", "leisure", "car", "accomp", "ride", "other"]

    agent_attr_DF = CSV.read(string("input/df_agents_attr_", Dates.today(), ".csv"), DataFrame)
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

    # VIOLIN PLOT OF TIME SPENT AT ACTIVITIES (agents whose activity durations sum up to ~24 h)
    agent_attr_24h_DF = filter(row -> abs(row.total_hours - 24) <= 0.5, agent_attr_DF)
    for age_group in (:all, :age65plus, :age18orless)
        plot_violin_activities(agent_attr_24h_DF, cols,
            string(output_path, "/distribution_time_at_activities_violin"), age_group)
    end

    # STACKED BAR CHART FOR SUBSET OF AGENTS
    # pick a manageable number of agents (e.g. 20 random ones)
    unique_ids = unique(agent_attr_DF.person)
    sample_ids = StatsBase.sample(unique_ids, min(20, length(unique_ids)); replace = false)

    sub = agent_attr_DF[in.(agent_attr_DF.person, Ref(sample_ids)), :]

    # matrix of values: rows = agents, columns = activities
    values_matrix = Matrix(sub[:, cols]) ./ 3600

    plot_stacked_activities(sub.person, values_matrix, cols,
        string(output_path, "/distribution_time_at_activities_stacked"))

    # STACKED BAR CHART FOR SUBSET OF AGENTS (TOO SHORT)
    agent_attr_toosmall_DF = CSV.read(string("input/df_agents_attr_toosmall_$(Dates.format(today(), "yyyy-mm-dd")).csv"), DataFrame)
    # pick a manageable number of agents (e.g. 20 random ones)
    unique_ids = unique(agent_attr_toosmall_DF.person)
    sample_ids = StatsBase.sample(unique_ids, min(20, length(unique_ids)); replace = false)

    sub_toosmall = agent_attr_toosmall_DF[in.(agent_attr_toosmall_DF.person, Ref(sample_ids)), :]

    # matrix of values: rows = agents, columns = activities
    values_matrix = Matrix(sub_toosmall[:, cols]) ./ 3600

    plot_stacked_activities(sub_toosmall.person, values_matrix, cols,
        string(output_path, "/preprocessing_distribution_time_at_activities_stacked_toosmall"))


    # STACKED BAR CHART FOR SUBSET OF AGENTS (TOO SHORT)
    agent_attr_toolong_DF = CSV.read(string("input/df_agents_attr_toolong_$(Dates.format(today(), "yyyy-mm-dd")).csv"), DataFrame)
    # pick a manageable number of agents (e.g. 20 random ones)
    unique_ids = unique(agent_attr_toolong_DF.person)
    sample_ids = StatsBase.sample(unique_ids, min(20, length(unique_ids)); replace = false)

    sub_toolong = agent_attr_toolong_DF[in.(agent_attr_toolong_DF.person, Ref(sample_ids)), :]

    # matrix of values: rows = agents, columns = activities
    values_matrix = Matrix(sub_toolong[:, cols]) ./ 3600

    plot_stacked_activities(sub_toolong.person, values_matrix, cols,
        string(output_path, "/preprocessing_distribution_time_at_activities_stacked_toolong"))

    return df_merged
end
