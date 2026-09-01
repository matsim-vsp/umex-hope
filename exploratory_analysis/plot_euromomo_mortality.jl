using HTTP, JSON, Plots, Measures

# Data stems from https://www.euromomo.eu/graphs-and-maps ("Pooled number of
# deaths by age group" panel).
#
# EuroMOMO does not expose this as a stand-alone data file: the numbers are
# baked into the page's JavaScript bundle at build time, and that bundle's
# filename changes (content hash) every time EuroMOMO redeploys the site.
# So instead of hard-coding today's bundle URL, we:
#   1) fetch the stable page URL,
#   2) find the *current* bundle filename referenced in that page's HTML,
#   3) download that bundle and pull the embedded JSON payload out of it.

# ---------------------------------------------------------------------
# 1) Download the data behind the "Pooled number of deaths by age group" plot
# ---------------------------------------------------------------------
page_url = "https://www.euromomo.eu/graphs-and-maps/"
html = String(HTTP.get(page_url).body)

m = match(r"component---src-templates-graphs-and-maps-jsx-[0-9a-f]+\.js", html)
m === nothing && error("Could not locate the graphs-and-maps JS bundle on the EuroMOMO page -- the site may have changed.")
bundle_url = "https://www.euromomo.eu/" * m.match
bundle_js  = String(HTTP.get(bundle_url).body)

# The whole dataset for the page is embedded as a single JSON.parse('...') call.
# (Wrapped in a function so the scan index has normal, unambiguous local scope --
# a `while` loop mutating a variable at top-level script scope triggers Julia's
# "soft scope" ambiguity warning/error.)
function extract_json_literal(bundle_js::AbstractString)
    marker = "JSON.parse('"
    start_idx = findfirst(marker, bundle_js)
    start_idx === nothing && error("Could not find the embedded JSON payload in the EuroMOMO bundle -- the site may have changed.")
    i = last(start_idx) + 1

    # Scan forward for the *unescaped* closing single quote of the JS string literal
    n = ncodeunits(bundle_js)
    j = i
    while j <= n
        c = bundle_js[j]
        if c == '\\'
            j += 2
            continue
        elseif c == '\''
            break
        end
        j += 1
    end
    json_literal = bundle_js[i:j-1]
    return replace(json_literal, "\\'" => "'")   # undo the single-quote escaping added by the bundler
end

json_text = extract_json_literal(bundle_js)

# ---------------------------------------------------------------------
# 2) Read in the data
# ---------------------------------------------------------------------
data = JSON.parse(json_text)

# data["ages"]             -> age-group labels, e.g. "0to14", "65P", "Total", ...
# data["pooled"]["weeks"]  -> calendar weeks, e.g. "2020-36"
# data["pooled"]["groups"] -> one entry per age group; "nbc" = weekly pooled
#                             observed death count (what the "Number" view of
#                             the "Pooled number of deaths by age group" chart shows)
weeks_str = data["pooled"]["weeks"]
groups    = data["pooled"]["groups"]

year_num = parse.(Int, first.(weeks_str, 4))
week_num = parse.(Int, last.(weeks_str, 2))
years    = sort(unique(year_num))

agegroups = [g["group"] for g in groups]

# ---------------------------------------------------------------------
# 3)+4) Multi-panel plot: one panel per year, same :tab20 palette as the
#    Destatis / RKI plots, one color per age group -- "Total" (the overall
#    count across all ages) is included as one of the lines.
# ---------------------------------------------------------------------
tab20 = palette(:tab20, length(agegroups))
color_map = Dict(a => tab20[i] for (i, a) in enumerate(agegroups))

plots_list = []

for yr in years
    idx = findall(==(yr), year_num)

    p = Plots.plot(
        title         = "Weekly deaths\nin 27 participating countries\nby age group ($yr)",
        xlabel        = "Calendar week",
        ylabel        = "Deaths",
        legend        = false,
        titlefontsize = 11,     # 5) font size large enough to read
        guidefontsize = 14,     #    axis titles
        tickfontsize  = 11,     #    axis tick labels
        xformatter    = x -> string(round(Int, x)),   # whole calendar weeks, no decimals
        yformatter    = :plain,                        # no scientific notation (e.g. 10^5) on the y-axis
        bottom_margin = 8mm,
        left_margin   = 12mm,
    )

    for g in groups
        counts = Float64.(g["nbc"])[idx]
        Plots.plot!(p, week_num[idx], counts,
            color     = color_map[g["group"]],
            linewidth = 1.5,
            label     = false,
        )
    end

    push!(plots_list, p)
end

# Shared legend panel (one entry per age group, incl. "Total")
legend_plot = Plots.plot(
    framestyle = :none,
    background_color_subplot = :transparent,
    xlims = (0, 1), ylims = (0, 1),
)
for a in agegroups
    Plots.plot!(legend_plot, [NaN], [NaN], color = color_map[a], label = a, linewidth = 2)
end
Plots.plot!(legend_plot, legend = :inside, legendfontsize = 11, legendtitle = "Age group")

# Combine all panels into a 2-row grid (wider panels than a single row).
# `layout = (nrows, ncols_grid)` is a plain (rows, cols) grid and works for
# any number of years; leftover slots (if total_panels < nrows*ncols_grid)
# are simply left blank.
nrows = 2
total_panels = length(plots_list) + 1   # + 1 for the legend panel
ncols_grid = ceil(Int, total_panels / nrows)

final_plot = Plots.plot(
    plots_list..., legend_plot,
    layout        = (nrows, ncols_grid),
    size          = (ncols_grid * 480, nrows * 380),
    top_margin    = 8mm,
    right_margin  = 8mm,
    bottom_margin = 8mm,
)

# ---------------------------------------------------------------------
# 6) Save
# ---------------------------------------------------------------------
savefig(final_plot, "euromomo_deaths_by_agegroup.pdf")
savefig(final_plot, "euromomo_deaths_by_agegroup.png")