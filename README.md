# Mid-Atlantic Nature Atlas

Effort-adjusted seasonality of fungi, plants, birds, and insects in Maryland, Pennsylvania,
and DC from iNaturalist data, built with Python (cleaning) and R + Quarto (analysis and site).

## Steps
1. On gbif.org, download the *iNaturalist Research-grade Observations* dataset filtered to
   US, state/province = Maryland, Pennsylvania, District of Columbia. Format: Simple (TSV).
2. Unzip into `data/raw/` so you have `data/raw/occurrence.txt` (or similar).
3. `pip install pandas` then `python scripts/prep_gbif.py data/raw/occurrence.txt`
4. In R: `install.packages(c("tidyverse", "here", "scales", "knitr"))`
5. For the plant phenology page: `install.packages(c("httr2", "lubridate"))` then
   `Rscript scripts/pull_phenology.R` (API pull, expect 10 to 20 minutes at the polite rate limit)
6. `quarto preview` to develop, `quarto render` to build into `docs/`
7. Push to GitHub and set Pages to deploy from the `/docs` folder.

`data/` contents are gitignored (large files).

## Data and attribution
Raw data are not included in this repo. Observations come from iNaturalist via a GBIF
download (research-grade records) and the iNaturalist API. Individual observations carry
their own Creative Commons licenses, and GBIF downloads have a citable DOI: cite yours
here once you have it. Observer names are replaced with a one-way hash in the processed files.

## License
Code is released under the MIT License (see `LICENSE`). The license covers the code, not
the underlying observation data.
