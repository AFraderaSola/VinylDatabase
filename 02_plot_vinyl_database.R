#!/usr/bin/env Rscript
# Refresh charts with source("02_plot_vinyl_database.R") or Rscript.
(function() {
  # source() supplies its filename in a call frame; Rscript uses --file.
  source_paths <- vapply(
    sys.frames(),
    function(frame) {
      path <- get0("ofile", envir = frame, inherits = FALSE)
      if (is.character(path) && length(path) == 1L && !is.na(path)) path else ""
    },
    character(1)
  )
  source_paths <- source_paths[nzchar(source_paths)]
  sourced <- length(source_paths) > 0L
  file_args <- grep("^--file=", commandArgs(), value = TRUE)
  script <- if (sourced) {
    tail(source_paths, 1L)
  } else if (length(file_args)) {
    sub("^--file=", "", file_args[[1]])
  } else {
    "02_plot_vinyl_database.R"
  }
  # With source(..., chdir = TRUE), the working directory may already be here.
  if (sourced && !file.exists(script) && file.exists(basename(script))) {
    script <- basename(script)
  }
  root <- dirname(normalizePath(script, mustWork = TRUE))
  previous_directory <- getwd()
  on.exit(setwd(previous_directory), add = TRUE)
  setwd(root)
  source(file.path(root, ".Rprofile"), local = TRUE)
  sys.source(file.path(root, "R", "vinyl_workflow.R"), envir = environment())
  sys.source(file.path(root, "R", "vinyl_plots.R"), envir = environment())
  plot_vinyl_database(
    file.path(root, "input", "Database.xlsx"),
    file.path(root, "state", "rotation_history.rds"),
    file.path(root, "output", "plots")
  )
})()
