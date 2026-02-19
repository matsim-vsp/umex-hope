# umex-hope

This repository contains the contribution of the [Transport Systems Planning and Transport Telematics group](https://www.vsp.tu-berlin.de) of [Technische Universität Berlin](https://www.tu.berlin/) to the umex-hope consortium (https://zkfn.de/umex-hope/).
_Disclaimer:_ We are in the **very** early stages of building this library. At this point in time, we do not recommend using this for anything.

<a rel="TU Berlin" href="https://www.vsp.tu-berlin.de"><img src="https://svn.vsp.tu-berlin.de/repos/public-svn/ueber_uns/logo/TU_BERLIN_Logo_Lang_RGB_SR_rot.svg" width="35%" height="35%"/></a>


The goal of this work is two-fold:

1. Read MATSim output files into Julia and prepare them for data analysis and modeling workflows
2. Build a agent-based model in Julia based on the output files from 1.

## Process an event file

As of now, an event file is converted to a dictionary. Each key corresponds to an activity type. The corresponding value is a data frame containing all events of the chosen type.

## Read a population file 

Allows you to read in and convert to a population file. Only columns necessary for subsequent analysis are kept. 

## Read facilities

Read a facilities file (XML) and convert it to a dataframe.

## Read a network

- **network.jl** : Read a network file (XML) and convert it to two dataframes (one for nodes, one for edges).
- **network_creation.jl** : Takes the two dataframes from _network.jl_ and converts them 

## Read experienced plans

Same formt as the _population_ file, but contains what the agent actually did, and not what they planned.
Agents and their attributes are returned as a dataframe. Activities of agents are returned as a nested dictionary. 

## Read plans

Same as _experienced plans_, see above. No separate function necessary. User may simple leverage _experienced_plans_reader_.

