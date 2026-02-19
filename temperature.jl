using DataFrames
using Dates

# Daily temperatures for Hannover, data from DWD, data comes from https://www.dwd.de/DE/leistungen/klimadatendeutschland/klimadatendeutschland.html;jsessionid=1F2F14AD99C7E4956A8F9614EB345D94.live31081?nn=561364#buehneTop

"""
    temperature_reader(file_path)

    # Arguments
    `file_path::String`: path of temperature file you want to read.

    #Returns
    `df`: Dataframe containing weather variables by date.
"""
function temperature_reader(file_path)

    # Read all lines
    lines = readlines(file_path)

    # Skip the HTML tag and find the header/data lines
    # Header is the line starting with " STAT", data lines start with "10338"
    data_lines = filter(l -> startswith(strip(l), "10338"), lines)

    # Parse each line
    function parse_field(s)
        s = strip(s) #Removes any leading/trailing whitespace from the string
        isempty(s) ? missing : parse(Float64, s) #if is empty, then position is filled with missing, allows parsing later
    end

    rows = map(data_lines) do line
        (
            STAT = parse(Int,     line[1:5]), #Collects positions 1 to 5, Stationnumber
            DATE = Date(          line[7:14], "yyyymmdd"), # Date
            QN   = parse(Int,     strip(line[16:17])), #Quality level of data (the lower, the more certain)
            TG   = parse(Float64, line[19:24]), #Minimum temperature at ground surface
            TN   = parse(Float64, line[26:31]), #Minimum air temperature
            TM   = parse(Float64, line[33:38]), #Mean air temperature
            TX   = parse(Float64, line[40:45]), #Maximum air temperature
            RFM  = parse_field(   line[47:52]), #Mean relative humidity
            FM   = parse_field(   line[54:59]), #Mean wind speed
            FX   = parse_field(   line[61:66]), #Maximum wind gust speed
            SO   = parse_field(   line[68:73]), #SO is the only column with missing entries, sunshine duration
            NM   = parse_field(   line[75:80]), #Mean cloud cover
            RR   = parse(Float64, line[82:87]), #Precipitation sum
            PM   = parse(Float64, line[89:94]), #Mean Air pressure
        )
    end

    df = DataFrame(rows)

    return df

end