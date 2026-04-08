using Pkg
Pkg.activate(@__DIR__)
using Agents, Random, Graphs, DataFrames, Statistics, CSV, Dates

include("calc_affection_chance.jl")

#This work partly recycles code from previous work https://github.com/matsim-vsp/epi-net-sim/blob/main/src/main/julia/model.jl

# Define Agent
@agent Person_Sim GraphAgent begin
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
    health_status::Int # 0: Susceptible; 1: Exposed; 2: Affected
    heat_exposure::Float64
    days_exposed :: Int
    inf_chance_for_iteration::Float64 # if susceptible person had contact with infectious person, then this variable saves the infection chance (including the reduction_factor). In all other cases: missing
    pregnancy::Int64
    premorbidity::Int64
    experienced_plans_reader::Dict
    affection_age_param::Int64
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
       
        # empty dictionary, which will be filled with respective stat (e.g. susceptible count) for each model run (all iterations, rows of matrix) for each seed (columns of matrix)
        results = Dict(
            # "shortestPath" => [],
            # "clusteringCoefficient" => [],
            "susceptible" => [],
            "exposed" => [],
            "affected" => [], 
            "affctedChance" => []
        )

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
            step!(model, agent_step!, model_step!, params[:iterations])

            # model stats for particular seed are added as column to each results matrix. 
            push!(results["susceptible"], model.hist_susceptible)
            push!(results["exposed"], model.hist_exposed)
            push!(results["affected"], model.hist_affected)

        end


        # prints each stat matrix in results dictionary to csv. 
        for (result_type, result_matrix_all_seeds) in results
            df = DataFrame()
            seed_counter = 1
            for results_for_single_seed in result_matrix_all_seeds
                vector_title = "seed$(seed_counter)"
                # if(typeof(results_for_single_seed)==Float64)
                #     df[!,vector_title] = [results_for_single_seed]
                # else
                df[!, vector_title] = results_for_single_seed
                # end
                seed_counter += 1
            end

            output_file_name = "TESTTESTTEST.csv"
            #CSV.write(output_path * output_file_name, df)
        end

        df = DataFrame(
            timer = model.hist_timer,
            susceptible = model.hist_susceptible,
            exposed = model.hist_exposed,
            affected = model.hist_affected
        )
        CSV.write(joinpath(output_path, "SusceptibleExposedAffected.csv"), df)

        df_diffbyage = DataFrame(
            timer = model.hist_timer,
            susceptible0010 = model.hist_susceptible0010,
            exposed0010 = model.hist_exposed0010,
            affected0010 = model.hist_affected0010,

            susceptible1120 = model.hist_susceptible1120,
            exposed1120 = model.hist_exposed1120,
            affected1120 = model.hist_affected1120,

            susceptible2130 = model.hist_susceptible2130,
            exposed2130 = model.hist_exposed2130,
            affected2130 = model.hist_affected2130,

            susceptible3140 = model.hist_susceptible3140,
            exposed3140 = model.hist_exposed3140,
            affected3140 = model.hist_affected3140,

            susceptible4150 = model.hist_susceptible4150,
            exposed4150 = model.hist_exposed4150,
            affected4150 = model.hist_affected4150,

            susceptible5160 = model.hist_susceptible5160,
            exposed5160 = model.hist_exposed5160,
            affected5160 = model.hist_affected5160,

            susceptible6170 = model.hist_susceptible6170,
            exposed6170 = model.hist_exposed6170,
            affected6170 = model.hist_affected6170,

            susceptible7180 = model.hist_susceptible7180,
            exposed7180 = model.hist_exposed7180,
            affected7180 = model.hist_affected7180,

            susceptible8190 = model.hist_susceptible8190,
            exposed8190 = model.hist_exposed8190,
            affected8190 = model.hist_affected8190,

            susceptible91inf = model.hist_susceptible91inf,
            exposed91inf = model.hist_exposed91inf,
            affected91inf = model.hist_affected91inf
        )
        CSV.write(joinpath(output_path, "SusceptibleExposedAffected_diffbyage.csv"), df_diffbyage)

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
    - agent::GraphAgent. Attribute health_status can be equal to 0 (susceptible), exposed (1), and affected (2).
