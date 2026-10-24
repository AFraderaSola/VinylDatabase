# Complete README source for this personal project. No package dependencies.
# Edit the title and text below, then source this file to refresh README.md.
project_title <- "VinylDatabase"
project_readme <- r"(
A personal vinyl collection managed in R from one Excel database, with artist-level moods, shelf ordering and a listening rotation.

## Update the collection

Maintain only manual source data in **`input/Database.xlsx`**. The updater never writes results back into it.

Collection has exactly these columns, in order: `DateAddition`, `Artist`, `Album`, `Edition`. The first three are mandatory for every row; `Edition` may be blank. A missing core value or invalid addition date stops the update before lookups or output changes.

Artists has exactly these columns, in order: `Artist`, `Shelf_Band`, `Shelf_Genre`, `Shelf_Mood`. Keep at most one row per artist. This worksheet is the only manual source for `Shelf_Genre` and `Shelf_Mood`. Every used `Shelf_Mood` must contain at least six distinct albums.

### What gets filled when blank

| Field | Behaviour |
|---|---|
| `Shelf_Genre` and `Shelf_Mood` | Uses the Artists worksheet. MusicBrainz tags may provide a provisional suggestion for a blank value, marked `Needs review`. |
| `Year` and `Recording_Type` | Reuses the generated metadata cache, then tries an exact MusicBrainz album match. `Year` is the original release year. |
| `Metadata_Subgenre` | Reuses the cache, then uses MusicBrainz release-group tags. |
| `Shelf_Band` | Uses the editable Artists value or a known band association. See Shelf order below. |
| `Last_Rotation_Date` | Set automatically whenever an album is selected for a generated rotation. |

Generated album metadata is stored in `state/metadata_cache.rds`, keyed by artist and album. Full updates query only missing details and install the cache, workbooks and rotation history as one transaction. Rotation-only runs use the cache without online lookups and do not change it. Missing shelf classification excludes an album from rotation; other missing metadata is reported through `Review_Status`.

MusicBrainz lookups require an internet connection and `httr2`, but no API key. Exact album-title and artist-credit matches are accepted; duplicate exact release groups are resolved deterministically to the oldest album entry. Set `Sys.setenv(VINYL_OFFLINE = "true")` to disable lookups during a full update.

Save and close the database and generated workbooks in Excel, and run from your project R session:

```r
source("01_update_vinyl_database.R")
```

Or run from a terminal in the project folder:

```bash
Rscript --vanilla 01_update_vinyl_database.R
```

The updater activates the project's R environment and creates four files in `output/`, using the input's theme, Arial font and compact layout:

| File | Contents |
|---|---|
| `Vinyl_Collection.xlsx` | Compact collection sorted by artist and release year, with album, edition, recording type and classification fields |
| `Vinyl_Shelf.xlsx` | Permanent shelf order and family shelf placement |
| `Vinyl_OnRotation.xlsx` | Current rotation with shelf fields, selection count and last rotation date |
| `Vinyl_Metadata.xlsx` | Selected album metadata, shelf placement, classification sources, suggestions and rotation details |

## On rotation

A rotation refresh draws a random selection of **five distinct albums per enabled genre**. A normal collection update preserves the current selection and its statistics. By default, only Jazz / Blues and Rock are enabled, giving **10 albums**. Multiple pressings count once, using the album's newest addition date. Rotation uses each artist's own genre and mood, not their band family's shelf section.

Within each genre:

1. Reserve **three slots for recent additions**. Take albums from the newest addition date first; if it has fewer than three, continue to the next newest date until three slots are filled. When a date has more albums than needed, choose randomly within the mood-coverage rule.
2. Fill the other **two slots randomly from all dates not used for those first three**. Exclude each used date entirely, including its unselected albums. These two slots have no date preference.
3. If the unused dates cannot supply two albums, fill the shortage from unselected albums on the used dates, newest first. This also permits five picks when all eligible albums share one date.
4. Within these quotas, prioritize mood coverage only for genre/mood groups containing at least four distinct albums in the collection. Smaller mood groups remain eligible for random selection but receive no coverage bonus. Maximize coverage among the qualifying moods. When all moods cannot fit, choose among equally good combinations at random, then choose albums randomly within each combination.

Date priority takes precedence over mood coverage. Each run excludes albums selected in the previous rotation before applying date quotas. If fewer than five alternatives remain in a genre, reuse only the necessary number of previous picks, preferring lower rotation counts and breaking ties randomly. Energy, danceability and listening history do not affect selection, and the script does not mark albums as played. If a genre has fewer than five classified albums, include all available albums and report the shortage rather than borrowing slots from another genre.

