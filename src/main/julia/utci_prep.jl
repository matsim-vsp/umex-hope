include("compute_mrt.jl")
include("wind_speed.jl")
include("relative_humidity.jl")
include("air_temperature.jl")

# 1. Rename :datetime to :timestamp in df_mrt to have a common key
df_mrt_renamed = rename(df_mrt, :datetime => :timestamp)

# 2. Join everything onto df_temp's timestamps
df_merged = leftjoin(df_temp,     df_humidity;    on = :timestamp)
df_merged = leftjoin(df_merged,   df_wind;        on = :timestamp)
df_merged = leftjoin(df_merged,   df_mrt_renamed; on = :timestamp)

# 3. Keep only the columns you care about
select!(df_merged, :timestamp, :air_temperature_c, :relative_humidity_pct,
                  :wind_speed_ms, :Tmrt_C)

df_merged = filter(row -> Time(row.timestamp) == Time(12, 0, 0), df_merged)

println(first(df_merged, 5))
println("\n$(nrow(df_merged)) rows, columns: $(names(df_merged))")