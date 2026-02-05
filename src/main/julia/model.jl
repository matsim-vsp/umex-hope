using Pkg
using agents

#This work partly recycles code from previous work https://github.com/matsim-vsp/epi-net-sim/blob/main/src/main/julia/model.jl

# Define Agent
@agent Person_Sim GraphAgent begin
    id::Int64
    SNZ_age::Int64
    SNZ_gender::String
    SNZ_hhIncome::Int64
    SNZ_hhSize::Int64
    home_x::Float64
    home_y::Float64
    income::Float64
    sex::String
    health_status::Int # 0: Susceptible; 1: Exposed; 2: Affected; 9: Recovered
    heat_exposure::Float64
    inf_chance_for_iteration::Float64 # if susceptible person had contact with infectious person, then this variable saves the infection chance (including the reduction_factor). In all other cases: missing
end

# activates agents in following order: Recovered -> Infectious -> Presymptomatic -> Exposed -> Susceptible 
function RAES_scheduler(agent)
    return -agent.health_status
end

function initialize(net,
    base_susceptibility, # chance of being affected between 0.0 (no chance) and 1.0 (100% chance), given (heat) exposure
    recovery_rate, # for affected agents, chance that they will recover, between 0.0 and 1.0
    seed, # random seed
    days_until_affected # number of days agent can be exposed before probability of becoming affected triggers. If 0, agent may become affected on the first day of a heat period. 
)

# create a space
    space = GraphSpace(net)

    # define model properties
    properties = Dict(
        :base_susceptibility => base_susceptibility,
        :recovery_rate => recovery_rate,
        :days_until_affectes => days_until_affected,

        # current count for each disease state
        :cnt_susceptible => 0,
        :cnt_exposed => 0,
        :cnt_affected => 0,
        :cnt_recovered => 0,

        #history of count for each iteration
        :hist_susceptible => [],
        :hist_exposed => [],
        :hist_affected => [],
        :hist_recovered => []
    )

    # create random number generator
    rng = Random.Xoshiro(seed)

    # scheduler for order in which agents are activated for agent-step function: Recovered -> Affected -> Exposed -> Susceptible
    scheduler = Schedulers.ByProperty(RAES_scheduler)

    # Model; unremovable = agents never leave the model
    model = UnremovableABM(
        Person_Sim, space;
        properties, rng, scheduler=scheduler
    )

    # add agents to model
    for id in 1:n_nodes
        p = Person_Sim(id, 1, 0, -1, NaN64)
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
        elseif agent.health_status == 9
            model.cnt_recovered += 1
        else
            throw(DomainError)
        end
    end

    # push cnts to first entry in history of each disease states
    push_state_count_to_history!(model)

    return model
end
