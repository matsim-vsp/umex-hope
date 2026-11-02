using Pkg
Pkg.activate(@__DIR__)
using Agents, Random, Graphs, DataFrames, Statistics, CSV, Dates

include("compute_affection_chance.jl")

#This work partly recycles code from previous work https://github.com/matsim-vsp/epi-net-sim/blob/main/src/main/julia/model.jl

# Define Agent
@agent struct Person_Sim(GraphAgent)
    SNZ_id::String
    SNZ_age::Int64
    SNZ_gender::String
    SNZ_hhIncome::Int64
    SNZ_hhSize::Int64
    home_x::Float64
    home_y::Float64
    income::Float64
    sex::String
    not_home_time::Float64
    home_time::Float64
    education_time::Float64
    errands_time::Float64
    pt_time::Float64
    bike_time::Float64
    visit_time::Float64
    shop_time::Float64
    work_time::Float64
    business_time::Float64
    walk_time::Float64
    leisure_time::Float64
    car_time::Float64
    accomp_time::Float64
    ride_time::Float64
    other_time::Float64
    health_status::String # susceptible, exposed, affected, newlyaffected
    dosis::Float64
    dosis_midnight::Float64 # dosis accumulated up to the end of the previous day (incl. remainder of earlier nights), overwritten every day
    heat_exposure::Float64
    days_exposed :: Int
    inf_chance_for_iteration::Float64 # if susceptible person had contact with infectious person, then this variable saves the infection chance (including the reduction_factor). In all other cases: missing
    pregnancy::Int64
    premorbidity::Int64
    experienced_plans_reader::Dict
    affection_theta::Float64
    relative_risk::Float64
end

"""
    run_model(params)

    # Arguments
    - params::Dict. Dictionary containing all the necessary model parameters.
"""
function run_model(params)
    @time begin

        # sets output directory. If running on cluster, output folder is specified by start_multiple_sh. If run locally, a new folder will be created w/ current datetime 
        if ismissing(params[:output_folder])
            output_path = "output/" * replace(first(string(now()), 19), ":" => "")
            mkpath(output_path)
        else
            output_path = params[:output_folder]
        end

        # writes _info.csv with all relevant input parameters; agent_attributes needs to be removed, is simply too large
        params_subset = filter(p -> p.first != :agent_attributes, params)
        params_subset = filter(p -> p.first != :network, params_subset)
        params_subset = filter(p -> p.first != :temperature, params_subset)
        params_subset = filter(p -> p.first != :experienced_plans_dict, params_subset)
        params_subset[:output_path] = output_path  
        CSV.write(joinpath(output_path, "input_params.csv"), params_subset)

        println("#######################")
        println("PRINT STH INTERESTING WHILE RUNNING THE SIMULATION")
        println("#######################")

        local model 

        # loop through all seeds
        for seed in 1:params[:seeds]

            # Create network 
            net = initializeNetwork(params[:network])

            # Create model
            model = initialize(
                net,
                params[:base_susceptibility],
                params[:recovery_rate],
                seed,
                25,
                params[:days_necessary_exposure],
                params[:exp_trial],
                params[:affection_age_dependent])

            # Step through all iterations. In each iteration:
            #   1) agent_step function is applied to each agent
            #   2) model_step function occurs at end of iteration
            step!(model, params[:iterations])
            # (I think that step! is defined in the "Agents" package.  It will get the model_step and agent_step methods from the
            # model and then execute them.)
            # (Why that functions with exactly the above syntax is not clear to me.  I read as syntax step!(mode, function ), but I
            # do not understand how one can (a) give two functions, and how/why the last arg is interpreted as params and not a
            # function.)
            # (--> step_standard has something that looks a bit similar and probably resolves this)
        end

        start_time = DateTime(params[:start_date], Time(12, 0, 0))

        # Build the DataFrame from the dict. hist entry 1 is the initial state; entry i is recorded at the end of the step that simulated day start_time + (i-2)
        df = DataFrame(
            state    = [s        for (s, b) in keys(model.hist) for _ in eachindex(model.hist[(s,b)])],
            age_low  = [b[1]     for (s, b) in keys(model.hist) for _ in eachindex(model.hist[(s,b)])],
            age_high = [b[2]     for (s, b) in keys(model.hist) for _ in eachindex(model.hist[(s,b)])],
            timer     = [i        for (s, b) in keys(model.hist) for i in eachindex(model.hist[(s,b)])],
            datetime = [start_time + Dates.Day(i-2) for (s, b) in keys(model.hist) for i in eachindex(model.hist[(s,b)])],
            count    = [v        for (s, b) in keys(model.hist) for v in model.hist[(s,b)]]
        )

        # Export
        CSV.write(joinpath(output_path, "SusceptibleExposedAffected_diffbyage.csv"), df)
        push!(model.output_path, output_path)

        df_aggregated = combine(
            groupby(df, [:state, :datetime]),
            :count => sum => :count
        )

        # Export
        CSV.write(joinpath(output_path, "SusceptibleExposedAffected.csv"), df_aggregated)
        push!(model.output_path, output_path)

        CSV.write(joinpath(output_path, "dosis_accumulation_df.csv"), model.dosis_accumulation_DF)
        CSV.write(joinpath(output_path, "recovery_efficiency.csv"), model.recovery_efficiency_DF)
        return model
    end
