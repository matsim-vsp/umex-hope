using Plots

function preprocessing(df_merged, output_path)
    df_merged = filter(r -> r.timestamp < DateTime("2026-03-22T12:00:00"), df_merged)

    df_merged.air_temperature_c = coalesce.(df_merged.air_temperature_c, 0.0)
    df_merged.relative_humidity_pct = coalesce.(df_merged.relative_humidity_pct, 0.0)
    df_merged.wind_speed_ms = coalesce.(df_merged.wind_speed_ms, 0.0)
    df_merged.Tmrt_C    = coalesce.(df_merged.Tmrt_C, 0.0)

    vars   = [:air_temperature_c, :relative_humidity_pct, :wind_speed_ms, :Tmrt_C]
    labels = ["Air Temperature (°C)", "Relative Humidity (%)", "Wind Speed (m/s)", "Tmrt (°C)"]

    plots = [
        Plots.plot(df_merged.timestamp, df_merged[!, v];
            label     = nothing,
            ylabel    = l,
            linewidth = 1.5,
            color     = :steelblue)
        for (v, l) in zip(vars, labels)
    ]

    Plots.plot(plots...;
        layout  = (4, 1),
        xlabel  = ["" "" "" "Timestamp"],   # only label the bottom panel
        size    = (900, 800),
        plot_title = "UTCI input variables"
    )

    savefig(string(output_path,"/UTCI_input_variables.pdf"))
end