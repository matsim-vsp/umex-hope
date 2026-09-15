include("compute_dosis.jl")

"""
    compute_affected_chance(params, model, person)

    Calculates chance of becoming affected.
"""

function compute_agent_relative_risk(params, model, person)
    # Based on Scovronick et al 10.1097/EE9.0000000000000336
    if params[:relative_risk_module] == "Scovronick"
        if person.SNZ_age < 40
            person.relative_risk = 1
        elseif person.SNZ_age >= 40 && person.SNZ_age < 55
            person.relative_risk = 1.06 + 0.015 * randn()
        elseif person.SNZ_age >= 55 && person.SNZ_age < 70
            person.relative_risk = 1.09 + 0.015 * randn()
        elseif person.SNZ_age >= 70 && person.SNZ_age < 85
            person.relative_risk = 1.09 + 0.015 * randn()
        else
            person.relative_risk = 1.16 + 0.015 * randn()
        end
    end
end

function compute_affection_chance(params, model, person)
    person.affection_theta = 10
    compute_agent_relative_risk(params, model, person)
    dosis = compute_dosis(params,model,person)
    if params[:heat_time_module] == "activity_based"
        inf_chance = (1-exp(-person.relative_risk*person.affection_theta*dosis))
        inf_chance = (1-exp(-person.relative_risk*person.affection_theta*dosis))
    elseif params[:heat_time_module] == "out_of_home_duration" 
        inf_chance = (1-exp(-person.relative_risk*person.affection_theta*dosis))
        inf_chance = (1-exp(-person.relative_risk*person.affection_theta*dosis))
    else params[:heat_time_module] == "24_hours"
        inf_chance = (1-exp(-person.relative_risk*person.affection_theta*dosis))
        inf_chance = (1-exp(-person.relative_risk*person.affection_theta*dosis))
    end    
    return dosis, inf_chance
end