end

"""
    initializeNetwork(network)

    initializes network on which agents operate.

    # Arguments
    - network
"""
function initializeNetwork(network)
    return network
end


"""
    AES_scheduler(agent)

    activates agents in following order: Affected -> Exposed -> Susceptible 

    # Arguments
    - agent::GraphAgent. Attribute health_status can be equal to "susceptible", "exposed", and "affected"
"""
function AES_scheduler(agent)
    order = Dict(
        "affected"    => 1,
        "exposed"     => 2,
        "susceptible" => 3
    )
    return order[agent.health_status]
end

const age_bins = [(0,10), (11,20), (21,30), (31,40), (41,50),
                  (51,60), (61,70), (71,80), (81,90), (91,200)]
const states = ["susceptible", "exposed", "affected", "newlyaffected"] 

# Helper to find the right bin for an agent:
age_bin(age) = age_bins[findfirst(b -> age <= b[2], age_bins)]

"""
    initialize(net, base_susceptibility, recovery_rate, seed, temp, days_necessary_exposure)

    Initialization of model.

    # Arguments
    - net
    - base_susceptibility
    - recovery_rate
    - seed
    - temp
    - days_necessary_exposure
    - affection_age_dependent
"""

function initialize(net,
    base_susceptibility, # chance of being affected between 0.0 (no chance) and 1.0 (100% chance), given (heat) exposure
    recovery_rate, # for affected agents, chance that they will recover, between 0.0 and 1.0
    seed, # random seed
    temp,
    days_necessary_exposure, # number of days agent can be exposed before probability of becoming affected triggers. If 0, agent may become affected on the first day of a heat period. 
    exp_trial,
    affection_age_dependent
)

# create a space
    space = GraphSpace(net)
    hist = Dict((s, bin) => Int[] for s in states, bin in age_bins)

    start_time = DateTime(params[:start_date], Time(12, 0, 0))

    # define model properties
    properties = Dict(
        :base_susceptibility => base_susceptibility,
        :recovery_rate => recovery_rate,
        :temp => temp,
        :days_necessary_exposure => days_necessary_exposure,
        :affection_age_dependent => affection_age_dependent,
        # one iteration = one day. The timer only marks the day (always 12:00); the dosis sums over all 24 hours of that day
        :timer => start_time,
        :exp_trial => exp_trial,
        :output_path => [],
        :hist => hist,
        :newly_affected => Dict(bin => 0 for bin in age_bins), # S -> A transitions during the current iteration, per age bin
        :hist_timer => [],
        :dosis_accumulation_DF => DataFrame(agentid = String[], heatdosis = Float64[], timer = DateTime[]),
        # hourly UTCI (timestamp -> UTCI) and, per agent, seconds spent at each activity in each hour of the day (see compute_dosis.jl)
        :utci_hourly => hourly_utci(params[:df_merged]),
        :hourly_activity_seconds => Dict{String, Matrix{Float64}}(),
        # hourly air temperature (timestamp -> °C), used for the nightly minimum temperature
        :air_temperature_hourly => Dict(zip(params[:df_merged].timestamp, params[:df_merged].air_temperature_c)),
        # recomputed at the beginning of every day (first day: in initialize, then in model_step!) from the minimum temperature between 00:00 and 05:59 of that day
        :recovery_efficiency => 1.0,
        :recovery_efficiency_DF => DataFrame(date = Date[], recovery_efficiency = Float64[], min_temperature = Float64[]),
        :max_night_recovery_rate => params[:max_night_recovery_rate]
    )

    # create random number generator
    rng = Random.Xoshiro(seed)

    # scheduler for order in which agents are activated for agent-step function: Affected -> Exposed -> Susceptible
    scheduler = Schedulers.ByProperty(AES_scheduler)

    # Model; unremovable = agents never leave the model
    model = StandardABM(
        Person_Sim, space;
        properties, rng, scheduler=scheduler,
        agent_step! = agent_step!,
        model_step! = model_step!
    )

    # add agents to model
    #for id in 1:nrow(params[:agent_attributes])
    if params[:exp_trial] == "Y"
        nagents = 100
    else
        nagents = nrow(params[:agent_attributes])
    end
    for id in 1:nagents
        p = Person_Sim(id, 1, params[:agent_attributes][id,1],
                                params[:agent_attributes][id,2], 
                                params[:agent_attributes][id,3], 
                                params[:agent_attributes][id,4], 
                                params[:agent_attributes][id,5], 
                                params[:agent_attributes][id,6], 
                                params[:agent_attributes][id,7],
                                params[:agent_attributes][id,8], 
                                params[:agent_attributes][id,9],
                                params[:agent_attributes][id,10],
                                params[:agent_attributes][id,11],
                                params[:agent_attributes][id,12], 
                                params[:agent_attributes][id,13], 
                                params[:agent_attributes][id,14], 
                                params[:agent_attributes][id,15], 
                                params[:agent_attributes][id,16], 
                                params[:agent_attributes][id,17],
                                params[:agent_attributes][id,18], 
                                params[:agent_attributes][id,19],
                                params[:agent_attributes][id,20],
                                params[:agent_attributes][id,21],
                                params[:agent_attributes][id,22], 
                                params[:agent_attributes][id,23], 
                                params[:agent_attributes][id,24], 
                                params[:agent_attributes][id,25], 
                                params[:health_status], 
                                0,
                                0,
                                params[:heat_exposure], params[:days_exposed], 0, params[:pregnancy], params[:premorbidity],
                                params[:experienced_plans_dict], 1, 1)
        
        add_agent_single!(p, model)
        model.hourly_activity_seconds[p.SNZ_id] = hourly_activity_seconds(params[:experienced_plans_dict][p.SNZ_id])
    end

    # set initial values for pregnancy
    for agent in allagents(model)
        if agent.SNZ_age > 16 && agent.SNZ_age < 45 && agent.SNZ_gender == "f"
           if rand() < 0.5
            agent.pregnancy = 1
           end 
        end
    end

    # set initial values for pre-morbidity
    for agent in allagents(model)
        if agent.SNZ_age > 65
            if rand() < 0.5
                agent.premorbidity = 1
            end
        end
    end

    # push cnts to first entry in history of each disease states
    push_state_count_to_history!(model)

    # recovery_efficiency for the first day, before any agent steps
    update_recovery_efficiency!(model)
    return model
