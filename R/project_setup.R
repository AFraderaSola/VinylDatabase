# Shared project functions loaded by .Rprofile and analysis scripts.

use_project_python <- function(project_root = ".", required = TRUE) {
  if (!requireNamespace("reticulate", quietly = TRUE)) {
    stop("Package 'reticulate' is required to use the project Python environment.",
      call. = FALSE
    )
  }

  python_path <- if (.Platform$OS.type == "windows") {
    file.path(project_root, ".venv", "python.exe")
  } else {
    file.path(project_root, ".venv", "bin", "python")
  }

  if (!file.exists(python_path)) {
    setup_message <- paste(
      "Project Python environment not found at", shQuote(python_path),
      "Create it with:",
      "conda env create --prefix .venv --file python/environment.yml"
    )
    if (required) stop(setup_message, call. = FALSE)
    warning(setup_message, call. = FALSE)
    return(invisible(NULL))
  }

  python_path <- normalizePath(python_path, winslash = "/", mustWork = TRUE)
  reticulate::use_python(python_path, required = required)
  invisible(python_path)
}

theme_afs_minimal <- function() {
  if (!requireNamespace("ggplot2", quietly = TRUE)) {
    stop("Package 'ggplot2' is required for theme_afs_minimal().", call. = FALSE)
  }

  ggplot2::theme_minimal() +
    ggplot2::theme(
      axis.text.y = ggplot2::element_text(size = 8),
      axis.text.x = ggplot2::element_text(size = 8),
      axis.title = ggplot2::element_text(size = 8, face = "bold"),
      title = ggplot2::element_text(size = 8, face = "bold"),
      legend.title = ggplot2::element_text(size = 7, face = "bold"),
      legend.text = ggplot2::element_text(size = 7),
      legend.key.size = grid::unit(0.1, "in"),
      legend.position = "top",
      strip.text = ggplot2::element_text(size = 8, face = "bold"),
      panel.grid.minor = ggplot2::element_line(linewidth = 0.1),
      panel.grid.major = ggplot2::element_line(linewidth = 0.25)
    )
}

theme_afs_bw <- function() {
  if (!requireNamespace("ggplot2", quietly = TRUE)) {
    stop("Package 'ggplot2' is required for theme_afs_bw().", call. = FALSE)
  }

  ggplot2::theme_bw() +
    ggplot2::theme(
      axis.text.y = ggplot2::element_text(size = 8),
      axis.text.x = ggplot2::element_text(size = 8),
      axis.title = ggplot2::element_text(size = 8, face = "bold"),
      title = ggplot2::element_text(size = 8, face = "bold"),
      legend.title = ggplot2::element_text(size = 7, face = "bold"),
      legend.text = ggplot2::element_text(size = 7),
      legend.key.size = grid::unit(0.1, "in"),
      legend.position = "top",
      strip.text = ggplot2::element_text(size = 8, face = "bold"),
      panel.grid.minor = ggplot2::element_line(linewidth = 0.1),
      panel.grid.major = ggplot2::element_line(linewidth = 0.25),
      panel.background = ggplot2::element_rect(fill = "transparent", color = NA),
      legend.background = ggplot2::element_rect(fill = "transparent", color = NA),
      plot.background = ggplot2::element_rect(fill = "transparent", color = NA)
    )
}

theme_afs_void <- function() {
  if (!requireNamespace("ggplot2", quietly = TRUE)) {
    stop("Package 'ggplot2' is required for theme_afs_void().", call. = FALSE)
  }

  ggplot2::theme_void() +
    ggplot2::theme(
      title = ggplot2::element_text(size = 8, face = "bold"),
      legend.title = ggplot2::element_text(size = 7, face = "bold"),
      legend.text = ggplot2::element_text(size = 7),
      legend.key.size = grid::unit(0.1, "in"),
      legend.position = "top"
    )
}
