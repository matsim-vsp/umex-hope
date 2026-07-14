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
    heat_exposure::Float64
    days_exposed :: Int
    inf_chance_for_iteration::Float64 # if susceptible person had contact with infectious person, then this variable saves the infection chance (including the reduction_factor). In all other cases: missing
    pregnancy::Int64
    premorbidity::Int64
    experienced_plans_reader::Dict
    affection_theta::Float64
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
            output_path = "data/" * replace(first(string(now()), 19), ":" => "")
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

        start_time = DateTime(2025, 1, 9, 12, 00)

        # Build the DataFrame from the dict
        df = DataFrame(
            state    = [s        for (s, b) in keys(model.hist) for _ in eachindex(model.hist[(s,b)])],
            age_low  = [b[1]     for (s, b) in keys(model.hist) for _ in eachindex(model.hist[(s,b)])],
            age_high = [b[2]     for (s, b) in keys(model.hist) for _ in eachindex(model.hist[(s,b)])],
            timer     = [i        for (s, b) in keys(model.hist) for i in eachindex(model.hist[(s,b)])],
            datetime = [start_time + Dates.Day(i-1) for (s, b) in keys(model.hist) for i in eachindex(model.hist[(s,b)])],
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

        # df_diffbyage = DataFrame(
        #     timer = model.hist_timer,
        #     susceptible0010 = model.hist_susceptible0010,
        #     exposed0010 = model.hist_exposed0010,
        #     affected0010 = model.hist_affected0010,
        #     newlyaffected0010 = model.hist_newlyaffected0010,

        #     susceptible1120 = model.hist_susceptible1120,
        #     exposed1120 = model.hist_exposed1120,
        #     affected1120 = model.hist_affected1120,
        #     newlyaffected1120 = model.hist_newlyaffected1120,

        #     susceptible2130 = model.hist_susceptible2130,
        #     exposed2130 = model.hist_exposed2130,
        #     affected2130 = model.hist_affected2130,
        #     newlyaffected2130 = model.hist_newlyaffected2130,

        #     susceptible3140 = model.hist_susceptible3140,
        #     exposed3140 = model.hist_exposed3140,
        #     affected3140 = model.hist_affected3140,
        #     newlyaffected3140 = model.hist_newlyaffected3140,

        #     susceptible4150 = model.hist_susceptible4150,
        #     exposed4150 = model.hist_exposed4150,
        #     affected4150 = model.hist_affected4150,
        #     newlyaffected4150 = model.hist_newlyaffected4150,

        #     susceptible5160 = model.hist_susceptible5160,
        #     exposed5160 = model.hist_exposed5160,
        #     affected5160 = model.hist_affected5160,
        #     newlyaffected5160 = model.hist_newlyaffected5160,

        #     susceptible6170 = model.hist_susceptible6170,
        #     exposed6170 = model.hist_exposed6170,
        #     affected6170 = model.hist_affected6170,
        #     newlyaffected6170 = model.hist_newlyaffected6170,

        #     susceptible7180 = model.hist_susceptible7180,
        #     exposed7180 = model.hist_exposed7180,
        #     affected7180 = model.hist_affected7180,
        #     newlyaffected7180 = model.hist_newlyaffected7180,

        #     susceptible8190 = model.hist_susceptible8190,
        #     exposed8190 = model.hist_exposed8190,
        #     affected8190 = model.hist_affected8190,
        #     newlyaffected8190 = model.hist_newlyaffected8190,

        #     susceptible91inf = model.hist_susceptible91inf,
        #     exposed91inf = model.hist_exposed91inf,
        #     affected91inf = model.hist_affected91inf,
        #     newlyaffected91inf = model.hist_newlyaffected91inf
        # )
        # CSV.write(joinpath(output_path, "SusceptibleExposedAffected_diffbyage.csv"), df_diffbyage)
        CSV.write(joinpath(output_path, "dosis_accumulation_df.csv"), model.dosis_accumulation_DF)
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

    # define model properties
    properties = Dict(
        :base_susceptibility => base_susceptibility,
        :recovery_rate => recovery_rate,
        :temp => temp,
        :days_necessary_exposure => days_necessary_exposure,
        :affection_age_dependent => affection_age_dependent,
        #starting time, start at midnight
        :timer => DateTime(2025, 1, 9, 12, 00), #TODO: Need to figure out starting date
        :exp_trial => exp_trial,
        :output_path => [],
        :hist => hist,
        :hist_timer => [],
        :dosis_accumulation_DF => DataFrame(agentid = String[], heatdosis = Float64[], timer = DateTime[])
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
                                params[:heat_exposure], params[:days_exposed], 0, params[:pregnancy], params[:premorbidity],
                                params[:experienced_plans_dict], 1)
        
        add_agent_single!(p, model)
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
    return model
end

# model state occurs at end of each iteration, after agent_step is applied to all agents
function model_step!(model)
    # push disease state counts for current (ending) iteration to respective history. 
    push_state_count_to_history!(model)
    model.timer += Dates.Day(1)
end


"""
    push_state_count_to_history(model)

    Updates disease state histories with disease state counts for current iteration.
"""
function push_state_count_to_history!(model)
    for s in states
        for bin in age_bins
            c = sum(agent.health_status == s && age_bin(agent.SNZ_age) == bin for agent in allagents(model))
            push!(model.hist[(s, bin)], c)
        end
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
        end
    end

    # if susceptible
    if person.health_status == "susceptible"

        # S -> A
        dosis, affected_chance = compute_affection_chance(params, model, person)
        push!(model.dosis_accumulation_DF, (agentid = person.SNZ_id, heatdosis = dosis, timer = model.timer))        
        #affected_chance = 0.3
        if rand() <= affected_chance
            person.health_status = "affected"
        else
            person.health_status = "susceptible"
            person.days_exposed = 0
        end
    end

end

