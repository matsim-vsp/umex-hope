# umex-hope

This repository contains the contribution of the [Transport Systems Planning and Transport Telematics group](https://www.vsp.tu-berlin.de) of [Technische Universität Berlin](https://www.tu.berlin/) to the [umex-hope consortium](https://zkfn.de/umex-hope/).
_Disclaimer:_ We are in the early stages of building this library. At this point in time, we do not recommend using this for anything.

<a rel="TU Berlin" href="https://www.vsp.tu-berlin.de"><img src="https://svn.vsp.tu-berlin.de/repos/public-svn/ueber_uns/logo/TU_BERLIN_Logo_Lang_RGB_SR_rot.svg" width="35%" height="35%"/></a>


The goal of this work is two-fold:

1. Read MATSim output files into Julia and prepare them for data analysis and modeling workflows
2. Build a agent-based model in Julia based on the output files from 1.

## Read MATSim output files into Julia

### Process an event file

As of now, an event file is converted to a dictionary. Each key corresponds to an activity type. The corresponding value is a data frame containing all events of the chosen type.

### Read a population file 

Allows you to read in and convert to a population file. Only columns necessary for subsequent analysis are kept. 

### Read facilities

Read a facilities file (XML) and convert it to a dataframe.

### Read a network

- **network.jl** : Read a network file (XML) and convert it to two dataframes (one for nodes, one for edges).
- **network_creation.jl** : Takes the two dataframes from _network.jl_ and converts them 

### Read experienced plans

Same formt as the _population_ file, but contains what the agent actually did, and not what they planned.
Agents and their attributes are returned as a dataframe. Activities of agents are returned as a nested dictionary. 

### Read plans

Same as _experienced plans_, see above. No separate function necessary. User may simple leverage _experienced_plans_reader_.

## Agent-based model in Julia

The ABM simulates heat-related adverse health effects for the synthetic population of Hannover. Each agent is a person from the MATSim population, and how much heat they are exposed to depends on how long they spend at each activity. One model step is one simulated day (evaluated at 12:00). The default run covers 2026-05-01 to 2026-08-31, which is the last day with mean radiant temperature data.

All ABM code is in [src/main/julia/](src/main/julia/). It is built on [Agents.jl](https://juliadynamics.github.io/Agents.jl/) and partly reuses code from [epi-net-sim](https://github.com/matsim-vsp/epi-net-sim).

### Getting started

**run_locally.jl** is the entry point. It sets up all inputs, defines the model parameters, runs the model and calls the postprocessing. Run it from the repository root so that the relative paths (`input/`, `data/`, `../shared-svn/...`) resolve. The script does the following:

1. Creates an output folder `data/<current datetime>/`.
2. Prepares the weather input (UTCI input variables). If it already exists, it is read from `input/df_utci_<today>.csv`; otherwise `utci_prep.jl` is run.
3. Prepares the observed health data used for comparison (`input/mortality_data_combined_<today>.csv`, plus a plot).
4. Prepares the agent attributes. If they already exist, they are read from `input/df_agents_attr_<today>.csv`; otherwise they are built from the MATSim output (see below).
5. Runs `preprocessing` (input plots, UTCI computation).
6. Runs the model with `run_model(params)`.
7. Plots the model output against the observed data and runs `postprocessing`.

The intermediate files in `input/` carry the current date in their names, so they are reused within a day and rebuilt on the next day.

### Input data and preprocessing

**Agents (MATSim output)**
- The population file (`population_reader`) provides the socio-demographic attributes (age, gender, household income and size, home coordinates, ...).
- The experienced plans (`experienced_plans_reader`) and `out_of_home_duration.jl` give the time each agent spends at each activity or travel mode per day: `home`, `educ`, `errands`, `pt`, `bike`, `visit`, `shop`, `work`, `business`, `walk`, `leisure`, `car`, `accomp`, `ride`, `other`, as well as the total time away from home.
- Only agents whose daily times add up to between 23.5 h and 24 h are kept. Agents outside this range are written to `df_agents_attr_toolong_<date>.csv` and `df_agents_attr_toosmall_<date>.csv` so that they can be inspected.

**Weather (DWD open data, station 02014 Hannover)**
- **air_temperature.jl**, **relative_humidity.jl**, **wind_speed.jl**: download hourly DWD observations and parse them.
- **compute_mrt.jl**: computes the hourly mean radiant temperature (Tmrt) from DWD solar radiation and air temperature data, for an unobstructed standing person (Klima-Michel model / ISO 7726).
- **utci_prep.jl**: joins the four variables on their timestamps and writes `input/df_utci_<date>.csv`.
- **utci.jl**: `utci(ta, tr, vel, rh)` computes the Universal Thermal Climate Index (Bröde et al. 2012 polynomial approximation). `utci_stress_category(u)` maps a UTCI value to its thermal stress category.

**Observed health data (for validation)**
- **pre_and_post_mortality_data.jl**: `preprocess_mortality_data()` combines four sources into one long-format CSV (`date`, `deaths`, `source`). The sources are the RKI heat-related mortality estimates, Destatis weekly death counts, EuroMOMO pooled weekly deaths, and the daily ambulance (RTW) dispatch counts of the Helmstedt control centre. `plot_mortality_data(...)` plots these sources, either on their own (`pre_or_post = "pre"`) or together with the model output (`pre_or_post = "post"`).

**preprocessing.jl**
- `preprocessing(df_merged, output_path)` restricts the weather data to the simulation period, fills missing values, and computes the UTCI for every timestamp. It also writes plots of the UTCI input variables, the daily UTCI at noon, and the distribution of time spent at each activity (including stacked bar charts for random samples of valid, too-short and too-long agents).

### Model structure (model.jl)

**Agent (`Person_Sim`)**: holds the MATSim attributes (age, gender, income, household size, home location), the time spent per activity, and the model state: `health_status`, `dosis`, `relative_risk`, `affection_theta`, `pregnancy` and `premorbidity`.

**Health states**: `susceptible` and `affected`. In addition, `newlyaffected` counts the susceptible → affected transitions per day, which is comparable to a daily incidence. `exposed` is defined in the scheduler but not used by any transition at the moment.

**Main functions**
- `run_model(params)`: writes `input_params.csv`, initialises and steps the model for each seed, and exports the results.
- `initialize(...)`: creates the `StandardABM` on a `GraphSpace` built from the MATSim network and adds one agent per row of the agent attributes (or 100 agents if `exp_trial == "Y"`). It also assigns placeholder values for pregnancy (women aged 17–44) and pre-morbidity (agents older than 65), each with a probability of 0.5.
- `AES_scheduler(agent)`: activates agents in the order affected → exposed → susceptible.
- `agent_step!(person, model)`: an affected agent recovers with probability `recovery_rate`. For a susceptible agent, the heat dose and affection probability are computed (see below), and the agent becomes affected with that probability. Each agent's daily dose is logged.
- `model_step!(model)`: records the state counts per 10-year age group and moves the timer forward by one day.
- `push_state_count_to_history!(model)`: writes the counts per state and age bin into `model.hist` and resets the daily `newlyaffected` counter.

### Heat dose and probability of being affected

**compute_dosis.jl**: the daily heat dose is a cumulative UTCI exceedance (based on [Sadeghi et al. 2021](https://doi.org/10.1016/j.buildenv.2021.107947)):

```
dose = max( Σ_activities (UTCI − threshold_uncomfortable(activity)) · hours_at_activity , 0 )
```

Each activity has its own "uncomfortable" and "critical" UTCI thresholds (`thresholds` table); currently only the "uncomfortable" threshold is used. How the time component is computed is chosen with `:heat_time_module`:

| `:heat_time_module`      | Time used for the dose                                                    |
|--------------------------|---------------------------------------------------------------------------|
| `"24_hours"`             | The agent is exposed for 24 h with the `not_home` threshold              |
| `"out_of_home_duration"` | Time away from home, with the `not_home` threshold                       |
| `"activity_based"`       | Time at each activity, each with its own threshold (summed)              |

**compute_affection_chance.jl**: the dose is turned into a daily probability of being affected:

```
P(affected) = 1 − exp(−RR · θ · dose)
```

Here, θ is `:affection_theta` (calibrated) and RR is the agent's age-dependent relative risk, chosen with `:relative_risk_module`:

| `:relative_risk_module` | Source                                                                                         |
|-------------------------|------------------------------------------------------------------------------------------------|
| `"Scovronick"`          | [Scovronick et al.](https://doi.org/10.1097/EE9.0000000000000336), RR with small random noise |
| `"Choudhary"`           | [CDC MMWR](https://www.cdc.gov/mmwr/preview/mmwrhtml/ss6313a1.htm), Table 1                    |
| `"Winklmayr"`           | [Winklmayr et al.](https://doi.org/10.3238/arztebl.m2022.0202), Fig. 7, region north           |

### Main parameters (set in run_locally.jl)

| Parameter                  | Meaning                                                                    |
|----------------------------|----------------------------------------------------------------------------|
| `:seeds`                   | Number of random seeds                                                     |
| `:iterations`              | Number of simulated days                                                   |
| `:start_date`              | First simulated day                                                        |
| `:affection_theta`         | Scaling factor θ between dose and affection probability                    |
| `:recovery_rate`           | Daily probability that an affected agent recovers                          |
| `:heat_time_module`        | How exposure time is computed (see above)                                  |
| `:relative_risk_module`    | Source of the age-dependent relative risks (see above)                     |
| `:disease`                 | `"heat"` (only option implemented; `"covid"` and `"rsv"` are placeholders) |
| `:exp_trial`               | `"Y"` runs a quick test with 100 agents                                    |
| `:df_merged`               | Weather/UTCI input from `preprocessing`                                    |
| `:agent_attributes`        | Agent attribute data frame                                                 |

`:base_susceptibility`, `:days_necessary_exposure`, `:affection_age_dependent` and `:threshold_temp` are passed in but not used by the current transition logic.

### Outputs

The following files are written to `data/<datetime>/`:
- `input_params.csv`: parameters of the run
- `SusceptibleExposedAffected.csv`: daily counts per state
- `SusceptibleExposedAffected_diffbyage.csv`: daily counts per state and age group
- `dosis_accumulation_df.csv`: daily heat dose per agent
- Plots from preprocessing (UTCI inputs, UTCI, activity time distributions)

**postprocessing.jl**: `postprocessing(output_path)` plots the states over time, the modelled daily incidence (per 100,000) against the control-centre data, the affected agents per age group, and the heat dose over time for 20 random agents. Separately, `run_locally.jl` calls `plot_mortality_data(..., pre_or_post = "post")`, which writes `output-mortality.png` comparing the model with the observed health data.
