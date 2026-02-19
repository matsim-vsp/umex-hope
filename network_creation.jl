using Graphs
#using GraphPlot
#using Compose
using GraphMakie
using GLMakie

include("network.jl")

"""
network_creation(path_file)

Creates a graph based on your network. Network needs to be provided as XML. Calls on network_reader, which actually reads in network file and creates one data frame containing the nodes and one containing the edges.

# Arguments
- `path_file::String`: path of network file you want to turn into a graph.

# Returns
- `g::SimpleGraph`. Graph type from graphs.jl library.
"""
function network_creation(path_file)
    #nodes_df, links_df = network_reader("hannover-1pct.output_network.xml")
    nodes_df, links_df = network_reader(path_file)

    link_ids = nodes_df.id
    x_coords = nodes_df.x
    y_coords = nodes_df.y

    # Create mapping
    id_to_index = Dict(link_ids[i] => i for i in 1:length(link_ids))
    id_to_index = sort(id_to_index)
    index_to_id = Dict(i => link_ids[i] for i in 1:length(link_ids))

    g = SimpleGraph(length(link_ids))

    # Add edges using your IDs
    for i in 1:length(link_ids)
        start_node = id_to_index[links_df.from_node[i]]
        end_node = id_to_index[links_df.to_node[i]]
        add_edge!(g, start_node, end_node)
    end

    #Plotting to check if network's been read in correctly
    # Pick the first 10,000 nodes
    # sub_nodes = collect(1:10000)

    # # Create subgraph - returns the subgraph and a mapping back to original indices
    # subg, vmap = induced_subgraph(g, sub_nodes)
    # layout = [Point2(x_coords[vmap[i]], y_coords[vmap[i]]) for i in 1:length(vmap)]
    # # Plot it
    # GraphMakie.graphplot(subg, layout = layout)

    return g

end