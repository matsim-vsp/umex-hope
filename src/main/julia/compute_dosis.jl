
"""
    compute_dosis_for_activity_based_heat(params, model, person)

    Calculates heat dosis agent is exposed to over the course of the day.
"""
function compute_dosis_for_activity_based_heat(params, model, person)
    dosis = 0
    if params[:heat_time_module] == "24_hours"
        dosis += 24 * avg_concentration #TODO: Should xx_concentration be a model parameter?
    elseif params[:heat_time_module] == "out_of_home_duration"
        dosis += person.not_home_time * not_home_concentration
    elseif params[:heat_time_module] == "activity_based"    
        for activity in activities
        dosis += person.Symbol(activity, "_time") * Symbol(activity, "_concentration") 
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