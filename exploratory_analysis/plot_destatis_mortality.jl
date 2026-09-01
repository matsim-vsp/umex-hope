## destatis_weekly_deaths.jl
##
## Downloads Destatis' "Sterbefälle nach Tagen, Wochen und Monaten" report,
## extracts sheet "12613-01" (weekly deaths in Germany by age group), and
## plots a line chart of weekly death counts per age group.
##
## Needed packages (run once):
##   using Pkg
##   Pkg.add(["XLSX", "DataFrames", "Plots"])

using Downloads
using XLSX
using DataFrames
using Plots

# ---------------------------------------------------------------------
# 1) Download the current xlsx file from Destatis
# ---------------------------------------------------------------------
url = "https://www.destatis.de/DE/Themen/Gesellschaft-Umwelt/Bevoelkerung/" *
      "Sterbefaelle-Lebenserwartung/Publikationen/Downloads-Sterbefaelle/" *
      "statistischer-bericht-sterbefaelle-tage-wochen-monate-aktuell-5126109.xlsx" *
      "?__blob=publicationFile&v=165"

xlsx_path = joinpath(tempdir(), "destatis_sterbefaelle.xlsx")
Downloads.download(url, xlsx_path)

# ---------------------------------------------------------------------
# 2) Read sheet "12613-01"
#    ("Sterbefälle nach Kalenderwochen und Altersgruppen in Deutschland")
# ---------------------------------------------------------------------
xf    = XLSX.readxlsx(xlsx_path)
sheet = xf["12613-01"]
dim   = XLSX.get_dimension(sheet)
raw   = sheet[dim]              # Matrix{Any}: full used range of the sheet

# ---------------------------------------------------------------------
# 3) Drop the descriptive header rows (rows 1-4: link/title/"Kalenderwoche"
#    banner/week-number row) and keep only the block of rows that belongs
#    to the most recent year.
#
#    NOTE: In the current file this data block is 16 rows long (row 5 =
#    "Insgesamt" + rows 6-20 = the 15 age groups), i.e. it ends at row 20,
#    not row 24/25 -- the sheet immediately repeats the same 16-row layout
#    for the previous year (2025) starting at row 21, then 2024, etc.
#    Rather than hard-coding a row number that would need to be revisited
#    whenever Destatis reshuffles the file, we detect the block dynamically
#    from the "year" column so this keeps working as the file is updated.
# ---------------------------------------------------------------------
data_rows    = raw[5:end, :]                       # drop rows 1-4
current_year = data_rows[1, 1]                      # year of first data row (e.g. 2026)
keep         = [row[1] == current_year for row in eachrow(data_rows)]
data_rows    = data_rows[keep, :]                   # "Insgesamt" + all age groups, current year only

# ---------------------------------------------------------------------
# 4) Determine how many weeks are already filled in. Destatis pads
#    not-yet-published weeks with "..." -- truncate at the last real
#    (numeric) week column, i.e. "up until the current week".
# ---------------------------------------------------------------------
totals_row    = data_rows[1, :]                     # "Insgesamt" row, used as reference
last_week_col = findlast(x -> x isa Number, totals_row)
n_weeks       = last_week_col - 2                   # columns 1:2 are year / agegroup

data_rows = data_rows[:, 1:last_week_col]

# ---------------------------------------------------------------------
# 5) Build the tidy table: col 1 = year, col 2 = agegroup, col 3.. = weekly counts
# ---------------------------------------------------------------------
header = vcat([:year, :agegroup], [Symbol("week$i") for i in 1:n_weeks])
df = DataFrame(data_rows, header)

df.year = Int.(df.year)
for i in 1:n_weeks
    df[!, Symbol("week$i")] = Int.(df[!, Symbol("week$i")])
end

# ---------------------------------------------------------------------
# 6) Line chart: calendar week (x) vs. death count (y), one colored line
#    per age group. "Insgesamt" (the yearly total across all ages) is
#    excluded from the plot by default so it doesn't dwarf the individual
#    age-group lines -- comment out the `continue` line below to include it.
# ---------------------------------------------------------------------
weeks = 1:n_weeks

plt = Plots.plot(
    xlabel        = "Calendar week ($(current_year))",
    ylabel        = "Deaths",
    title         = "Weekly deaths in Germany by age group ($(current_year))",
    legend        = :outertopright,
    legendtitle   = "Age group",
    palette       = :tab20,
    size          = (950, 600),
    guidefontsize = 14,   # font size of the axis titles ("Calendar week ...", "Deaths")
    tickfontsize  = 12,   # font size of the axis tick labels
)
 
for row in eachrow(df)
    row.agegroup == "Insgesamt" && continue
    counts = [row[Symbol("week$i")] for i in 1:n_weeks]
    Plots.plot!(plt, weeks, counts, label = row.agegroup, linewidth = 2)
end
 
display(plt)
savefig(plt, "Destatis_deaths_by_agegroup.png")
savefig(plt, "Destatis_deaths_by_agegroup.pdf")
println("Figured saved as: Destatis_deaths_by_agegroup.pdf")