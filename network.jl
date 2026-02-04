using Pkg
using DataFrames
using EzXML

function network_reader(file_path)
    document = read(file_path, String)
    xml_doc = parsexml(document)

    # Get all node elements
    nodes = findall("//node", xml_doc)

    # Create rows of data frame that contain info on nodes (id, x coordinate, y coordinate)
    rows = []

    for node in nodes
        row = (node["id"], node["x"], node["y"])
        push!(rows, row)
    end

    df = DataFrame(rows)
    df = rename!(df,[:id,:x, :y]) 

end
