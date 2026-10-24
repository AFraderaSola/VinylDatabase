# Shared classification, validation and safe output helpers.

#' Normalize text for stable matching
#'
#' @param x A vector coercible to character.
#' @return A transliterated, lowercase character vector with punctuation and
#'   repeated spaces collapsed. Missing values become empty strings.
#' @noRd
normalize <- function(x) {
  x <- ifelse(is.na(x), "", as.character(x))
  x <- iconv(x, from = "", to = "ASCII//TRANSLIT")
  trimws(gsub(" +", " ", gsub("[^a-z0-9]+", " ", tolower(x))))
}
#' Identify blank values
#' @param x A vector.
#' @return A logical vector marking `NA` and empty trimmed strings.
#' @noRd
is_missing <- function(x) is.na(x) | !nzchar(trimws(as.character(x)))
#' Build stable album keys
#' @param artist,album Artist and album vectors of equal length.
#' @return Normalized `artist|album` keys.
#' @noRd
key_for <- function(artist, album) paste(normalize(artist), normalize(album), sep = "|")
#' Require named columns
#' @param data A data frame.
#' @param columns Required column names.
#' @param label Human-readable source label used in errors.
#' @return `NULL` invisibly; stops when a column is absent.
#' @noRd
require_columns <- function(data, columns, label) {
  missing <- setdiff(columns, names(data))
  if (length(missing)) stop(label, " is missing: ", paste(missing, collapse = ", "))
}
#' Validate a unique nonempty key
#' @param data A data frame.
#' @param key Name of the key column.
#' @param label Human-readable source label used in errors.
#' @return `NULL` invisibly; stops for missing or duplicate keys.
#' @noRd
unique_keys <- function(data, key, label) {
  if (any(is_missing(data[[key]])) || anyDuplicated(data[[key]]))
    stop(label, " needs one nonempty ", key, " per row. Resolve duplicate or missing keys first.")
}
#' Prevent input overwrite
#' @param input,output File paths to compare.
#' @return `NULL` invisibly; stops when the normalized paths are identical.
#' @noRd
different_paths <- function(input, output) {
  if (normalizePath(input, mustWork = FALSE) == normalizePath(output, mustWork = FALSE))
    stop("Input and output must be different files.")
}
#' Install a staged file
#' @param staging Existing staged file.
#' @param path Destination path.
#' @return `NULL` invisibly; stops if the atomic rename fails.
#' @noRd
install_file <- function(staging, path) {
  if (!file.rename(staging, path)) stop("Could not replace ", path)
}

#' Normalize a generated XLSX package
#'
#' Repairs worksheet dimensions produced by the pinned `openxlsx`, removes only
#' known dangling drawing references, and optionally preserves the input theme.
#' @param path XLSX file to normalize in place.
#' @param rows,cols Final worksheet dimensions.
#' @param template Optional XLSX file whose Office theme should be retained.
#' @return `NULL` invisibly; modifies `path` in place.
#' @noRd
finalize_xlsx_package <- function(path, rows, cols, template = NULL) {
  expanded <- tempfile("vinyl-xlsx-")
  dir.create(expanded)
  on.exit(unlink(expanded, recursive = TRUE), add = TRUE)
  utils::unzip(path, exdir = expanded)
  # Keep the input workbook's Office theme, including its table colours.
  if (!is.null(template)) {
    theme <- "xl/theme/theme1.xml"
    if (theme %in% utils::unzip(template, list = TRUE)$Name)
      utils::unzip(template, files = theme, exdir = expanded, overwrite = TRUE)
  }
  sheet_path <- file.path(expanded, "xl", "worksheets", "sheet1.xml")
  xml <- paste(readLines(sheet_path, warn = FALSE), collapse = "\n")
  dimension <- sprintf('<dimension ref="A1:%s%d"/>', openxlsx::int2col(cols), rows)
  if (grepl("<dimension\\b[^>]*/>", xml)) {
    xml <- sub("<dimension\\b[^>]*/>", dimension, xml)
  } else {
    xml <- sub("(<worksheet[^>]*>)", paste0("\\1", dimension), xml)
  }
  writeBin(charToRaw(xml), sheet_path)
  removed_parts <- character()
  relationship_files <- list.files(expanded, pattern = "\\.rels$", recursive = TRUE,
                                    full.names = TRUE, all.files = TRUE)
  for (rel_path in relationship_files) {
    document <- xml2::read_xml(rel_path)
    base <- dirname(dirname(rel_path))
    changed <- FALSE
    for (rel in xml2::xml_find_all(document, '//*[local-name()="Relationship"]')) {
      if (identical(xml2::xml_attr(rel, "TargetMode"), "External")) next
      target <- xml2::xml_attr(rel, "Target")
      target_path <- if (startsWith(target, "/")) file.path(expanded, substring(target, 2)) else file.path(base, target)
      if (file.exists(target_path)) next
      kind <- sub(".*/", "", xml2::xml_attr(rel, "Type"))
      if (!kind %in% c("drawing", "vmlDrawing")) stop("XLSX has a missing part: ", target)
      removed_parts <- c(removed_parts, basename(target))
      owner <- file.path(base, sub("\\.rels$", "", basename(rel_path)))
      if (file.exists(owner)) {
        sheet_doc <- xml2::read_xml(owner)
        expression <- sprintf('//*[local-name()="drawing" or local-name()="legacyDrawing" or local-name()="legacyDrawingHF"][@*[local-name()="id"]="%s"]', xml2::xml_attr(rel, "Id"))
        dangling <- xml2::xml_find_all(sheet_doc, expression)
        if (length(dangling)) {
          xml2::xml_remove(dangling)
          xml2::write_xml(sheet_doc, owner)
        }
      }
      xml2::xml_remove(rel)
      changed <- TRUE
    }
    if (changed) xml2::write_xml(document, rel_path)
  }
  types_path <- file.path(expanded, "[Content_Types].xml")
  types <- xml2::read_xml(types_path)
  changed <- FALSE
  for (part in xml2::xml_find_all(types, '//*[local-name()="Override"]')) {
    name <- xml2::xml_attr(part, "PartName")
    if (file.exists(file.path(expanded, sub("^/", "", name)))) next
    if (!basename(name) %in% removed_parts) stop("XLSX declares a missing part: ", name)
    xml2::xml_remove(part)
    changed <- TRUE
  }
  if (changed) xml2::write_xml(types, types_path)
  repacked <- tempfile("vinyl-repacked-", fileext = ".xlsx")
  on.exit(unlink(repacked), add = TRUE)
  zip::zipr(repacked, files = list.files(expanded, recursive = TRUE, all.files = TRUE),
            root = expanded, include_directories = FALSE, mode = "mirror")
  if (!file.copy(repacked, path, overwrite = TRUE)) stop("Could not finalize XLSX package")
}
#' Write and verify a generated workbook
#' @param data Data frame to export.
#' @param path Destination XLSX path.
#' @param sheet_name Worksheet name.
#' @param table_name Excel table name.
#' @param template Optional input workbook used for theme preservation.
#' @return `path`, invisibly.
#' @noRd
write_table <- function(data, path, sheet_name, table_name, template = NULL) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  wb <- openxlsx::createWorkbook()
  openxlsx::modifyBaseFont(wb, fontName = "Arial", fontSize = 11, fontColour = "#000000")
  openxlsx::addWorksheet(wb, sheet_name, gridLines = FALSE)
  openxlsx::writeDataTable(wb, sheet_name, data, tableStyle = "TableStyleMedium2",
                           withFilter = TRUE, tableName = table_name, keepNA = FALSE)
  openxlsx::freezePane(wb, sheet_name, firstRow = TRUE)
  # Match the input's compact layout; notes must not stretch the whole table.
  widths <- c(Artist = 36, Album = 52, Year = 10, Edition = 40,
              DateAddition = 17, Recording_Type = 20, Metadata_Subgenre = 25,
              MusicBrainz_URL = 55, Metadata_Retrieved = 22, Review_Status = 22,
              Shelf_Band = 36, Shelf_Group = 36, Shelf_Genre = 27, Shelf_Mood = 19,
              Shelf_Group_Genre = 27, Shelf_Group_Mood = 19,
              Shelf_Genre_Source = 24, Shelf_Mood_Source = 24,
              Suggested_Shelf_Genre = 27, Suggested_Shelf_Mood = 19,
              Shelf_Order = 15, Collection_Row = 18, Rotation_Order = 19,
              Rotation_Reason = 32, Rotation_Count = 18,
              Last_Rotation_Run = 21, Last_Rotation_Date = 22)
  widths <- widths[names(data)]
  widths[is.na(widths)] <- 22
  openxlsx::setColWidths(wb, sheet_name, cols = seq_len(ncol(data)), widths = widths)
  openxlsx::setRowHeights(wb, sheet_name, rows = 1, heights = 30)
  openxlsx::addStyle(wb, sheet_name, openxlsx::createStyle(valign = "center"),
                     rows = seq_len(nrow(data) + 1L), cols = seq_len(ncol(data)),
                     gridExpand = TRUE, stack = TRUE)
  openxlsx::addStyle(wb, sheet_name,
                     openxlsx::createStyle(fontColour = "#FFFFFF", fgFill = "#4F81BD", textDecoration = "bold", valign = "center", wrapText = TRUE),
                     rows = 1, cols = seq_len(ncol(data)), gridExpand = TRUE, stack = TRUE)
  if (nrow(data)) {
    rows <- seq_len(nrow(data)) + 1L
    text_cols <- which(vapply(data, is.character, logical(1)))
    openxlsx::setRowHeights(wb, sheet_name, rows = rows, heights = 32)
    openxlsx::addStyle(wb, sheet_name, openxlsx::createStyle(wrapText = TRUE, valign = "center"),
                       rows = rows, cols = text_cols, gridExpand = TRUE, stack = TRUE)
    date_cols <- which(vapply(data, inherits, logical(1), "Date"))
    if (length(date_cols)) openxlsx::addStyle(wb, sheet_name, openxlsx::createStyle(numFmt = "yyyy-mm-dd"),
                                              rows = rows, cols = date_cols, gridExpand = TRUE, stack = TRUE)
    numeric_cols <- which(vapply(data, is.numeric, logical(1)))
    if (length(numeric_cols)) openxlsx::addStyle(wb, sheet_name, openxlsx::createStyle(numFmt = "0"),
                                                 rows = rows, cols = numeric_cols, gridExpand = TRUE, stack = TRUE)
  }
  tmp <- tempfile(".vinyl-", tmpdir = dirname(path), fileext = ".xlsx")
  on.exit(unlink(tmp), add = TRUE)
  openxlsx::saveWorkbook(wb, tmp, overwrite = TRUE)
  finalize_xlsx_package(tmp, nrow(data) + 1L, ncol(data), template)
  check <- readxl::read_excel(tmp)
  stopifnot(nrow(check) == nrow(data), identical(names(check), names(data)))
  # Validate every data value, allowing the normal Excel date round trip.
  for (field in names(data)) {
    expected <- data[[field]]
    actual <- check[[field]]
    if (inherits(expected, "Date")) actual <- as.Date(actual)
    e <- as.character(expected); a <- as.character(actual)
    e[is_missing(e)] <- ""; a[is_missing(a)] <- ""
    if (!identical(e, a)) stop("XLSX verification failed for ", field)
  }
  install_file(tmp, path)
  invisible(path)
}

