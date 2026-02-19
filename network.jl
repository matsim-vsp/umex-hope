using Pkg
using DataFrames
using EzXML

"""
network_reader(file_path)

Reads in network file. Network must be provided as XML.

# Arguments
- `path_file::String`: path of network file you want to read.

# Returns
- `df_nodes`. Dataframe containing node_id, their x- and y-coordinate.
- `df_links`. Dataframe containing edge_id, their starting and ending node.
"""
function network_reader(file_path)
    document = read(file_path, String)
    xml_doc = parsexml(document)

    # Get all node elements
    nodes = findall("//node", xml_doc)
    links = findall("//link", xml_doc)

    # Create rows of data frame that contain info on nodes (id, x coordinate, y coordinate)
    rows_nodes = []
    rows_links = []

    for node in nodes
        row = (node["id"], parse(Float32, node["x"]), parse(Float32, node["y"]))
        push!(rows_nodes, row)
    end

    for link in links
        row = (link["id"], strip(link["from"]), strip(link["to"]))
        push!(rows_links, row)
    end

    df_nodes = DataFrame(rows_nodes)
    df_nodes = rename!(df_nodes,[:id,:x, :y]) 
    filter!(row -> !contains(row.id, "pt_short"), df_nodes)

    df_links = DataFrame(rows_links)
    df_links = rename!(df_links,[:id_link,:from_node, :to_node]) 
    filter!(row -> !contains(row.id_link, "pt"), df_links)

    # Create a helper dataframe with the desired order
    order_df = DataFrame(from_node = df_nodes.id, order = 1:nrow(df_nodes))

    # Join and sort
    df_links = leftjoin(df_links, order_df, on = :from_node)
    sort!(df_links, :order)
    select!(df_links, Not(:order))  # drop the helper column

    return df_nodes, df_links

end
