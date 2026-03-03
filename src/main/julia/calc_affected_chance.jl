"""
    calc_affected_chance(params, model, person)

    Calculates chance of becoming affected.
"""

function calc_affected_chance(params, model, person)

    if params[:heat_time_module] == "24hours"
    inf_chance = 24*params[:base_susceptibility]
    return inf_chance

    elseif params[:heat_time_module] == "out_of_home_duration"
    inf_chance = person.not_home_time*params[:base_susceptibility]
    return inf_chance

    elseif params[:heat_time_module] == "activity_based"
    #TODO
    end

end