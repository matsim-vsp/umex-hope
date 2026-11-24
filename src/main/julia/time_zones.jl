using Dates

# ── Time zones ────────────────────────────────────────────────────────────────
# All weather lookups (model.utci_hourly, model.utci_home_hourly, model.air_temperature_hourly) are keyed by UTC timestamps:
# the DWD station data is in UTC, and the indoor measurements are converted from CET to UTC in indoor_utci.jl.
# The agents' activity times (experienced plans, hourly_activity_seconds) and the simulated days, however, are in
# local German time (CET in winter, CEST = UTC+2 in summer). Every lookup of "hour h of day d" therefore has to
# convert the local time to UTC first, using local_to_utc. Without this conversion, all exposures would be
# shifted by 2 hours in summer (e.g. the local 14:00 - 14:59 would get the UTCI of 16:00 - 16:59 local time).
# Plots of hourly / daily values use utc_to_local, so that they show the same local time as the model.

"""
    local_to_utc(t::DateTime) -> DateTime

    Converts a local German time (Europe/Berlin) to UTC, using the EU daylight saving time rule:
    CEST (UTC+2) from the last Sunday of March, 02:00 local, to the last Sunday of October, 03:00 local; CET (UTC+1) otherwise.
    Edge cases at the switches: the non-existent hour 02:00 - 02:59 in March is treated as CEST,
    and the hour 02:00 - 02:59 that occurs twice in October is mapped to its first occurrence (CEST).
"""
function local_to_utc(t::DateTime)
    y = year(t)
    dst_start = DateTime(Dates.tolast(Date(y, 3), Dates.Sunday; of = Month), Time(2))
    dst_end   = DateTime(Dates.tolast(Date(y, 10), Dates.Sunday; of = Month), Time(3))
    return dst_start <= t < dst_end ? t - Hour(2) : t - Hour(1)
end

"""
    utc_to_local(t::DateTime) -> DateTime

    Converts a UTC time to local German time (Europe/Berlin): CEST (UTC+2) from the last Sunday of March, 01:00 UTC,
    to the last Sunday of October, 01:00 UTC; CET (UTC+1) otherwise. Unambiguous in this direction.
"""
function utc_to_local(t::DateTime)
    y = year(t)
    dst_start = DateTime(Dates.tolast(Date(y, 3), Dates.Sunday; of = Month), Time(1))
    dst_end   = DateTime(Dates.tolast(Date(y, 10), Dates.Sunday; of = Month), Time(1))
    return dst_start <= t < dst_end ? t + Hour(2) : t + Hour(1)
end

# ── Hourly intervals ──────────────────────────────────────────────────────────
# The model treats hour hh as the interval hh:00 - hh:59 (dose, night recovery), and the indoor values are means over
# exactly that interval (indoor_utci.jl). The DWD values labelled hh, however, describe (approximately) the moment hh:00:
#   - air temperature and relative humidity: value at the full hour hh:00
#   - wind speed: 10-minute mean ending at hh:00
#   - Tmrt: from solar radiation sums over roughly (hh-1):20 - hh:20 UTC (true local solar time hours,
#     the timestamps are floored to the full hour in compute_mrt.jl)
# Using them directly for hh:00 - hh:59 would take the outdoor exposure ~30 minutes too early.
# outdoor_hourly_means therefore assigns to hour hh the mean of the DWD values at hh:00 and (hh+1):00.

"""
    outdoor_hourly_means(df_merged) -> DataFrame

    Hourly DWD values (UTC, labelled hh) -> values representing the interval hh:00 - hh:59 (UTC, labelled hh):
    the mean of the values at hh:00 and (hh+1):00, for air temperature, relative humidity, wind speed and Tmrt.
    If the value at (hh+1):00 is missing (last hour of the data, or a gap), the value at hh:00 is used.
    UTCI is computed afterwards from these means (as for the indoor data), not averaged itself.
"""
function outdoor_hourly_means(df_merged)
    cols = [:air_temperature_c, :relative_humidity_pct, :wind_speed_ms, :Tmrt_C]
    row_of = Dict(t => i for (i, t) in enumerate(df_merged.timestamp))
    df = select(df_merged, :timestamp, cols)
    for c in cols
        v = df_merged[!, c]
        df[!, c] = [begin
                        j = get(row_of, t + Hour(1), nothing)
                        isnothing(j) ? v[i] : (v[i] + v[j]) / 2
                    end for (i, t) in enumerate(df_merged.timestamp)]
    end
    return df
end
