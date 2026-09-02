using XLSX, DataFrames, Plots, ColorSchemes, Measures

#Data stems from https://edoc.rki.de/handle/176904/11174
#Alternatively access archive via https://www.rki.de/DE/Themen/Gesundheit-und-Gesellschaft/Gesundheitliche-Einflussfaktoren-A-Z/H/Hitze/Bericht_Hitzemortalitaet.html

Deaths_or_Incidence = "Deaths" #Alternative option: "Incidence"
Cumulative_or_New = "New"
Gender = false #If true, plot "Gesamt", "weiblich" and "maennlich" separately. If false, plot only "Gesamt" for each age group.

# Read in RKI mortality excel file
df = DataFrame(XLSX.readtable("./HitzebedingteMortalitaetRKI.xlsx", "Daten"))
df.Jahr = Int.(df.Jahr)
df.KW = Int.(df.KW)
df.Geschaetzte_Anzahl_Sterbefaelle = parse.(Float64, string.(df.Geschaetzte_Anzahl_Sterbefaelle))
df.Unteres_95_Praediktionsintervall = parse.(Float64, string.(df.Unteres_95_Praediktionsintervall))
df.Oberes_95_Praediktionsintervall = parse.(Float64, string.(df.Oberes_95_Praediktionsintervall))
df.Sterbefaelle_pro_100000 = parse.(Float32, string.(df.Sterbefaelle_pro_100000))
df.pro_100000_Unteres_95_Praediktionsintervall = parse.(Float32, string.(df.pro_100000_Unteres_95_Praediktionsintervall))
df.pro_100000_Oberes_95_Praediktionsintervall = parse.(Float32, string.(df.pro_100000_Oberes_95_Praediktionsintervall))

# Monday of a given ISO calendar week (kept for reference / potential future use)
iso_monday(jahr, kw) = firstdayofweek(Date(jahr, 1, 4)) + Week(kw - 1)
df.Datum = iso_monday.(df.Jahr, df.KW)

# Make sure rows are ordered by week within each group first
sort!(df, [:Geschlecht, :Altersgruppe, :Jahr, :KW])

# Weekly new deaths = first cumulative value, then week-over-week differences
transform!(
    groupby(df, [:Geschlecht, :Altersgruppe, :Jahr]),
    :Geschaetzte_Anzahl_Sterbefaelle =>
        (x -> [first(x); diff(x)]) =>
        :Woechentliche_Sterbefaelle
)

# Get unique values
years = sort(unique(df.Jahr))
combos = unique(df[:, [:Geschlecht, :Altersgruppe]])

# If Gender is false, restrict to "Gesamt" only -- everything downstream (colors,
# panel loop, legend) is built from `combos`, so filtering it here is enough.
if !Gender
    combos = filter(row -> row.Geschlecht == "Gesamt", combos)
end

# Build a stable, ordered list of all (Geschlecht, Altersgruppe) combinations
combo_order = DataFrame(Geschlecht = String[], Altersgruppe = String[])
for g in ["Gesamt", "weiblich", "maennlich"]
    sub = filter(row -> row.Geschlecht == g, combos)
    for a in sort(unique(sub.Altersgruppe))
        push!(combo_order, (g, a))
    end
end

# Same color palette as used for the Destatis plot (:tab20), one color per combo
tab20 = palette(:tab20, nrow(combo_order))
color_map = Dict(
    (row.Geschlecht, row.Altersgruppe) => tab20[i]
    for (i, row) in enumerate(eachrow(combo_order))
)

# Create one panel per year
plots_list = []

