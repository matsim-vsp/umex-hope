include("../../../experienced_plans.jl")

exp_plans_file = "hannover-1pct.output_experienced_plans.xml"
exp_plans_pop_df, exp_plans_dict = experienced_plans_reader(exp_plans_file)

target_time = Time("01:00:00")

# Find matching keys
matching_keys = [key for (key, val) in exp_plans_dict["1017085"] if Time(val["start_time"]) <= target_time <= Time(val["end_time"])]

println(matching_keys)  # ["period_A", "period_C"]