using Printf
using Dates
using DataFrames

function parse_time(t::String)
    parts = split(t, ":")
    h = parse(Int, parts[1])
    if h >= 24
        return Time(23, 59, 59)
    end
    return Time(t)
end

function out_of_home_duration(activities::Dict)
    total_seconds = 0
    start_times = [parse_time(val["start_time"]) for (key, val) in activities if haskey(val, "start_time")]
    earliest = isempty(start_times) ? Time(0, 0, 0) : minimum(start_times)
    total_seconds += Dates.value(Second(earliest - Time(0, 0, 0)))
    
    for (key, val) in activities
        if startswith(key, "home")
            start_t = haskey(val, "start_time") ? parse_time(val["start_time"]) : Time(0, 0, 0)
            end_t = haskey(val, "end_time") ? parse_time(val["end_time"]) : Time(23, 59, 59)
            total_seconds += Dates.value(Second(end_t - start_t))
        end
    end
    
    h = total_seconds ÷ 3600
    m = (total_seconds % 3600) ÷ 60
    s = total_seconds % 60
    #return @sprintf("%02d:%02d:%02d", h, m, s)
    return 24 - total_seconds/3600
end

function process_all_agents(agents::Dict)
    rows = []
    
    for agent_id in keys(agents)
        time_str = out_of_home_duration(agents[agent_id])
        push!(rows, (person=agent_id, home_time=time_str))
    end
    
    return DataFrame(rows)
end