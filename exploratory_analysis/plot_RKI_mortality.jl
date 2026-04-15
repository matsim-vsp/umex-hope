using XLSX, DataFrames, Plots, ColorSchemes, Measures

Deaths_or_Incidence = "Incidence" #Alternative option: "Incidence"

# Load the Excel file
df = DataFrame(XLSX.readtable("./HitzebedingteMortalitaetRKI.xlsx", "Daten"))

df.Geschaetzte_Anzahl_Sterbefaelle = parse.(Float64, string.(df.Geschaetzte_Anzahl_Sterbefaelle))
df.Unteres_95_Praediktionsintervall = parse.(Float64, string.(df.Unteres_95_Praediktionsintervall))
df.Oberes_95_Praediktionsintervall = parse.(Float64, string.(df.Oberes_95_Praediktionsintervall))
df.Sterbefaelle_pro_100000 = parse.(Float32, string.(df.Sterbefaelle_pro_100000))
df.pro_100000_Unteres_95_Praediktionsintervall = parse.(Float32, string.(df.pro_100000_Unteres_95_Praediktionsintervall))
df.pro_100000_Oberes_95_Praediktionsintervall = parse.(Float32, string.(df.pro_100000_Oberes_95_Praediktionsintervall))

# Get unique values
years = sort(unique(df.Jahr))
combos = unique(df[:, [:Geschlecht, :Altersgruppe]])

# Assign colors per Geschlecht group
function get_colors(geschlecht, n)
    if geschlecht == "Gesamt"
        return [RGB(0, g, 0) for g in range(0.35, 0.9, length=n)]
    elseif geschlecht == "weiblich"
        return [RGB(0, 0, b) for b in range(0.35, 0.9, length=n)]
    elseif geschlecht == "maennlich"
        return [RGB(r, 0, 0) for r in range(0.35, 0.9, length=n)]
    else
        return [RGB(0.5, 0.5, 0.5) for _ in 1:n]
    end
end

# Build a color mapping: (Geschlecht, Altersgruppe) => Color
color_map = Dict()
for g in ["Gesamt", "weiblich", "maennlich"]
    sub = filter(row -> row.Geschlecht == g, combos)
    alters = sort(unique(sub.Altersgruppe))
    colors = get_colors(g, length(alters))
    for (i, a) in enumerate(alters)
        color_map[(g, a)] = colors[i]
    end
end

# Create one panel per year
plots_list = []

for yr in years
    df_yr = filter(row -> row.Jahr == yr, df)

    p = plot(
        title = "Year $(Int(yr))",
        xlabel = "Calendar week",
        ylabel = "Estimated deaths",
        legend = false,
        titlefontsize = 9,
        labelfontsize = 7,
        bottom_margin = 8mm,
        left_margin = 12mm,
    )

    for (g, a) in zip(combos.Geschlecht, combos.Altersgruppe)
        sub = filter(r -> r.Geschlecht == g && r.Altersgruppe == a, df_yr)
        isempty(sub) && continue
        sub = sort(sub, :KW)

        c = color_map[(g, a)]

        if Deaths_or_Incidence == "Deaths"
            y_axis = sub.Geschaetzte_Anzahl_Sterbefaelle
            lower_ribbon = sub.Geschaetzte_Anzahl_Sterbefaelle .- sub.Unteres_95_Praediktionsintervall
            upper_ribbon = sub.Oberes_95_Praediktionsintervall .- sub.Geschaetzte_Anzahl_Sterbefaelle
        elseif Deaths_or_Incidence == "Incidence"
            y_axis = sub.Sterbefaelle_pro_100000
            lower_ribbon = sub.Sterbefaelle_pro_100000 .- sub.pro_100000_Unteres_95_Praediktionsintervall
            upper_ribbon = sub.pro_100000_Oberes_95_Praediktionsintervall .- sub.Sterbefaelle_pro_100000
        else 
            error("You entered an invalid parameter for Deaths_or_Incidence")
        end

        plot!(p,
            sub.KW,
            y_axis,
            ribbon = (
                lower_ribbon,
                upper_ribbon
            ),
            fillalpha = 0.15,
            linewidth = 1.5,
            color = c,
            label = false,
        )
    end

    push!(plots_list, p)
end

# Create a dummy legend panel
legend_plot = plot(
    framestyle = :none,
    background_color_subplot = :transparent,
    xlims = (0, 1), ylims = (0, 1),
)

for (g, a) in zip(combos.Geschlecht, combos.Altersgruppe)
    c = color_map[(g, a)]
    plot!(legend_plot,
        [NaN], [NaN],
        color = c,
        label = string(g, " / ", a),
        linewidth = 1.5,
    )
end

plot!(legend_plot, legend = :inside, legendfontsize = 7)

# Combine all panels
ncols = length(years)

final_plot = plot(
    plots_list..., legend_plot,
    layout = @layout([a b c d{0.1w}]),
    size = ((ncols + 1) * 350, nrows * 320),
    plot_title = "Heat-related deaths by year, gender, and age group",
    plot_titlevspan = 0.09,
    top_margin = 10mm,
)

if Deaths_or_Incidence == "Deaths"
    savefig(final_plot, "Mortality_Count_RKI.png")
    savefig(final_plot, "Mortality_Count_RKI.pdf")
elseif Deaths_or_Incidence == "Incidence"
    savefig(final_plot, "Mortality_Incidence_RKI.png")
    savefig(final_plot, "Mortality_Incidence_RKI.pdf")
end
display(final_plot)