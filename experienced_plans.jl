using Pkg
using DataFrames
using LightXML
using EzXML

function experienced_plans_reader(file_path)

    document = read(file_path, String)
        #document = read("009.output_events.xml", String)
    xml_doc = parsexml(document)
    
    # Get all event elements
    persons = findall("//person", xml_doc)

    # First pass: collect all unique attribute names across all persons
    all_attr_names = Set{String}()
    for person in persons
        for attr in findall(".//attribute", person)
            push!(all_attr_names, attr["name"])
        end
    end

    # Convert to sorted vector for consistent column ordering
    attr_names = sort(collect(all_attr_names))

    # Second pass: build the data row by row
    rows = []
    for person in persons
        row = Dict{String, Any}()
        row["id"] = person["id"]
        
        # Initialize all attributes as missing
        for name in attr_names
            row[name] = missing
        end
        
        # Fill in the attributes that exist for this person
        for attr in findall(".//attribute", person)
            col_name = attr["name"]
            col_value = nodecontent(attr)
            row[col_name] = col_value
        end
        
        push!(rows, row)
    end

    # Build the DataFrame from the rows
    df = DataFrame(rows)
    df = select(df, :id, :carAvail, :sex, :SNZ_hhSize, :SNZ_hhIncome, :income, :SNZ_gender, :home_x, :home_y, :SNZ_age)
    df = filter(row -> !occursin("goodsTraffic", row.id) && !occursin("freight", row.id) && !occursin("commercial", row.id), df)

    return df

end