shelf_genres <- sort(c("Electronic", "Rock", "Pop", "Jazz / Blues", "Classical / Soundtrack"), method = "radix")
shelf_moods <- sort(c("Intimate", "Reflective", "Melancholic", "Warm", "Groovy",
                "Intense", "Immersive"), method = "radix")
#' Build artist matching and sorting keys
#' @param x Artist names.
#' @return Normalized names with a leading English "The" or Spanish definite
#'   article ("El", "La", "Los", "Las") removed for matching, grouping,
#'   counting and ordering.
#' @noRd
artist_key <- function(x) sub("^(the|el|la|los|las) ", "", normalize(x))
# Editable Artists!Shelf_Band values override these known associations.
originating_bands <- c(
  "Robe" = "Extremoduro", "Nick Mason" = "Pink Floyd",
  "Roger Waters" = "Pink Floyd", "David Gilmour" = "Pink Floyd",
  "Richard Wright" = "Pink Floyd", "Rick Wright" = "Pink Floyd",
  "Syd Barrett" = "Pink Floyd", "Paul Mccartney" = "The Beatles",
  "John Lennon" = "The Beatles", "George Harrison" = "The Beatles",
  "Ringo Starr" = "The Beatles",
  "Janis Joplin" = "Big Brother And The Holding Company",
  "Lou Reed" = "The Velvet Underground & Nico"
)
#' Find known originating bands
#' @param artist Artist names.
#' @return Matched band names or `NA`.
#' @noRd
default_shelf_band <- function(artist) {
  unname(originating_bands[match(artist_key(artist), artist_key(names(originating_bands)))])
}

#' Read an optional data-frame field
#' @param data A data frame.
#' @param name Column name.
#' @return The column, or an `NA_character_` vector with one value per row.
#' @noRd
optional <- function(data, name) {
  if (name %in% names(data)) data[[name]] else rep(NA_character_, nrow(data))
}
#' Parse supported spreadsheet dates
#'
#' Accepts R dates, Excel serial dates, `YYYYMMDD`, ISO dates and ISO date-time
#' strings. ISO date-times retain their stated calendar date without timezone
#' conversion.
#' @param x Values to parse.
#' @param name Field name used in validation errors.
#' @return A `Date` vector.
#' @noRd
dates <- function(x, name) {
  if (inherits(x, "Date") || inherits(x, "POSIXt")) return(as.Date(x))
  result <- as.Date(rep(NA_character_, length(x)))
  for (i in which(!is_missing(x))) {
    value <- trimws(as.character(x[[i]]))
    if (grepl("^[0-9]{8}$", value)) {
      result[[i]] <- as.Date(value, format = "%Y%m%d")
    } else if (grepl("^[0-9]+(\\.[0-9]+)?$", value) && as.numeric(value) <= 100000) {
      result[[i]] <- as.Date(as.numeric(value), origin = "1899-12-30")
    } else if (grepl(
      "^[0-9]{4}-[0-9]{2}-[0-9]{2}([T ][0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?(Z|[+-][0-9]{2}:?[0-9]{2})?)?$",
      value
    )) {
      # Some XLSX readers serialize date cells as ISO-8601 timestamps. Keep
      # the workbook's calendar date rather than shifting it across time zones.
      result[[i]] <- as.Date(substr(value, 1, 10), format = "%Y-%m-%d")
    }
    if (is.na(result[[i]])) stop("Invalid ", name, " date: ", value)
  }
  result
}
#' Verify required XLSX package relationships
#' @param path Workbook path.
#' @return `TRUE`, invisibly; stops for a malformed package or broken link.
#' @noRd
verify_package <- function(path) {
  directory <- tempfile("vinyl-input-check-")
  dir.create(directory)
  on.exit(unlink(directory, recursive=TRUE), add=TRUE)
  utils::unzip(path, exdir=directory)
  if (!file.exists(file.path(directory, "[Content_Types].xml"))) stop("Invalid Excel package: ", path)
  for (file in list.files(directory, pattern="\\.rels$", recursive=TRUE, full.names=TRUE, all.files=TRUE)) {
    document <- xml2::read_xml(file)
    for (rel in xml2::xml_find_all(document, '//*[local-name()="Relationship"]')) {
      if (identical(xml2::xml_attr(rel,"TargetMode"), "External")) next
      target <- xml2::xml_attr(rel,"Target")
      resolved <- if (startsWith(target,"/")) file.path(directory,substring(target,2)) else file.path(dirname(dirname(file)),target)
      if (!file.exists(resolved)) stop("Workbook contains a broken reference: ", target, ". Restore a recovery copy.")
    }
  }
  invisible(TRUE)
}

