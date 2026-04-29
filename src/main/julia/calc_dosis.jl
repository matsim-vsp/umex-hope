"""
    calc_dosis(params, model, person)

    Calculates heat dosis agent is exposed to over the course of the day.
"""
function calc_dosis(params, model, person)
    if params[:heat_time_module] == "24_hours"
        time_exposed = 24

    elseif params[:heat_time_module] == "out_of_home_duration"
        time_exposed = person.not_home_time

    elseif params[:heat_time_module] == "activity_based"
        time_exposed = person.work_time + person.public_leisure_time + person.private_leisure_time + person_daycare_time + person.education_time + person_other_non_home_time + person_walk_time + person_car_time + person_pt_time + person_bike_time
    end

end
