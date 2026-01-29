using Pkg
using CSV
using DataFrames

function population(file_path)

    populationDf = CSV.read(file_path, DataFrame, 
                            header = 1, 
                            select=["person", "SNZ_age", "SNZ_gender", "SNZ_hhIncome", "SNZ_hhSize", "home_x", "home_y", "income", "sex"])

    prefixes = ["freight", "goodsTraffic", "commercialPersonTraffic"]
    populationDf = filter(:person => p -> !any(startswith(p, prefix) for prefix in prefixes), populationDf) #remove these "agents" as they are not of interest for us
end

