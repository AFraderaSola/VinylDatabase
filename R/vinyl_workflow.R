# Shared classification, validation and safe output helpers.
normalize <- function(x) {
  x <- ifelse(is.na(x), "", as.character(x))
  x <- iconv(x, from = "", to = "ASCII//TRANSLIT")
  trimws(gsub(" +", " ", gsub("[^a-z0-9]+", " ", tolower(x))))
}
is_missing <- function(x) is.na(x) | !nzchar(trimws(as.character(x)))
key_for <- function(artist, album) paste(normalize(artist), normalize(album), sep = "|")
require_columns <- function(data, columns, label) {
  missing <- setdiff(columns, names(data))
  if (length(missing)) stop(label, " is missing: ", paste(missing, collapse = ", "))
}
unique_keys <- function(data, key, label) {
  if (any(is_missing(data[[key]])) || anyDuplicated(data[[key]]))
    stop(label, " needs one nonempty ", key, " per row. Resolve duplicate or missing keys first.")
}
different_paths <- function(input, output) {
  if (normalizePath(input, mustWork = FALSE) == normalizePath(output, mustWork = FALSE))
    stop("Input and output must be different files; source files are read-only.")
}
install_file <- function(staging, path) {
  if (!file.rename(staging, path)) stop("Could not replace ", path)
}

# This openxlsx version leaves dimension="A1" and references absent default drawings.
# Normalize those package declarations, rejecting other missing parts before install.
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
              DateAddition = 17, Discogs_Flagged = 21, Genre = 27, Mood = 19,
              Subgenre = 25, Recording_Type = 20,
              Year_Pressing = 18, Last_Played = 17, Discogs_ID = 18,
              Discogs_Entity = 20, Discogs_Confirmed = 23, Review_Status = 22,
              Album_Notes = 65, Year_Source = 65, Discogs_Notes = 65,
              Discogs_URL = 55, Discogs_Genre = 25, Discogs_Style = 35,
              Discogs_Retrieved = 22, Metadata_Source = 65,
              Shelf_Band = 36, Shelf_Group = 36, Shelf_Genre = 27, Shelf_Mood = 19,
              Shelf_Order = 15, Collection_Row = 18, Rotation_Order = 19, Rotation_Reason = 32)
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

genres <- sort(c("Electronic", "Rock", "Pop", "Jazz / Blues", "Classical / Soundtrack"), method = "radix")
moods <- sort(c("Intimate", "Reflective", "Melancholic", "Warm", "Groovy",
                "Intense", "Immersive"), method = "radix")
artist_key <- function(x) sub("^the ", "", normalize(x))
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
default_shelf_band <- function(artist) {
  unname(originating_bands[match(artist_key(artist), artist_key(names(originating_bands)))])
}