# MusicBrainz public API: https://musicbrainz.org/doc/MusicBrainz_API

#' Create a rate-limited MusicBrainz client
#'
#' Requests are cached for the current update and spaced by at least 1.1
#' seconds. `VINYL_OFFLINE=true` disables all requests.
#' @return A function accepting an API entity and query-parameter list. The
#'   returned function yields decoded JSON or `NULL` when unavailable.
#' @noRd
musicbrainz_client <- function() {
  cache <- new.env(parent = emptyenv())
  last_request <- -Inf
  function(entity, parameters = list()) {
    if (tolower(Sys.getenv("VINYL_OFFLINE", "false")) %in% c("true", "1", "yes")) return(NULL)
    if (!requireNamespace("httr2", quietly = TRUE)) {
      if (!exists("missing_package", cache, inherits = FALSE)) {
        warning("Install/restore httr2 for missing-detail lookups; unresolved fields remain blank.")
        assign("missing_package", TRUE, cache)
      }
      return(NULL)
    }
    key <- paste(entity, paste(names(parameters), unlist(parameters), collapse = "|"))
    if (exists(key, cache, inherits = FALSE)) return(get(key, cache))
    Sys.sleep(max(0, 1.1 - (as.numeric(Sys.time()) - last_request)))
    last_request <<- as.numeric(Sys.time())
    result <- tryCatch({
      request <- httr2::request(paste0("https://musicbrainz.org/ws/2/", entity)) |>
        httr2::req_user_agent(Sys.getenv("VINYL_USER_AGENT", "VinylDatabase/1.0 (personal collection manager)")) |>
        httr2::req_timeout(20)
      request <- do.call(httr2::req_url_query, c(list(request), parameters, list(fmt = "json")))
      httr2::resp_body_json(httr2::req_perform(request))
    }, error = function(e) {
      warning("MusicBrainz lookup unavailable; missing details remain for review.")
      NULL
    })
    assign(key, result, cache)
    result
  }
}
#' Extract a scalar MusicBrainz value
#' @param value A possibly null or empty API value.
#' @param default Value returned when no scalar is present.
#' @return A length-one character value.
#' @noRd
mb_scalar <- function(value, default = NA_character_) {
  if (is.null(value) || !length(value) || is_missing(value[[1]])) default else as.character(value[[1]])
}
#' Order MusicBrainz tags by usage count
#' @param entity A decoded MusicBrainz entity.
#' @return A unique character vector of tag names.
#' @noRd
mb_tags <- function(entity) {
  entries <- c(entity$genres, entity$tags)
  if (!length(entries)) return(character())
  counts <- vapply(entries, function(x) suppressWarnings(as.numeric(mb_scalar(x$count, "1"))), numeric(1))
  counts[is.na(counts)] <- 0
  unique(vapply(entries[order(-counts)], function(x) mb_scalar(x$name, ""), character(1)))
}
#' Escape text for a Lucene phrase
#' @param value Text inserted into a MusicBrainz search query.
#' @return Escaped character text.
#' @noRd
lucene_phrase <- function(value) {
  value <- gsub("\\\\", "\\\\\\\\", as.character(value))
  gsub('"', '\\\\"', value, fixed = TRUE)
}
#' Reconstruct a release-group artist credit
#' @param group A decoded MusicBrainz release group.
#' @return The joined artist credit as character text.
#' @noRd
release_group_credit <- function(group) {
  credit <- group[["artist-credit"]]
  if (!length(credit)) return("")
  paste0(vapply(credit, function(x)
    paste0(mb_scalar(x$name, mb_scalar(x$artist$name, "")), mb_scalar(x$joinphrase, "")),
    character(1)), collapse = "")
}
#' Select an exact MusicBrainz album group
#' @param groups Candidate release groups.
#' @param artist,album Expected artist credit and album title.
#' @return The preferred exact release group, or `NULL`.
#' @noRd
select_album_group <- function(groups, artist, album) {
  matches <- Filter(function(group) {
    identical(normalize(mb_scalar(group$title)), normalize(album)) &&
      identical(artist_key(release_group_credit(group)), artist_key(artist))
  }, groups)
  if (!length(matches)) return(NULL)
  albums <- Filter(function(group) identical(mb_scalar(group[["primary-type"]]), "Album"), matches)
  if (length(albums)) matches <- albums
  # MusicBrainz can contain duplicate exact release groups. Prefer the oldest
  # dated album, then the best search score, with the MBID as a stable tie-break.
  date <- vapply(matches, function(group) {
    value <- substr(mb_scalar(group[["first-release-date"]], ""), 1L, 10L)
    if (grepl("^[0-9]{4}(-[0-9]{2}(-[0-9]{2})?)?$", value)) value else "9999"
  }, character(1))
  score <- vapply(matches, function(group)
    suppressWarnings(as.numeric(mb_scalar(group$score, "0"))), numeric(1))
  score[is.na(score)] <- 0
  id <- vapply(matches, function(group) mb_scalar(group$id, ""), character(1))
  matches[[order(date, -score, id)[[1]]]]
}
#' Look up generated metadata for one album
#' @param artist,album Artist and album text.
#' @param request Client returned by [musicbrainz_client()].
#' @return A metadata list, or `NULL` when no exact match exists.
#' @noRd
lookup_album <- function(artist, album, request) {
  # Preserve punctuation in Lucene phrases (for names such as Fontaines D.C.).
  # Search by artist first, then retry by exact album title and validate the
  # returned artist credit locally if MusicBrainz tokenization differs.
  title <- lucene_phrase(album)
  credit <- lucene_phrase(artist)
  query <- sprintf('releasegroup:"%s" AND artist:"%s" AND primarytype:album', title, credit)
  search <- request("release-group", list(query = query, limit = 100))
  if (is.null(search) || is.null(search[["release-groups"]])) return(NULL)
  match <- select_album_group(search[["release-groups"]], artist, album)
  if (is.null(match)) {
    search <- request("release-group", list(
      query = sprintf('releasegroup:"%s" AND primarytype:album', title), limit = 100))
    if (is.null(search) || is.null(search[["release-groups"]])) return(NULL)
    match <- select_album_group(search[["release-groups"]], artist, album)
  }
  if (is.null(match)) return(NULL)
  id <- mb_scalar(match$id)
  if (is_missing(id)) return(NULL)
  group <- request(paste0("release-group/", id), list(inc = "artist-credits+genres+tags"))
  if (is.null(group)) return(NULL)
  credit <- group[["artist-credit"]]
  artist_tags <- character()
  if (length(credit) == 1L) {
    artist_id <- mb_scalar(credit[[1]]$artist$id)
    if (!is_missing(artist_id)) artist_tags <- mb_tags(request(paste0("artist/", artist_id), list(inc = "genres+tags")))
  }
  secondary <- unlist(group[["secondary-types"]])
  kind <- if ("Compilation" %in% secondary) "Compilation" else if ("Live" %in% secondary) "Live" else
    if (identical(group[["primary-type"]], "Album")) "Studio" else NA_character_
  year <- substr(mb_scalar(group[["first-release-date"]], ""), 1, 4)
  if (!grepl("^[0-9]{4}$", year)) year <- NA_character_
  list(Year = year, Recording_Type = kind, tags = mb_tags(group), artist_tags = artist_tags,
       MusicBrainz_URL = paste0("https://musicbrainz.org/release-group/", id))
}
#' Suggest artist shelf classifications
#' @param tags MusicBrainz genre and tag names.
#' @param genre Existing genre, or `NA` when a genre suggestion is needed.
#' @return A list containing `Shelf_Genre` and `Shelf_Mood` suggestions.
#' @noRd
suggest_artist <- function(tags, genre = NA_character_) {
  tags <- normalize(tags)
  broad <- function(tag) {
    if (grepl("classical|soundtrack|orchestral|opera", tag)) return("Classical / Soundtrack")
    if (grepl("jazz|blues|soul|flamenco", tag)) return("Jazz / Blues")
    if (grepl("pop", tag)) return("Pop")
    if (grepl("electronic|techno|house|trance|ambient", tag)) return("Electronic")
    if (grepl("rock|metal|punk|folk|country|reggae|funk", tag)) return("Rock")
    NA_character_
  }
  if (is_missing(genre)) {
    candidates <- vapply(tags, broad, character(1))
    candidates <- candidates[!is_missing(candidates)]
    if (length(candidates)) genre <- candidates[[1]]
  }
  text <- paste(tags, collapse = " ")
  # Suggestions describe a listening character, not an audio-derived measurement.
  # Use specific tags; Pop alone is not evidence of a groove or an emotion.
  mood <- if (grepl("melanchol|sadcore", text)) "Melancholic" else
    if (grepl("ambient|psychedelic|dream pop|shoegaze|progressive rock|symphonic rock|post rock", text)) "Immersive" else
    if (grepl("metal|punk|grunge|hard rock", text)) "Intense" else
    if (grepl("funk|disco|dance|ska", text)) "Groovy" else
    if (grepl("acoustic", text)) "Intimate" else
    if (grepl("folk|singer songwriter", text)) "Reflective" else
    if (grepl("soul|blues|reggae", text)) "Warm" else
    if (grepl("orchestral|opera|theatrical", text)) "Immersive" else NA_character_
  # No generic mood is assigned just because an artist belongs to a broad genre.
  list(Shelf_Genre = genre, Shelf_Mood = mood)
}
metadata_cache_fields <- c(
  "Album_Key", "Artist", "Album", "Year", "Recording_Type", "Metadata_Subgenre",
  "MusicBrainz_URL", "Metadata_Retrieved", "Suggested_Shelf_Genre", "Suggested_Shelf_Mood"
)
#' Create an empty metadata cache
#' @return A versioned cache list with an empty album table.
#' @noRd
empty_metadata_cache <- function() {
  list(version = 1L, albums = data.frame(
    Album_Key = character(), Artist = character(), Album = character(), Year = integer(),
    Recording_Type = character(), Metadata_Subgenre = character(), MusicBrainz_URL = character(),
    Metadata_Retrieved = character(), Suggested_Shelf_Genre = character(),
    Suggested_Shelf_Mood = character(), stringsAsFactors = FALSE
  ))
}
#' Return the first populated value
#' @param x Values to inspect.
#' @param numeric Whether to coerce to integer before selecting.
#' @return A scalar character or integer value, or the matching typed `NA`.
#' @noRd
first_present <- function(x, numeric = FALSE) {
  if (numeric) {
    x <- suppressWarnings(as.integer(x))
    x <- x[!is.na(x)]
    return(if (length(x)) x[[1]] else NA_integer_)
  }
  x <- as.character(x)
  x <- x[!is_missing(x)]
  if (length(x)) x[[1]] else NA_character_
}
#' Convert generated metadata into cache rows
#' @param data A data frame containing at least `Artist` and `Album`.
#' @return A versioned metadata-cache list with one row per album key.
#' @noRd
metadata_cache_from_data <- function(data) {
  require_columns(data, c("Artist", "Album"), "Completed metadata")
  raw <- data.frame(
    Album_Key = key_for(data$Artist, data$Album), Artist = as.character(data$Artist),
    Album = as.character(data$Album), Year = suppressWarnings(as.integer(optional(data, "Year"))),
    Recording_Type = as.character(optional(data, "Recording_Type")),
    Metadata_Subgenre = as.character(optional(data, "Metadata_Subgenre")),
    MusicBrainz_URL = as.character(optional(data, "MusicBrainz_URL")),
    Metadata_Retrieved = as.character(optional(data, "Metadata_Retrieved")),
    Suggested_Shelf_Genre = as.character(optional(data, "Suggested_Shelf_Genre")),
    Suggested_Shelf_Mood = as.character(optional(data, "Suggested_Shelf_Mood")),
    stringsAsFactors = FALSE
  )
  rows <- lapply(unique(raw$Album_Key), function(key) {
    x <- raw[raw$Album_Key == key, , drop = FALSE]
    data.frame(
      Album_Key = key, Artist = first_present(x$Artist), Album = first_present(x$Album),
      Year = first_present(x$Year, numeric = TRUE),
      Recording_Type = first_present(x$Recording_Type),
      Metadata_Subgenre = first_present(x$Metadata_Subgenre),
      MusicBrainz_URL = first_present(x$MusicBrainz_URL),
      Metadata_Retrieved = first_present(x$Metadata_Retrieved),
      Suggested_Shelf_Genre = first_present(x$Suggested_Shelf_Genre),
      Suggested_Shelf_Mood = first_present(x$Suggested_Shelf_Mood),
      stringsAsFactors = FALSE
    )
  })
  list(version = 1L, albums = if (length(rows)) do.call(rbind, rows) else empty_metadata_cache()$albums)
}
#' Read or initialize the metadata cache
#' @param path Metadata-cache RDS path.
#' @return A validated versioned cache list.
#' @noRd
read_metadata_cache <- function(path) {
  cache <- if (file.exists(path)) readRDS(path) else empty_metadata_cache()
  if (!is.list(cache) || !identical(cache$version, 1L) || !is.data.frame(cache$albums))
    stop("Invalid metadata cache: ", path)
  require_columns(cache$albums, metadata_cache_fields, "Metadata cache")
  if (nrow(cache$albums)) unique_keys(cache$albums, "Album_Key", "Metadata cache")
  cache$albums <- cache$albums[metadata_cache_fields]
  cache
}
#' Fill missing generated fields from cache
#' @param records Collection records.
#' @param cache A validated metadata cache.
#' @return `records` with available missing fields populated.
#' @noRd
apply_metadata_cache <- function(records, cache) {
  hit <- match(records$Album_Key, cache$albums$Album_Key)
  for (field in setdiff(metadata_cache_fields, c("Album_Key", "Artist", "Album"))) {
    value <- cache$albums[[field]][hit]
    empty <- if (field == "Year") is.na(records[[field]]) else is_missing(records[[field]])
    records[[field]][empty] <- value[empty]
  }
  records
}
#' Merge completed records into the metadata cache
#' @param cache Existing validated metadata cache.
#' @param records Completed collection records.
#' @return The updated cache, retaining albums absent from the current input.
#' @noRd
update_metadata_cache <- function(cache, records) {
  fresh <- metadata_cache_from_data(records)$albums
  old <- cache$albums[!cache$albums$Album_Key %in% fresh$Album_Key, , drop = FALSE]
  cache$albums <- rbind(old, fresh)
  rownames(cache$albums) <- NULL
  cache
}