Use `--rotation-only` to redraw rotation and its metadata without changing the collection and permanent shelf files. Use `--refresh-rotation` to redraw it during a full collection update. Without either option, the saved rotation is preserved. The total is calculated as five times the number of enabled genres. The optional `--rotation-size=N` must match that total; normally omit it.

Rotation history is maintained automatically in `state/rotation_history.rds`. Only a successful explicit rotation refresh advances the run number and increments `Rotation_Count` once per selected album, regardless of pressing. `Last_Rotation_Run` identifies the latest selected run and `Last_Rotation_Date` records its generation date. Ordinary collection updates do not change these values. Failed output installation restores previous outputs and generated state.

### Settings when using source()

Edit the settings near the top of `01_update_vinyl_database.R`:

```r
reset_rotation_history <- FALSE
refresh_rotation <- FALSE
rotation_genres <- c(
  "Classical / Soundtrack" = FALSE,
  "Electronic" = FALSE,
  "Jazz / Blues" = TRUE,
  "Pop" = FALSE,
  "Rock" = TRUE
)
```

Then run `source("01_update_vinyl_database.R")`. Leave `refresh_rotation` FALSE for ordinary collection updates. Set it to TRUE only when you want a new selection, then return it to FALSE. Set a genre to TRUE to include it or FALSE to exclude it; at least one must be enabled. Every enabled genre follows the same date quotas, mood threshold and cooldown rules. Disabled genres remain in the collection and permanent shelf, and keep their saved counters.

For a reset, change `reset_rotation_history` to TRUE and source the script. With `refresh_rotation` left FALSE, this clears history for **all genres** and leaves the current rotation empty. Set both toggles to TRUE only when you want to clear the statistics and immediately generate a new run 1. **Change both toggles back to FALSE afterwards.** A failed update leaves saved history intact.

The terminal option remains available:

```bash
Rscript --vanilla 01_update_vinyl_database.R --rotation-only
Rscript --vanilla 01_update_vinyl_database.R --reset-rotation-history
```

Technical details stay in Vinyl_Metadata.xlsx. Collection_Row preserves input order and DateAddition records when the copy entered the collection. Shelf_Group and its genre/mood describe physical family placement; Shelf_Genre and Shelf_Mood remain the individual artist classification used for collection and rotation views, while their Source columns record provenance. Rotation_Reason records the addition date used for the random selection. During rotation-only updates, metadata shelf positions are recalculated, but the saved permanent shelf is not refreshed. Run a full update after changing the collection to keep them aligned.

## Shelf order

The permanent shelf sorts by **`Shelf_Genre` → `Shelf_Mood` → artist family → artist → year**. Shelf fields and artist families sort alphabetically. Within a family, the band comes first, followed by solo artists alphabetically. Leading articles “The”, “El”, “La”, “Los” and “Las” are ignored whenever artist names are matched, grouped, counted or sorted; displayed names remain unchanged. Years sort oldest first, with unknown years last. Unclassified records remain at the end.

Use **Artists → Shelf_Band** to place a solo artist beside their originating band. Every artist in the family shares one shelf genre and mood, chosen separately by the most common value among the family's artists present in the collection. Each artist gets one vote, regardless of album or pressing count; blank values are ignored. Ties favour the originating band's value when it is tied for first place, then alphabetical order. The collection and rotation keep each artist's own classification. For example, Robe follows Extremoduro, and Nick Mason and Roger Waters follow Pink Floyd. The metadata file records both the artist's classification and their shelf section.

Blank Shelf_Band cells use known associations, including Pink Floyd's solo members and Paul McCartney with The Beatles. Enter another band to override this, or the artist's own name to keep them separate. If the band is absent from the collection, the artist keeps their own section. Circular associations are rejected.

Each artist has one `Shelf_Mood`, shared by all their albums: Groovy, Immersive, Intense, Intimate, Melancholic, Reflective or Warm. Each shelf mood must contain at least six distinct albums across the collection; different pressings count once. `Metadata_Subgenre` can vary by album.

Moods are subjective artist-level listening choices, not measurements from audio or lyrics. Saved choices in Artists take precedence. For new artists, specific MusicBrainz tags provide a provisional suggestion marked Needs review; a broad genre alone is not enough. Progressive rock suggests Immersive, while Pop alone does not imply Groovy.

