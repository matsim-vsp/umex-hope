"""
    calc_affected_chance(params, model, person)

    Calculates chance of becoming affected.
"""

function calc_affection_chance(params, model, person)

    if params[:heat_time_module] == "24_hours"
        inf_chance = 24*person.affection_age_param*params[:base_susceptibility]
    elseif params[:heat_time_module] == "out_of_home_duration"
        inf_chance = person.affection_age_param*person.not_home_time*params[:base_susceptibility]

    elseif params[:heat_time_module] == "activity_based"
    #TODO
    end
    
    return inf_chance
end