#' Complete collection records
#'
#' Applies Artists classifications, cached metadata and optional exact
#' MusicBrainz lookups. Manual input is never modified.
#' @param records Validated Collection rows.
#' @param artists Validated Artists rows with `Artist_Key`.
#' @param cache A validated metadata cache.
#' @param online Whether MusicBrainz requests may be made.
#' @return A list with completed `records` and the updated `cache`.
#' @noRd
complete_records <- function(records, artists, cache, online = TRUE) {
  character_fields <- c(
    "Recording_Type", "Metadata_Subgenre", "MusicBrainz_URL", "Metadata_Retrieved",
    "Suggested_Shelf_Genre", "Suggested_Shelf_Mood", "Shelf_Genre", "Shelf_Mood", "Shelf_Band",
    "Shelf_Genre_Source", "Shelf_Mood_Source", "Review_Status"
  )
  for (field in character_fields) records[[field]] <- as.character(optional(records, field))
  records$Year <- suppressWarnings(as.integer(optional(records, "Year")))
  records <- apply_metadata_cache(records, cache)
  keys <- artist_key(records$Artist)
  request <- if (online) musicbrainz_client() else NULL
  lookups <- new.env(parent = emptyenv())
  for (key in unique(keys)) {
    idx <- which(keys == key)
    hit <- match(key, artists$Artist_Key)
    known <- !is.na(hit)
    if (known) records$Artist[idx] <- artists$Artist[[hit]]

    artist_genre <- if (known) optional(artists, "Shelf_Genre")[[hit]] else NA_character_
    shelf_genre <- if (!is_missing(artist_genre)) as.character(artist_genre) else NA_character_
    genre_source <- if (!is_missing(artist_genre)) "Artists" else NA_character_
    shelf_mood <- if (known) as.character(optional(artists, "Shelf_Mood")[[hit]]) else NA_character_
    mood_source <- if (!is_missing(shelf_mood)) "Artists" else NA_character_
    shelf_band <- if (known) as.character(optional(artists, "Shelf_Band")[[hit]]) else NA_character_
    if (is_missing(shelf_band)) shelf_band <- default_shelf_band(records$Artist[idx[[1]]])
    records$Shelf_Band[idx] <- shelf_band

    tags <- character()
    cached_genre <- unique(records$Suggested_Shelf_Genre[idx][!is_missing(records$Suggested_Shelf_Genre[idx])])
    cached_mood <- unique(records$Suggested_Shelf_Mood[idx][!is_missing(records$Suggested_Shelf_Mood[idx])])
    if (is_missing(shelf_genre) && length(cached_genre)) {
      shelf_genre <- sort(cached_genre, method = "radix")[[1]]
      genre_source <- "MusicBrainz suggestion"
    }
    if (is_missing(shelf_mood) && length(cached_mood)) {
      shelf_mood <- sort(cached_mood, method = "radix")[[1]]
      mood_source <- "MusicBrainz suggestion"
    }

    for (i in idx[order(normalize(records$Album[idx]))]) {
      need_album <- is.na(records$Year[[i]]) || is_missing(records$Recording_Type[[i]]) ||
        is_missing(records$Metadata_Subgenre[[i]])
      need_artist <- is_missing(shelf_genre) || is_missing(shelf_mood)
      if (!online || (!need_album && !need_artist)) next
      album_key <- records$Album_Key[[i]]
      if (!exists(album_key, lookups, inherits = FALSE))
        assign(album_key, lookup_album(records$Artist[[i]], records$Album[[i]], request), lookups)
      result <- get(album_key, lookups)
      if (is.null(result)) next
      tags <- unique(c(tags, result$artist_tags, result$tags))
      if (is.na(records$Year[[i]]) && !is_missing(result$Year))
        records$Year[[i]] <- suppressWarnings(as.integer(result$Year))
      if (is_missing(records$Recording_Type[[i]]) && !is_missing(result$Recording_Type))
        records$Recording_Type[[i]] <- result$Recording_Type
      if (is_missing(records$Metadata_Subgenre[[i]]) && length(result$tags))
        records$Metadata_Subgenre[[i]] <- tools::toTitleCase(result$tags[[1]])
      records$MusicBrainz_URL[[i]] <- result$MusicBrainz_URL
      records$Metadata_Retrieved[[i]] <- as.character(Sys.Date())
    }
    suggestion <- suggest_artist(tags, shelf_genre)
    if (is_missing(shelf_genre) && !is_missing(suggestion$Shelf_Genre)) {
      shelf_genre <- suggestion$Shelf_Genre
      genre_source <- "MusicBrainz suggestion"
    }
    if (is_missing(shelf_mood) && !is_missing(suggestion$Shelf_Mood)) {
      shelf_mood <- suggestion$Shelf_Mood
      mood_source <- "MusicBrainz suggestion"
    }
    records$Shelf_Genre[idx] <- shelf_genre
    records$Shelf_Mood[idx] <- shelf_mood
    records$Shelf_Genre_Source[idx] <- genre_source
    records$Shelf_Mood_Source[idx] <- mood_source
    if (identical(genre_source, "MusicBrainz suggestion"))
      records$Suggested_Shelf_Genre[idx] <- shelf_genre
    if (identical(mood_source, "MusicBrainz suggestion"))
      records$Suggested_Shelf_Mood[idx] <- shelf_mood
  }
  bad_type <- !is_missing(records$Recording_Type) &
    !records$Recording_Type %in% c("Studio", "Live", "Mixed", "Compilation", "Unknown")
  if (any(bad_type)) stop("Recording_Type must be Studio, Live, Mixed, Compilation or Unknown.")
  bad_year <- !is.na(records$Year) & (records$Year < 1000L | records$Year > 9999L)
  if (any(bad_year)) stop("Generated Year must contain four digits or be blank.")
  incomplete <- is_missing(records$Shelf_Genre) | is_missing(records$Shelf_Mood) |
    is.na(records$Year) | is_missing(records$Metadata_Subgenre) |
    is_missing(records$Recording_Type)
  suggested <- records$Shelf_Genre_Source == "MusicBrainz suggestion" |
    records$Shelf_Mood_Source == "MusicBrainz suggestion"
  suggested[is.na(suggested)] <- FALSE
  records$Review_Status <- ifelse(incomplete | suggested, "Needs review", "Complete")
  records$Album_Key <- key_for(records$Artist, records$Album)
  list(records = records, cache = update_metadata_cache(cache, records))
}

