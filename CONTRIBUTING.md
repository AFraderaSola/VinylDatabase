# Contributing

Thank you for contributing to this scientific analysis repository.

## Repository workflow

- Work from the repository root unless a script explicitly documents another working directory.
- Keep analysis scripts in the corresponding analysis folders.
- Preserve the established Input and Output folder conventions.
- Do not commit temporary, cache, or machine-specific files.
- Do not redistribute controlled or patient-linked data.

## Project startup

The tracked `.Rprofile` activates the project-specific `renv` library, loads
shared functions from `R/project_setup.R`, and then loads optional local
settings.

Machine-specific paths and preferences belong in `.Rprofile.local.R`, which is
ignored by Git. Analysis scripts must source shared project functions directly:

```r
source("R/project_setup.R")
```

## R dependencies

Restore the recorded R environment with:

```r
renv::restore()
```

After intentionally adding or updating a package, update the lockfile:

```r
renv::snapshot()
```

Commit `renv.lock` whenever shared R dependencies change.

## Python dependencies

Create the recorded Conda environment with:

```bash
conda env create -f python/environment.yml
```

Update `python/environment.yml` whenever shared Python dependencies change.

## Data and outputs

- Treat raw and patient-linked data according to the applicable access restrictions.
- Do not modify raw data unless the change is intentional and documented.
- Review large reports before committing them to avoid accidental duplicates.
- Preserve intentionally empty project directories with `.gitkeep`.
- Keep generated outputs beside the scripts and inputs defined by the existing project structure.

## README updates

After changing the project structure, analysis progress, contributor history, or
project metadata, regenerate the README:

```r
source(".EditREADME.R")
```

When generator configuration changes, commit both `.EditREADME.R` and the
regenerated `README.md`.

## Before committing

Confirm that:

- Modified scripts parse without errors.
- New dependencies are recorded.
- `.Rprofile.local.R` and cache files remain untracked.
- The README is current.
- No controlled data or unintended large files have been added.
- The automated repository checks pass.

## Commit messages

Use a concise, action-oriented title, for example:

```text
Update plasma preprocessing workflow
```

Use the commit description to explain why the change was needed and identify
important effects on data, results, figures, or reproducibility.

## Automated checks

GitLab validates R syntax, repository hygiene, environment consistency, and
README integrity. All checks should pass before changes are merged into the
main branch.

