using Pkg
using DataFrames
using LightXML
using EzXML
using Dates

"""
    experienced_plans_reader(file_path)

    # Arguments
    `file_path::String`: path of experienced plans file you want to read.
"""
function experienced_plans_reader(file_path)
    # Read and parse XML file
    document = read(file_path, String)
    xml_doc = parsexml(document)
    # Get all person elements
    persons = findall("//person", xml_doc)

    # Collect all unique attribute names across all persons
    all_attr_names = Set{String}()
    for person in persons
        for attr in findall(".//attribute", person)
            push!(all_attr_names, attr["name"])
        end
    end

    # Build df/dictionary person by person
    rows = []
    activities_dictionary = Dict{String, Dict{String, Dict{String, String}}}()
    legs_dictionary = Dict{String, Dict{String, Dict{String, String}}}()

    for person in persons
        row = Dict{String, Any}()
        row["id"] = person["id"]
        
        # Initialize all attributes as missing
        for name in all_attr_names
            row[name] = missing
        end
        
        # Fill in the attributes that exist for this person
        for attr in findall(".//attribute", person)
            col_name = attr["name"]
            col_value = nodecontent(attr)
            row[col_name] = col_value
        end
        
        push!(rows, row)

        # We are not interested in commercial agents, they are excluded from the dictionary
        prefixes = ["freight", "goodsTraffic", "commercialPersonTraffic"]
        if !any(prefix -> startswith(person["id"], prefix), prefixes)
            activities = findall(".//activity", person)

            inner_dict = Dict{String, Dict{String, String}}()
            for activity in activities
                inner_dict[activity["type"]] = Dict(attr.name => attr.content for attr in eachattribute(activity))
            end 

            activities_dictionary[person["id"]] = inner_dict
        end

        prefixes = ["freight", "goodsTraffic", "commercialPersonTraffic"]
        if !any(prefix -> startswith(person["id"], prefix), prefixes)
            legs = findall(".//leg", person)
            
            inner_dict_legs = Dict{String, Dict{Any, Any}}()
            for leg in legs
                inner_dict_legs[leg["mode"]] = Dict(attr.name => attr.content for attr in eachattribute(leg))
                # SP 04/03/26: We are checking if start_time < 24h. Otherwise the Dates package is giving me trouble. This is probably not a permanent solution and may require fixing
                try
                    inner_dict_legs[leg["mode"]]["start_time"] = Dates.format(Time(pop!(inner_dict_legs[leg["mode"]], "dep_time")), "HH:MM:SS")
                catch e
                    if isa(e, ArgumentError)
                        delete!(inner_dict_legs[leg["mode"]], "start_time")
                    end
                end
                if haskey(inner_dict_legs[leg["mode"]], "start_time")
                    #SP 04/03/26: Again, we are checking if end_time < 24h. If this is true, then the end_time is not added. May cause entries, where there exists a start_time, but no end_time
                    try
                        t_start = Time(inner_dict_legs[leg["mode"]]["start_time"])
                        t_trav = Time(inner_dict_legs[leg["mode"]]["trav_time"])

                        result = t_start + Second(hour(t_trav) * 3600 + minute(t_trav) * 60 + second(t_trav))
                        inner_dict_legs[leg["mode"]]["end_time"] = Dates.format(result, "HH:MM:SS")
                    catch e
                        if isa(e, ArgumentError)
                            delete!(inner_dict_legs[leg["mode"]], "end_time")
                            delete!(inner_dict_legs[leg["mode"]], "start_time")
                        end
                    end
                end
            end 

        legs_dictionary[person["id"]] = inner_dict_legs
        end
    end

    for (person_id, nested_dict) in activities_dictionary
        for (key, val) in nested_dict
            if startswith(key, "home")
                if !haskey(nested_dict[key], "start_time")
                    nested_dict[key]["start_time"] = "00:00:00"
                end
                if !haskey(nested_dict[key], "end_time")
                    nested_dict[key]["end_time"] = "23:59:59"
                end
            end
        end
    end

    # Build the DataFrame from the rows
    df = DataFrame(rows)
    df = select(df, :id, :carAvail, :sex, :SNZ_hhSize, :SNZ_hhIncome, :income, :SNZ_gender, :home_x, :home_y, :SNZ_age)
    df = filter(row -> !occursin("goodsTraffic", row.id) && !occursin("freight", row.id) && !occursin("commercial", row.id), df)

    return df, activities_dictionary, legs_dictionary

end