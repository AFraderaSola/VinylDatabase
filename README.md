<!-- AUTO-GEN:PROJECT_TITLE:START -->
# VinylDatabase
<!-- AUTO-GEN:PROJECT_TITLE:END -->

<!-- AUTO-GEN:PROJECT_README:START -->
A personal vinyl collection managed in R from one Excel database, with artist-level moods, shelf ordering and a listening rotation.

## Update the collection

Maintain collection data in **`input/Database.xlsx`**, with its Collection and Artists worksheets. Rotation toggles live at the top of `01_update_vinyl_database.R`; history is maintained automatically.

**Minimum for every record:** enter `Artist`, `Album` and `DateAddition` in Collection. All three are mandatory. A missing or invalid addition date stops the update before lookups or output changes; dates are never invented. For example: `Parcels`, `Day/Night`, `2026-09-13`.

In Artists, keep one row per artist with your chosen `Genre` and `Mood`. An existing artist's choices apply to every album and override Collection values. For a new artist, you can add the artist here, supply Genre and an optional Mood column in Collection, or leave classification blank for a provisional suggestion. Conflicting values without an Artists choice stop the update. Every used mood must contain at least six distinct albums.

### What gets filled when blank

| Field | Behaviour |
|---|---|
| Genre and Mood | Uses the artist's saved choices, then supplied Collection values. Otherwise, artist tags from an unambiguous MusicBrainz match may suggest a classification, marked Needs review. No useful match means it stays blank. |
| Year and Recording_Type | Reuses an existing entry for the same artist and album, then tries MusicBrainz. Year is the original release year; Recording_Type may be Studio, Live or Compilation from that match. |
| Subgenre | Reuses the same album's value, then the artist default, then MusicBrainz release tags. |
| Shelf_Band | Uses the editable Artists value or a known band association. See Shelf order below. |
| Edition, Year_Pressing, notes and Discogs identifiers | Not guessed. Enter these yourself when known. |
| Last_Played | Enter after listening. For multiple pressings of the same album, the latest supplied date applies to all of them. Selecting a rotation does not mark anything played. |

Album-level subgenre takes precedence over the artist default. Filled album details are preserved. Missing genre, mood, year, subgenre or recording type sets `Review_Status` to Needs review. Missing genre or mood excludes an album from rotation; other optional missing details do not. Mandatory fields are always validated first. Shelf placement uses the family rules below, with unresolved shelf sections placed last.

**Autofilled values appear only in outputs.** The input is never rewritten. Copy useful results back into the input if you want them saved for later runs; save accepted genre and mood suggestions in Artists.

Collection columns start with Artist, Album, Year and Edition, followed by Genre, Subgenre, Recording_Type and DateAddition. Discogs fields are grouped next, followed by the remaining details. Column names matter; their positions do not. Keep worksheet names and headers intact. Dates may be Excel dates, `YYYY-MM-DD`, or older `YYYYMMDD` entries.

MusicBrainz lookups require an internet connection and `httr2`, but no API key. Only an unambiguous artist-and-album match is accepted. Set `Sys.setenv(VINYL_OFFLINE = "true")` to disable MusicBrainz lookups; supplied values and artist defaults still work. Discogs requests are separately controlled by confirmed IDs and a token, as described below.

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
| `VinylCollection_completed.xlsx` | Everyday collection list: artist, album, year, edition, genre, mood, subgenre, addition date and last played |
| `VinylShelf_Permanent.xlsx` | Shelf reference: position, genre, mood, artist, album, year and edition |
| `Vinyl_On_Rotation.xlsx` | Listening list: position, artist, album, year, genre, mood, edition and last played |
| `Vinyl_Metadata.xlsx` | Full details, review flags, notes, MusicBrainz/Discogs sources and rotation reasons |

## On rotation

Each run draws a fresh random selection of **five distinct albums per enabled genre**. By default, only Jazz / Blues and Rock are enabled, giving **10 albums**. Multiple pressings count once, using the album's newest addition date. Rotation uses each artist's own genre and mood, not their band family's shelf section.

Within each genre:

1. Reserve **three slots for recent additions**. Take albums from the newest addition date first; if it has fewer than three, continue to the next newest date until three slots are filled. When a date has more albums than needed, choose randomly within the mood-coverage rule.
2. Fill the other **two slots randomly from all dates not used for those first three**. Exclude each used date entirely, including its unselected albums. These two slots have no date preference.
3. If the unused dates cannot supply two albums, fill the shortage from unselected albums on the used dates, newest first. This also permits five picks when all eligible albums share one date.
4. Within these quotas, prioritize mood coverage only for genre/mood groups containing at least four distinct albums in the collection. Smaller mood groups remain eligible for random selection but receive no coverage bonus. Maximize coverage among the qualifying moods. When all moods cannot fit, choose among equally good combinations at random, then choose albums randomly within each combination.

