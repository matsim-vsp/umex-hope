using Downloads, ZipFile, CSV, DataFrames, Dates

const STATION_ID = "02014"
const STATION_ID_BACKUP = "00662"   # Braunschweig
# Period in which station STATION_ID (Hannover) has missing data → use backup station
const BACKUP_START = DateTime(2026, 3, 1, 0)
const BACKUP_END   = DateTime(2026, 7, 31, 23)
const BASE_URL   = "https://opendata.dwd.de/climate_environment/CDC/" *
                   "observations_germany/climate/hourly/wind/recent/"

function get_zip_url(station_id::String)
    return BASE_URL * "stundenwerte_FF_$(station_id)_akt.zip"
end

function download_dwd_zip(url::String)
    buf = IOBuffer()
    Downloads.download(url, buf)
    seekstart(buf)
    return ZipFile.Reader(buf)
end

function extract_data_file(zr::ZipFile.Reader)
    for f in zr.files
        if startswith(basename(f.name), "produkt_")
            return read(f, String)
        end
    end
    error("No data file found in ZIP archive")
end

function parse_wind_data(csv_text::String)
    df = CSV.read(IOBuffer(csv_text), DataFrame;
                  delim           = ';',
                  missingstring   = ["-999", "-999.0"],
                  stripwhitespace = true)

    rename!(df, strip.(names(df)) .|> Symbol)

    # FF_10: mean wind speed at 10 m height [m/s]
    # DD:    wind direction [degrees], included for context
    select!(df, :MESS_DATUM, :F)
    rename!(df,
        :MESS_DATUM => :timestamp,
        :F     => :wind_speed_ms)

    df.timestamp = DateTime.(string.(df.timestamp), dateformat"yyyymmddHH")

    return df
end

function load_station(station_id::String)
    url = get_zip_url(station_id)
    println("Downloading: $url")
    zr       = download_dwd_zip(url)
    csv_text = extract_data_file(zr)
    close(zr)
    return parse_wind_data(csv_text)
end

df_main   = load_station(STATION_ID)
df_backup = load_station(STATION_ID_BACKUP)

# Use Braunschweig data in the backup period and for any other hour that is
# missing (value or whole row) at Hannover
in_backup_period(t) = BACKUP_START <= t <= BACKUP_END
df_wind = outerjoin(df_main, rename(df_backup, :wind_speed_ms => :wind_speed_backup);
                    on = :timestamp)
df_wind.wind_speed_ms = ifelse.(in_backup_period.(df_wind.timestamp),
                                df_wind.wind_speed_backup,
                                coalesce.(df_wind.wind_speed_ms, df_wind.wind_speed_backup))
select!(df_wind, :timestamp, :wind_speed_ms)
sort!(df_wind, :timestamp)

println("\nFirst 5 rows:")
println(first(df_wind, 5))
println("\n$(nrow(df_wind)) rows, columns: $(names(df_wind))")
println("Missing wind speed values: $(count(ismissing, df_wind.wind_speed_ms))")