"""
function AES_scheduler(agent)
    return -agent.health_status
end


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

    # define model properties
    properties = Dict(
        :base_susceptibility => base_susceptibility,
        :recovery_rate => recovery_rate,
        :temp => temp,
        :days_necessary_exposure => days_necessary_exposure,
        :affection_age_dependent => affection_age_dependent,

        # current count for each disease state
        :cnt_susceptible => 0,
        :cnt_exposed => 0,
        :cnt_affected => 0,

        :cnt_susceptible0010 => 0,
        :cnt_susceptible1120 => 0,
        :cnt_susceptible2130 => 0,
        :cnt_susceptible3140 => 0,
        :cnt_susceptible4150 => 0,
        :cnt_susceptible5160 => 0,
        :cnt_susceptible6170 => 0,
        :cnt_susceptible7180 => 0,
        :cnt_susceptible8190 => 0,
        :cnt_susceptible91inf => 0,

        :cnt_exposed0010 => 0,
        :cnt_exposed1120 => 0,
        :cnt_exposed2130 => 0,
        :cnt_exposed3140 => 0,
        :cnt_exposed4150 => 0,
        :cnt_exposed5160 => 0,
        :cnt_exposed6170 => 0,
        :cnt_exposed7180 => 0,
        :cnt_exposed8190 => 0,
        :cnt_exposed91inf => 0,

        :cnt_affected0010 => 0,
        :cnt_affected1120 => 0,
        :cnt_affected2130 => 0,
        :cnt_affected3140 => 0,
        :cnt_affected4150 => 0,
        :cnt_affected5160 => 0,
        :cnt_affected6170 => 0,
        :cnt_affected7180 => 0,
        :cnt_affected8190 => 0,
        :cnt_affected91inf => 0,

        #history of count for each iteration
        :hist_timer => [],
        :hist_susceptible => [],
        :hist_exposed => [],
        :hist_affected => [],

        :hist_susceptible0010 => [],
        :hist_susceptible1120 => [],
        :hist_susceptible2130 => [],
        :hist_susceptible3140 => [],
        :hist_susceptible4150 => [],
        :hist_susceptible5160 => [],
        :hist_susceptible6170 => [],
        :hist_susceptible7180 => [],
        :hist_susceptible8190 => [],
        :hist_susceptible91inf => [],

        :hist_exposed0010 => [],
        :hist_exposed1120 => [],
        :hist_exposed2130 => [],
        :hist_exposed3140 => [],
        :hist_exposed4150 => [],
        :hist_exposed5160 => [],
        :hist_exposed6170 => [],
        :hist_exposed7180 => [],
        :hist_exposed8190 => [],
        :hist_exposed91inf => [],

        :hist_affected0010 => [],
        :hist_affected1120 => [],
        :hist_affected2130 => [],
        :hist_affected3140 => [],
        :hist_affected4150 => [],
        :hist_affected5160 => [],
        :hist_affected6170 => [],
        :hist_affected7180 => [],
        :hist_affected8190 => [],
        :hist_affected91inf => [],

        #starting time, start at midnight
        :timer => DateTime(2024, 1, 15, 00, 00), #TODO: Need to figure out starting date
        :exp_trial => exp_trial
    )

    # create random number generator
    rng = Random.Xoshiro(seed)

    # scheduler for order in which agents are activated for agent-step function: Affected -> Exposed -> Susceptible
    scheduler = Schedulers.ByProperty(AES_scheduler)

    # Model; unremovable = agents never leave the model
    model = UnremovableABM(
        Person_Sim, space;
        properties, rng, scheduler=scheduler
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
                                params[:health_status], params[:heat_exposure], params[:days_exposed], 0, params[:pregnancy], params[:premorbidity],
                                params[:experienced_plans_dict], 1)
        
        add_agent_single!(p, model)
    end

    # set initial values for cnt_DISEASE_STATE
    for agent in allagents(model)
        if agent.health_status == 0
            model.cnt_susceptible += 1
            if agent.SNZ_age <= 10
                model.cnt_susceptible0010 += 1
            elseif agent.SNZ_age <= 20 && agent.SNZ_age > 10
                model.cnt_susceptible1120 += 1
            elseif agent.SNZ_age <= 30 && agent.SNZ_age > 20
                model.cnt_susceptible2130 += 1
            elseif agent.SNZ_age <= 40 && agent.SNZ_age > 30
                model.cnt_susceptible3140 += 1
            elseif agent.SNZ_age <= 50 && agent.SNZ_age > 40
                model.cnt_susceptible4150 += 1
            elseif agent.SNZ_age <= 60 && agent.SNZ_age > 50
                model.cnt_susceptible5160 += 1
            elseif agent.SNZ_age <= 70 && agent.SNZ_age > 60
                model.cnt_susceptible6170 += 1
            elseif agent.SNZ_age <= 80 && agent.SNZ_age > 70
                model.cnt_susceptible7180 += 1
            elseif agent.SNZ_age <= 90 && agent.SNZ_age > 80
                model.cnt_susceptible8190 += 1
            elseif agent.SNZ_age > 90
                model.cnt_susceptible91inf += 1 
            end
        elseif agent.health_status == 1
            model.cnt_exposed += 1
            if agent.SNZ_age <= 10
                model.cnt_expoed0010 += 1
            elseif agent.SNZ_age <= 20 && agent.SNZ_age > 10
                model.cnt_exposed1120 += 1
            elseif agent.SNZ_age <= 30 && agent.SNZ_age > 20
                model.cnt_exposed02130 += 1
            elseif agent.SNZ_age <= 40 && agent.SNZ_age > 30
                model.cnt_exposed3140 += 1
            elseif agent.SNZ_age <= 50 && agent.SNZ_age > 40
                model.cnt_exposed4150 += 1
            elseif agent.SNZ_age <= 60 && agent.SNZ_age > 50
                model.cnt_exposed5160 += 1
            elseif agent.SNZ_age <= 70 && agent.SNZ_age > 60
                model.cnt_exposed6170 += 1
            elseif agent.SNZ_age <= 80 && agent.SNZ_age > 70
                model.cnt_exposed7180 += 1
            elseif agent.SNZ_age <= 90 && agent.SNZ_age > 80
                model.cnt_exposed8190 += 1
            elseif agent.SNZ_age > 90
                model.cnt_exposed91inf += 1
            end
        elseif agent.health_status == 2
            model.cnt_affected += 1
            if agent.SNZ_age <= 10
                model.cnt_affected0010 += 1
            elseif agent.SNZ_age <= 20 && agent.SNZ_age > 10
                model.cnt_affected1120 += 1
            elseif agent.SNZ_age <= 30 && agent.SNZ_age > 20
                model.cnt_affected02130 += 1
            elseif agent.SNZ_age <= 40 && agent.SNZ_age > 30
                model.cnt_affected3140 += 1
            elseif agent.SNZ_age <= 50 && agent.SNZ_age > 40
                model.cnt_affected4150 += 1
            elseif agent.SNZ_age <= 60 && agent.SNZ_age > 50
                model.cnt_affected5160 += 1
            elseif agent.SNZ_age <= 70 && agent.SNZ_age > 60
                model.cnt_affected6170 += 1
            elseif agent.SNZ_age <= 80 && agent.SNZ_age > 70
                model.cnt_affected7180 += 1
            elseif agent.SNZ_age <= 90 && agent.SNZ_age > 80
                model.cnt_affected8190 += 1
            elseif agent.SNZ_age > 90
                model.cnt_affected91inf += 1
            end
        else
            throw(DomainError)
        end
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

    #set affection chance according to age
    if model.affection_age_dependent == "Y"
        for agent in allagents(model)
            if agent.SNZ_age <= 5
                agent.affection_age_param = 2
            elseif agent.SNZ_age <= 70
                agent.affection_age_param = 1
            elseif agent.SNZ_age > 70
                agent.affection_age_param = 2
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
    push!(model.hist_timer, model.timer)
    push!(model.hist_susceptible, model.cnt_susceptible)
    push!(model.hist_exposed, model.cnt_exposed)
    push!(model.hist_affected, model.cnt_affected)

    push!(model.hist_susceptible0010, model.cnt_susceptible0010)
    push!(model.hist_susceptible1120, model.cnt_susceptible1120)
    push!(model.hist_susceptible2130, model.cnt_susceptible2130)
    push!(model.hist_susceptible3140, model.cnt_susceptible3140)
    push!(model.hist_susceptible4150, model.cnt_susceptible4150)
    push!(model.hist_susceptible5160, model.cnt_susceptible5160)
    push!(model.hist_susceptible6170, model.cnt_susceptible6170)
    push!(model.hist_susceptible7180, model.cnt_susceptible7180)
    push!(model.hist_susceptible8190, model.cnt_susceptible8190)
    push!(model.hist_susceptible91inf, model.cnt_susceptible91inf)

    push!(model.hist_exposed0010, model.cnt_exposed0010)
    push!(model.hist_exposed1120, model.cnt_exposed1120)
    push!(model.hist_exposed2130, model.cnt_exposed2130)
    push!(model.hist_exposed3140, model.cnt_exposed3140)
    push!(model.hist_exposed4150, model.cnt_exposed4150)
    push!(model.hist_exposed5160, model.cnt_exposed5160)
    push!(model.hist_exposed6170, model.cnt_exposed6170)
    push!(model.hist_exposed7180, model.cnt_exposed7180)
    push!(model.hist_exposed8190, model.cnt_exposed8190)

    push!(model.hist_exposed91inf, model.cnt_exposed91inf)
    push!(model.hist_affected0010, model.cnt_affected0010)
    push!(model.hist_affected1120, model.cnt_affected1120)
    push!(model.hist_affected2130, model.cnt_affected2130)
    push!(model.hist_affected3140, model.cnt_affected3140)
    push!(model.hist_affected4150, model.cnt_affected4150)
    push!(model.hist_affected5160, model.cnt_affected5160)
    push!(model.hist_affected6170, model.cnt_affected6170)
    push!(model.hist_affected7180, model.cnt_affected7180)
    push!(model.hist_affected8190, model.cnt_affected8190)
    push!(model.hist_affected91inf, model.cnt_affected91inf)
end

"""
    agent_step!(person, model)

    Transitions agents from one disease state to another.
