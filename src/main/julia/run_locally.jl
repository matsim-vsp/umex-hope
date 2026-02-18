include("model.jl")
include("../../../population.jl")
include("../../../network_creation.jl")

pop_file = "006.output_persons.csv"
agent_attr = population_reader(pop_file)
network_file = "hannover-1pct.output_network.xml"
network = network_creation(network_file)
trajectories_file = "path"


params = Dict(
    :seeds => 1,
    :iterations => 10,
    :base_susceptibility => [0.1],
    :recovery_rate => 0.2,
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
    :output_folder => missing
)

run_model(params)