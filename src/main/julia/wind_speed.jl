using Downloads, ZipFile, CSV, DataFrames, Dates

const STATION_ID = "02014"
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

url      = get_zip_url(STATION_ID)
println("Downloading: $url")

zr       = download_dwd_zip(url)
csv_text = extract_data_file(zr)
close(zr)

df_wind = parse_wind_data(csv_text)

println("\nFirst 5 rows:")
println(first(df, 5))
println("\n$(nrow(df)) rows, columns: $(names(df))")