for yr in years
    df_yr = filter(row -> row.Jahr == yr, df)

    if Deaths_or_Incidence == "Deaths"
        ylabel = "Estimated deaths (RKI)"
    elseif Deaths_or_Incidence == "Incidence"
        ylabel = "Estimated deaths per 100.000 inhabitants (RKI)"
    else
       error("You entered an invalid parameter for Deaths_or_Incidence")
    end

    p = Plots.plot(
        title = "Weekly deaths\nin Germany\nby age group ($(Int(yr)))",
        xlabel = "Calendar week",
        ylabel = ylabel,
        legend = false,
        titlefontsize = 9,
        labelfontsize = 7,
        bottom_margin = 8mm,
        left_margin = 12mm,
        xformatter = x -> string(round(Int, x)),   # whole calendar weeks, no decimals
    )

    for (g, a) in zip(combos.Geschlecht, combos.Altersgruppe)
        sub = filter(r -> r.Geschlecht == g && r.Altersgruppe == a, df_yr)
        isempty(sub) && continue
        sub = sort(sub, :KW)   # calendar week is now the x-axis, sort by it directly

        c = color_map[(g, a)]

        if Deaths_or_Incidence == "Deaths"
            if Cumulative_or_New == "Cumulative"
                y_axis = sub.Geschaetzte_Anzahl_Sterbefaelle
                lower_ribbon = sub.Geschaetzte_Anzahl_Sterbefaelle .- sub.Unteres_95_Praediktionsintervall
                upper_ribbon = sub.Oberes_95_Praediktionsintervall .- sub.Geschaetzte_Anzahl_Sterbefaelle
            elseif Cumulative_or_New == "New"
                y_axis = sub.Woechentliche_Sterbefaelle
            else
                error("You entered an invalued parameter for Cumulative_or_New")
            end
        elseif Deaths_or_Incidence == "Incidence"
            y_axis = sub.Sterbefaelle_pro_100000
            lower_ribbon = sub.Sterbefaelle_pro_100000 .- sub.pro_100000_Unteres_95_Praediktionsintervall
            upper_ribbon = sub.pro_100000_Oberes_95_Praediktionsintervall .- sub.Sterbefaelle_pro_100000
        else
            error("You entered an invalid parameter for Deaths_or_Incidence")
        end

        if Cumulative_or_New == "Cumulative"
            Plots.plot!(p,
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
        elseif  Cumulative_or_New == "New"
            Plots.plot!(p,
                sub.KW,
                y_axis,
                fillalpha = 0.15,
                linewidth = 1.5,
                color = c,
                label = false,
            )
        end
    end

    push!(plots_list, p)
end

# Create a dummy legend panel
legend_plot = Plots.plot(
    framestyle = :none,
    legendtitle   = "Age group",
    background_color_subplot = :transparent,
    xlims = (0, 1), ylims = (0, 1),
)

for (g, a) in zip(combos.Geschlecht, combos.Altersgruppe)
    c = color_map[(g, a)]
    Plots.plot!(legend_plot,
        [NaN], [NaN],
        color = c,
        label = string(g, " / ", a),
        linewidth = 1.5,
    )
end

Plots.plot!(legend_plot, legend = :inside, legendfontsize = 7)

# Combine all panels
ncols = length(years)
nrows = 1

final_plot = Plots.plot(
    plots_list..., legend_plot,
    layout = @layout([a b c d e{0.1w}]),
    size = ((ncols + 1) * 350, nrows * 320),
    #plot_title = "Heat-related deaths by year, gender, and age group",
    plot_titlevspan = 0.09,
    top_margin = 10mm,
    right_margin = 10mm,
    bottom_margin = 10mm,
    guidefontsize = 16,
    tickfontsize  = 10,
        legendfontsize = 10,
        titlefontsize = 16,
)

if Deaths_or_Incidence == "Deaths"
    if Cumulative_or_New == "Cumulative"
        savefig(final_plot, "RKI_cumulative_deaths_by_agegroup.png")
        savefig(final_plot, "RKI_cumulative_deaths_by_agegroup.pdf")
        println("Figured saved as: RKI_cumulative_deaths_by_agegroup.pdf")
    elseif Cumulative_or_New == "New"
        savefig(final_plot, "RKI_new_deaths_by_agegroup.png")
        savefig(final_plot, "RKI_new_deaths_by_agegroup.pdf")
        println("Figured saved as: RKI_new_deaths_by_agegroup.pdf")
    end
elseif Deaths_or_Incidence == "Incidence"
        savefig(final_plot, "RKI_deaths_incidence_by_agegroup.png")
        savefig(final_plot, "RKI_deaths_incidence_by_agegroup.pdf")
        println("Figured saved as: RKI_deaths_incidence_by_agegroup.pdf")
end