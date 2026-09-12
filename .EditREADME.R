# Personal README helper. Edit the README text directly in README.md.
# This script creates a starter README if missing, or updates only its title.

project_title <- "VinylDatabase"
readme_file <- "README.md"

title_block <- c(
  "<!-- AUTO-GEN:PROJECT_TITLE:START -->",
  paste0("# ", project_title),
  "<!-- AUTO-GEN:PROJECT_TITLE:END -->"
)

starter <- c(
  title_block,
  "",
  "A personal vinyl collection managed in R from one Excel database, with artist-level moods, shelf ordering and a listening rotation.",
  "",
  "## Organizing the collection",
  "",
  "The permanent shelf sorts by **genre → mood → artist → year**. The four broad genres are Electronic, Rock, Jazz / Blues, and Classical / Soundtrack.",
  "",
  "Each artist has one mood, shared by all their albums. Each mood must contain at least six distinct albums; different pressings count once. Subgenres can vary by album.",
  "",
  "## Updating the collection",
  "",
  "Maintain the Excel database: add records and album details in **Collection**, and set moods and classification defaults in **Artists**. Update `Last_Played` after listening to help refresh the rotation.",
  "",
  "The collection list, shelf order and listening rotation are generated from that database.",
  "",
  "## Editing this README",
  "",
  "Edit this file directly. `.EditREADME.R` only refreshes the project title or creates this starter text when the README is missing."
)

readme <- if (file.exists(readme_file)) {
  readLines(readme_file, warn = FALSE, encoding = "UTF-8")
} else {
  starter
}

start <- which(readme == title_block[[1]])
end <- which(readme == title_block[[3]])
if (length(start) || length(end)) {
  if (length(start) != 1L || length(end) != 1L || start >= end) {
    stop("The README project-title markers are incomplete or duplicated.")
  }
  before <- if (start > 1L) readme[seq_len(start - 1L)] else character()
  after <- if (end < length(readme)) {
    readme[seq.int(end + 1L, length(readme))]
  } else {
    character()
  }
  readme <- c(before, title_block, after)
} else {
  heading <- grep("^# +", readme)
  if (length(heading)) {
    readme[heading[[1]]] <- paste0("# ", project_title)
  } else {
    readme <- c(title_block, "", readme)
  }
}

writeLines(enc2utf8(readme), readme_file, useBytes = TRUE)
message("README.md updated.")
