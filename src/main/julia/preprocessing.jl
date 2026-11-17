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

function preprocessing(df_merged, agent_attr, output_path)
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

    # one value per day: daily mean
    df_plot = filter(r -> r.timestamp >= PLOT_START, df_merged)
    df_plot.date = Date.(df_plot.timestamp)
    df_plot = combine(groupby(df_plot, :date), vars .=> mean .=> vars)
    sort!(df_plot, :date)

    plots = [
        Plots.plot(df_plot.date, df_plot[!, v];
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
    
    # one value per day: daily mean UTCI
    df_daily = filter(r -> r.timestamp >= PLOT_START, df_merged)
    df_daily.date = Date.(df_daily.timestamp)
    df_daily = combine(groupby(df_daily, :date), :UTCI => mean => :UTCI)
    sort!(df_daily, :date)

    # x-ticks on the first of every month, up to and including the first of the month after the last data point
    tick_end   = firstdayofmonth(maximum(df_daily.date)) + Month(1)
    tick_dates = collect(Date(PLOT_START):Month(1):tick_end)

    p_daily = Plots.plot(df_daily.date, df_daily.UTCI;
            label     = nothing,
            ylabel    = "Temperature (°C)",
            xlabel    = "Date",
            xticks    = (Dates.value.(tick_dates), Dates.format.(tick_dates, "yyyy-mm-dd")),
            xlims     = (Dates.value(first(tick_dates)), Dates.value(tick_end)),
            linewidth = 3,
            color     = :steelblue,
            title     = "Daily mean")

    # hourly UTCI for a single day
    utci_day = Date(2026, 6, 26)
    df_day = filter(r -> Date(r.timestamp) == utci_day, df_merged)
    sort!(df_day, :timestamp)
    isempty(df_day) && error("No data for $(utci_day). Cannot plot hourly UTCI")
    hours = Dates.hour.(df_day.timestamp) .+ Dates.minute.(df_day.timestamp) ./ 60

    p_hourly = Plots.plot(hours, df_day.UTCI;
            label     = nothing,
            ylabel    = "Temperature (°C)",
            xlabel    = "Time of day",
            # tick every hour, label every third hour
            xticks    = (0:24, [h % 3 == 0 ? string(lpad(h, 2, '0'), ":00") : "" for h in 0:24]),
            xlims     = (0, 24),
            linewidth = 3,
            color     = :steelblue,
            title     = "Hourly values on $(utci_day)")

    Plots.plot(p_daily, p_hourly;
            layout  = (2, 1),
            size    = (1200, 800),
            plot_title = "UTCI",
            plot_titlefontsize = 22,
            titlefontsize = 18,
            guidefontsize = 18,
            tickfontsize  = 14,
            left_margin   = 10mm,   # keep y-axis label from being cut off
            bottom_margin = 10mm,   # keep x-axis label from being cut off
            right_margin  = 20mm)   # keep last x-tick labels (final date, 24:00) from being cut off

    savefig(string(output_path,"/UTCI.pdf"))
    savefig(string(output_path,"/UTCI.png"))

    # AGENT POPULATION: GENDER DISTRIBUTION
    gender_labels = Dict("f" => "Female", "m" => "Male")
    gender_counts = StatsBase.countmap(agent_attr.SNZ_gender)
    genders = sort(collect(keys(gender_counts)))
    gender_values = [gender_counts[g] for g in genders]
    gender_shares = gender_values ./ sum(gender_values)

    gender_colors = Dict("f" => ACTIVITY_COLORS[2], "m" => ACTIVITY_COLORS[1])   # female orange, male blue (same as activity plots)

    # pie drawn from shapes (Plots.pie always starts at 3 o'clock): first split at 12 o'clock, slices run clockwise
    bounds = π / 2 .- 2π .* [0; cumsum(gender_shares)]
    p_gender = Plots.plot(;
        title          = "Gender distribution",
        titlefontsize  = 22,
        framestyle     = :none,
        aspect_ratio   = 1,
        size           = (1000, 800),
        legend         = :outerright,   # keep legend clear of the pie
        legendfontsize = 18)
    for (i, g) in enumerate(genders)
        θs = range(bounds[i], bounds[i + 1]; length = 100)
        Plots.plot!(p_gender, Plots.Shape([0; cos.(θs)], [0; sin.(θs)]);
            label     = get(gender_labels, g, g),
            color     = get(gender_colors, g, :grey),
            linecolor = :white)
        # % label at the slice's mid-angle
        θ_mid = (bounds[i] + bounds[i + 1]) / 2
        Plots.annotate!(p_gender, 0.5 * cos(θ_mid), 0.5 * sin(θ_mid),
            Plots.text("$(round(100 * gender_shares[i]; digits = 1)) %", 26, :white, :center))
    end

    savefig(p_gender, string(output_path, "/agent_gender_distribution.pdf"))
    savefig(p_gender, string(output_path, "/agent_gender_distribution.png"))

    # AGENT POPULATION: GENDER DISTRIBUTION COMPARED TO DESTATIS (Hannover)
    destatis_gender_counts = Dict("f" => 578256, "m" => 550889)   # total: 1129158 #Data comes from https://www.statistik.niedersachsen.de/download/208549
    destatis_gender_pct = [100 * destatis_gender_counts[g] / sum(values(destatis_gender_counts)) for g in genders]
    gender_x = [get(gender_labels, g, g) for g in genders]
    p_gender_cmp = Plots.bar(gender_x, 100 .* gender_shares;
        label     = "Agents",
        color     = ACTIVITY_COLORS[1],
        linecolor = :white,
        ylabel    = "Share (%)",
        title     = "Gender distribution:\nagents vs. Destatis",
        ylims     = (0, 1.1 * maximum([100 .* gender_shares; destatis_gender_pct])),
        size      = (700, 700),
        legend    = :outerbottom,   # below the plot, entries side by side on one line
        legend_columns = 2,
        titlefontsize  = 22,
        guidefontsize  = 20,
        tickfontsize   = 16,
        legendfontsize = 16,
        left_margin    = 12mm,
        bottom_margin  = 12mm)
    # Destatis as outlined (unfilled) bars on top of the agent bars
    Plots.bar!(p_gender_cmp, gender_x, destatis_gender_pct;
        label     = "Destatis",
        fillalpha = 0,
        linecolor = :black,
        linewidth = 3)

    # difference agents − Destatis (percentage points) above each pair of bars; categorical bars sit at x = 0.5, 1.5, ...
    for (i, (a, d)) in enumerate(zip(100 .* gender_shares, destatis_gender_pct))
        diff = a - d
        Plots.annotate!(p_gender_cmp, i - 0.5, max(a, d) + 2.5,
            Plots.text("$(diff >= 0 ? "+" : "−")$(abs(round(diff; digits = 1))) %", 16, :black, :center))
    end

    savefig(p_gender_cmp, string(output_path, "/agent_gender_vs_destatis.pdf"))
    savefig(p_gender_cmp, string(output_path, "/agent_gender_vs_destatis.png"))

    # AGENT POPULATION: AGE DISTRIBUTION (10-year age bins: 0-9, 10-19, ...)
    age_bin_counts = StatsBase.countmap(10 .* fld.(agent_attr.SNZ_age, 10))
    age_bins = minimum(keys(age_bin_counts)):10:maximum(keys(age_bin_counts))
    age_bin_pct = [100 * get(age_bin_counts, b, 0) / nrow(agent_attr) for b in age_bins]   # share of all agents (%)
    p_age = Plots.bar(["$(b)-$(b + 9)" for b in age_bins], age_bin_pct;
        label     = nothing,
        xlabel    = "Age group (years)",
        ylabel    = "Share of agents (%)",
        ylims     = (0, 1.1 * maximum(age_bin_pct)),   # headroom above the tallest bar
        title     = "Age distribution",
        color     = :steelblue,
        linecolor = :white,
        size      = (1200, 700),
        titlefontsize = 22,
        guidefontsize = 20,
        tickfontsize  = 16,
        left_margin   = 12mm,
        bottom_margin = 12mm)

    savefig(p_age, string(output_path, "/agent_age_distribution.pdf"))
    savefig(p_age, string(output_path, "/agent_age_distribution.png"))

    # AGENT POPULATION: AGE DISTRIBUTION COMPARED TO DESTATIS (Hannover), using the Destatis age groups
    # (label, youngest age, oldest age, Destatis count)
    destatis_age_groups = [
        ("<3",    0,   2,  31602),
        ("3-5",   3,   5,  32444),
        ("6-9",   6,   9,  41576),
        ("10-15", 10,  15, 61954),
        ("16-18", 16,  18, 30428),
        ("19-24", 19,  24, 74614),
        ("25-39", 25,  39, 223375),
        ("40-59", 40,  59, 311110),
        ("60-66", 60,  66, 103637),
        ("67-74", 67,  74, 89960),
        ("75+",   75,  typemax(Int), 128455)]
    age_group_labels = first.(destatis_age_groups)
    destatis_age_pct = 100 .* last.(destatis_age_groups) ./ sum(last.(destatis_age_groups))
    agent_age_pct = [100 * count(a -> lo <= a <= hi, agent_attr.SNZ_age) / nrow(agent_attr)
                     for (_, lo, hi, _) in destatis_age_groups]

    p_age_cmp = Plots.bar(age_group_labels, agent_age_pct;
        label     = "Agents",
        color     = ACTIVITY_COLORS[1],
        linecolor = :white,
        xlabel    = "Age group (years)",
        ylabel    = "Share (%)",
        title     = "Age distribution: agents vs. Destatis",
        ylims     = (0, 1.12 * maximum([agent_age_pct; destatis_age_pct])),   # headroom for the difference labels
        size      = (1400, 800),
        legend    = :outerbottom,   # below the plot, entries side by side on one line
        legend_columns = 2,
        titlefontsize  = 22,
        guidefontsize  = 20,
        tickfontsize   = 16,
        legendfontsize = 16,
        left_margin    = 12mm,
        bottom_margin  = 12mm)
    # Destatis as outlined (unfilled) bars on top of the agent bars
    Plots.bar!(p_age_cmp, age_group_labels, destatis_age_pct;
        label     = "Destatis",
        fillalpha = 0,
        linecolor = :black,
        linewidth = 3)

    # difference agents − Destatis (percentage points) above each pair of bars; categorical bars sit at x = 0.5, 1.5, ...
    for (i, (a, d)) in enumerate(zip(agent_age_pct, destatis_age_pct))
        diff = a - d
        Plots.annotate!(p_age_cmp, i - 0.5, max(a, d) + 1.2,
            Plots.text("$(diff >= 0 ? "+" : "−")$(abs(round(diff; digits = 1))) %", 14, :black, :center))
    end

    savefig(p_age_cmp, string(output_path, "/agent_age_vs_destatis.pdf"))
    savefig(p_age_cmp, string(output_path, "/agent_age_vs_destatis.png"))

    # COMBINED TWO-PANEL PLOT: GENDER AND AGE COMPARED TO DESTATIS
    # copies, so the single-panel plots above stay unchanged; one shared legend in the age panel
    p_gender_panel = Plots.plot!(deepcopy(p_gender_cmp); title = "Gender", xlabel = "Gender", legend = false)
    p_age_panel    = Plots.plot!(deepcopy(p_age_cmp); title = "Age", legend = :topleft, legend_columns = 1)
    p_population_cmp = Plots.plot(p_gender_panel, p_age_panel;
        layout     = Plots.grid(1, 2; widths = [0.25, 0.75]),
        size       = (1800, 800),
        plot_title = "Agent population vs. Destatis (Hannover)",
        plot_titlefontsize = 24,
        left_margin   = 12mm,
        bottom_margin = 12mm)

    savefig(p_population_cmp, string(output_path, "/agent_population_vs_destatis.pdf"))
    savefig(p_population_cmp, string(output_path, "/agent_population_vs_destatis.png"))

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