optional <- function(data, name) {
  if (name %in% names(data)) data[[name]] else rep(NA_character_, nrow(data))
}
numbers <- function(x, name, low, high) {
  value <- suppressWarnings(as.numeric(x))
  bad <- !is_missing(x) & (is.na(value) | value < low | value > high | value != floor(value))
  if (any(bad)) stop(name, " must contain whole numbers from ", low, " to ", high, " or blanks.")
  value
}
booleans <- function(x, name, blank = FALSE) {
  text <- tolower(trimws(as.character(x)))
  bad <- !is_missing(x) & !text %in% c("true","false","1","0","yes","no")
  if (any(bad)) stop(name, " must contain TRUE, FALSE or blanks.")
  ifelse(is_missing(x), blank, text %in% c("true","1","yes"))
}
dates <- function(x, name) {
  if (inherits(x, "Date") || inherits(x, "POSIXt")) return(as.Date(x))
  result <- as.Date(rep(NA_character_, length(x)))
  for (i in which(!is_missing(x))) {
    value <- trimws(as.character(x[[i]]))
    if (grepl("^[0-9]{8}$", value)) {
      result[[i]] <- as.Date(value, format = "%Y%m%d")
    } else if (grepl("^[0-9]+(\\.[0-9]+)?$", value) && as.numeric(value) <= 100000) {
      result[[i]] <- as.Date(as.numeric(value), origin = "1899-12-30")
    } else if (grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}( 00:00:00)?$", value)) {
      result[[i]] <- as.Date(substr(value, 1, 10), format = "%Y-%m-%d")
    }
    if (is.na(result[[i]])) stop("Invalid ", name, " date: ", value)
  }
  result
}
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
# Requests are cached for this run and spaced more than one second apart.
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
mb_scalar <- function(value, default = NA_character_) {
  if (is.null(value) || !length(value) || is_missing(value[[1]])) default else as.character(value[[1]])
}
mb_tags <- function(entity) {
  entries <- c(entity$genres, entity$tags)
  if (!length(entries)) return(character())
  counts <- vapply(entries, function(x) suppressWarnings(as.numeric(mb_scalar(x$count, "1"))), numeric(1))
  counts[is.na(counts)] <- 0
  unique(vapply(entries[order(-counts)], function(x) mb_scalar(x$name, ""), character(1)))
}
lookup_album <- function(artist, album, request) {
  # Normalize search syntax, then require a single exact title AND artist credit.
  query <- sprintf('releasegroup:"%s" AND artist:"%s"', normalize(album), normalize(artist))
  search <- request("release-group", list(query = query, limit = 100))
  if (is.null(search) || is.null(search[["release-groups"]])) return(NULL)
  if (!is.null(search$count) && search$count > 100) return(NULL)
  matches <- Filter(function(group) {
    credit <- paste0(vapply(group[["artist-credit"]], function(x)
      paste0(mb_scalar(x$name, mb_scalar(x$artist$name, "")), mb_scalar(x$joinphrase, "")), character(1)), collapse = "")
    identical(normalize(mb_scalar(group$title)), normalize(album)) &&
      identical(artist_key(credit), artist_key(artist))
  }, search[["release-groups"]])
  if (length(matches) != 1L) return(NULL)
  id <- mb_scalar(matches[[1]]$id)
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
       url = paste0("https://musicbrainz.org/release-group/", id))
}
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
  list(Genre = genre, Mood = mood,
       Subgenre = if (length(tags)) tools::toTitleCase(tags[[1]]) else NA_character_)
}
complete_records <- function(records, artists) {
  fields <- c("Genre", "Mood", "Subgenre", "Year", "Recording_Type",
              "Review_Status", "Year_Source", "Metadata_Source", "Shelf_Band")
  for (field in fields) records[[field]] <- as.character(optional(records, field))
  keys <- artist_key(records$Artist)
  album_keys <- key_for(keys, records$Album)
  request <- musicbrainz_client()
  lookups <- new.env(parent = emptyenv())
  for (key in unique(keys)) {
    idx <- which(keys == key)
    hit <- match(key, artists$Artist_Key)
    known <- !is.na(hit)
    if (known) records$Artist[idx] <- artists$Artist[[hit]]
    shared <- list()
    for (field in c("Genre", "Mood")) {
      saved <- if (known) optional(artists, field)[[hit]] else NA_character_
      supplied <- unique(records[[field]][idx][!is_missing(records[[field]][idx])])
      if (!is_missing(saved)) {
        # Artists is the authority for existing artists, including Pop.
        shared[[field]] <- as.character(saved)
        if (any(supplied != saved)) message("Using Artists!", field, " for ", records$Artist[idx[[1]]], ".")
      } else {
        if (length(supplied) > 1L) stop("Conflicting ", field, " values for ", records$Artist[idx[[1]]], "; choose one in Artists.")
        shared[[field]] <- if (length(supplied)) supplied[[1]] else NA_character_
      }
    }
    saved_band <- if (known) optional(artists, "Shelf_Band")[[hit]] else NA_character_
    supplied_band <- unique(records$Shelf_Band[idx][!is_missing(records$Shelf_Band[idx])])
    if (is_missing(saved_band)) {
      if (length(supplied_band) > 1L)
        stop("Conflicting Shelf_Band values for ", records$Artist[idx[[1]]], "; choose one in Artists.")
      saved_band <- if (length(supplied_band)) supplied_band[[1]] else default_shelf_band(records$Artist[idx[[1]]])
    }
    records$Shelf_Band[idx] <- saved_band
    # Copy known album facts between pressings, but never edition or pressing year.
    for (album_key in unique(album_keys[idx])) {
      same <- idx[album_keys[idx] == album_key]
      for (field in c("Year", "Subgenre", "Recording_Type")) {
        value <- unique(records[[field]][same][!is_missing(records[[field]][same])])
        if (length(value) == 1L) records[[field]][same[is_missing(records[[field]][same])]] <- value[[1]]
      }
    }
    for (field in c("Subgenre")) {
      saved <- if (known) optional(artists, field)[[hit]] else NA_character_
      empty <- idx[is_missing(records[[field]][idx])]
      if (!is_missing(saved)) records[[field]][empty] <- as.character(saved)
    }
    tags <- character()
    for (i in idx[order(normalize(records$Album[idx]))]) {
      need_artist <- any(vapply(shared, is_missing, logical(1)))
      need_album <- any(is_missing(unlist(records[i, c("Year", "Recording_Type", "Subgenre")], use.names = FALSE)))
      if (!need_artist && !need_album) next
      album_key <- album_keys[[i]]
      if (!exists(album_key, lookups, inherits = FALSE))
        assign(album_key, lookup_album(records$Artist[[i]], records$Album[[i]], request), lookups)
      result <- get(album_key, lookups)
      if (is.null(result)) next
      tags <- unique(c(tags, result$artist_tags))
      for (field in c("Year", "Recording_Type")) {
        if (is_missing(records[[field]][[i]]) && !is_missing(result[[field]])) {
          records[[field]][[i]] <- result[[field]]
          if (field == "Year") records$Year_Source[[i]] <- result$url
        }
      }
      if (is_missing(records$Subgenre[[i]]) && length(result$tags))
        records$Subgenre[[i]] <- tools::toTitleCase(result$tags[[1]])
      records$Metadata_Source[[i]] <- result$url
    }
    suggestion <- suggest_artist(tags, shared$Genre)
    inferred <- FALSE
    for (field in c("Genre", "Mood")) {
      if (is_missing(shared[[field]]) && !is_missing(suggestion[[field]])) {
        shared[[field]] <- suggestion[[field]]
        inferred <- TRUE
      }
      records[[field]][idx] <- shared[[field]]
    }
    if (inferred) records$Review_Status[idx] <- "Needs review"
    # Ratings are personal choices; reuse supplied artist/album ratings only.
    if (any(is_missing(shared$Genre), is_missing(shared$Mood))) records$Review_Status[idx] <- "Needs review"
  }
  records
}

