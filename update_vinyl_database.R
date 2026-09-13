#!/usr/bin/env Rscript
# Run with source("update_vinyl_database.R") or Rscript.
# All user-maintained data is in input/Database.xlsx.
(function() {
  # EDIT THESE SETTINGS, then source this file.
  reset_rotation_history <- FALSE # Set TRUE for a reset; return to FALSE afterwards.
  rotation_genres <- c(
    "Classical / Soundtrack" = FALSE,
    "Electronic" = FALSE,
    "Jazz / Blues" = TRUE,
    "Pop" = FALSE,
    "Rock" = TRUE
  )
  if (
    !is.logical(rotation_genres) ||
      anyNA(rotation_genres) ||
      is.null(names(rotation_genres)) ||
      anyDuplicated(names(rotation_genres)) ||
      !any(rotation_genres)
  ) {
    stop("Enable at least one rotation genre with TRUE/FALSE toggles.")
  }
  if (
    !is.logical(reset_rotation_history) ||
      length(reset_rotation_history) != 1L ||
      is.na(reset_rotation_history)
  ) {
    stop("reset_rotation_history must be TRUE or FALSE.")
  }
  included_genres <- names(rotation_genres)[rotation_genres]

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
    "update_vinyl_database.R"
  }
  # With source(..., chdir = TRUE), the working directory may already be here.
  if (sourced && !file.exists(script) && file.exists(basename(script))) {
    script <- basename(script)
  }
  root <- dirname(normalizePath(script, mustWork = TRUE))
  # Ignore arguments belonging to the caller's R session when sourced.
  args <- if (sourced) character() else commandArgs(trailingOnly = TRUE)
  unknown <- args[
    !grepl("^--rotation-size=", args) &
      !args %in% c("--rotation-only", "--reset-rotation-history", "--help")
  ]
  if (length(unknown)) {
    stop("Unknown option: ", paste(unknown, collapse = ", "))
  }
  if ("--help" %in% args) {
    cat(
      'In R: source("update_vinyl_database.R")\n',
      "Terminal: Rscript update_vinyl_database.R [--rotation-only] [--rotation-size=N] [--reset-rotation-history]\n",
      "Reads input/Database.xlsx and rebuilds workbooks in output/.\n"
    )
    return(invisible(NULL))
  }
  option <- grep("^--rotation-size=", args, value = TRUE)
  if (length(option) > 1L) {
    stop("Specify --rotation-size only once.")
  }
  size <- if (length(option)) {
    suppressWarnings(as.numeric(sub("^--rotation-size=", "", option)))
  } else {
    5L * length(included_genres)
  }

  # Activate the project environment and restore the caller's folder on exit.
  previous_directory <- getwd()
  on.exit(setwd(previous_directory), add = TRUE)
  setwd(root)
  source(file.path(root, ".Rprofile"), local = TRUE)
  suppressPackageStartupMessages({
    library(readxl)
    library(openxlsx)
  })
  sys.source(file.path(root, "R", "vinyl_workflow.R"), envir = environment())
  run_update(
    file.path(root, "input", "Database.xlsx"),
    file.path(root, "output"),
    rotation_size = size,
    rotation_only = "--rotation-only" %in% args,
    reset_rotation_history = reset_rotation_history ||
      "--reset-rotation-history" %in% args,
    rotation_genres = included_genres
  )
})()