Date priority takes precedence over mood coverage. Each run excludes albums selected in the previous rotation before applying date quotas. If fewer than five alternatives remain in a genre, reuse only the necessary number of previous picks, preferring lower rotation counts and breaking ties randomly. Energy, danceability and listening history do not affect selection, and the script does not mark albums as played. If a genre has fewer than five classified albums, include all available albums and report the shortage rather than borrowing slots from another genre.

Use `--rotation-only` to redraw rotation and its metadata without changing the collection and permanent shelf files. The total is calculated as five times the number of enabled genres. The optional `--rotation-size=N` must match that total; normally omit it.

Rotation history is maintained automatically in `state/rotation_history.rds`. Each successful update, including `--rotation-only`, advances the run number and increments Rotation_Count once per selected album, regardless of pressing. Last_Rotation_Run records its latest selected run; both columns appear in metadata. The first run seeds history from the existing rotation file, counting those albums once; earlier rotations cannot be reconstructed. Keep the state file (and commit it with the database) to preserve history across machines. If it is deleted, the next run seeds new history from the existing rotation file. Use the reset toggle for a complete reset. History does not modify the input or Last_Played. Failed output installation restores previous outputs and history.

### Settings when using source()

Edit the settings near the top of `01_update_vinyl_database.R`:

```r
reset_rotation_history <- FALSE
rotation_genres <- c(
  "Classical / Soundtrack" = FALSE,
  "Electronic" = FALSE,
  "Jazz / Blues" = TRUE,
  "Pop" = FALSE,
  "Rock" = TRUE
)
```

Then run `source("01_update_vinyl_database.R")`. Set a genre to TRUE to include it or FALSE to exclude it; at least one must be enabled. Every enabled genre follows the same date quotas, mood threshold and cooldown rules. Disabled genres remain in the collection and permanent shelf, and keep their saved counters.

For a reset, change `reset_rotation_history` to TRUE and source the script. Reset clears history for **all genres**, ignores the previous rotation file and generates run 1 for the enabled genres. Selected albums get count 1 and the others count 0. **Change the toggle back to FALSE afterwards**, or subsequent runs will reset again. A failed update leaves saved history intact.

The terminal option remains available:

```bash
Rscript --vanilla 01_update_vinyl_database.R --rotation-only --reset-rotation-history
```

Technical details stay in Vinyl_Metadata.xlsx. Collection_Row identifies the input record, Shelf_Order links to the permanent shelf, and Rotation_Reason records the addition date used for the random selection. During rotation-only updates, metadata shelf positions are recalculated, but the saved permanent shelf is not refreshed. Run a full update after changing the collection to keep them aligned.

## Shelf order

The permanent shelf sorts by **genre → mood → artist family → artist → year**. Genre, mood and artist families each sort alphabetically. Within a family, the band comes first, followed by solo artists alphabetically. The genre order is Classical / Soundtrack, Electronic, Jazz / Blues, Pop, Rock. A leading “The” is ignored in artist names; years sort oldest first, with unknown years last. Album titles and editions sort alphabetically when years are equal. Unclassified records remain at the end.

Use **Artists → Shelf_Band** to place a solo artist beside their originating band. Every artist in the family shares one shelf genre and mood, chosen separately by the most common value among the family's artists present in the collection. Each artist gets one vote, regardless of album or pressing count; blank values are ignored. Ties favour the originating band's value when it is tied for first place, then alphabetical order. The collection and rotation keep each artist's own classification. For example, Robe follows Extremoduro, and Nick Mason and Roger Waters follow Pink Floyd. The metadata file records both the artist's classification and their shelf section.

Blank Shelf_Band cells use known associations, including Pink Floyd's solo members and Paul McCartney with The Beatles. Enter another band to override this, or the artist's own name to keep them separate. If the band is absent from the collection, the artist keeps their own section. Circular associations are rejected.

Each artist has one mood, shared by all their albums: Groovy, Immersive, Intense, Intimate, Melancholic, Reflective or Warm. Each mood must contain at least six distinct albums across the collection; different pressings count once. Subgenres can vary by album.

