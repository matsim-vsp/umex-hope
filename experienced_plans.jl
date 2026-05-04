using Pkg
using DataFrames
using LightXML
using EzXML
using Dates

include("out_of_home_duration.jl")

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
    #activities_dictionary = Dict{String, Dict{String, Dict{String, String}}}()
    #activities_dictionary = Dict{String, Dict{String, Vector{Dict{String, String}}}}()
    activities_dictionary = Dict{String, Vector{Dict{String, String}}}()
    #legs_dictionary = Dict{String, Dict{String, Dict{String, String}}}()
    legs_dictionary = Dict{String, Vector{Dict{String, String}}}()

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

            #Each list is structured as follows
            inner_list = Vector{Dict{String, String}}()
            for activity in activities
                push!(inner_list, Dict(attr.name => attr.content for attr in eachattribute(activity)))
            end

            for val in inner_list
                if !haskey(val, "start_time")
                    val["start_time"] = "00:00:00"
                end
            end
            
            # Adding durations (in seconds) of activities
            for val in inner_list
                start_t = haskey(val, "start_time") ? parse_time(val["start_time"]) : Time(0, 0, 0)
                end_t = haskey(val, "end_time") ? parse_time(val["end_time"]) : Time(23, 59, 59)
                val["duration"] = string(Dates.value(Second(end_t - start_t)))
            end

            # Change names of activities. E.g. work_36600 -> work
            for val in inner_list
                val["type"] = split(val["type"], "_")[1]
            end

            # Remove duplicates by type, keeping the first occurrence #TODO: NEEDS TO BE FIXED. TIMES SHOULD BE ADDED, NOT SECOND ONE REMOVED!!!
            #TODO: Apply sanity check. Do I now actually keep the second activity
            # unique_types = Set{String}()
            # filter!(val -> begin
            #     t = val["type"]
            #     if t in unique_types
            #         false
            #     else
            #         push!(unique_types, t)
            #         true
            #     end
            # end, inner_list)

            activities_dictionary[person["id"]] = inner_list
        end

        # Also reading in legs, not just activities. 04/03: TODO Add start_link and end_link to dictionary
        prefixes = ["freight", "goodsTraffic", "commercialPersonTraffic"]
        if !any(prefix -> startswith(person["id"], prefix), prefixes)
            legs = findall(".//leg", person)
            
            #inner_dict_legs = Dict{String, Dict{Any, Any}}()
            inner_list_legs = Vector{Dict{String, String}}()

            inner_list_legs = Vector{Dict{String, String}}()

            for leg in legs
                push!(inner_list_legs, Dict(attr.name => attr.content for attr in eachattribute(leg)))
                val = last(inner_list_legs)  # reference to the just-added dict

                # SP 04/03/26: We are checking if start_time < 24h. Otherwise the Dates package is giving me trouble. This is probably not a permanent solution and may require fixing
                try
                    val["start_time"] = Dates.format(Time(pop!(val, "dep_time")), "HH:MM:SS")
                catch e
                    if isa(e, ArgumentError)
                        delete!(val, "start_time")
                    end
                end

                if haskey(val, "start_time")
                    # SP 04/03/26: Again, we are checking if end_time < 24h. If this is true, then the end_time is not added. May cause entries, where there exists a start_time, but no end_time
                    try
                        t_start = Time(val["start_time"])
                        t_trav = Time(val["trav_time"])

                        result = t_start + Second(hour(t_trav) * 3600 + minute(t_trav) * 60 + second(t_trav))
                        val["end_time"] = Dates.format(result, "HH:MM:SS")
                    catch e
                        if isa(e, ArgumentError)
                            delete!(val, "end_time")
                            delete!(val, "start_time")
                        end
                    end
                end

                # Adding durations (in seconds) of legs
                start_t = haskey(val, "start_time") ? parse_time(val["start_time"]) : Time(0, 0, 0)
                end_t = haskey(val, "end_time") ? parse_time(val["end_time"]) : Time(23, 59, 59)
                val["duration"] = string(Dates.value(Second(end_t - start_t)))
            end

            legs_dictionary[person["id"]] = inner_list_legs
        end
    end

    # Adding default start/end times for home activities
    for (person_id, inner_list) in activities_dictionary
        for val in inner_list
            if startswith(val["type"], "home")
                get!(val, "start_time", "00:00:00")
                get!(val, "end_time", "23:59:59")
            end
        end
    end

    # Adding legs to activities dictionary
    for (key, value) in legs_dictionary
        if haskey(activities_dictionary, key)
            append!(activities_dictionary[key], value)
        else
            activities_dictionary[key] = value
        end
    end

    # Build the DataFrame from the rows
    df = DataFrame(rows)
    df = select(df, :id, :carAvail, :sex, :SNZ_hhSize, :SNZ_hhIncome, :income, :SNZ_gender, :home_x, :home_y, :SNZ_age)
    df = filter(row -> !occursin("goodsTraffic", row.id) && !occursin("freight", row.id) && !occursin("commercial", row.id), df)

    # Build DataFrame from activities_dictionary
    # Build DataFrame from activities_dictionary
    rows = []
    all_cols = Set{String}()

    for (person_id, inner_list) in activities_dictionary
        row = Dict{String, Any}()
        row["person"] = person_id

        for val in inner_list
            col = haskey(val, "type") ? val["type"] : haskey(val, "mode") ? val["mode"] : nothing
            if !isnothing(col) && haskey(val, "duration")
                dur = parse(Int, val["duration"])
                push!(all_cols, col)
                if haskey(row, col)
                    row[col] += dur
                else
                    row[col] = dur
                end
            end
        end

        push!(rows, row)
    end

    # Ensure all rows have all columns
    for row in rows
        for col in all_cols
            if !haskey(row, col)
                row[col] = 0
            end
        end
    end

    df_durations = DataFrame(rows)
    df_durations = coalesce.(df_durations, 0)
    df_durations = select(df_durations, Not(["bike interaction", "pt interaction", "ride interaction", "car interaction"]))

    return df, activities_dictionary, df_durations

end