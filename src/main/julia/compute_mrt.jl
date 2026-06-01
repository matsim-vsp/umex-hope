"""
Mean Radiant Temperature (MRT) for Hannover from DWD Open Data
==============================================================
Data sources used:
  - Hourly solar radiation (global + diffuse + longwave downward):
      https://opendata.dwd.de/climate_environment/CDC/observations_germany/climate/hourly/solar/
  - Hourly air temperature:
      https://opendata.dwd.de/climate_environment/CDC/observations_germany/climate/hourly/air_temperature/

Method (Klima-Michel-Model / ISO 7726 outdoor approach)
-------------------------------------------------------
For an unobstructed outdoor standing person:

  Tmrt = [ (1/(εp*σ)) * (
      fp * αk * I_dir / sin(h_sun)   # direct solar on projected body area
    + 0.5 * αk * (I_diff + albedo*I_glob)  # diffuse shortwave
    + 0.5 * εp * (L_down + L_up)           # longwave (sky + ground)
  ) ]^0.25  - 273.15

Constants:
  σ      = 5.67e-8  W m⁻² K⁻⁴   Stefan–Boltzmann
  fp     = 0.308    projected area factor (standing person)
  αk     = 0.70     shortwave absorption coefficient (clothed body)
  εp     = 0.97     longwave emissivity (clothed body)
  εg     = 0.95     ground emissivity
  albedo = 0.20     ground albedo

DWD unit: J/cm²  →  W/m²  by dividing by 3600 s and multiplying by 10 000.
"""

using HTTP
using CSV
using DataFrames
using ZipFile
using Dates
using Printf
using Statistics

# ── Configuration ────────────────────────────────────────────────────────────
const BASE_URL  = "https://opendata.dwd.de/climate_environment/CDC/observations_germany/climate"
const HAN_LAT   = 52.4641
const HAN_LON   = 9.6851
const HAN_ALT   = 55.0       # metres above sea level

# Radiation constants
const SIGMA   = 5.67e-8   # Stefan-Boltzmann  [W m-2 K-4]
const ALPHA_K = 0.70      # shortwave absorption (clothed body)
const EPS_P   = 0.97      # longwave emissivity (clothed body)
const EPS_G   = 0.95      # ground emissivity
const FP      = 0.308     # projected area factor
const ALBEDO  = 0.20      # ground albedo

# ── Helpers ───────────────────────────────────────────────────────────────────

"""Download bytes from url; raise on HTTP error."""
function fetch_bytes(url::String)::Vector{UInt8}
    resp = HTTP.get(url; readtimeout=120, connect_timeout=30)
    if resp.status != 200
        error("HTTP $(resp.status) for $url")
    end
    return resp.body
end

"""Read a single CSV file from a ZIP archive (first matching prefix)."""
function read_csv_from_zip(data::Vector{UInt8}, prefix::String)::DataFrame
    r = ZipFile.Reader(IOBuffer(data))
    for f in r.files
        if startswith(basename(f.name), prefix)
            content = read(f)
            close(r)
            return CSV.read(IOBuffer(content), DataFrame;
                            delim=';', missingstring=["-999", "-1", "-999.0"],
                            silencewarnings=true)
        end
    end
    close(r)
    error("No file with prefix '$prefix' found in ZIP")
end

"""Convert DWD J/cm² per hour → W/m²."""
jcm2_to_Wm2(x) = x / 3600.0 * 10_000.0

# ── Solar elevation (Spencer / Michalsky, no external package needed) ─────────

"""
Approximate solar elevation angle [radians] for a UTC datetime,
latitude [°], longitude [°].
Returns elevation in radians (0 when below horizon).
"""
function solar_elevation(dt::DateTime, lat_deg::Float64, lon_deg::Float64)::Float64
    # Day of year
    doy = dayofyear(dt)
    # Hour angle
    B = 2π * (doy - 1) / 365.0
    # Equation of time (minutes)
    eot = 229.18 * (0.000075 + 0.001868*cos(B) - 0.032077*sin(B)
                    - 0.014615*cos(2B) - 0.04089*sin(2B))
    # Solar declination (radians)
    decl = 0.006918 - 0.399912*cos(B) + 0.070257*sin(B) -
           0.006758*cos(2B) + 0.000907*sin(2B) -
           0.002697*cos(3B) + 0.00148*sin(3B)
    # Solar noon correction
    hour_utc = hour(dt) + minute(dt)/60.0
    solar_time = hour_utc + lon_deg/15.0 + eot/60.0
    ha = deg2rad(15.0 * (solar_time - 12.0))   # hour angle [rad]
    lat = deg2rad(lat_deg)
    sin_elev = sin(lat)*sin(decl) + cos(lat)*cos(decl)*cos(ha)
    return max(0.0, asin(clamp(sin_elev, -1.0, 1.0)))