- **Groovy:** driven by rhythm, swing or a dance pulse.
- **Immersive:** expansive, atmospheric or absorbing.
- **Intense:** forceful, urgent or hard-driving.
- **Intimate:** close, personal or understated.
- **Melancholic:** wistful, sombre or sorrowful.
- **Reflective:** thoughtful or contemplative.
- **Warm:** relaxed, welcoming or soulful.

## Collection plots

Run `source("02_plot_vinyl_database.R")` to refresh six numbered PDF charts directly in `output/`. Their `Vinyl_01_` through `Vinyl_06_` prefixes keep them in the logical order shown below. This is independent of the updater: it reads the manual input, generated metadata cache and saved rotation history without making online requests, selecting a new rotation, or changing counters.

- **Collection by genre:** distinct album counts using each artist's classification.
- **Moods by genre:** album counts for every genre/mood combination.
- **Collection growth:** cumulative albums by first addition date; multiple pressings count once.
- **Release decades:** original release years, excluding unknown years.
- **Most-collected artists:** the top 15, with alphabetical tie-breaking.
- **Rotation coverage:** a ranked dot plot of current picks and the most-selected albums (up to 15 per genre), highlighting the current rotation. Each panel summarizes how many albums have never rotated. Only genres represented in the latest saved rotation and still present in the database are shown; changing the genre toggles alone does not change this chart. Compare counts within each genre.

Charts use ggplot2 and [MetBrewer](https://github.com/BlakeRMills/MetBrewer): five Archambault swatches without yellow or orange, reversed (direction -1), for genre colours (Classical / Soundtrack brick red, Electronic coral, Jazz / Blues plum, Pop deep purple, Rock blue) and Hokusai2 for the mood-count heatmap. Zero-count heatmap cells are gray. Run a full update to refresh missing cached metadata before plotting. A single addition date produces one growth point, not an inferred purchasing history.

## Project setup and folders

Open this repository as your R project. Its `.Rprofile` activates `renv`. Restore the vinyl packages once in the project R console:

```r
renv::restore(packages = c("readxl", "openxlsx", "zip", "xml2", "httr2", "ggplot2", "MetBrewer"))
```

The updater uses R only. The input database, generated Excel/PDF outputs and generated state are tracked so collection results remain reproducible across machines. Local environments and personal settings stay outside Git.

```text
input/Database.xlsx           Your collection and artist settings
output/                      Generated Excel files and numbered Vinyl PDF charts
state/metadata_cache.rds      Automatically maintained album metadata
state/rotation_history.rds    Automatically maintained rotation counts and dates
R/vinyl_workflow.R            Collection, shelf and rotation functions
R/vinyl_plots.R               ggplot charts
01_update_vinyl_database.R    Run the update
02_plot_vinyl_database.R      Refresh charts without changing rotation
renv.lock, renv/              R package environment
.EditREADME.R                 Source for this README
README.md                    Generated project guide
```

The updater treats the input workbook as read-only and creates no automatic backups. Commit the input database, generated outputs and both state files together so metadata, shelf views, plots and rotation history remain synchronized across machines.

## Edit this README

Edit `project_title` and `project_readme` in `.EditREADME.R`, then run `source(".EditREADME.R")` from the project folder. That file contains the complete project guide and regenerates `README.md`; direct edits to the generated README are replaced.
)"

# Resolve the project directory when sourced or run with Rscript.
script <- tryCatch(sys.frame(1)$ofile, error = function(e) NULL)
if (is.null(script)) {
  flag <- grep("^--file=", commandArgs(), value = TRUE)
  script <- if (length(flag)) sub("^--file=", "", flag[[1]]) else NULL
}
root <- if (is.null(script)) "." else dirname(normalizePath(script))
body <- strsplit(project_readme, "\n", fixed = TRUE)[[1]]
while (length(body) && !nzchar(body[[1]])) {
  body <- body[-1]
}
while (length(body) && !nzchar(body[[length(body)]])) {
  body <- body[-length(body)]
}
readme <- c(
  "<!-- AUTO-GEN:PROJECT_TITLE:START -->",
  paste0("# ", project_title),
  "<!-- AUTO-GEN:PROJECT_TITLE:END -->",
  "",
  "<!-- AUTO-GEN:PROJECT_README:START -->",
  body,
  "<!-- AUTO-GEN:PROJECT_README:END -->"
)
writeLines(enc2utf8(readme), file.path(root, "README.md"), useBytes = TRUE)
message("README.md updated.")
