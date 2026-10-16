# Contributing to VinylDatabase

This is a personal vinyl collection managed from `input/Database.xlsx`.

## Collection changes

- Keep Collection columns in this exact order: DateAddition, Artist, Album, Edition. The first three are mandatory.
- Keep Artists columns in this exact order: Artist, Shelf_Band, Shelf_Genre, Shelf_Mood, with one row per artist.
- Keep Shelf_Genre and Shelf_Mood only in Artists. Use Shelf_Band to group solo artists with their band.
- Do not add generated metadata columns to the input workbook. Close Excel before running the updater.

## Script changes

Use the project's R environment and restore dependencies with `renv::restore()` when needed. Run `source("01_update_vinyl_database.R")` from R or `Rscript --vanilla 01_update_vinyl_database.R` from the project folder. Set `VINYL_OFFLINE=true` to disable MusicBrainz lookups.

Document reusable functions with concise roxygen2 blocks that describe parameters, return values and side effects. Use ordinary inline comments for implementation decisions and invariants rather than narrating obvious statements.

Before committing, check that the updater leaves the input workbook unchanged, updates `state/metadata_cache.rds` only during full updates, and keeps shelf grouping correct. Ordinary full updates must preserve the current rotation and its counters. Check rotation-only changes leave the input, metadata cache, collection output and shelf output untouched. An explicit rotation refresh draws five albums per enabled shelf genre, follows newest-first date quotas, maximizes shelf-mood coverage, and updates Last_Rotation_Date. Generated outputs, local settings and package libraries stay outside Git.

Edit `.EditREADME.R` to update the guide, then regenerate README.md. Commit both files, relevant script changes, the input database and both state files to preserve metadata and rotation history. Update renv.lock if dependencies change. Use a short commit message describing the actual change.
