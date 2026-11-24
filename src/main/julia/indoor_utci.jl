using CSV, DataFrames, Dates, Statistics, Plots

include("utci.jl")

# ── Indoor UTCI from the living-room measurements (Braunschweig research apartment) ──
#
# Inputs measured (1-minute resolution): air temperature (2 m), relative humidity (2 m), black globe temperature (1.9 m).
# Not measured: air speed and mean radiant temperature. Assumptions:
#   - Tmrt is derived from the black globe temperature following ISO 7726 (globe not exposed to direct sun, see Readme).
#   - Indoor air speed is assumed to be INDOOR_AIR_SPEED_MS (still air). This is only used for the globe convection correction.
#   - UTCI expects the wind speed at 10 m height; we use INDOOR_WIND_SPEED_10M_MS = 0.5 m/s, the lower validity limit of the
#     UTCI polynomial (utci() clamps to it anyway), corresponding to ~0.3 m/s at body height.

# Campbell Scientific BLACKGLOBE-L: 15 cm (6") copper sphere, matte black
const GLOBE_DIAMETER_M         = 0.15
const GLOBE_EMISSIVITY         = 0.95
const STEFAN_BOLTZMANN         = 5.67e-8
const INDOOR_AIR_SPEED_MS      = 0.1   # air speed at body height, for the globe correction
const INDOOR_WIND_SPEED_10M_MS = 0.5   # UTCI wind input (10 m reference height)

# The indoor measurements are in CET (UTC+1, no daylight saving time); the DWD data in df_merged is in UTC
const INDOOR_UTC_OFFSET = Hour(1)

# Indoor measurement timestamp (CET) -> local German time (CET/CEST, see time_zones.jl), for plots
indoor_to_local(t::DateTime) = utc_to_local(t - INDOOR_UTC_OFFSET)

"""
    tmrt_from_globe(tg, ta; va, D, ε) -> Float64

Mean radiant temperature [°C] from the globe temperature `tg` [°C] and air temperature `ta` [°C] (ISO 7726).
The convective heat transfer coefficient of the globe is the larger of natural and forced convection.
"""
function tmrt_from_globe(tg::Real, ta::Real; va::Real = INDOOR_AIR_SPEED_MS,
                         D::Real = GLOBE_DIAMETER_M, ε::Real = GLOBE_EMISSIVITY)::Float64
    h_natural = 1.4 * (abs(tg - ta) / D)^0.25
    h_forced  = 6.3 * va^0.6 / D^0.4
    h = max(h_natural, h_forced)
    return ((tg + 273.15)^4 + h / (ε * STEFAN_BOLTZMANN) * (tg - ta))^0.25 - 273.15
end

"""
    indoor_utci_hourly(csv_path) -> DataFrame

Reads the 1-minute indoor measurements, converts the timestamps from CET to UTC (to match df_merged),
averages air temperature, relative humidity and globe temperature over each hour (hh:00 - hh:59, labelled hh:00)
and computes Tmrt and UTCI from these hourly means.
Columns: timestamp (UTC), air_temperature_c, relative_humidity_pct, globe_temperature_c, Tmrt_C, UTCI, n_minutes.
"""
function indoor_utci_hourly(csv_path)
    df = CSV.read(csv_path, DataFrame; dateformat = "yyyy-mm-dd HH:MM:SS")
    dropmissing!(df, [:Datetime, :Air_temperature_C, :Relative_humidity_percent, :BlackGlobe_temperature_C])

    df.timestamp = floor.(df.Datetime .- INDOOR_UTC_OFFSET, Hour)
    hourly = combine(groupby(df, :timestamp),
        :Air_temperature_C         => mean => :air_temperature_c,
        :Relative_humidity_percent => mean => :relative_humidity_pct,
        :BlackGlobe_temperature_C  => mean => :globe_temperature_c,
        nrow => :n_minutes)
    sort!(hourly, :timestamp)

    hourly.Tmrt_C = tmrt_from_globe.(hourly.globe_temperature_c, hourly.air_temperature_c)
    hourly.UTCI   = utci.(hourly.air_temperature_c, hourly.Tmrt_C, INDOOR_WIND_SPEED_10M_MS, hourly.relative_humidity_pct)
    return hourly
