# umex-hope

This repository contains out contribution to the umex-hope consortium (https://zkfn.de/umex-hope/). _Disclaimer:_ We are in the **very** early stages of building this library. At this point in time, we do not recommend using this for anything.
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

## Read plans

Same as "population", see above.

## Read experienced plans

Same formt as the "population" file, but contains what the agent actually did, and not what he/she planned.
Agents and their attributes are returned as a dataframe. Activities of agents are returned as a nested dictionary. 
