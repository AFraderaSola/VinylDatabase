# Activate the R environment and optional machine-specific settings.
local({
  if (file.exists("renv/activate.R")) source("renv/activate.R")
  if (file.exists(".Rprofile.local.R"))
    sys.source(".Rprofile.local.R", envir = .GlobalEnv)
})
