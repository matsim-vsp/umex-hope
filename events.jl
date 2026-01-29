using Pkg
using DataFrames
using XML
using EzXML

function event_reader(file_path)

    """ Read an events file (xml), yielding each contained event.
        Events will be
    """
    document = read(file_path, String)
    #document = read("009.output_events.xml", String)
    xml_doc = parsexml(document)
  
    # Get all event elements
    events = findall("//event", xml_doc)

    # Create a dictionary to store DataFrames by type
    dfs_by_type = Dict{String, DataFrame}()

    # Process each event
    for event in events
        # Extract attributes

        #event = events[1]

        if haskey(event, "actType")
            act_type = event["actType"]
            act_type = rsplit(act_type, '_', limit=2)[1]
        else
            act_type = "no_actType"  # Or use: continue to skip these events
        end
        
        # Collect all attributes as strings
        attrs = Dict(attr.name => attr.content for attr in eachattribute(event))
        
        # Initialize DataFrame for this type if it doesn't exist
        if !haskey(dfs_by_type, act_type)
            dfs_by_type[act_type] = DataFrame()
        end
        
        # Append this event's data
        push!(dfs_by_type[act_type], attrs, cols=:union)
    end

    return dfs_by_type

end
