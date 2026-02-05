using Pkg
Pkg.activate(@__DIR__)
using Agents, Random, Graphs, DataFrames, Statistics, CSV, Dates

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
    health_status::Int # 0: Susceptible; 1: Exposed; 2: Affected
    heat_exposure::Float64
    days_exposed :: Int
    inf_chance_for_iteration::Float64 # if susceptible person had contact with infectious person, then this variable saves the infection chance (including the reduction_factor). In all other cases: missing
end

function run_model(params)
    @time begin

        # sets output directory. If running on cluster, output folder is specified by start_multiple_sh. If run locally, a new folder will be created w/ current datetime 
        if ismissing(params[:output_folder])
            output_path = "data/" * replace(first(string(now()), 19), ":" => "")
            mkpath(output_path)

        else
            output_path = params[:output_folder]
        end

        # writes _info.csv with all relevant input parameters
        # TODO: when running on cluster, _info.csv gets overwritten by each seperate job.
        #CSV.write(output_path * "/_info.csv", params)
       
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

        # loop through all seeds
        for seed in 1:params[:seeds]

            # Create network 
            net = initializeNetwork(
            )

            # Create model
            model = initialize(
                net,
                base_susceptibility,
                params[:recovery_rate],
                seed,
                25,
                params[:days_necessary_exposure])

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
    end
end

# creates network with default values
function initializeNetwork()
        net = Graphs.random_regular_graph(100, 5)
    return net
end


# activates agents in following order: Recovered -> Infectious -> Presymptomatic -> Exposed -> Susceptible 
function AES_scheduler(agent)
    return -agent.health_status
end

function initialize(net,
    base_susceptibility, # chance of being affected between 0.0 (no chance) and 1.0 (100% chance), given (heat) exposure
    recovery_rate, # for affected agents, chance that they will recover, between 0.0 and 1.0
    seed, # random seed
    temp,
    days_necessary_exposure # number of days agent can be exposed before probability of becoming affected triggers. If 0, agent may become affected on the first day of a heat period. 
)

# create a space
    space = GraphSpace(net)

    # define model properties
    properties = Dict(
        :base_susceptibility => base_susceptibility,
        :recovery_rate => recovery_rate,
        :temp => temp,
        :days_necessary_exposure => days_necessary_exposure,

        # current count for each disease state
        :cnt_susceptible => 0,
        :cnt_exposed => 0,
        :cnt_affected => 0,

        #history of count for each iteration
        :hist_susceptible => [],
        :hist_exposed => [],
        :hist_affected => []
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
    for id in 1:nrow(params[:agent_attributes])
        p = Person_Sim(id, 1, params[:agent_attributes][id,1],
                                params[:agent_attributes][id,2], 
                                params[:agent_attributes][id,3], 
                                params[:agent_attributes][id,4], 
                                params[:agent_attributes][id,5], 
                                params[:agent_attributes][id,6], 
                                params[:agent_attributes][id,7],
                                params[:agent_attributes][id,8], 
                                params[:agent_attributes][id,9],
                                0, 0, 0, 0)
                                
        add_agent_single!(p, model)
    end

    # set initial values for cnt_DISEASE_STATE
    for agent in allagents(model)
        if agent.health_status == 0
            model.cnt_susceptible += 1
        elseif agent.health_status == 1
            model.cnt_exposed += 1
        elseif agent.health_status == 2
            model.cnt_affected += 1
        else
            throw(DomainError)
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

end

# updates disease state histories with disease state counts for current iteration
function push_state_count_to_history!(model)
    push!(model.hist_susceptible, model.cnt_susceptible)
    push!(model.hist_exposed, model.cnt_exposed)
    push!(model.hist_affected, model.cnt_affected)
    #push!(model.hist_affcted_chance, model.sum_affected_prob_for_it / model.cnt_potential_affected_for_it)
end

# Agent Step Function: this transitions agents from one disease state to another
function agent_step!(person, model)
    
    # if showing symptoms 
    if person.health_status == 2
        if rand(model.rng) <= model.recovery_rate #Agents recover with a probability of recovery_rate
            person.health_status = 0
            model.cnt_affected -= 1
            model.cnt_susceptible += 1
        end
    end

    # if exposed
    if person.health_status == 1
        # E -> S
        if model.threshold_temp <= 25 #Agents recover with a probability of recovery_rate
            person.health_status = 0
            person.days_exposed = 0
            model.cnt_exposed -= 1
            model.cnt_susceptible += 1
        # E -> I
        # calculate infection chance
        affected_chance = calc_affected_chance(model, person)
        
    elseif person.days_exposed == model.days_necessary_exposure
            if rand(model.rng) < affected_chance
                person.health_status = 2
                model.cnt_exposed -= 1
                model.cnt_affected += 1
            else
                person.health_status = 0
                model.cnt_exposed -= 1
                model.cnt_susceptible += 1
            end
        end
    end

    # if susceptible
    if person.health_status == 0
        if model.temp > 25
            person.health_status = 1 # change to exposed
            model.cnt_exposed += 1
            model.cnt_susceptible -= 1
        end
    end
end

# calculate infection chance 
function calc_affected_chance(model, person)
    params[:base_susceptibility]

    return inf_chance
end