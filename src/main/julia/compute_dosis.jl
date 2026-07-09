using DataFrames

#include("compute_mrt.jl")
#include("utci_prep.jl")
include("utci.jl")

thresholds = DataFrame(activity =  ["not_home", "home", "education", "errands", "pt", "bike", "visit", "shop", "work", "business", "walk", 
                                    "leisure", "car", "accomp", "ride", "other"],
                        uncomfortable = [24, 24, 24, 24, 28, 25, 24, 24, 26, 26, 20, 22, 25, 25, 25, 24],
                        critical  = [26, 25, 26, 26, 35, 30, 26, 26, 30,30, 30, 26, 30, 30, 30, 26])
# (I think that the above works in "vertical" direction.  E.g., for "not_home", the uncomfortable temperature is 24, and the critical temperature is 26.)

"""
    compute compute_cumulative_UTCI_exceedance(thresholds, person, activity)

    Calculates the cumulative UTCI exceedance for a single activitiy.
    Based on the work by Sadeghi et al (2021) https://doi.org/10.1016/j.buildenv.2021.107947
"""
function compute_cumulative_UTCI_exceedance(airtemp, meanradianttemp, vel, rh, thresholds, person, activity)
    if params[:heat_time_module] == "24_hours"
        compute_cumulative_UTCI_exceedance = (utci(airtemp, meanradianttemp, vel, rh) - thresholds[thresholds.activity .== String(activity), :uncomfortable][1]) * 24
    else
        compute_cumulative_UTCI_exceedance = (utci(airtemp, meanradianttemp, vel, rh) - thresholds[thresholds.activity .== String(activity), :uncomfortable][1]) * getproperty(person, Symbol(activity, "_time"))
    end
end

"""
    compute_dosis_for_activity_based_heat(params, model, person)

    Calculates heat dosis agent is exposed to over the course of the day.
"""
function compute_dosis_for_activity_based_heat(params, thresholds, model, person)
    dosis = 0
    df_merged = params[:df_merged]
    air_temp = df_merged[df_merged.timestamp .== model.timer, :air_temperature_c][1]
    mean_radiant_temp = df_merged[df_merged.timestamp .== model.timer, :Tmrt_C][1]
    vel = df_merged[df_merged.timestamp .== model.timer, :wind_speed_ms][1]
    rh = df_merged[df_merged.timestamp .== model.timer, :relative_humidity_pct][1]
    if params[:heat_time_module] == "24_hours"
        dosis += compute_cumulative_UTCI_exceedance(air_temp, mean_radiant_temp, vel, rh, thresholds, person, "not_home")
    elseif params[:heat_time_module] == "out_of_home_duration"
        dosis += compute_cumulative_UTCI_exceedance(air_temp, mean_radiant_temp, vel, rh, thresholds, person, "not_home")
    elseif params[:heat_time_module] == "activity_based"    
        for activity in thresholds.activity
        dosis += compute_cumulative_UTCI_exceedance(air_temp, mean_radiant_temp, vel, rh, thresholds, person, activity)  
        end
    end
    return max(dosis, 0) # ensure that dosis is not negative
end

"""
    compute_dosis(params, model, person)

    Calculates dosis (e.g. of heat or virus particles) agent is exposed to over the course of the day.
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

end