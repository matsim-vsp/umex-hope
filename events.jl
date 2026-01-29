using Pkg
using DataFrames
using XML
using EzXML

function event_reader(file_path, actType_or_person)

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

        if haskey(event, actType_or_person)
            act_type = event[actType_or_person]
            act_type = rsplit(act_type, '_', limit=2)[1]
        else
            if actType_or_person == "actType"
                act_type = "no_actType"  # Or use: continue to skip these events
            end
            if actType_or_person == "person"
                act_type = "no_person"  # Or use: continue to skip these events
            end
        end
        
        if !occursin("pt_pt", act_type)
            # Collect all attributes as strings
            attrs = Dict(attr.name => attr.content for attr in eachattribute(event))
            
            # Initialize DataFrame for this type if it doesn't exist
            if !haskey(dfs_by_type, act_type)
                dfs_by_type[act_type] = DataFrame()
            end
            
            # Append this event's data
            push!(dfs_by_type[act_type], attrs, cols=:union)
        end
    end

    return dfs_by_type

end
