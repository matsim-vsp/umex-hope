#!/usr/bin/env julia
"""
preprocess_mortality_data.jl

Combines four data sources relevant to heat-related adverse health effects
into a single tidy, long-format CSV with exactly three columns:

    date    -- Date
    deaths  -- Float64  (overall count, no age breakdown)
    source  -- String   ("RKI", "Destatis", "EuroMOMO", "Wolfsburg_Leitstelle")

Data sources
------------
1. RKI heat-related mortality estimates
   Weekly ("Kalenderwoche"), local xlsx you provide.
   Only Geschlecht == "Gesamt" & Altersgruppe == "Gesamt" rows are used.

2. Destatis official death counts
   Weekly ("Kalenderwoche"), downloaded xlsx, sheet "12613-01"
   ("Sterbefälle nach Kalenderwochen und Altersgruppen in Deutschland").
   Only the "Insgesamt" (all age groups) row of each year-block is used.

3. EuroMOMO pooled weekly deaths
   Weekly, scraped from the euromomo.eu "graphs-and-maps" page. This is the
   POOLED figure across all participating European countries (matches your
   "European death counts" description) -- not Germany-specific. Only the
   "Total" age group is used.

4. Wolfsburg Leitstelle (RTW dispatch) counts
   Daily, local csv you provide.
   NOTE: this is NOT a death count -- it's the daily number of ambulance
   ("Rettungswagen") dispatches. It's included in the same 3-column schema
   as a fourth calibration signal; the "deaths" column for this source
   really means "RTW dispatch count". Adjust downstream if that's not what
   you want alongside true death counts.

Weekly sources (RKI, Destatis, EuroMOMO) are stamped with the Monday of
their ISO-8601 calendar week, so all four sources line up on one date axis.

Two independent entry points -- run either on its own, or both (as the
bottom of this file does by default):
    preprocess_data()  -- load all sources, write OUTPUT_CSV_PATH
    plot_combined()     -- read OUTPUT_CSV_PATH back in, write PLOT_PATH

Required packages (install once):
    import Pkg
    Pkg.add(["DataFrames", "XLSX", "CSV", "HTTP", "JSON", "Plots"])
"""

using DataFrames, XLSX, CSV, HTTP, JSON, Downloads, Dates, Plots

# =====================================================================
# Configuration -- adjust paths as needed
# =====================================================================
const RKI_XLSX_PATH       = "HitzebedingteMortalitaetRKI.xlsx"
const RKI_YEAR            = 2026   # only this year's RKI rows are kept
const LEITSTELLE_CSV_PATH = "Taegliche_RTW_Counts_gesamt_2026-01-01_bis_2026-07-06.csv"
const OUTPUT_CSV_PATH     = "input/mortality_data_combined_$(Dates.format(today(), "yyyy-mm-dd")).csv"
const PLOT_PATH           = "input/mortality_data_combined_$(Dates.format(today(), "yyyy-mm-dd")).png"
const PLOT_YEAR           = 2026   # plot_combined() only shows this year's data

# Panel order (top to bottom) and one fixed colour per source, so a given
# source always maps to the same colour if you reuse these elsewhere.
const SOURCE_ORDER  = ["RKI", "Destatis", "EuroMOMO", "Wolfsburg_Leitstelle"]
const SOURCE_COLORS = Dict(
    "RKI"                  => "#2a78d6",  # blue
    "Destatis"              => "#eb6834",  # orange
    "EuroMOMO"              => "#1baf7a",  # aqua
    "Wolfsburg_Leitstelle"  => "#eda100",  # yellow
)

const DESTATIS_URL = "https://www.destatis.de/DE/Themen/Gesellschaft-Umwelt/Bevoelkerung/" *
      "Sterbefaelle-Lebenserwartung/Publikationen/Downloads-Sterbefaelle/" *
      "statistischer-bericht-sterbefaelle-tage-wochen-monate-aktuell-5126109.xlsx" *
      "?__blob=publicationFile&v=165"
const DESTATIS_SHEET = "12613-01"

const EUROMOMO_PAGE_URL = "https://www.euromomo.eu/graphs-and-maps/"

# =====================================================================
# Helpers
# =====================================================================

