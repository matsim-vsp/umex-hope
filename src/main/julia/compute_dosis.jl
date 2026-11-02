using DataFrames
using Dates

#include("compute_mrt.jl")
#include("utci_prep.jl")
include("utci.jl")

thresholds = DataFrame(activity =  ["not_home", "home", "education", "errands", "pt", "bike", "visit", "shop", "work", "business", "walk", 
                                    "leisure", "car", "accomp", "ride", "other"],
                        uncomfortable = [24, 24, 24, 24, 28, 25, 24, 24, 26, 26, 20, 22, 25, 25, 25, 24],
                        critical  = [26, 25, 26, 26, 35, 30, 26, 26, 30,30, 30, 26, 30, 30, 30, 26])
# (I think that the above works in "vertical" direction.  E.g., for "not_home", the uncomfortable temperature is 24, and the critical temperature is 26.)

# activity types / leg modes in the experienced plans whose name differs from the one in thresholds
const plan_activity_names = Dict("educ" => "education")

"""
    hourly_utci(df_merged)

    Builds a lookup table timestamp -> UTCI from the hourly weather data.
"""
function hourly_utci(df_merged)
    return Dict(zip(df_merged.timestamp,
                    utci.(df_merged.air_temperature_c, df_merged.Tmrt_C, df_merged.wind_speed_ms, df_merged.relative_humidity_pct)))
end

"""
    hourly_activity_seconds(plan)

    Seconds an agent spends at each activity in each hour of the day, based on the start and end times of the activities and legs in their experienced plan.
    Returns a 24 x nrow(thresholds) matrix: row h+1 is the hour h:00 - h:59, columns follow thresholds.activity.
    "not_home" is the part of each hour that is not spent at home.
"""
function hourly_activity_seconds(plan)
    seconds = zeros(24, nrow(thresholds))
    home_col = findfirst(==("home"), thresholds.activity)
    not_home_col = findfirst(==("not_home"), thresholds.activity)
    for val in plan
        name = haskey(val, "type") ? val["type"] : haskey(val, "mode") ? val["mode"] : nothing
        isnothing(name) && continue
        col = findfirst(==(get(plan_activity_names, name, name)), thresholds.activity)
        isnothing(col) && continue
        # same defaults as in experienced_plans_reader
        start_s = haskey(val, "start_time") ? Dates.value(Second(parse_time(val["start_time"]) - Time(0, 0, 0))) : 0
        end_s = haskey(val, "end_time") ? Dates.value(Second(parse_time(val["end_time"]) - Time(0, 0, 0))) : 86399
        for h in 0:23
            overlap = min(end_s, 3600 * (h + 1)) - max(start_s, 3600 * h)
            if overlap > 0
                seconds[h + 1, col] += overlap
            end
        end
    end
    seconds[:, not_home_col] = max.(3600 .- seconds[:, home_col], 0)
    return seconds
end

"""
    compute compute_cumulative_UTCI_exceedance(utci_value, activity_index, hours)

    Calculates the UTCI exceedance for a single activitiy during a single hour.
    Hours below the threshold contribute 0, i.e. they do not compensate for hot hours.
    Based on the work by Sadeghi et al (2021) https://doi.org/10.1016/j.buildenv.2021.107947
"""
function compute_cumulative_UTCI_exceedance(utci_value, activity_index, hours)
    return max(utci_value - thresholds.uncomfortable[activity_index], 0) * hours
end

"""
    compute_hourly_dosis(params, model, agentid, day)

    Heat dosis an agent is exposed to in each hour of the given day. Returns a vector of 24 values: entry h+1 is the hour h:00 - h:59.
"""
function compute_hourly_dosis(params, model, agentid, day)
    hourly_dosis = zeros(24)
    day_start = DateTime(day)
    not_home_col = findfirst(==("not_home"), thresholds.activity)
    seconds = model.hourly_activity_seconds[agentid]
    for h in 0:23
        utci_value = model.utci_hourly[day_start + Hour(h)]
        if params[:heat_time_module] == "24_hours"
            hourly_dosis[h + 1] += compute_cumulative_UTCI_exceedance(utci_value, not_home_col, 1)
        elseif params[:heat_time_module] == "out_of_home_duration"
            hourly_dosis[h + 1] += compute_cumulative_UTCI_exceedance(utci_value, not_home_col, seconds[h + 1, not_home_col] / 3600)
        elseif params[:heat_time_module] == "activity_based"
            for col in eachindex(thresholds.activity)
                col == not_home_col && continue
                hourly_dosis[h + 1] += compute_cumulative_UTCI_exceedance(utci_value, col, seconds[h + 1, col] / 3600)
            end
        end
    end
    return hourly_dosis
end

"""
    compute_dosis_for_activity_based_heat(params, model, person)

    Calculates heat dosis agent is exposed to over the course of the day, summed over the 24 hourly UTCI values of the current day.
"""
function compute_dosis_for_activity_based_heat(params, thresholds, model, person)
    return sum(compute_hourly_dosis(params, model, person.SNZ_id, Date(model.timer)))
end

"""
    nighttime_recovery(agent, model)

    Recovery from the dosis accumulated throughout the previous day while sleeping (00:00 - 05:59).
    Modeled as exponential decay s(t) = s_0 * exp(-max_night_recovery_rate * recovery_efficiency * t) for t in 0:5,
    where s_0 = agent.dosis_midnight. On hot (tropical) nights recovery_efficiency < 1, so part of the dosis remains.
    Returns the remaining dosis s(5), to which the dosis of the new day is added.
"""
function nighttime_recovery(agent, model)
    s_0 = agent.dosis_midnight
    s = [s_0 * exp(-model.max_night_recovery_rate * model.recovery_efficiency * t) for t in 0:5]
    return s[end]
end

"""
    compute_dosis(params, model, person)

    Calculates dosis (e.g. of heat or virus particles) agent is exposed to over the course of the day,
    plus the remainder of the previous day's dosis that was not recovered during the night (see nighttime_recovery).
"""
function compute_dosis(params, model, person)
    if params[:heat_time_module] == "24_hours"
        if params[:disease] == "heat"
            dosis = compute_dosis_for_activity_based_heat(params, thresholds, model, person)
        end
    elseif params[:heat_time_module] == "out_of_home_duration"
        if params[:disease] == "heat" 
            dosis = compute_dosis_for_activity_based_heat(params, thresholds, model, person)
        end
    elseif params[:heat_time_module] == "activity_based"
        if params[:disease] == "heat"
            dosis = compute_dosis_for_activity_based_heat(params, thresholds, model, person)
        end
    end
    return nighttime_recovery(person, model) + dosis
end