#' Read, validate and enrich the vinyl database
#'
#' The Collection worksheet is read-only manual input. Artists is the only
#' manual source for shelf genre, mood and band-family settings.
#' @param path Input XLSX path.
#' @param cache_path Optional generated metadata-cache RDS path.
#' @param online Whether missing metadata may be requested from MusicBrainz.
#' @return A list containing completed `records` and the updated `cache`.
#' @noRd
read_database <- function(path, cache_path = NULL, online = TRUE) {
  verify_package(path)
  sheets <- readxl::excel_sheets(path)
  if (!all(c("Collection", "Artists") %in% sheets))
    stop("Database.xlsx needs Collection and Artists worksheets.")
  records <- as.data.frame(readxl::read_excel(path, sheet = "Collection", col_types = "text"))
  artists <- as.data.frame(readxl::read_excel(path, sheet = "Artists", col_types = "text"))
  collection_columns <- c("DateAddition", "Artist", "Album", "Edition")
  artist_columns <- c("Artist", "Shelf_Band", "Shelf_Genre", "Shelf_Mood")
  if (!identical(names(records), collection_columns))
    stop("Collection columns must be, in order: ", paste(collection_columns, collapse = ", "), ".")
  if (!identical(names(artists), artist_columns))
    stop("Artists columns must be, in order: ", paste(artist_columns, collapse = ", "), ".")
  if (!nrow(records)) stop("Collection is empty.")
  core_fields <- collection_columns[1:3]
  missing_core <- lapply(core_fields, function(field) which(is_missing(records[[field]])) + 1L)
  names(missing_core) <- core_fields
  missing_core <- missing_core[lengths(missing_core) > 0L]
  if (length(missing_core)) {
    details <- vapply(names(missing_core), function(field)
      paste0(field, " row(s) ", paste(missing_core[[field]], collapse = ", ")), character(1))
    stop("Collection requires DateAddition, Artist and Album for every record. Missing: ",
         paste(details, collapse = "; "), ".")
  }
  artists <- artists[!is_missing(artists$Artist), , drop = FALSE]
  artists$Artist_Key <- artist_key(artists$Artist)
  unique_keys(artists, "Artist_Key", "Artists worksheet")
  for (field in c("Shelf_Genre", "Shelf_Mood")) {
    allowed <- if (field == "Shelf_Genre") shelf_genres else shelf_moods
    if (any(!is_missing(artists[[field]]) & !artists[[field]] %in% allowed))
      stop("Invalid Artists ", field, ". Use: ", paste(allowed, collapse = ", "))
  }
  addition_dates <- dates(records$DateAddition, "DateAddition")
  records$DateAddition <- addition_dates
  records$Album_Key <- key_for(records$Artist, records$Album)
  cache <- if (is.null(cache_path)) empty_metadata_cache() else
    read_metadata_cache(cache_path)
  completed <- complete_records(records, artists, cache, online = online)
  records <- completed$records
  for (field in c("Shelf_Genre", "Shelf_Mood")) {
    allowed <- if (field == "Shelf_Genre") shelf_genres else shelf_moods
    if (any(!is_missing(records[[field]]) & !records[[field]] %in% allowed))
      stop("Invalid ", field, ". Use: ", paste(allowed, collapse = ", "))
  }
  counts <- table(records$Shelf_Mood[!duplicated(records$Album_Key)])
  narrow <- counts[counts < 6]
  if (length(narrow)) stop("Each Shelf_Mood needs at least six distinct albums. Reassign artists for: ",
                           paste(paste0(names(narrow), " (", narrow, ")"), collapse = ", "))
  list(records = records, cache = completed$cache)
}
#' Resolve permanent-shelf artist families
#'
#' Family grouping changes shelf placement only; it does not overwrite each
#' artist's own classification used in collection and rotation views.
#' @param records Completed collection records.
#' @return A data frame with family group, family genre and family mood.
#' @noRd
shelf_placement <- function(records) {
  keys <- artist_key(records$Artist)
  first <- which(!duplicated(keys))
  artists <- records[first, , drop = FALSE]
  parent <- match(artist_key(optional(artists, "Shelf_Band")), keys[first])
  roots <- seq_along(first)
  for (i in roots) {
    current <- i
    visited <- integer()
    while (!is.na(parent[[current]]) && parent[[current]] != current) {
      if (current %in% visited)
        stop("Circular Shelf_Band association involving ", artists$Artist[[i]], ".")
      visited <- c(visited, current)
      current <- parent[[current]]
    }
    roots[[i]] <- current
  }
  # One vote per artist, independent of album or pressing counts.
  majority <- function(values, preferred) {
    values <- values[!is_missing(values)]
    if (!length(values)) return(NA_character_)
    counts <- table(values)
    tied <- names(counts)[counts == max(counts)]
    if (!is_missing(preferred) && preferred %in% tied) return(preferred)
    sort(tied, method = "radix")[[1]]
  }
  family_genre <- family_mood <- rep(NA_character_, nrow(artists))
  for (family in unique(roots)) {
    members <- which(roots == family)
    family_genre[[family]] <- majority(artists$Shelf_Genre[members], artists$Shelf_Genre[[family]])
    family_mood[[family]] <- majority(artists$Shelf_Mood[members], artists$Shelf_Mood[[family]])
  }
  root <- roots[match(keys, keys[first])]
  data.frame(Group = artists$Artist[root], Shelf_Genre = family_genre[root],
             Shelf_Mood = family_mood[root], Is_Member = keys != keys[first][root],
             stringsAsFactors = FALSE)
}
#' Order records for the permanent shelf
#' @param records Completed records containing resolved shelf-group fields.
#' @return Integer row indices in permanent-shelf order.
#' @noRd
permanent_order <- function(records) {
  shelf <- shelf_placement(records)
  order(is_missing(shelf$Shelf_Genre) | is_missing(shelf$Shelf_Mood),
        normalize(shelf$Shelf_Genre), normalize(shelf$Shelf_Mood), artist_key(shelf$Group),
        shelf$Is_Member, artist_key(records$Artist),
        records$Year, normalize(records$Album), normalize(records$Edition),
        na.last = TRUE, method = "radix")
}
# Maximize coverage of qualifying moods within fixed date quotas.
# Pool rare moods together so a singleton never earns its own coverage bonus.
#' Allocate rotation slots across moods and date groups
#' @param pool Eligible records for one shelf genre.
#' @param date_group Integer date-group membership for each pool row.
#' @param quotas Required selections per date group.
#' @param priority_moods Moods eligible for coverage prioritization.
#' @return Integer row indices selected from `pool`.
#' @noRd
rotation_mood_sample <- function(pool, date_group, quotas, priority_moods) {
  mood_group <- ifelse(pool$Shelf_Mood %in% priority_moods, pool$Shelf_Mood, "Other unprioritized moods")
  labels <- sort(unique(mood_group), method = "radix")
  buckets <- lapply(labels, function(mood)
    lapply(seq_along(quotas), function(group) which(mood_group == mood & date_group == group)))
  memo <- new.env(parent = emptyenv())
  allocations <- function(capacity, remaining) {
    choices <- list(integer())
    for (j in seq_along(remaining)) {
      next_choices <- list()
      for (prefix in choices) for (n in 0:min(capacity[[j]], remaining[[j]]))
        next_choices[[length(next_choices) + 1L]] <- c(prefix, n)
      choices <- next_choices
    }
    choices
  }
  # Memoized search: remaining holds unfilled slots in each date group.
  # Keep every best allocation, then randomly choose one during reconstruction.
  solve <- function(i, remaining) {
    if (i > length(labels)) return(list(score = if (all(remaining == 0L)) 0 else -Inf))
    key <- paste(c(i, remaining), collapse = ":")
    if (exists(key, memo, inherits = FALSE)) return(get(key, memo))
    best <- -Inf; options <- list()
    for (counts in allocations(lengths(buckets[[i]]), remaining)) {
      score <- as.integer(sum(counts) > 0L && labels[[i]] != "Other unprioritized moods") + solve(i + 1L, remaining - counts)$score
      if (!is.finite(score)) next
      if (score > best) { best <- score; options <- list() }
      if (score == best) options[[length(options) + 1L]] <- counts
    }
    result <- list(score = best, options = options)
    assign(key, result, memo)
    result
  }
  selected <- integer(); remaining <- quotas
  if (!is.finite(solve(1L, remaining)$score)) stop("Cannot satisfy rotation quotas.")
  for (i in seq_along(labels)) {
    options <- solve(i, remaining)$options
    counts <- options[[sample.int(length(options), 1L)]]
    for (j in seq_along(counts)) if (counts[[j]] > 0L) {
      candidates <- buckets[[i]][[j]]
      selected <- c(selected, candidates[sample.int(length(candidates), counts[[j]])])
    }
    remaining <- remaining - counts
  }
  selected[sample.int(length(selected))]
}
#' Validate enabled rotation genres
#' @param rotation_genres Character vector of enabled shelf genres.
#' @return The validated genres in deterministic order.
#' @noRd
validate_rotation_genres <- function(rotation_genres) {
  if (!is.character(rotation_genres) || !length(rotation_genres) ||
      anyNA(rotation_genres) || anyDuplicated(rotation_genres) ||
      any(!rotation_genres %in% shelf_genres))
    stop("Choose distinct rotation genres from: ", paste(shelf_genres, collapse = ", "))
  sort(rotation_genres, method = "radix")
}
#' Draw a new listening rotation
#'
#' Selects five distinct albums per enabled genre using recency quotas, previous
#' rotation cooldown and eligible mood coverage.
#' @param records Completed collection records.
#' @param size Optional expected total; must equal five times the genre count.
#' @param history Validated rotation history.
#' @param rotation_genres Enabled shelf genres.
#' @return Selected album rows with rotation order and reason columns.
#' @noRd
select_rotation <- function(records, size = NULL, history = empty_rotation_history(),
                            rotation_genres = c("Jazz / Blues", "Rock")) {
  rotation_genres <- validate_rotation_genres(rotation_genres)
  expected_size <- 5L * length(rotation_genres)
  if (!is.null(size) && (length(size) != 1L || is.na(size) || size != expected_size))
    stop("Rotation needs ", expected_size, " albums: five per enabled genre. Omit --rotation-size or use that total.")
  records <- records[!is_missing(records$Shelf_Genre) & !is_missing(records$Shelf_Mood), , drop = FALSE]
  # Multiple pressings count once, using the album's newest addition date.
  records <- records[order(-as.numeric(records$DateAddition), artist_key(records$Artist),
                           normalize(records$Album), normalize(records$Edition), na.last = TRUE), , drop = FALSE]
  records <- records[!duplicated(records$Album_Key), , drop = FALSE]
  selected <- list()
  for (genre in rotation_genres) {
    pool <- records[records$Shelf_Genre == genre, , drop = FALSE]
    if (!nrow(pool)) { warning("No classified albums available for ", genre, "."); next }
    # Eligibility uses the full genre, before cooldown/date filtering.
    mood_counts <- table(pool$Shelf_Mood)
    priority_moods <- names(mood_counts)[mood_counts > 3L]
    target <- min(5L, nrow(pool))
    hit <- match(pool$Album_Key, history$albums$Album_Key)
    last_run <- history$albums$Last_Rotation_Run[hit]
    recent <- !is.na(last_run) & last_run == history$run
    # Priority order: cooldown, addition-date quotas, then mood coverage.
    # Only unavoidable repeats are readmitted, with lower counts preferred.
    available <- which(!recent)
    if (length(available) < target) {
      repeats <- which(recent)
      counts <- history$albums$Rotation_Count[hit[repeats]]
      repeats <- repeats[order(counts, runif(length(repeats)))]
      available <- c(available, head(repeats, target - length(available)))
    }
    pool <- pool[available, , drop = FALSE]
    dates <- sort(unique(pool$DateAddition), decreasing = TRUE)
    group <- match(pool$DateAddition, dates)
    capacity <- tabulate(group, nbins = length(dates))
    # Reserve only three recency slots across dates, not three per date.
    quotas <- integer(length(dates)); left <- min(3L, target)
    for (j in seq_along(dates)) {
      quotas[[j]] <- min(capacity[[j]], left)
      left <- left - quotas[[j]]
      if (!left) break
    }
    used_dates <- which(quotas > 0L)
    # Two random slots draw from ALL dates untouched by the recent three.
    other_dates <- setdiff(seq_along(dates), used_dates)
    random_n <- min(target - sum(quotas), sum(capacity[other_dates]))
    if (length(other_dates)) {
      random_group <- length(dates) + 1L
      group[group %in% other_dates] <- random_group
      quotas <- c(quotas, random_n)
    }
    # If untouched dates cannot fill five, relax the exclusion as a fallback.
    left <- target - sum(quotas)
    if (left > 0L) for (j in used_dates) {
      extra <- min(capacity[[j]] - quotas[[j]], left)
      quotas[[j]] <- quotas[[j]] + extra
      left <- left - extra
      if (!left) break
    }
    active <- which(quotas > 0L)
    eligible <- which(group %in% active)
    picked <- eligible[rotation_mood_sample(pool[eligible, , drop = FALSE],
                                           match(group[eligible], active), quotas[active], priority_moods)]
    result <- pool[picked, , drop = FALSE]
    result$Rotation_Reason <- paste0("Random mood coverage; added ", result$DateAddition)
    selected[[length(selected) + 1L]] <- result
    if (target < 5L) warning("Only ", target, " distinct classified albums available for ", genre, ".")
  }
  if (!length(selected)) {
    result <- records[FALSE, , drop = FALSE]
    result$Rotation_Reason <- character()
  } else result <- do.call(rbind, selected)
  result$Rotation_Order <- seq_len(nrow(result))
  rownames(result) <- NULL
  result
}
#' Create empty rotation history
#' @return A versioned history list with run zero and no album rows.
#' @noRd
empty_rotation_history <- function() {
  list(version = 2L, run = 0L, albums = data.frame(
    Album_Key = character(), Rotation_Count = integer(), Last_Rotation_Run = integer(),
    Last_Rotation_Date = as.Date(character()), stringsAsFactors = FALSE
  ))
}
#' Advance rotation history
#' @param history Validated rotation history.
#' @param keys Selected album keys.
#' @param rotation_date Date assigned to the new rotation run.
#' @return Updated history with one increment per distinct album.
#' @noRd
advance_rotation_history <- function(history, keys, rotation_date = Sys.Date()) {
  keys <- unique(keys)
  history$run <- history$run + 1L
  missing <- setdiff(keys, history$albums$Album_Key)
  if (length(missing)) history$albums <- rbind(history$albums,
    data.frame(Album_Key = missing, Rotation_Count = 0L, Last_Rotation_Run = 0L,
               Last_Rotation_Date = as.Date(NA)))
  hit <- match(keys, history$albums$Album_Key)
  history$albums$Rotation_Count[hit] <- history$albums$Rotation_Count[hit] + 1L
  history$albums$Last_Rotation_Run[hit] <- history$run
  history$albums$Last_Rotation_Date[hit] <- as.Date(rotation_date)
  history
}
#' Read and validate rotation history
#' @param path Rotation-history RDS path.
#' @return Validated history, or empty history when the file is absent.
#' @noRd
read_rotation_history <- function(path) {
  if (!file.exists(path)) return(empty_rotation_history())
  history <- readRDS(path)
  if (!is.list(history) || !identical(history$version, 2L) ||
      length(history$run) != 1L || !is.numeric(history$run) || is.na(history$run) ||
      history$run < 0 || history$run != floor(history$run) || !is.data.frame(history$albums))
    stop("Invalid rotation history: ", path)
  require_columns(history$albums, c("Album_Key", "Rotation_Count", "Last_Rotation_Run", "Last_Rotation_Date"),
                  "Rotation history")
  unique_keys(history$albums, "Album_Key", "Rotation history")
  for (field in c("Rotation_Count", "Last_Rotation_Run")) {
    x <- history$albums[[field]]
    if (!is.numeric(x) || anyNA(x) || any(x < 1 | x != floor(x) | x > history$run))
      stop("Invalid ", field, " in rotation history.")
  }
  history$albums$Last_Rotation_Date <- as.Date(history$albums$Last_Rotation_Date)
  if (any(history$albums$Last_Rotation_Date > Sys.Date(), na.rm = TRUE))
    stop("Last_Rotation_Date cannot be in the future.")
  history
}