"""
    iso_week_to_date(year, week) -> Date

Monday of the given ISO-8601 calendar week (year, week). Used as the
representative date for every weekly source.
"""
function iso_week_to_date(year::Integer, week::Integer)
    jan4 = Date(year, 1, 4)                                   # always in ISO week 1
    week1_monday = jan4 - Dates.Day(Dates.dayofweek(jan4) - 1)
    return week1_monday + Dates.Week(week - 1)
end

# =====================================================================
# 1) RKI -- heat-related mortality estimates (weekly)
# =====================================================================
function load_rki(path::AbstractString; year::Integer = RKI_YEAR)
    tbl = DataFrame(XLSX.readtable(path, "Daten"))
    total = filter(
        row -> row.Geschlecht == "Gesamt" && row.Altersgruppe == "Gesamt" && Int(row.Jahr) == year,
        tbl,
    )
    total.Jahr = Int.(total.Jahr)
    total.KW   = Int.(total.KW)
    sort!(total, [:Jahr, :KW])
 
    # RKI reports season-to-date CUMULATIVE estimated deaths per calendar week
    # (verified: values are non-decreasing within a year) -- undo that with a
    # within-year first difference to get weekly new deaths.
    cumulative = Float64.(total.Geschaetzte_Anzahl_Sterbefaelle)
    weekly_new = similar(cumulative)
    for i in eachindex(cumulative)
        if i == 1 || total.Jahr[i] != total.Jahr[i - 1]
            weekly_new[i] = cumulative[i]              # first reported week of that season
        else
            weekly_new[i] = cumulative[i] - cumulative[i - 1]
        end
    end
 
    DataFrame(
        date   = iso_week_to_date.(total.Jahr, total.KW),
        deaths = weekly_new,
        source = "RKI",
    )
end

# =====================================================================
# 2) Destatis -- official death counts (weekly, all age groups summed)
# =====================================================================
function load_destatis(; url = DESTATIS_URL, sheet = DESTATIS_SHEET)
    xlsx_path = joinpath(tempdir(), "destatis_sterbefaelle.xlsx")
    Downloads.download(url, xlsx_path)
 
    xf  = XLSX.readxlsx(xlsx_path)
    sh  = xf[sheet]
    raw = sh[XLSX.get_dimension(sh)]   # Matrix{Any}, full used range
    raw = raw[5:end, :]                # drop descriptive header rows 1-4
 
    dates  = Date[]
    deaths = Float64[]
    for i in axes(raw, 1)
        isequal(raw[i, 2], "Insgesamt") || continue   # "total" row of each year-block (isequal handles missing blank cells)
        year = raw[i, 1]
        year isa Number || continue
        for col in 3:size(raw, 2)
            val = raw[i, col]
            val isa Number || continue           # skips blanks & "..." placeholders
            week = col - 2
            push!(dates, iso_week_to_date(Int(year), week))
            push!(deaths, Float64(val))
        end
    end
 
    DataFrame(date = dates, deaths = deaths, source = "Destatis")
end

# =====================================================================
# 3) EuroMOMO -- pooled weekly deaths across participating countries
# =====================================================================
function extract_json_literal(bundle_js::AbstractString)
    marker = "JSON.parse('"
    start_idx = findfirst(marker, bundle_js)
    start_idx === nothing && error("Could not find the embedded JSON payload in the EuroMOMO bundle -- the site may have changed.")
    i = last(start_idx) + 1

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
    return replace(json_literal, "\\'" => "'")
end

function load_euromomo(; page_url = EUROMOMO_PAGE_URL)
    html = String(HTTP.get(page_url).body)

    m = match(r"component---src-templates-graphs-and-maps-jsx-[0-9a-f]+\.js", html)
    m === nothing && error("Could not locate the graphs-and-maps JS bundle on the EuroMOMO page -- the site may have changed.")
    bundle_url = "https://www.euromomo.eu/" * m.match
    bundle_js  = String(HTTP.get(bundle_url).body)

    json_text = extract_json_literal(bundle_js)
    data = JSON.parse(json_text)

    weeks_str = data["pooled"]["weeks"]      # e.g. "2020-36"
    groups    = data["pooled"]["groups"]     # one entry per age group

    year_num = parse.(Int, first.(weeks_str, 4))
    week_num = parse.(Int, last.(weeks_str, 2))

    total_labels = ("Total", "total", "TOTAL", "Alle", "ALL")
    idx = findfirst(g -> g["group"] in total_labels, groups)
    idx === nothing && error(
        "Could not find an overall/'Total' age group in EuroMOMO data. " *
        "Available groups: $(join([g["group"] for g in groups], ", "))"
    )
    total_group = groups[idx]

    DataFrame(
        date   = iso_week_to_date.(year_num, week_num),
        deaths = Float64.(total_group["nbc"]),
        source = "EuroMOMO",
    )
