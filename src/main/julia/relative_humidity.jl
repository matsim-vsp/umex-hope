using Downloads, ZipFile, CSV, DataFrames, Dates

# ─────────────────────────────────────────────
# 1. Configuration
# ─────────────────────────────────────────────
const STATION_ID = "02014"          # DWD station: Hannover
const BASE_URL   = "https://opendata.dwd.de/climate_environment/CDC/" *
                   "observations_germany/climate/hourly/air_temperature/recent/"

# ─────────────────────────────────────────────
# 2. Find the correct ZIP filename dynamically
#    (DWD filenames embed the date range, e.g.
#     stundenwerte_TU_02564_akt.zip)
# ─────────────────────────────────────────────
function get_zip_url(station_id::String)
    # The "recent" files follow a stable naming pattern
    return BASE_URL * "stundenwerte_TU_$(station_id)_akt.zip"
end

# ─────────────────────────────────────────────
# 3. Download & unzip in memory
# ─────────────────────────────────────────────
function download_dwd_zip(url::String)
    buf = IOBuffer()
    Downloads.download(url, buf)
    seekstart(buf)
    return ZipFile.Reader(buf)
end

# ─────────────────────────────────────────────
# 4. Extract the data file (starts with "produkt_")
# ─────────────────────────────────────────────
function extract_data_file(zr::ZipFile.Reader)
    for f in zr.files
        if startswith(basename(f.name), "produkt_")
            return read(f, String)
        end
    end
    error("No data file found in ZIP archive")
end

# ─────────────────────────────────────────────
# 5. Parse CSV → DataFrame, keep only humidity
# ─────────────────────────────────────────────
function parse_humidity(csv_text::String)
    df = CSV.read(IOBuffer(csv_text), DataFrame;
                  delim      = ';',
                  missingstring = ["-999", "-999.0"],
                  stripwhitespace = true)

    # DWD column names have trailing spaces → normalize
    rename!(df, strip.(names(df)) .|> Symbol)

    # Relevant columns:
    #   MESS_DATUM  → timestamp (YYYYMMDDhh)
    #   TT_TU       → air temperature [°C]
    #   RF_TU       → relative humidity [%]
    select!(df, :MESS_DATUM, :RF_TU)
    rename!(df, :MESS_DATUM => :timestamp, :RF_TU => :relative_humidity_pct)

    # Parse timestamp string → DateTime
    df.timestamp = DateTime.(string.(df.timestamp), dateformat"yyyymmddHH")

    return df
end

# ─────────────────────────────────────────────
# 6. Main
# ─────────────────────────────────────────────
url    = get_zip_url(STATION_ID)
println("Downloading: $url")

zr     = download_dwd_zip(url)
csv_text = extract_data_file(zr)
close(zr)

df_humidity = parse_humidity(csv_text)

println("\nFirst 40 rows:")
println(first(df, 40))

println("\nDataFrame info: $(nrow(df)) rows, columns: $(names(df))")