using Pkg
using DataFrames
using XML
using EzXML

function facility_reader(file_path)
    """ Read a facilities file (xml) and convert it to a df for further analysis.

    param: filepath path to the file
    """

    facilities_document = read(file_path)
    xml_doc = parsexml(facilities_document)

    facilities = findall("//facility", xml_doc)
    
    data = []

    for facility in facilities
        attrs = Dict(attr.name => attr.content for attr in eachattribute(facility))
        push!(data, attrs)
    end

    return DataFrame(data)
  
end
