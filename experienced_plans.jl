using Pkg
using DataFrames
using LightXML
using EzXML


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

    end

    # Build the DataFrame from the rows
    df = DataFrame(rows)
    df = select(df, :id, :carAvail, :sex, :SNZ_hhSize, :SNZ_hhIncome, :income, :SNZ_gender, :home_x, :home_y, :SNZ_age)
    df = filter(row -> !occursin("goodsTraffic", row.id) && !occursin("freight", row.id) && !occursin("commercial", row.id), df)

    return df, activities_dictionary

end