end

# model state occurs at end of each iteration, after agent_step is applied to all agents
function model_step!(model)
    # push disease state counts for current (ending) iteration to respective history. 
    push_state_count_to_history!(model)
    model.timer += Dates.Day(1)
    # recovery_efficiency for the day that starts now, so it is available during the agent steps of that day.
    # abmtime is only incremented after model_step!, so the last simulated day ends when abmtime(model) + 1 == iterations
    if abmtime(model) + 1 < params[:iterations]
        update_recovery_efficiency!(model)
    end
end

"""
    update_recovery_efficiency!(model)

    Sets recovery_efficiency = clamp(-0.1 * min_temp + 2.5, 0, 1), where min_temp is the minimum air temperature between 00:00 and 05:59 of the current day,
    and appends it to recovery_efficiency_DF. Called at the beginning of each day.
"""
function update_recovery_efficiency!(model)
    day = Date(model.timer)
    min_temp = minimum(model.air_temperature_hourly[DateTime(day) + Hour(h)] for h in 0:5)
    model.recovery_efficiency = clamp(-0.1 * min_temp + 2.5, 0, 1)
    push!(model.recovery_efficiency_DF, (date = day, recovery_efficiency = model.recovery_efficiency, min_temperature = min_temp))
end


"""
    push_state_count_to_history(model)

    Updates disease state histories with disease state counts for current iteration.
"""
function push_state_count_to_history!(model)
    for s in states
        for bin in age_bins
            if s == "newlyaffected"
                # not a health_status agents hold -- counted as S -> A transitions in agent_step!
                c = model.newly_affected[bin]
            else
                c = sum(agent.health_status == s && age_bin(agent.SNZ_age) == bin for agent in allagents(model))
            end
            push!(model.hist[(s, bin)], c)
        end
    end
    # reset transition counter for the next iteration
    for bin in age_bins
        model.newly_affected[bin] = 0
    end
end

"""
    agent_step!(person, model)

    Transitions agents from one disease state to another.
"""

function agent_step!(person, model)
    
    iteration = abmtime(model) + 1 #Such that iteration 0 coincides with 1st line of data frame
    maxTemp = params[:temperature][iteration, "TX"]
    # if affected
    if person.health_status == "affected"
        if rand() <= model.recovery_rate #Agents recover with a probability of recovery_rate
            person.health_status = "susceptible"
            person.days_exposed = -1
            person.dosis_midnight = 0
        end
    end

    # if susceptible
    if person.health_status == "susceptible"

        # S -> A
        dosis, affected_chance = compute_affection_chance(params, model, person)
        person.dosis_midnight = dosis
        push!(model.dosis_accumulation_DF, (agentid = person.SNZ_id, heatdosis = dosis, timer = model.timer))        
        #affected_chance = 0.3
        if rand() <= affected_chance
            person.health_status = "affected"
            model.newly_affected[age_bin(person.SNZ_age)] += 1
        else
            person.health_status = "susceptible"
            person.days_exposed = 0
        end
    end

end

