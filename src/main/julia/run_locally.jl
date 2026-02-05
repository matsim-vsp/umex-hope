include("model.jl")
include("../../../population.jl")

agent_attr = population_reader("006.output_persons.csv")

params = Dict(
    :seeds => 1,
    :iterations => 10,
    :base_susceptibilities => [0.1],
    :recovery_rate => 0.2,
    :days_necessary_exposure => 1,
    :output_folder => missing,
    :agent_attributes => agent_attr
)

run_model(params)