read_database <- function(path) {
  verify_package(path)
  if (!all(c("Collection","Artists") %in% readxl::excel_sheets(path)))
    stop("Database.xlsx needs Collection and Artists worksheets.")
  # Parse fields explicitly below, including columns mixing Excel dates and YYYYMMDD.
  records <- as.data.frame(readxl::read_excel(path, sheet="Collection", col_types="text"))
  artists <- as.data.frame(readxl::read_excel(path, sheet="Artists", col_types="text"))
  require_columns(records, c("Artist","Album","DateAddition"), "Collection")
  require_columns(artists, c("Artist","Mood"), "Artists")
  if (!nrow(records)) stop("Collection is empty.")
  if (any(is_missing(records$Artist) | is_missing(records$Album))) stop("Every Collection row needs an Artist and Album.")
  artists$Artist_Key <- artist_key(artists$Artist)
  unique_keys(artists, "Artist_Key", "Artists worksheet")
  # Validate mandatory dates before lookups or output creation.
  addition_dates <- dates(records$DateAddition, "DateAddition")
  missing_dates <- which(is.na(addition_dates))
  if (length(missing_dates))
    stop("DateAddition is required for every record. Fill Collection row(s): ",
         paste(missing_dates + 1L, collapse = ", "), ".")
  records <- complete_records(records, artists)
  for (field in c("Genre", "Mood")) {
    allowed <- if (field == "Genre") genres else moods
    if (any(!is_missing(records[[field]]) & !records[[field]] %in% allowed))
      stop("Invalid ", field, ". Use: ", paste(allowed, collapse = ", "))
  }
  records$Year_Recording <- numbers(optional(records,"Year"), "Year", 1000, 9999)
  records$Year_Pressing <- numbers(optional(records,"Year_Pressing"), "Year_Pressing", 1000, 9999)
  records$Addition_Date <- addition_dates
  records$Last_Played <- dates(optional(records,"Last_Played"), "Last_Played")
  if (any(records$Last_Played > Sys.Date(),na.rm=TRUE)) stop("Last_Played cannot be in the future.")
  records$Album_Key <- key_for(records$Artist,records$Album)
  # A play of either pressing counts as a play of the album.
  for (key in unique(records$Album_Key)) {
    idx <- which(records$Album_Key==key)
    played <- records$Last_Played[idx]
    if (any(!is.na(played))) records$Last_Played[idx] <- max(played,na.rm=TRUE)
  }
  for (field in c("Edition","Recording_Type","Review_Status","Album_Notes","Year_Source","Discogs_Notes",
                  "Discogs_ID","Discogs_Entity")) records[[field]] <- as.character(optional(records,field))
  bad_type <- !is_missing(records$Recording_Type) & !records$Recording_Type %in% c("Studio","Live","Mixed","Compilation","Unknown")
  if (any(bad_type)) stop("Recording_Type must be Studio, Live, Mixed, Compilation or Unknown.")
  incomplete <- is_missing(records$Genre) | is_missing(records$Mood) |
    is.na(records$Year_Recording) | is_missing(records$Subgenre) |
    is_missing(records$Recording_Type)
  records$Review_Status[incomplete] <- "Needs review"
  records$Review_Status[is_missing(records$Review_Status)] <- "Suggested"
  records$Discogs_Flagged <- booleans(optional(records,"Discogs_Flagged"),"Discogs_Flagged") | is.na(records$Year_Recording)
  records$Discogs_Confirmed <- booleans(optional(records,"Discogs_Confirmed"),"Discogs_Confirmed")
  records$Year_Source[is_missing(records$Year_Source) & !is.na(records$Year_Recording)] <- "Database entry"
  counts <- table(records$Mood[!duplicated(records$Album_Key)])
  narrow <- counts[counts<6]
  if (length(narrow)) stop("Each mood needs at least six distinct albums. Reassign artists for: ",
                           paste(paste0(names(narrow)," (",narrow,")"),collapse=", "))
  records
}
fetch_discogs <- function(records) {
  for (field in c("Discogs_URL","Discogs_Genre","Discogs_Style","Discogs_Retrieved")) records[[field]] <- NA_character_
  token <- Sys.getenv("DISCOGS_TOKEN",unset="")
  ids <- which(records$Discogs_Confirmed)
  if (any(!grepl("^[0-9]+$",records$Discogs_ID[ids]) | !records$Discogs_Entity[ids] %in% c("release","master")))
    stop("Confirmed Discogs entries need a numeric ID and release/master entity.")
  fetched <- new.env(parent=emptyenv())
  for (i in ids) {
    id <- records$Discogs_ID[[i]]; entity <- records$Discogs_Entity[[i]]
    records$Discogs_URL[[i]] <- sprintf("https://www.discogs.com/%s/%s",entity,id)
    if (!nzchar(token)) next
    if (!requireNamespace("httr2",quietly=TRUE)) stop("Install httr2 to use DISCOGS_TOKEN.")
    key <- paste(entity,id,sep="-")
    if (!exists(key,fetched,inherits=FALSE)) {
      response <- tryCatch({
        request <- httr2::request(sprintf("https://api.discogs.com/%ss/%s",entity,id)) |>
          httr2::req_headers(Authorization=paste0("Discogs token=",token)) |>
          httr2::req_user_agent("VinylCollection/3.0") |>
          httr2::req_timeout(20) |>
          httr2::req_retry(max_tries=3)
        httr2::resp_body_json(httr2::req_perform(request))
      },error=function(e) {warning("Could not fetch Discogs ID ",id,"; source tags left blank."); NULL})
      assign(key,response,fetched)
      Sys.sleep(1)
    }
    response <- get(key,fetched)
    if (!is.null(response) && identical(as.character(response$id),id)) {
      records$Discogs_Genre[[i]] <- paste(unlist(response$genres),collapse="; ")
      records$Discogs_Style[[i]] <- paste(unlist(response$styles),collapse="; ")
      records$Discogs_Retrieved[[i]] <- as.character(Sys.Date())
    }
  }
  records
}
# Resolve families without changing the artist's own classification.
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
    family_genre[[family]] <- majority(artists$Genre[members], artists$Genre[[family]])
    family_mood[[family]] <- majority(artists$Mood[members], artists$Mood[[family]])
  }
  root <- roots[match(keys, keys[first])]
  data.frame(Group = artists$Artist[root], Genre = family_genre[root],
             Mood = family_mood[root], Is_Member = keys != keys[first][root],
             stringsAsFactors = FALSE)
}
permanent_order <- function(records) {
  shelf <- shelf_placement(records)
  order(is_missing(shelf$Genre) | is_missing(shelf$Mood),
        normalize(shelf$Genre), normalize(shelf$Mood), artist_key(shelf$Group),
        shelf$Is_Member, artist_key(records$Artist),
        records$Year_Recording, normalize(records$Album), normalize(records$Edition),
        na.last = TRUE, method = "radix")
}
# Maximize distinct moods within date quotas; randomize equally good choices.
rotation_mood_sample <- function(pool, date_group, quotas, priority_moods) {
  mood_group <- ifelse(pool$Mood %in% priority_moods, pool$Mood, "Other unprioritized moods")
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
validate_rotation_genres <- function(rotation_genres) {
  if (!is.character(rotation_genres) || !length(rotation_genres) ||
      anyNA(rotation_genres) || anyDuplicated(rotation_genres) ||
      any(!rotation_genres %in% genres))
    stop("Choose distinct rotation genres from: ", paste(genres, collapse = ", "))
  sort(rotation_genres, method = "radix")
}
select_rotation <- function(records, size = NULL, history = empty_rotation_history(),
                            rotation_genres = c("Jazz / Blues", "Rock")) {
  rotation_genres <- validate_rotation_genres(rotation_genres)
  expected_size <- 5L * length(rotation_genres)
  if (!is.null(size) && (length(size) != 1L || is.na(size) || size != expected_size))
    stop("Rotation needs ", expected_size, " albums: five per enabled genre. Omit --rotation-size or use that total.")
  records <- records[!is_missing(records$Genre) & !is_missing(records$Mood), , drop = FALSE]
  # Multiple pressings count once, using the album's newest addition date.
  records <- records[order(-as.numeric(records$Addition_Date), artist_key(records$Artist),
                           normalize(records$Album), normalize(records$Edition), na.last = TRUE), , drop = FALSE]
  records <- records[!duplicated(records$Album_Key), , drop = FALSE]
  selected <- list()
  for (genre in rotation_genres) {
    pool <- records[records$Genre == genre, , drop = FALSE]
    if (!nrow(pool)) { warning("No classified albums available for ", genre, "."); next }
    mood_counts <- table(pool$Mood)
    priority_moods <- names(mood_counts)[mood_counts > 3L]
    target <- min(5L, nrow(pool))
    hit <- match(pool$Album_Key, history$albums$Album_Key)
    last_run <- history$albums$Last_Rotation_Run[hit]
    recent <- !is.na(last_run) & last_run == history$run
    available <- which(!recent)
    if (length(available) < target) {
      repeats <- which(recent)
      counts <- history$albums$Rotation_Count[hit[repeats]]
      repeats <- repeats[order(counts, runif(length(repeats)))]
      available <- c(available, head(repeats, target - length(available)))
    }
    pool <- pool[available, , drop = FALSE]
    dates <- sort(unique(pool$Addition_Date), decreasing = TRUE)
    group <- match(pool$Addition_Date, dates)
    capacity <- tabulate(group, nbins = length(dates))
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
    result$Rotation_Reason <- paste0("Random mood coverage; added ", result$Addition_Date)
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
empty_rotation_history <- function() {
  list(version = 1L, run = 0L, albums = data.frame(Album_Key = character(),
       Rotation_Count = integer(), Last_Rotation_Run = integer(), stringsAsFactors = FALSE))
}
advance_rotation_history <- function(history, keys) {
  keys <- unique(keys)
  history$run <- history$run + 1L
  missing <- setdiff(keys, history$albums$Album_Key)
  if (length(missing)) history$albums <- rbind(history$albums,
    data.frame(Album_Key = missing, Rotation_Count = 0L, Last_Rotation_Run = 0L))
  hit <- match(keys, history$albums$Album_Key)
  history$albums$Rotation_Count[hit] <- history$albums$Rotation_Count[hit] + 1L
  history$albums$Last_Rotation_Run[hit] <- history$run
  history
}
read_rotation_history <- function(path, output_dir) {
  if (!file.exists(path)) {
    history <- empty_rotation_history()
    previous <- file.path(output_dir, "Vinyl_On_Rotation.xlsx")
    if (file.exists(previous)) {
      old <- as.data.frame(readxl::read_excel(previous))
      require_columns(old, c("Artist", "Album"), "Previous rotation")
      history <- advance_rotation_history(history, key_for(old$Artist, old$Album))
    }
    return(history)
  }
  history <- readRDS(path)
  if (!is.list(history) || !identical(history$version, 1L) ||
      length(history$run) != 1L || !is.numeric(history$run) || is.na(history$run) ||
      history$run < 0 || history$run != floor(history$run) || !is.data.frame(history$albums))
    stop("Invalid rotation history: ", path)
  require_columns(history$albums, c("Album_Key", "Rotation_Count", "Last_Rotation_Run"), "Rotation history")
  unique_keys(history$albums, "Album_Key", "Rotation history")
  for (field in c("Rotation_Count", "Last_Rotation_Run")) {
    x <- history$albums[[field]]
    if (!is.numeric(x) || anyNA(x) || any(x < 1 | x != floor(x) | x > history$run))
      stop("Invalid ", field, " in rotation history.")
  }
  history
}

run_update <- function(input,output_dir,rotation_size=NULL,rotation_only=FALSE,
                       reset_rotation_history=FALSE,rotation_genres=c("Jazz / Blues", "Rock")) {
  rotation_genres <- validate_rotation_genres(rotation_genres)
  message("Input database: ", normalizePath(input, mustWork = TRUE))
  message("Output folder: ", normalizePath(output_dir, mustWork = FALSE))
  history_dir <- file.path(dirname(dirname(normalizePath(input))), "state")
  dir.create(history_dir, recursive = TRUE, showWarnings = FALSE)
  lock <- file.path(history_dir, ".rotation-lock")
  if (!dir.create(lock, showWarnings = FALSE)) stop("Another rotation update is running (", lock, ").")
  on.exit(unlink(lock, recursive = TRUE), add = TRUE)
  history_path <- file.path(history_dir, "rotation_history.rds")
  history <- if (reset_rotation_history) empty_rotation_history() else read_rotation_history(history_path, output_dir)
  source_hash <- unname(tools::md5sum(input))
  records <- fetch_discogs(read_database(input))
  records$Year <- records$Year_Recording
  records$DateAddition <- records$Addition_Date
  records$Collection_Row <- seq_len(nrow(records))
  placement <- shelf_placement(records)
  records$Shelf_Group <- placement$Group
  records$Shelf_Genre <- placement$Genre
  records$Shelf_Mood <- placement$Mood
  shelf_index <- permanent_order(records)
  records$Shelf_Order <- match(seq_len(nrow(records)), shelf_index)
  rotation <- select_rotation(records, rotation_size, history, rotation_genres)
  history <- advance_rotation_history(history, rotation$Album_Key)
  history_hit <- match(records$Album_Key, history$albums$Album_Key)
  records$Rotation_Count <- history$albums$Rotation_Count[history_hit]
  records$Rotation_Count[is.na(records$Rotation_Count)] <- 0L
  records$Last_Rotation_Run <- history$albums$Last_Rotation_Run[history_hit]
  selected <- match(records$Album_Key, rotation$Album_Key)
  records$Rotation_Order <- rotation$Rotation_Order[selected]
  records$Rotation_Reason <- rotation$Rotation_Reason[selected]

  # Everyday views contain only the fields needed for their purpose.
  collection_columns <- c("Artist", "Album", "Year", "Edition", "Genre", "Mood",
                          "Subgenre", "DateAddition", "Last_Played")
  shelf_columns <- c("Shelf_Order", "Genre", "Mood", "Artist", "Album", "Year", "Edition")
  rotation_columns <- c("Rotation_Order", "Artist", "Album", "Year", "Genre", "Mood",
                        "Edition", "Last_Played")
  # One detailed output holds sources, review information and selection details.
  metadata_columns <- c("Collection_Row", "Shelf_Order", "Shelf_Band", "Shelf_Group",
                        "Shelf_Genre", "Shelf_Mood", "Artist", "Album", "Edition",
                        "Year", "Year_Pressing", "Genre", "Mood", "Subgenre",
                        "DateAddition", "Last_Played",
                        "Recording_Type", "Review_Status", "Album_Notes", "Year_Source",
                        "Metadata_Source", "Discogs_Flagged", "Discogs_ID", "Discogs_Entity",
                        "Discogs_Confirmed", "Discogs_URL", "Discogs_Genre", "Discogs_Style",
                        "Discogs_Retrieved", "Discogs_Notes", "Rotation_Order", "Rotation_Reason",
                        "Rotation_Count", "Last_Rotation_Run")
  dir.create(output_dir,recursive=TRUE,showWarnings=FALSE)
  staging <- tempfile(".vinyl-run-",tmpdir=output_dir); dir.create(staging)
  on.exit(unlink(staging,recursive=TRUE),add=TRUE)
  files <- character()
  if (!rotation_only) {
    write_table(records[collection_columns],file.path(staging,"VinylCollection_completed.xlsx"),
                "Collection","VinylCollection",template=input)
    shelf_view <- records[shelf_index, shelf_columns, drop = FALSE]
    shelf_view$Genre <- records$Shelf_Genre[shelf_index]
    shelf_view$Mood <- records$Shelf_Mood[shelf_index]
    write_table(shelf_view,file.path(staging,"VinylShelf_Permanent.xlsx"),
                "Permanent Shelf","VinylShelf",template=input)
    files <- c(files,"VinylCollection_completed.xlsx","VinylShelf_Permanent.xlsx")
  }
  write_table(rotation[rotation_columns],file.path(staging,"Vinyl_On_Rotation.xlsx"),
              "On Rotation","VinylRotation",template=input)
  write_table(records[metadata_columns],file.path(staging,"Vinyl_Metadata.xlsx"),
              "Metadata","VinylMetadata",template=input)
  files <- c(files,"Vinyl_On_Rotation.xlsx","Vinyl_Metadata.xlsx")
  if (!identical(source_hash,unname(tools::md5sum(input)))) stop("Database changed during the run. Outputs were not replaced; rerun the updater.")
  for (name in files) different_paths(input,file.path(output_dir,name))
  # Install outputs and history together; restore prior files on an install failure.
  staged_history <- file.path(staging, "rotation_history.rds")
  saveRDS(history, staged_history)
  destinations <- c(file.path(output_dir, files), history_path)
  sources <- c(file.path(staging, files), staged_history)
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
  counts <- table(records$Mood[!duplicated(records$Album_Key)])
  genre_counts <- table(records$Genre)
  mood_summary <- if (length(counts)) paste0("Each mood has ", min(counts), "+ albums. ") else "No classified albums yet. "
  message("Updated ",length(files)," workbook(s): ",nrow(records)," records, ",length(unique(records$Album_Key)),
          " albums, ",length(unique(artist_key(records$Artist)))," artists. ", mood_summary,
          "Genres: ", paste(paste0(names(genre_counts), " (", genre_counts, ")"), collapse=", "), ".")
  invisible(records)
}