#' Reconstruct the current rotation without drawing again
#' @param records Completed collection records.
#' @param history Validated rotation history.
#' @param output_dir Generated-workbook directory used to retain saved order.
#' @return Current rotation rows, or an empty typed data frame.
#' @noRd
current_rotation <- function(records, history, output_dir) {
  keys <- history$albums$Album_Key[history$albums$Last_Rotation_Run == history$run]
  if (!history$run || !length(keys)) {
    result <- records[FALSE, , drop = FALSE]
    result$Rotation_Reason <- character()
    result$Rotation_Order <- integer()
    return(result)
  }
  # Prefer the current filename but accept the former name during migration.
  previous <- file.path(output_dir, c("Vinyl_OnRotation.xlsx", "Vinyl_On_Rotation.xlsx"))
  previous <- previous[file.exists(previous)]
  if (length(previous)) {
    previous <- previous[[1]]
    old <- as.data.frame(readxl::read_excel(previous))
    if (all(c("Artist", "Album") %in% names(old))) {
      old_keys <- key_for(old$Artist, old$Album)
      keys <- unique(c(old_keys[old_keys %in% keys], keys[!keys %in% old_keys]))
    }
  }
  hit <- match(keys, records$Album_Key)
  result <- records[hit[!is.na(hit)], , drop = FALSE]
  result$Rotation_Reason <- paste0("Preserved from rotation run ", history$run)
  result$Rotation_Order <- seq_len(nrow(result))
  rownames(result) <- NULL
  result
}