end

# =====================================================================
# 4) Wolfsburg Leitstelle -- daily RTW dispatch counts
# =====================================================================
function load_leitstelle(path::AbstractString)
    tbl = CSV.read(path, DataFrame)
    DataFrame(
        date   = Date.(tbl.Datum),
        deaths = Float64.(tbl.Anzahl),
        source = "Wolfsburg_Leitstelle",
    )
end

### FROM HERE: PART OF POSTPROCESSING

# =====================================================================
# Plotting -- one row per data source, x-axes aligned
# =====================================================================
"""
    plot_combined(csv_path = OUTPUT_CSV_PATH; save_path = PLOT_PATH)
 
Reads the combined CSV back from disk, keeps only rows from `year`
(default `PLOT_YEAR`), and draws a 4-row, 1-column figure (one panel per
data source), sharing a single, aligned date axis via `link = :x`. Saves a
PNG and returns the plot object.
"""
function plot_mortality_data(csv_path::AbstractString = OUTPUT_CSV_PATH; save_path::AbstractString = PLOT_PATH, year::Integer = PLOT_YEAR)
    df = CSV.read(csv_path, DataFrame)
    df.date = Date.(df.date)
    filter!(row -> Dates.year(row.date) == year, df)
 
    sources = filter(s -> s in df.source, SOURCE_ORDER)   # keep fixed order, drop any that failed to load
    isempty(sources) && error("No sources found in $csv_path -- nothing to plot.")
 
    panels = map(enumerate(sources)) do (i, src)
        sub = sort(filter(row -> row.source == src, df), :date)
        is_bottom = i == length(sources)
        Plots.plot(
            sub.date, sub.deaths;
            seriestype  = :line,
            linewidth   = 2,
            color       = SOURCE_COLORS[src],
            label       = false,           # single series per panel -- title names it, no legend needed
            title       = src,
            titlefontsize = 10,
            ylabel      = "count",
            guidefontsize = 8,
            tickfontsize  = 7,
            gridalpha   = 0.15,             # recessive gridlines
            framestyle  = :box,
            xformatter  = is_bottom ? :auto : (_ -> ""),   # only the bottom panel needs date labels
            yformatter  = :plain           # e.g. "20000" instead of "2×10⁴"
        )
    end
 
    fig = Plots.plot(
        panels...;
        layout = (length(panels), 1),      # rows, not columns
        link   = :x,                       # aligned x-axes across panels
        size   = (900, 900),
        left_margin  = 6Plots.mm,
        bottom_margin = 2Plots.mm,
    )
    Plots.xlabel!(fig[length(panels)], "date")   # only the bottom panel needs the axis label
 
    savefig(fig, save_path)
    println("Saved plot to $save_path")
    return fig
end
 

# =====================================================================
# Preprocessing -- load all four sources, combine, write the CSV
# =====================================================================
"""
    preprocess_data() -> DataFrame

Loads all four sources, combines them into the tidy long-format table, and
writes it to `OUTPUT_CSV_PATH`. Independent of plotting -- call this alone
to (re)generate the CSV.
"""
function preprocess_mortality_data()
    dfs = DataFrame[]

    println("Loading RKI heat mortality data ...")
    push!(dfs, load_rki(RKI_XLSX_PATH))

    println("Downloading + loading Destatis data ...")
    try
        push!(dfs, load_destatis())
    catch e
        @warn "Destatis load failed, skipping" exception = (e, catch_backtrace())
    end

    println("Scraping + loading EuroMOMO data ...")
    try
        push!(dfs, load_euromomo())
    catch e
        @warn "EuroMOMO load failed, skipping" exception = (e, catch_backtrace())
    end

    println("Loading Wolfsburg Leitstelle data ...")
    push!(dfs, load_leitstelle(LEITSTELLE_CSV_PATH))

    combined = vcat(dfs...; cols = :union)
    sort!(combined, [:source, :date])

    CSV.write(OUTPUT_CSV_PATH, combined)
    println("Wrote $(nrow(combined)) rows to $OUTPUT_CSV_PATH")

    return combined
end