end

# ── Step 2: Download solar data ───────────────────────────────────────────────

function download_solar(sid::Int)::DataFrame
    url = "$BASE_URL/hourly/solar/stundenwerte_ST_$(lpad(sid,5,'0'))_row.zip"
    println("Downloading solar data …\n  $url")
    data = fetch_bytes(url)
    df   = read_csv_from_zip(data, "produkt_")

    # Normalise column names
    rename!(df, strip.(names(df)) .=> strip.(names(df)))

    # Parse datetime
    #df[!, :datetime] = DateTime.(string.(df[!, :MESS_DATUM]), dateformat"yyyymmddHH:MM")
    df[!, :datetime] = floor.(DateTime.(string.(df[!, :MESS_DATUM]), dateformat"yyyymmddHH:MM"), Dates.Hour)
    # Identify radiation columns by content of name
    col_I_glob = findfirst(c -> occursin(r"global|FG_LBERG"i, string(c)), names(df))
    col_I_diff = findfirst(c -> occursin(r"diffus|FD_LBERG"i, string(c)), names(df))
    col_L_down = findfirst(c -> occursin(r"atmo|gegenstrahlung|langwellig|ATMO"i, string(c)), names(df))

    isnothing(col_I_glob) && error("Global radiation column not found. Columns: $(names(df))")
    isnothing(col_I_diff) && error("Diffuse radiation column not found.")
    isnothing(col_L_down) && error("Longwave downward column not found.")

    result = DataFrame(
        datetime = df[!, :datetime],
        I_glob   = jcm2_to_Wm2.(coalesce.(df[!, col_I_glob], NaN)),
        I_diff   = jcm2_to_Wm2.(coalesce.(df[!, col_I_diff], NaN)),
        L_down   = jcm2_to_Wm2.(coalesce.(df[!, col_L_down], NaN)),
    )
    # Clip negatives to 0
    result[!, :I_glob] = max.(result[!, :I_glob], 0.0)
    result[!, :I_diff] = max.(result[!, :I_diff], 0.0)
    result[!, :L_down] = max.(result[!, :L_down], 0.0)

    sort!(result, :datetime)
    @printf("  %d hourly solar records (%s – %s)\n\n",
            nrow(result),
            Date(minimum(result.datetime)),
            Date(maximum(result.datetime)))
    return result
end

# ── Step 3: Download air temperature ─────────────────────────────────────────

function find_historical_filename(sid::Int)::Union{String, Nothing}
    url = "$BASE_URL/hourly/air_temperature/historical/"
    resp = HTTP.get(url; readtimeout=30, connect_timeout=30)
    body = String(resp.body)
    pattern = Regex("stundenwerte_TU_$(lpad(sid,5,'0'))_\\d+_\\d+_hist\\.zip")
    m = match(pattern, body)
    return isnothing(m) ? nothing : m.match
end