end

"""
    plot_indoor_vs_outdoor_utci(df_indoor, df_merged, output_path)

Daily mean indoor UTCI vs. outdoor UTCI over the period covered by the indoor measurements, and Tmrt vs. air temperature indoors.
Writes <output_path>/UTCI_indoor_vs_outdoor.{pdf,png}.
"""
function plot_indoor_vs_outdoor_utci(df_indoor, df_merged, output_path)
    # daily means per local day (timestamps are UTC, see time_zones.jl); incomplete days (< 23 hours) dropped as in plot_utci
    function daily(df, cols)
        d = combine(groupby(transform(df, :timestamp => ByRow(t -> Date(utc_to_local(t))) => :date), :date),
                    cols .=> mean .=> cols, nrow => :n_hours)
        return sort!(filter!(r -> r.n_hours >= 23, d), :date)
    end

    indoor_daily  = daily(df_indoor, [:UTCI, :air_temperature_c, :Tmrt_C])
    first_date, last_date = extrema(indoor_daily.date)
    # outdoor: hourly means over hh:00 - hh:59, as used in the model (see outdoor_hourly_means in time_zones.jl)
    outdoor = filter(r -> first_date <= Date(utc_to_local(r.timestamp)) <= last_date, outdoor_hourly_means(df_merged))
    outdoor.UTCI = utci.(outdoor.air_temperature_c, outdoor.Tmrt_C, outdoor.wind_speed_ms, outdoor.relative_humidity_pct)
    outdoor_daily = daily(outdoor, [:UTCI])

    tick_dates = collect(firstdayofmonth(first_date) + Month(1):Month(1):last_date)
    date_ticks = (Dates.value.(tick_dates), Dates.format.(tick_dates, "yyyy-mm-dd"))
    date_lims  = (Dates.value(first_date), Dates.value(last_date))
    style = (titlefontsize = 18, guidefontsize = 18, tickfontsize = 14, legendfontsize = 14, linewidth = 3,
             xticks = date_ticks, xlims = date_lims)

    # tree in front of the window was cut down on 2026-07-23 (no more shading at midday afterwards)
    tree_cut = Dates.value(Date(2026, 7, 23))

    p_utci = Plots.plot(outdoor_daily.date, outdoor_daily.UTCI; label = "Outdoor (Hannover)", color = "#4E79A7",
        ylabel = "UTCI (°C)", legend = :topright, title = "UTCI", style...)
    Plots.plot!(p_utci, indoor_daily.date, indoor_daily.UTCI; label = "Indoor (living room)", color = "#F28E2B", linewidth = 3)
    Plots.vline!(p_utci, [tree_cut]; label = "Tree cut down", color = :grey, linestyle = :dash, linewidth = 2)

    p_tmrt = Plots.plot(indoor_daily.date, Matrix(indoor_daily[:, [:air_temperature_c, :Tmrt_C]]);
        label = ["Air temperature" "Tmrt (from black globe)"], color = ["#4E79A7" "#F28E2B"],
        ylabel = "Temperature (°C)", xlabel = "Date", legend = :topright, title = "Indoor UTCI inputs", style...)
    Plots.vline!(p_tmrt, [tree_cut]; label = nothing, color = :grey, linestyle = :dash, linewidth = 2)

    p = Plots.plot(p_utci, p_tmrt;
        layout = (2, 1), size = (1200, 900),
        plot_title = "Indoor vs. outdoor UTCI (daily mean)", plot_titlefontsize = 22,
        left_margin = 12Plots.mm, bottom_margin = 10Plots.mm, right_margin = 20Plots.mm)

    savefig(p, string(output_path, "/UTCI_indoor_vs_outdoor.pdf"))
    savefig(p, string(output_path, "/UTCI_indoor_vs_outdoor.png"))
end
