include("model.jl")
include("../../../population.jl")
include("../../../network_creation.jl")
include("../../../temperature.jl")
include("../../../experienced_plans.jl")
include("../../../out_of_home_duration.jl")
include("plot_singlescenario.jl")


pop_file = "hannover-1pct.output_persons.csv"
agent_attr = population_reader(pop_file)
network_file = "hannover-1pct.output_network.xml"
network = network_creation(network_file)
trajectories_file = "path"
temperature_file = "TemperatureHannoverDWD.txt"
temperature = temperature_reader(temperature_file)
exp_plans_file = "hannover-1pct.output_experienced_plans.xml"
exp_plans_pop_df, exp_plans_dict = experienced_plans_reader(exp_plans_file)
out_of_home_duration_df = process_all_agents(exp_plans_dict)
agent_attr = leftjoin(agent_attr, out_of_home_duration_df, on = :person)

params = Dict(
    :seeds => 1,
    :iterations => nrow(temperature),
    :base_susceptibility => 0.05,
    :recovery_rate => 1,
    :days_necessary_exposure => 1,
    :agent_attributes => agent_attr,
    :health_status => 0,
    :heat_exposure => 0, 
    :days_exposed => 0,
    :pregnancy => 0, 
    :premorbidity => 0,
    :pop_file => pop_file,
    :network_file => network_file,
    :network => network,
    :trajectories_file => trajectories_file,
    :temperature_file => temperature_file,
    :temperature => temperature,
    :threshold_temp => 20,
    :output_folder => missing,
    :experienced_plans_dict => exp_plans_dict,
    :exp_trial => "Y", #Determines number of agents. If == "Y", then no. of agents = 100, else: no of agents according to population file
    :heat_time_module => "24_hours", #Options: "24_hours", "out_of_home_duration", "activity_based"
    :affection_age_dependent => "Y" #Options: "Y" (makes affection chance age dependent), "N" (all agents experience exposure equally)
)

model = run_model(params)

postprocessing(model.output_path[1])