function download_temperature(sid::Int)::DataFrame
    frames = DataFrame[]

    # Recent
    url = "$BASE_URL/hourly/air_temperature/recent/" *
          "stundenwerte_TU_$(lpad(sid,5,'0'))_akt.zip"
    try
        data = fetch_bytes(url)
        df   = read_csv_from_zip(data, "produkt_")
        rename!(df, strip.(names(df)) .=> strip.(names(df)))
        println("  Temperature columns found: ", names(df))
        println("  First 3 rows: ", first(df, 3))
        df[!, :datetime] = DateTime.(string.(df[!, :MESS_DATUM]), dateformat"yyyymmddHH")
        push!(frames, DataFrame(
            datetime = df[!, :datetime],
            T_air_C  = df[!, "TT_TU"]
        ))
    catch e
        @warn "Could not load temperature (recent): $e"
    end

    # Historical — discover filename dynamically
    hist_file = find_historical_filename(sid)
    if !isnothing(hist_file)
        url = "$BASE_URL/hourly/air_temperature/historical/$hist_file"
        try
            data = fetch_bytes(url)
            df   = read_csv_from_zip(data, "produkt_")
            rename!(df, strip.(names(df)) .=> strip.(names(df)))
            df[!, :datetime] = DateTime.(string.(df[!, :MESS_DATUM]), dateformat"yyyymmddHH")
            push!(frames, DataFrame(
                datetime = df[!, :datetime],
                T_air_C  = df[!, "TT_TU"]
            ))
        catch e
            @warn "Could not load temperature (historical): $e"
        end
    else
        @warn "No historical temperature file found for station $sid"
    end

    isempty(frames) && return DataFrame(datetime=DateTime[], T_air_C=Float64[])

    result = vcat(frames...)
    sort!(result, :datetime)
    unique!(result, :datetime)
    @printf("  %d hourly temperature records (%s – %s)\n\n",
            nrow(result),
            Date(minimum(result.datetime)),
            Date(maximum(result.datetime)))
    return result
end

# ── Step 4: Compute MRT ───────────────────────────────────────────────────────

function compute_mrt!(df::DataFrame, lat::Float64, lon::Float64)::DataFrame
    n = nrow(df)
    Tmrt = Vector{Float64}(undef, n)

    for i in 1:n
        I_glob = isnan(df.I_glob[i]) ? 0.0 : df.I_glob[i]
        I_diff = isnan(df.I_diff[i]) ? 0.0 : df.I_diff[i]
        L_down = isnan(df.L_down[i]) ? 300.0 : df.L_down[i]
        T_air_K = (coalesce(df.T_air_C[i], 15.0) + 273.15)

        h_sun = solar_elevation(df.datetime[i], lat, lon)

        # Direct horizontal irradiance
        I_dir_h = max(I_glob - I_diff, 0.0)

        # Ground longwave upward
        L_up = EPS_G * SIGMA * T_air_K^4

        # Shortwave: direct beam on body
        SW_direct = if sin(h_sun) > 0.01
            FP * ALPHA_K * I_dir_h / sin(h_sun)
        else
            0.0
        end

        # Shortwave: diffuse (sky + ground reflection)
        SW_diffuse = 0.5 * ALPHA_K * (I_diff + ALBEDO * I_glob)

        # Longwave: upper + lower hemisphere
        LW = 0.5 * EPS_P * (L_down + L_up)

        # Total absorbed flux → Tmrt
        S_abs = SW_direct + SW_diffuse + LW
        Tmrt[i] = (S_abs / (EPS_P * SIGMA))^0.25 - 273.15
    end

    df[!, :Tmrt_C] = round.(Tmrt; digits=2)
    return df
end

# ── Step 5: Main ──────────────────────────────────────────────────────────────

function main()
    println("=" ^ 65)
    println("  Mean Radiant Temperature – Hannover – DWD Open Data")
    println("=" ^ 65 * "\n")

    sid = 00662

    solar = download_solar(sid)

    temp = download_temperature(sid)
    if nrow(temp) == 0
        @warn "No temperature data found for station $sid; using 15 °C fallback."
        temp = DataFrame(datetime=solar.datetime, T_air_C=fill(15.0, nrow(solar)))
    end

    # Merge solar + temperature on datetime
    df_mrt = leftjoin(solar, temp; on=:datetime)
    df_mrt[!, :T_air_C] = coalesce.(df_mrt[!, :T_air_C], 15.0)

    # # Compute MRT
    println("Computing MRT …")
    df_mrt = compute_mrt!(df_mrt, HAN_LAT, HAN_LON)

    # # ── Print sample ──────────────────────────────────────────────────────
    println("\nLast 24 hourly rows:")
    show(last(df_mrt[!, [:datetime, :I_glob, :I_diff, :L_down, :T_air_C, :Tmrt_C]], 200),
         allrows=true)

    # # ── Save CSV ──────────────────────────────────────────────────────────
    # out = joinpath(@__DIR__, "hannover_mrt_hourly.csv")
    # CSV.write(out, df[!, [:datetime, :I_glob, :I_diff, :L_down, :T_air_C, :Tmrt_C]])
    # println("\nFull hourly data saved to: $out")
    # println("Done.")
    return df_mrt
end

df_mrt = main()

