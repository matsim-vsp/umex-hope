include("compute_dosis.jl")

"""
    compute_affected_chance(params, model, person)

    Calculates chance of becoming affected.
"""

function compute_affection_chance(params, model, person)

    person.affection_theta = 10^(-6)
    dosis = compute_dosis(params,model,person)

    if params[:heat_time_module] == "activity_based"
        inf_chance = (1-exp(-person.affection_theta*dosis))
        inf_chance = (1-exp(-person.affection_theta*dosis))
    elseif params[:heat_time_module] == "out_of_home_duration" 
        inf_chance = (1-exp(-person.affection_theta*dosis))
        inf_chance = (1-exp(-person.affection_theta*dosis))
    elseif params[:heat_time_module] == "24_hours"
        inf_chance = (1-exp(-person.affection_theta*dosis))
        inf_chance = (1-exp(-person.affection_theta*dosis))
    end
    
    return dosis, inf_chance
    return dosis, inf_chance
end