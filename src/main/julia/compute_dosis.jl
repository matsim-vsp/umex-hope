using DataFrames

include("utci.jl")

thresholds = DataFrame(activity =  ["not_home", "home", "education", "errands", "pt", "bike", "visit", "shop", "work", "business", "walk", 
                                    "leisure", "car", "accomp", "ride", "other"],
                        uncomfortable = [24, 24, 24, 24, 28, 25, 24, 24, 26, 26, 20, 22, 25, 25, 25, 24],
                        critical  = [26, 25, 26, 26, 35, 30, 26, 26, 30,30, 30, 26, 30, 30, 30, 26])

"""
    compute compute_cumulative_UTCI_exceedance(thresholds, person, activity)

    Calculates the cumulative UTCI exceedance for a single activitiy.
    Based on the work by Sadeghi et al (2021) https://doi.org/10.1016/j.buildenv.2021.107947
"""
function compute_cumulative_UTCI_exceedance(temp, thresholds, person, activity)
    compute_cumulative_UTCI_exceedance = (utci(temp) - thresholds[thresholds.activity .== String(activity), :uncomfortable][1]) * person.Symbol(activity, "_time")
end

"""
    compute_dosis_for_activity_based_heat(params, model, person)

    Calculates heat dosis agent is exposed to over the course of the day.
"""
function compute_dosis_for_activity_based_heat(temp, thresholds, person)
    dosis = 0
    if params[:heat_time_module] == "24_hours"
        dosis += 24 * avg_concentration #TODO: Should xx_concentration be a model parameter?
    elseif params[:heat_time_module] == "out_of_home_duration"
        dosis += compute_cumulative_UTCI_exceedance(temp, thresholds, person, Symbol(not_home))
    elseif params[:heat_time_module] == "activity_based"    
        for activity in thresholds.activity
        dosis += compute_cumulative_UTCI_exceedance(temp, thresholds, person, activity)  
        end
    end
    return dosis
end

"""
    calc_dosis(params, model, person)

    Calculates dosis (e.g. of heat or virus particles) agent is exposed to over the course of the day.
"""
function compute_dosis(params, model, person)
    if params[:heat_time_module] == "24_hours"
        if params[:disease] == "heat"
            dosis = compute_dosis_for_activity_based_heat(params, model, person)
        end
    elseif params[:heat_time_module] == "out_of_home_duration"
        if params[:disease] == "heat"
            dosis = compute_dosis_for_activity_based_heat(params, model, person)
        end
        elseif params[:heat_time_module] == "activity_based"
        if params[:disease] == "heat"
            dosis = compute_dosis_for_activity_based_heat(params, model, person)
        end
    end

end