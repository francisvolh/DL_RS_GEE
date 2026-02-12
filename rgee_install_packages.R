# Script: Script with installation procedures to use the RGEE ------------------------------------------------------------
# Author: Ricardo Dal'Agnol da Silva (ricds@hotmail.com)
# Date Created: 2021-10-26
# R version 4.1.1 (2021-08-10)
#
# updated R version 4.5.2
# UPDATES by Francis van Oordt: feb 12 2026
# main changes: 1) some changes in packages and links to web downloads needed
#               2) ignoring some steps that call for raster and rgeos which are defunct now
#              3) simplifying package use to lighten up the original instructions

# clean environment
rm(list = ls()); gc()

# GEE account -------------------------------------------------------------

## you need a GEE account
## log in the https://code.earthengine.google.com/ and register for one
# will need to be sure your code editor works and its connected to active accout
# do not creat an OAuth , the process will do it automatically one  linking to GEE
# be sure to register the project when the Code editor prompts it...
# very IMPORTANT: in the code editor, under the ASSEST button (top left) create an Assests folder in the project you want to link
# (rgee will require any folder in the assets tab for syncing)


# installing conda environment --------------------------------------------------------------------

## the conda environment is where the GEE Python API will be located. The RGEE package uses it.
## first you need to install the Miniconda OUTSIDE of R
## install Miniconda3 at anaconda.com/download
## open 'anaconda' in the command prompt (window button --> anaconda, you will see anaconda prompt)
## then type in the commands below one-by-one (without the #) to install the rgee_py environment and packages (not specifying which python version will call the latest):
# conda create -n rgee_py python
# activate rgee_py
# pip install google-api-python-client
# pip install earthengine-api
# pip install numpy

## ok conda should now be installed, now lets get the path to the environment, type inside anaconda:
# conda env list

## copy the path to the rgee_py environment, you will need it set in the variable below inside R:
## note the use of double backslashes \\ 
## this below is where is located in MY computer, you have to use the 'conda env list' command to find where it is located on yours
### VERIFY ITS YOUR COMPUTER'S ROUTE!!!
rgee_environment_dir = "C:\\ProgramData\\Miniconda3\\envs\\rgee_py\\"



# pre-requirements for R --------------------------------------------------

## R: version at least 3.6 (current 4.5.2 works!)
# Link: https://cran.r-project.org/bin/windows/base/

## RStudio: a recent version is recommended.
## Older versions do not show the GEE images in Viewer correctly.
# Link: https://www.rstudio.com/products/rstudio/download/

## RTools: needed to build some packages in R from source
# Link: https://cran.r-project.org/bin/windows/Rtools/
## after installing the Rtools, make sure to run this command line below inside RStudio:
writeLines('PATH="${RTOOLS40_HOME}\\usr\\bin;${PATH}"', con = "~/.Renviron")



# R packages -------------------------------------------------------------

## if you installed everything above, you can now install the packages inside R
pkgs <- c("geojsonio", "remotes", "reticulate", "devtools", "googledrive")
to_install <- pkgs[!pkgs %in% installed.packages()[, "Package"]] 
install.packages(to_install)

# installing rgee from the github repo will call latest version
install_github("r-spatial/rgee")

## sometimes at this point you are required to restart R or the computer before proceeding
## try restarting if the installation do not finish properly and run the installation again after restart

# 
# set python
reticulate::use_python(rgee_environment_dir, required=T)
rgee::ee_install_set_pyenv(
  py_path = rgee_environment_dir, # Change it for your own Python PATH
  py_env = "rgee_py" # Change it for your own Python ENV
)
# will ask to restart R most likely, accept, and continue with next lines:

Sys.setenv(RETICULATE_PYTHON = rgee_environment_dir)
Sys.setenv(EARTHENGINE_PYTHON = rgee_environment_dir)

