using Downloads, ZipFile, CSV, DataFrames, Dates

const STATION_ID = "02014"
const BASE_URL   = "https://opendata.dwd.de/climate_environment/CDC/" *
                   "observations_germany/climate/hourly/air_temperature/recent/"

function get_zip_url(station_id::String)
    return BASE_URL * "stundenwerte_TU_$(station_id)_akt.zip"
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

function parse_climate_data(csv_text::String)
    df = CSV.read(IOBuffer(csv_text), DataFrame;
                  delim           = ';',
                  missingstring   = ["-999", "-999.0"],
                  stripwhitespace = true)

    rename!(df, strip.(names(df)) .|> Symbol)

    select!(df, :MESS_DATUM, :TT_TU)
    rename!(df,
        :MESS_DATUM => :timestamp,
        :TT_TU      => :air_temperature_c)

    df.timestamp = DateTime.(string.(df.timestamp), dateformat"yyyymmddHH")

    return df
end

url      = get_zip_url(STATION_ID)
println("Downloading: $url")

zr       = download_dwd_zip(url)
csv_text = extract_data_file(zr)
close(zr)

df_temp = parse_climate_data(csv_text)

println("\nFirst 5 rows:")
println(first(df, 5))
println("\n$(nrow(df)) rows, columns: $(names(df))")