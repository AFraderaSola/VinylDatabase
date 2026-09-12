# Canonical project startup. Keep machine-specific settings in .Rprofile.local.R.
local({
  renv_activate <- file.path("renv", "activate.R")
  if (file.exists(renv_activate)) source(renv_activate)

  project_setup <- file.path("R", "project_setup.R")
  if (file.exists(project_setup)) sys.source(project_setup, envir = .GlobalEnv)

  if (file.exists(".Rprofile.local.R")) {
    sys.source(".Rprofile.local.R", envir = .GlobalEnv)
  }
})