"""

function agent_step!(person, model)
    
    iteration = abmtime(model) + 1 #Such that iteration 0 coincides with 1st line of data frame
    maxTemp = params[:temperature][iteration, "TX"]
    # if affected
    if person.health_status == 2
        if rand() <= model.recovery_rate #Agents recover with a probability of recovery_rate
            person.health_status = 0
            person.days_exposed = -1
            model.cnt_affected -= 1
            model.cnt_susceptible += 1
            if person.SNZ_age <= 10
                model.cnt_affected0010 -= 1
                model.cnt_susceptible0010 += 1
            elseif person.SNZ_age > 10 && person.SNZ_age <= 20
                model.cnt_affected1120 -= 1
                model.cnt_susceptible1120 += 1  
            elseif person.SNZ_age > 20 && person.SNZ_age <= 30
                model.cnt_affected2130 -= 1
                model.cnt_susceptible2130 += 1   
            elseif person.SNZ_age > 30 && person.SNZ_age <= 40
                model.cnt_affected3140 -= 1
                model.cnt_susceptible3140 += 1  
            elseif person.SNZ_age > 40 && person.SNZ_age <= 50
                model.cnt_affected4150 -= 1
                model.cnt_susceptible4150 += 1  
            elseif person.SNZ_age > 50 && person.SNZ_age <= 60
                model.cnt_affected5160 -= 1
                model.cnt_susceptible5160 += 1 
            elseif person.SNZ_age > 60 && person.SNZ_age <= 70
                model.cnt_affected6170 -= 1
                model.cnt_susceptible6170 += 1  
            elseif person.SNZ_age > 70 && person.SNZ_age <= 80
                model.cnt_affected7180 -= 1
                model.cnt_susceptible7180 += 1     
            elseif person.SNZ_age > 80 && person.SNZ_age <= 90
                model.cnt_affected8190 -= 1
                model.cnt_susceptible8190 += 1  
            elseif person.SNZ_age > 90 
                model.cnt_affected91inf -= 1
                model.cnt_susceptible91inf += 1    
            end        
        end
    end

    # if exposed
    if person.health_status == 1
        # E -> S
        if params[:threshold_temp] <= maxTemp
            person.days_exposed += 1
        end

        # E -> I
        affected_chance = calc_affection_chance(params, model, person)        
        if person.days_exposed == model.days_necessary_exposure
            if rand() <= affected_chance
                person.health_status = 2
                model.cnt_exposed -= 1
                model.cnt_affected += 1
                if person.SNZ_age <= 10
                    model.cnt_exposed0010 -= 1
                    model.cnt_affected0010 += 1
                elseif person.SNZ_age > 10 && person.SNZ_age <= 20
                    model.cnt_exposed1120 -= 1
                    model.cnt_affected1120 += 1
                elseif person.SNZ_age > 20 && person.SNZ_age <= 30
                    model.cnt_exposed2130 -= 1
                    model.cnt_affected2130 += 1
                elseif person.SNZ_age > 30 && person.SNZ_age <= 40
                    model.cnt_exposed3140 -= 1
                    model.cnt_affected3140 += 1
                elseif person.SNZ_age > 40 && person.SNZ_age <= 50
                    model.cnt_exposed4150 -= 1
                    model.cnt_affected4150 += 1
                elseif person.SNZ_age > 50 && person.SNZ_age <= 60
                    model.cnt_exposed5160 -= 1
                    model.cnt_affected5160 += 1
                elseif person.SNZ_age > 60 && person.SNZ_age <= 70
                    model.cnt_exposed6170 -= 1
                    model.cnt_affected6170 += 1
                elseif person.SNZ_age > 70 && person.SNZ_age <= 80
                    model.cnt_exposed7180 -= 1
                    model.cnt_affected7180 += 1
                elseif person.SNZ_age > 80 && person.SNZ_age <= 90
                    model.cnt_exposed8190 -= 1
                    model.cnt_affected8190 += 1
                elseif person.SNZ_age > 90
                    model.cnt_exposed91inf -= 1
                    model.cnt_affected91inf += 1
                end
            else
                person.health_status = 0
                model.cnt_exposed -= 1
                model.cnt_susceptible += 1
                person.days_exposed = 0
                if person.SNZ_age <= 10
                    model.cnt_exposed0010 -= 1
                    model.cnt_susceptible0010 += 1
                elseif person.SNZ_age > 10 && person.SNZ_age <= 20
                    model.cnt_exposed1120 -= 1
                    model.cnt_susceptible1120 += 1
                elseif person.SNZ_age > 20 && person.SNZ_age <= 30
                    model.cnt_exposed2130 -= 1
                    model.cnt_susceptible2130 += 1
                elseif person.SNZ_age > 30 && person.SNZ_age <= 40
                    model.cnt_exposed3140 -= 1
                    model.cnt_susceptible3140 += 1
                elseif person.SNZ_age > 40 && person.SNZ_age <= 50
                    model.cnt_exposed4150 -= 1
                    model.cnt_susceptible4150 += 1
                elseif person.SNZ_age > 50 && person.SNZ_age <= 60
                    model.cnt_exposed5160 -= 1
                    model.cnt_susceptible5160 += 1
                elseif person.SNZ_age > 60 && person.SNZ_age <= 70
                    model.cnt_exposed6170 -= 1
                    model.cnt_susceptible6170 += 1
                elseif person.SNZ_age > 70 && person.SNZ_age <= 80
                    model.cnt_exposed7180 -= 1
                    model.cnt_susceptible7180 += 1
                elseif person.SNZ_age > 80 && person.SNZ_age <= 90
                    model.cnt_exposed8190 -= 1
                    model.cnt_susceptible8190 += 1
                elseif person.SNZ_age > 90
                    model.cnt_exposed91inf -= 1
                    model.cnt_susceptible91inf += 1
                end
            end
        end
    end

    # if susceptible
    if person.health_status == 0 
        if person.days_exposed == 0
            if params[:threshold_temp] <= maxTemp
                person.health_status = 1 # change to exposed
                model.cnt_exposed += 1
                model.cnt_susceptible -= 1
            end
        elseif person.days_exposed == -1
            person.days_exposed += 1
        end
    end
end