# Initialize the Python Environment
# to clean credentials: ee_clean_credentials()
rgee::ee_Initialize(drive = T)
# Web browser pop up windows will come up for Tidyverse and for GEE as well.
# if when Generating a token web in the pop up and get an error, several posibilities:
# 1) invalid token --> may be because the app in the OAuth consent, is not in Test mode, be sure to set it to test
# 2) may have created the OAuth separately, and sync issues may arise, if the Error message suggests to create a New Project, do so!
## It worked if some text about google drive credentials appeared, and asked you to log in your GEE account.
## Congrats.

###########################################
###### TESTING CODE FOR rgee ##############
###########################################


# ---- 1. Parameters ----

end_year <- 2024

start_year <- end_year - 4

preview_year <- end_year



# ---- 2. Region of Interest (Canada) ----

canada <- rgee::ee$FeatureCollection('USDOS/LSIB_SIMPLE/2017')$
  
  filter(rgee::ee$Filter$eq('country_na', 'Canada'))



# ---- 3. Dataset (ERA5 Land) ----

era <- rgee::ee$ImageCollection('ECMWF/ERA5_LAND/MONTHLY_AGGR')



# ---- 4. The CMI Function (Server-Side Logic) ----

# We write a standard R function, but all operations inside utilize 'ee$' methods.

calc_annual_cmi <- function(y) {
  
  year <- rgee::ee$Number(y)
  
  s <- rgee::ee$Date$fromYMD(year, 1, 1)
  
  e <- s$advance(1, "year")
  
  # Filter ERA5 for this specific year & Canada
  
  eray <- era$filterDate(s, e)$filterBounds(canada)
  
  # Calculate Annual Sums (ERA5 is in meters, convert to mm)
  
  # Precip: Sum
  
  P_mm <- eray$select('total_precipitation_sum')$
    
    sum()$
    
    multiply(1000)$
    
    rename('P_mm')
  
  # PET: Sum (ERA5 PET is negative, so multiply by -1000)
  
  PET_mm <- eray$select('potential_evaporation_sum')$
    
    sum()$
    
    multiply(-1000)$
    
    rename('PET_mm')
  
  # CMI Calculation: (P - PET) / PET
  
  # We use .max(0.001) on PET to avoid DivisionByZero errors
  
  pet_safe <- PET_mm$max(0.001)
  
  cmi <- P_mm$subtract(pet_safe)$divide(pet_safe)$rename('CMI')
  
  # Return one image with all bands, carrying the year property
  
  return(
    
    P_mm$addBands(PET_mm)$addBands(cmi)$
      
      set('year', year)$
      
      set('system:time_start', s$millis())
    
  )
  
}



# ---- 5. Map the function (The "R" Way) ----



# 1. Use a standard R vector for the years

r_years <- start_year:end_year



# 2. Use 'lapply' (R's loop) to create a list of ee$Image objects

#    This runs the logic locally in R, creating the instructions for GEE.

image_list <- lapply(r_years, calc_annual_cmi)



# 3. Convert that R list into a server-side ImageCollection

cmi_ic <- rgee::ee$ImageCollection(image_list)



# Verify it worked by printing the size

print(paste("Collection size:", cmi_ic$size()$getInfo()))



# ---- 6. Visualization ----





# Define visualization parameters

vis_params <- list(
  
  min = -1,
  
  max = 1,
  
  palette = c('#9e0142','#f46d43','#fdae61','#ffffbf','#abdda4','#66c2a5','#3288bd')
  
)

preview_img <- cmi_ic$filter(rgee::ee$Filter$eq('year', preview_year))$first()

# Center Map on Canada

rgee::Map$centerObject(canada, zoom = 3)



# FIX: Select ONLY the 'CMI' band for visualization

rgee::Map$addLayer(
  
  eeObject = preview_img$select('CMI')$clip(canada),
  
  visParams = vis_params,
  
  name = paste0('CMI ', preview_year)
  
)
