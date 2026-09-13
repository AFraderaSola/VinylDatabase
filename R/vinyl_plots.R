# Descriptive plots are read-only: no metadata requests or rotation draws.
plot_vinyl_database <- function(input, history_path, output_dir) {
  for (package in c("ggplot2", "MetBrewer"))
    if (!requireNamespace(package, quietly = TRUE)) stop("Restore plotting dependency: ", package)
  # Reuse validation and saved artist defaults without starting online lookups.
  # Restore the caller's environment even if an export fails.
  old_offline <- Sys.getenv("VINYL_OFFLINE", unset = NA_character_)
  Sys.setenv(VINYL_OFFLINE = "true")
  on.exit(if (is.na(old_offline)) Sys.unsetenv("VINYL_OFFLINE") else
    Sys.setenv(VINYL_OFFLINE = old_offline), add = TRUE)
  records <- read_database(input)
  # Album counts and growth use the first acquired pressing of each album.
  records <- records[order(records$Addition_Date, na.last = TRUE), , drop = FALSE]
  albums <- records[!duplicated(records$Album_Key), , drop = FALSE]
  albums$Genre[is_missing(albums$Genre)] <- "Unclassified"
  albums$Mood[is_missing(albums$Mood)] <- "Unclassified"
  genre_levels <- c(genres, if ("Unclassified" %in% albums$Genre) "Unclassified")
  mood_levels <- c(moods, if ("Unclassified" %in% albums$Mood) "Unclassified")
  # Five original Archambault swatches, excluding yellow and orange, reversed (direction -1).
  archambault <- MetBrewer::met.brewer("Archambault")
  colours <- setNames(rev(as.character(archambault[c(1, 2, 3, 4, 5)])), genres)
  colours <- c(colours, Unclassified = "#999999")
  theme <- ggplot2::theme_minimal(base_size = 12, base_family = "sans") +
    ggplot2::theme(plot.background = ggplot2::element_rect(fill = "#FAF8F3", colour = NA),
      panel.background = ggplot2::element_rect(fill = "#FAF8F3", colour = NA),
      panel.grid.minor = ggplot2::element_blank(),
      plot.title = ggplot2::element_text(face = "bold", size = 19),
      plot.subtitle = ggplot2::element_text(colour = "#555555", margin = ggplot2::margin(b = 14)),
      plot.caption = ggplot2::element_text(colour = "#666666", hjust = 0),
      legend.position = "bottom", legend.title = ggplot2::element_blank(),
      plot.margin = ggplot2::margin(18, 24, 18, 18))
  caption <- sprintf("%d distinct albums | %d records | %d artists. Multiple pressings count once.",
                     nrow(albums), nrow(records), length(unique(artist_key(albums$Artist))))
  fill <- function() ggplot2::scale_fill_manual(values = colours, drop = FALSE)
  genre_count <- as.data.frame(table(Genre = factor(albums$Genre, levels = genre_levels)))
  genre_count$Genre <- factor(genre_count$Genre, levels = rev(genre_levels))
  plots <- list()
  plots$collection_by_genre <- ggplot2::ggplot(genre_count, ggplot2::aes(Freq, Genre, fill = Genre)) +
    ggplot2::geom_col(width = .65, show.legend = FALSE) +
    ggplot2::geom_text(ggplot2::aes(label = Freq), hjust = -.3) + fill() +
    ggplot2::scale_x_continuous(expand = ggplot2::expansion(mult = c(0, .12))) +
    ggplot2::labs(title = "Your collection by genre", subtitle = "Artist classifications from the input database",
                  x = "Distinct albums", y = NULL, caption = caption) + theme
  mood_count <- as.data.frame(table(Genre = factor(albums$Genre, levels = genre_levels),
                                    Mood = factor(albums$Mood, levels = rev(mood_levels))))
  mood_count$Label <- ifelse(mood_count$Freq == 0, "", as.character(mood_count$Freq))
  plots$moods_by_genre <- ggplot2::ggplot(mood_count, ggplot2::aes(Genre, Mood, fill = Freq)) +
    ggplot2::geom_tile(colour = "#FAF8F3", linewidth = 1.5) +
    ggplot2::geom_label(data = mood_count[mood_count$Freq > 0, ],
      ggplot2::aes(label = Label), fill = "#FAF8F3", colour = "#222222", linewidth = 0, size = 3.5) +
    ggplot2::scale_fill_gradientn(colours = MetBrewer::met.brewer("Hokusai2", n = 64, type = "continuous")) +
    ggplot2::scale_x_discrete(labels = function(x) gsub(" / ", " /\n", x, fixed = TRUE)) +
    ggplot2::labs(title = "The moods within each genre", subtitle = "Numbers show distinct albums; rotation coverage prioritizes groups of four or more",
                  x = NULL, y = NULL, caption = caption) + theme
  growth <- as.data.frame(table(albums$Addition_Date), stringsAsFactors = FALSE)
  names(growth) <- c("Date", "Added"); growth$Date <- as.Date(growth$Date)
  growth <- growth[order(growth$Date), ]; growth$Total <- cumsum(growth$Added)
  plots$collection_growth <- ggplot2::ggplot(growth, ggplot2::aes(Date, Total)) +
    (if (nrow(growth) > 1) ggplot2::geom_step(colour = colours[["Rock"]], linewidth = 1) else NULL) +
    ggplot2::geom_point(colour = colours[["Rock"]], size = 3) +
    ggplot2::scale_y_continuous(limits = c(0, NA), expand = ggplot2::expansion(mult = c(0, .1))) +
    ggplot2::labs(title = "How the collection grows", subtitle = "Cumulative albums by their first recorded addition date",
                  x = NULL, y = "Distinct albums", caption = paste(caption,
                    if (nrow(growth) == 1) "All additions currently share one date; no growth trend is yet available." else "Dates reflect database entries, not inferred purchases.")) + theme
  known <- albums[!is.na(albums$Year_Recording), , drop = FALSE]
  decade <- as.data.frame(table(Decade = paste0(floor(known$Year_Recording / 10) * 10, "s"), Genre = known$Genre))
  plots$release_decades <- ggplot2::ggplot(decade, ggplot2::aes(Decade, Freq, fill = Genre)) +
    ggplot2::geom_col(width = .75) + fill() +
    ggplot2::labs(title = "The decades on your shelves", subtitle = "Original release years, rather than pressing years",
                  x = NULL, y = "Distinct albums", caption = sprintf("%s %d albums have no release year and are omitted.", caption, sum(is.na(albums$Year_Recording)))) + theme
  artist_count <- aggregate(list(Albums = rep(1L, nrow(albums))),
                            list(Artist = albums$Artist, Genre = albums$Genre), sum)
  artist_count <- artist_count[order(-artist_count$Albums, artist_key(artist_count$Artist)), ]
  artist_count <- head(artist_count, 15)
  artist_count$Artist <- factor(artist_count$Artist, levels = rev(artist_count$Artist))
  plots$most_collected_artists <- ggplot2::ggplot(artist_count, ggplot2::aes(Albums, Artist, fill = Genre)) +
    ggplot2::geom_col(width = .7) + ggplot2::geom_text(ggplot2::aes(label = Albums), hjust = -.3) +
    fill() + ggplot2::scale_x_continuous(expand = ggplot2::expansion(mult = c(0, .15))) +
    ggplot2::labs(title = "Your most-collected artists", subtitle = "Top 15 by distinct albums; ties ordered alphabetically",
                  x = "Distinct albums", y = NULL, caption = caption) + theme
  albums$Rotation_Count <- 0L
  history_note <- "No saved rotation history yet."
  if (file.exists(history_path)) {
    history <- read_rotation_history(history_path, dirname(output_dir))
    hit <- match(albums$Album_Key, history$albums$Album_Key)
    albums$Rotation_Count <- history$albums$Rotation_Count[hit]
    albums$Rotation_Count[is.na(albums$Rotation_Count)] <- 0L
    history_note <- paste("Saved rotation run", history$run, "| Counts cover tracked history only.")
  }
  albums$Current <- FALSE
  if (file.exists(history_path))
    albums$Current <- !is.na(hit) & history$albums$Last_Rotation_Run[hit] == history$run
  # Use saved history, not the updater toggle: this describes the last actual draw.
  active_genres <- sort(unique(albums$Genre[albums$Current]))
  rotation_rows <- list()
  for (genre in active_genres) {
    pool <- albums[albums$Genre == genre, , drop = FALSE]
    # Always include current picks, then fill up to 15 with the most selected.
    ranked <- order(!pool$Current, -pool$Rotation_Count, artist_key(pool$Artist), normalize(pool$Album))
    ranked <- ranked[pool$Rotation_Count[ranked] > 0L]
    shown <- pool[head(ranked, max(15L, sum(pool$Current))), , drop = FALSE]
    shown$Panel <- sprintf("%s | %d of %d albums selected at least once | %d never selected",
                           genre, sum(pool$Rotation_Count > 0L), nrow(pool), sum(pool$Rotation_Count == 0L))
    rotation_rows[[length(rotation_rows) + 1L]] <- shown
  }
  if (length(rotation_rows)) {
    rotation_view <- do.call(rbind, rotation_rows)
    rotation_view <- rotation_view[order(rotation_view$Genre, rotation_view$Rotation_Count,
                                         rotation_view$Current, artist_key(rotation_view$Artist)), ]
    rotation_view$Row <- factor(rotation_view$Album_Key, levels = rotation_view$Album_Key)
    labels <- paste(rotation_view$Artist, rotation_view$Album, sep = " - ")
    labels <- ifelse(nchar(labels) > 65L, paste0(substr(labels, 1L, 62L), "..."), labels)
    names(labels) <- rotation_view$Album_Key
    rotation_view$Status <- ifelse(rotation_view$Current, "On rotation now", "Previously selected")
    plots$rotation_coverage <- ggplot2::ggplot(rotation_view,
      ggplot2::aes(Rotation_Count, Row)) +
      ggplot2::geom_segment(ggplot2::aes(x = 0, xend = Rotation_Count, yend = Row),
                           colour = "#D6D1C7", linewidth = .6) +
      ggplot2::geom_point(ggplot2::aes(colour = Status, shape = Status), size = 3.2, stroke = 1) +
      ggplot2::scale_colour_manual(values = c("On rotation now" = unname(colours[["Electronic"]]),
                                              "Previously selected" = "#7A7A7A")) +
      ggplot2::scale_shape_manual(values = c("On rotation now" = 16, "Previously selected" = 1)) +
      ggplot2::scale_y_discrete(labels = labels) +
      ggplot2::scale_x_continuous(breaks = function(limits) {
        ticks <- pretty(limits); ticks[ticks >= 0 & ticks == floor(ticks)]
      }, expand = ggplot2::expansion(mult = c(.02, .08))) +
      ggplot2::facet_wrap(~Panel, ncol = 1, scales = "free_y") +
      ggplot2::labs(title = "What keeps coming back to rotation?", subtitle = history_note,
        x = "Times selected", y = NULL,
        caption = "Current picks plus the most-selected albums, up to 15 per genre. Panels summarize all albums in each genre. Compare counts within genres; smaller collections repeat more often. Only genres in the latest saved rotation are shown.") + theme +
      ggplot2::theme(panel.grid.major.y = ggplot2::element_blank(),
                     strip.text = ggplot2::element_text(hjust = 0, face = "bold"))
    rotation_height <- max(7, 3 + nrow(rotation_view) * .28 + length(active_genres) * .5)
  } else {
    plots$rotation_coverage <- ggplot2::ggplot() +
      ggplot2::annotate("text", x = 0, y = 0, label = "Generate a rotation to see current picks and repeat counts.", size = 4) +
      ggplot2::labs(title = "What keeps coming back to rotation?", subtitle = history_note,
                    caption = "No albums in the current database match the latest saved rotation.") +
      theme + ggplot2::theme(axis.title = ggplot2::element_blank(), axis.text = ggplot2::element_blank(),
                            panel.grid = ggplot2::element_blank())
    rotation_height <- 7
  }
  # Vector PDFs overwrite only chart files; no input/history writes occur here.
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  for (name in names(plots)) {
    plots[[name]] <- plots[[name]] + ggplot2::labs(caption = paste(strwrap(plots[[name]]$labels$caption, width = 110), collapse = "\n"))
    ggplot2::ggsave(file.path(output_dir, paste0(name, ".pdf")), plots[[name]],
      width = if (name %in% c("moods_by_genre", "rotation_coverage")) 12 else 11,
      height = if (name == "rotation_coverage") rotation_height else if (name == "most_collected_artists") 8 else 7,
      device = grDevices::pdf, bg = "#FAF8F3")
  }
  message("Saved ", length(plots), " plots to ", normalizePath(output_dir))
  invisible(plots)
}
