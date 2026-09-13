# Contributing to VinylDatabase

This is a personal vinyl collection managed from `input/Database.xlsx`.

## Collection changes

- Add records in Collection with Artist, Album and DateAddition; all three are mandatory. Fill in any other details you know.
- Set each artist's genre and mood in Artists. Each mood needs at least six distinct albums; different pressings count once.
- Use Shelf_Band to group solo artists with their band. The family shares a shelf genre and mood by artist majority; collection classifications stay individual.
- Update Last_Played after listening. Confirm Discogs IDs only after checking the exact release or master.
- Keep worksheet names and column headers intact. Close Excel before running the updater.

## Script changes

Use the project's R environment and restore dependencies with `renv::restore()` when needed. Run `source("01_update_vinyl_database.R")` from R or `Rscript --vanilla 01_update_vinyl_database.R` from the project folder. Set `VINYL_OFFLINE=true` to disable MusicBrainz lookups. Leave DISCOGS_TOKEN unset to avoid Discogs requests during checks.

Before committing, check that the updater runs, the input remains unchanged, and the shelf still groups artists correctly. Check rotation-only changes leave the collection and shelf outputs untouched. Rotation draws five albums per enabled genre, follows newest-first date quotas, and maximizes mood coverage with random choices. Generated outputs, local settings and package libraries stay outside Git.

Edit `.EditREADME.R` to update the guide, then regenerate README.md. Commit both files, relevant script changes, the updated input database and state/rotation_history.rds to preserve rotation counts. Update renv.lock if dependencies change. Use a short commit message describing the actual change.
