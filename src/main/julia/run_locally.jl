# GR runs headless: plots are only written to disk via savefig, no pop-up windows. Must be set before Plots is loaded.
ENV["GKSwstype"] = "nul"

# Activate the project before any `using`, otherwise packages are loaded from the global environment and mixed with the project's versions
using Pkg
Pkg.activate(@__DIR__)

include("preprocessing.jl")
include("model.jl")
include("../../../population.jl")
include("../../../network_creation.jl")
include("../../../temperature.jl")
include("../../../experienced_plans.jl")
include("../../../out_of_home_duration.jl")
include("postprocessing.jl")
include("pre_and_post_mortality_data.jl")

output_path = "data/" * replace(first(string(now()), 19), ":" => "")
mkpath(output_path)

utci_filename = "input/df_utci_$(Dates.format(today(), "yyyy-mm-dd")).csv"
if isfile(utci_filename)
    df_utci_prep = CSV.read(utci_filename, DataFrame)
else
    include("utci_prep.jl")
end

mortality_filename = "input/df_mortality_$(Dates.format(today(), "yyyy-mm-dd")).csv"
if isfile(mortality_filename)
    df_mortality = CSV.read(mortality_filename, DataFrame)
else
    preprocess_mortality_data()
    plot_mortality_data(
    "input/mortality_data_combined_$(Dates.format(today(), "yyyy-mm-dd")).csv";
    save_path = "input/mortality_data_combined_$(Dates.format(today(), "yyyy-mm-dd")).png",
    start_date = Date(2026, 5, 1),
    pre_or_post = "pre"
    )
end

pop_file = "../public-svn/matsim/scenarios/countries/de/hannover/hannover-v1.0/output/10pct/006.output_persons.csv.gz"
agent_attr = population_reader(pop_file)
network_file = "../public-svn/matsim/scenarios/countries/de/hannover/hannover-v1.0/output/10pct/006.output_network.xml.gz"
network = network_creation(network_file)
trajectories_file = "path"
temperature_file = "TemperatureHannoverDWD.txt"
temperature = temperature_reader(temperature_file)

agents_filename = "input/df_agents_attr_$(Dates.format(today(), "yyyy-mm-dd")).csv"
agents_filename_toolong = "input/df_agents_attr_toolong_$(Dates.format(today(), "yyyy-mm-dd")).csv"
agents_filename_toosmall = "input/df_agents_attr_toosmall_$(Dates.format(today(), "yyyy-mm-dd")).csv"
exp_plans_file = "../public-svn/matsim/scenarios/countries/de/hannover/hannover-v1.0/output/10pct/006.output_experienced_plans.xml.gz"
exp_plans_pop_df, exp_plans_dict, exp_plans_durations_df = experienced_plans_reader(exp_plans_file)
if isfile(agents_filename)
    agent_attr = CSV.read(agents_filename, DataFrame; types = Dict(:person => String))
else    
    pop_file = "../public-svn/matsim/scenarios/countries/de/hannover/hannover-v1.0/output/10pct/006.output_persons.csv.gz"
    agent_attr = population_reader(pop_file)
    out_of_home_duration_df = process_all_agents(exp_plans_dict)

    agent_attr = leftjoin(agent_attr, out_of_home_duration_df, on = :person)
    agent_attr = leftjoin(agent_attr, exp_plans_durations_df, on = :person)

    #TODO: Agents who have legs that extend beyond midnight, have activities longer than 24h
    cols = ["home", "educ", "errands", "pt", "bike", "visit", "shop", "work", "business", "walk", "leisure", "car", "accomp", "ride", "other"]
    agent_attr.total_hours = [sum(row[col] for col in cols) / 3600 for row in eachrow(agent_attr)]
    agent_attr_toolong = filter(row -> row.total_hours > 24, agent_attr)
    agent_attr_toosmall = filter(row -> row.total_hours < 23.5, agent_attr)
    filter!(row -> 23.5 <= row.total_hours <= 24, agent_attr)
    CSV.write(agents_filename, agent_attr)
    CSV.write(agents_filename_toolong, agent_attr_toolong)
    CSV.write(agents_filename_toosmall, agent_attr_toosmall)
end 

df_merged = preprocessing(df_utci_prep, output_path)

params = Dict(
    :seeds => 1,
    :iterations => 123, # 2026-05-01 to 2026-08-31 (last day with Tmrt data)
    :start_date => Date(2026, 5, 1),
    :affection_theta => 1e-4, # calibrated: largest theta for which the model curve is still proportional to heat dosis
    :disease => "heat", #Options: "heat", "covid", "rsv"
    :base_susceptibility => 0.05,
    :recovery_rate => 1, # for affected agents, chance that they will recover, between 0.0 and 1.0
    :max_night_recovery_rate => 0.5, # decay parameter of exp decay --> agents recover over night
    :days_necessary_exposure => 1,
    :agent_attributes => agent_attr,
    :health_status => "susceptible",
    :heat_exposure => 0, 
    :days_exposed => 0,
    :pregnant => 0, # 0 = not pregnant, 1 = pregnant
    :days_pregnant => 0,
    :premorbidity => 0,
    :pop_file => pop_file,
    :network_file => network_file,
    :network => network,
    :trajectories_file => trajectories_file,
    :temperature_file => temperature_file,
    :temperature => temperature,
    :threshold_temp => 20,
    :output_folder => output_path,
    :experienced_plans_dict => exp_plans_dict,
    :exp_trial => "No", #Determines number of agents. If == "Y", then no. of agents = 100, else: no of agents according to population file
    :heat_time_module => "activity_based", #Options: "24_hours", "out_of_home_duration", "activity_based"
    :affection_age_dependent => "Y", #Options: "Y" (makes affection chance age dependent), "N" (all agents experience exposure equally)
    :df_merged => df_merged,
    :relative_risk_module => "Scovronick"
    )

    
DosisAccumulationDF = DataFrame(agentid = String[], heatdosis = Float64[], timer = DateTime[])

model = run_model(params)

plot_mortality_data(
    "input/mortality_data_combined_$(Dates.format(today(), "yyyy-mm-dd")).csv";
    save_path = string(model.output_path[1], "/output-mortality.png"),
    start_date = Date(2026, 5, 1),
    pre_or_post = "post",
    model_csv_path = string(model.output_path[1],"/SusceptibleExposedAffected.csv")
)

plot_mortality_data(
    "input/mortality_data_combined_$(Dates.format(today(), "yyyy-mm-dd")).csv";
    save_path = string(model.output_path[1], "/output-mortality.pdf"),
    start_date = Date(2026, 5, 1),
    pre_or_post = "post",
    model_csv_path = string(model.output_path[1],"/SusceptibleExposedAffected.csv")
)

postprocessing(model.output_path[1], params, model)