#' Update the vinyl collection outputs
#'
#' Validates read-only manual input, enriches generated metadata, builds shelf
#' views, optionally refreshes rotation, and installs workbooks plus state as a
#' transaction. A normal update preserves the saved rotation.
#' @param input Path to `input/Database.xlsx`.
#' @param output_dir Directory for generated workbooks.
#' @param rotation_size Optional expected rotation size.
#' @param rotation_only Whether to update only rotation and metadata outputs.
#' @param reset_rotation_history Whether to discard saved rotation statistics.
#' @param refresh_rotation Whether to draw a new rotation during a full update.
#' @param rotation_genres Character vector of enabled shelf genres.
#' @return Completed collection records, invisibly.
run_update <- function(input, output_dir, rotation_size = NULL,
                       rotation_only = FALSE,
                       reset_rotation_history = FALSE,
                       refresh_rotation = FALSE,
                       rotation_genres = c("Jazz / Blues", "Rock")) {
  refresh_rotation <- isTRUE(refresh_rotation) || isTRUE(rotation_only)
  rotation_genres <- validate_rotation_genres(rotation_genres)
  message("Input database: ", normalizePath(input, mustWork = TRUE))
  message("Output folder: ", normalizePath(output_dir, mustWork = FALSE))
  history_dir <- file.path(dirname(dirname(normalizePath(input))), "state")
  dir.create(history_dir, recursive = TRUE, showWarnings = FALSE)
  lock <- file.path(history_dir, ".rotation-lock")
  if (!dir.create(lock, showWarnings = FALSE)) stop("Another rotation update is running (", lock, ").")
  on.exit(unlink(lock, recursive = TRUE), add = TRUE)
  history_path <- file.path(history_dir, "rotation_history.rds")
  cache_path <- file.path(history_dir, "metadata_cache.rds")
  history <- if (reset_rotation_history) empty_rotation_history() else read_rotation_history(history_path)
  source_hash <- unname(tools::md5sum(input))
  database <- read_database(
    input, cache_path = cache_path,
    online = !rotation_only
  )
  records <- database$records
  records$Collection_Row <- seq_len(nrow(records))
  placement <- shelf_placement(records)
  records$Shelf_Group <- placement$Group
  records$Shelf_Group_Genre <- placement$Shelf_Genre
  records$Shelf_Group_Mood <- placement$Shelf_Mood
  shelf_index <- permanent_order(records)
  records$Shelf_Order <- match(seq_len(nrow(records)), shelf_index)
  if (refresh_rotation) {
    rotation <- select_rotation(records, rotation_size, history, rotation_genres)
    history <- advance_rotation_history(history, rotation$Album_Key)
  } else {
    rotation <- current_rotation(records, history, output_dir)
  }
  history_hit <- match(records$Album_Key, history$albums$Album_Key)
  records$Rotation_Count <- history$albums$Rotation_Count[history_hit]
  records$Rotation_Count[is.na(records$Rotation_Count)] <- 0L
  records$Last_Rotation_Run <- history$albums$Last_Rotation_Run[history_hit]
  records$Last_Rotation_Date <- history$albums$Last_Rotation_Date[history_hit]
  selected <- match(records$Album_Key, rotation$Album_Key)
  records$Rotation_Order <- rotation$Rotation_Order[selected]
  records$Rotation_Reason <- rotation$Rotation_Reason[selected]
  rotation_history_hit <- match(rotation$Album_Key, history$albums$Album_Key)
  rotation$Rotation_Count <- history$albums$Rotation_Count[rotation_history_hit]
  rotation$Last_Rotation_Date <- history$albums$Last_Rotation_Date[rotation_history_hit]

  # Everyday views contain only the fields needed for their purpose.
  collection_columns <- c(
    "Artist", "Year", "Album", "Edition", "Recording_Type",
    "Shelf_Genre", "Shelf_Mood", "Metadata_Subgenre"
  )
  shelf_columns <- c(
    "Shelf_Order", "Shelf_Genre", "Shelf_Mood", "Shelf_Group",
    "Artist", "Album", "Year", "Edition"
  )
  rotation_columns <- c(
    "Rotation_Order", "Artist", "Album", "Edition", "Year", "Shelf_Genre",
    "Shelf_Mood", "Last_Rotation_Date", "Rotation_Count"
  )
  # Detailed output follows input identity, album metadata, shelf placement,
  # classification provenance, lookup audit and rotation history.
  metadata_columns <- c(
    "Collection_Row", "DateAddition", "Artist", "Album", "Edition", "Year",
    "Recording_Type", "Metadata_Subgenre",
    "Shelf_Band", "Shelf_Group", "Shelf_Group_Genre", "Shelf_Group_Mood",
    "Shelf_Genre", "Shelf_Mood", "Shelf_Genre_Source", "Shelf_Mood_Source",
    "Suggested_Shelf_Genre", "Suggested_Shelf_Mood", "Review_Status",
    "MusicBrainz_URL", "Metadata_Retrieved", "Rotation_Order", "Rotation_Reason",
    "Rotation_Count", "Last_Rotation_Run", "Last_Rotation_Date"
  )
  dir.create(output_dir,recursive=TRUE,showWarnings=FALSE)
  staging <- tempfile(".vinyl-run-",tmpdir=output_dir); dir.create(staging)
  on.exit(unlink(staging,recursive=TRUE),add=TRUE)
  files <- character()
  if (!rotation_only) {
    # Keep this compact collection view alphabetical, then chronological within artist.
    collection_index <- order(
      artist_key(records$Artist), records$Year,
      na.last = TRUE, method = "radix"
    )
    write_table(records[collection_index, collection_columns, drop = FALSE],
                file.path(staging,"Vinyl_Collection.xlsx"),
                "Collection","VinylCollection",template=input)
    shelf_view <- records[shelf_index, shelf_columns, drop = FALSE]
    shelf_view$Shelf_Genre <- records$Shelf_Group_Genre[shelf_index]
    shelf_view$Shelf_Mood <- records$Shelf_Group_Mood[shelf_index]
    write_table(shelf_view,file.path(staging,"Vinyl_Shelf.xlsx"),
                "Permanent Shelf","VinylShelf",template=input)
    files <- c(files,"Vinyl_Collection.xlsx","Vinyl_Shelf.xlsx")
  }
  write_table(rotation[rotation_columns],file.path(staging,"Vinyl_OnRotation.xlsx"),
              "On Rotation","VinylRotation",template=input)
  write_table(records[metadata_columns],file.path(staging,"Vinyl_Metadata.xlsx"),
              "Metadata","VinylMetadata",template=input)
  files <- c(files,"Vinyl_OnRotation.xlsx","Vinyl_Metadata.xlsx")
  if (!identical(source_hash,unname(tools::md5sum(input)))) stop("Database changed during the run. Outputs were not replaced; rerun the updater.")
  for (name in files) different_paths(input,file.path(output_dir,name))
  # Install outputs and generated state together; restore prior files on failure.
  staged_history <- file.path(staging, "rotation_history.rds")
  saveRDS(history, staged_history)
  destinations <- c(file.path(output_dir, files), history_path)
  sources <- c(file.path(staging, files), staged_history)
  if (!rotation_only) {
    staged_cache <- file.path(staging, "metadata_cache.rds")
    saveRDS(database$cache, staged_cache)
    destinations <- c(destinations, cache_path)
    sources <- c(sources, staged_cache)
  }
  existed <- file.exists(destinations)
  rollback <- file.path(staging, paste0("rollback-", seq_along(destinations)))
  for (i in which(existed))
    if (!file.copy(destinations[[i]], rollback[[i]])) stop("Could not prepare output replacement.")
  tryCatch({
    for (i in seq_along(destinations)) install_file(sources[[i]], destinations[[i]])
  }, error = function(e) {
    for (i in seq_along(destinations)) {
      if (existed[[i]]) file.copy(rollback[[i]], destinations[[i]], overwrite = TRUE)
      else unlink(destinations[[i]])
    }
    stop(e)
  })
  obsolete_names <- "Vinyl_On_Rotation.xlsx"
  if (!rotation_only) {
    obsolete_names <- c(
      obsolete_names, "VinylCollection_completed.xlsx", "VinylShelf_Permanent.xlsx"
    )
  }
  for (obsolete_output in file.path(output_dir, obsolete_names)) {
    if (file.exists(obsolete_output) && unlink(obsolete_output) != 0L)
      warning("Could not remove obsolete output: ", obsolete_output,
              ". Close it in Excel and remove it manually.")
  }
  counts <- table(records$Shelf_Mood[!duplicated(records$Album_Key)])
  genre_counts <- table(records$Shelf_Genre)
  mood_summary <- if (length(counts)) paste0("Each mood has ", min(counts), "+ albums. ") else "No classified albums yet. "
  message("Updated ",length(files)," workbook(s): ",nrow(records)," records, ",length(unique(records$Album_Key)),
          " albums, ",length(unique(artist_key(records$Artist)))," artists. ", mood_summary,
          "Shelf genres: ", paste(paste0(names(genre_counts), " (", genre_counts, ")"), collapse=", "), ".")
  invisible(records)
}
