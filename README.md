<!-- AUTO-GEN:PROJECT_TITLE:START -->
# VinylDatabase
<!-- AUTO-GEN:PROJECT_TITLE:END -->

A personal vinyl collection managed in R from one Excel database, with artist-level moods, shelf ordering and a listening rotation.

## Organizing the collection

The permanent shelf sorts by **genre → mood → artist → year**. The four broad genres are Electronic, Rock, Jazz / Blues, and Classical / Soundtrack.

Each artist has one mood, shared by all their albums. Each mood must contain at least six distinct albums; different pressings count once. Subgenres can vary by album.

## Updating the collection

Maintain the Excel database: add records and album details in **Collection**, and set moods and classification defaults in **Artists**. Update `Last_Played` after listening to help refresh the rotation.

The collection list, shelf order and listening rotation are generated from that database.

## Editing this README

Edit this file directly. `.EditREADME.R` only refreshes the project title or creates this starter text when the README is missing.