Moods are subjective artist-level listening choices, not measurements from audio or lyrics. Saved choices in Artists take precedence. For new artists, specific MusicBrainz tags provide a provisional suggestion marked Needs review; a broad genre alone is not enough. Progressive rock suggests Immersive, while Pop alone does not imply Groovy.

- **Groovy:** driven by rhythm, swing or a dance pulse.
- **Immersive:** expansive, atmospheric or absorbing.
- **Intense:** forceful, urgent or hard-driving.
- **Intimate:** close, personal or understated.
- **Melancholic:** wistful, sombre or sorrowful.
- **Reflective:** thoughtful or contemplative.
- **Warm:** relaxed, welcoming or soulful.

## Collection plots

Run `source("02_plot_vinyl_database.R")` to refresh six PDF charts in `output/plots/`. This is independent of the updater: it reads the current input and saved rotation history without online requests, selecting a new rotation or changing counters.

- **Collection by genre:** distinct album counts using each artist's classification.
- **Moods by genre:** album counts for every genre/mood combination.
- **Collection growth:** cumulative albums by first addition date; multiple pressings count once.
- **Release decades:** original release years, excluding unknown years.
- **Most-collected artists:** the top 15, with alphabetical tie-breaking.
- **Rotation coverage:** a ranked dot plot of current picks and the most-selected albums (up to 15 per genre), highlighting the current rotation. Each panel summarizes how many albums have never rotated. Only genres represented in the latest saved rotation and still present in the database are shown; changing the genre toggles alone does not change this chart. Compare counts within each genre.

Charts use ggplot2 and [MetBrewer](https://github.com/BlakeRMills/MetBrewer): five Archambault swatches without yellow or orange, reversed (direction -1), for genre colours (Classical / Soundtrack brick red, Electronic coral, Jazz / Blues plum, Pop deep purple, Rock blue) and Hokusai2 for the mood-count heatmap. They use saved input details and artist defaults; refresh and save missing details in the database if you want them reflected in the plots. A single addition date produces one growth point, not an inferred purchasing history.

## Project setup and folders

Open this repository as your R project. Its `.Rprofile` activates `renv`. Restore the vinyl packages once in the project R console:

```r
renv::restore(packages = c("readxl", "openxlsx", "zip", "xml2", "httr2", "ggplot2", "MetBrewer"))
```

The updater uses R only. Generated outputs, local environments and personal settings stay outside Git; `input/Database.xlsx` is tracked.

```text
input/Database.xlsx           Your collection and artist settings
output/                      Generated Excel files and plots/ PDFs
state/rotation_history.rds    Automatically maintained rotation counts
R/vinyl_workflow.R            Collection, shelf and rotation functions
R/vinyl_plots.R               ggplot charts
01_update_vinyl_database.R    Run the update
02_plot_vinyl_database.R      Refresh charts without changing rotation
renv.lock, renv/              R package environment
.EditREADME.R                 Source for this README
README.md                    Generated project guide
```

The updater leaves the input workbook unchanged and creates no automatic backups. Commit the database to Git when you want to save a version.

## Discogs flags and optional details

- **Discogs_Flagged:** a review reminder. Set TRUE yourself when a record needs checking. In the output, the script also sets it TRUE if the original release year is still missing after autofill. A supplied TRUE stays TRUE even if the year is found; clear it in the input when resolved. It does not search Discogs, confirm a match, exclude a record from rotation, or alter its classification.
- **Discogs_ID and Discogs_Entity:** enter a verified numeric ID and either `release` for a specific edition or `master` for an album's master entry. These are not discovered automatically.
- **Discogs_Confirmed:** set TRUE only after checking that the ID matches. A confirmed row requires a valid numeric ID and entity. The output then includes its Discogs link. Discogs_Flagged and Discogs_Confirmed are independent.
- **DISCOGS_TOKEN:** with this environment variable set and `httr2` installed, confirmed IDs are used to fetch Discogs genre/style tags into the metadata output. Without a token, no Discogs API request is made. These tags never replace your genre, mood, year or other saved fields.
- **Discogs_Notes:** your own notes about identification or edition details.

Blank flags are treated as FALSE. Missing fields other than the year are covered by Review_Status, so Discogs_Flagged is not a general completeness check.

## Edit this README

Edit `project_title` and `project_readme` in `.EditREADME.R`, then run `source(".EditREADME.R")` from the project folder. That file contains the complete project guide and regenerates `README.md`; direct edits to the generated README are replaced.
<!-- AUTO-GEN:PROJECT_README:END -->
