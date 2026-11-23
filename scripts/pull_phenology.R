# Pull plant phenology annotations from the iNaturalist API for a short list of
# species in Maryland, Pennsylvania, and DC. This is a small job (a few hundred
# requests), which is the kind of use the API is meant for.
#
# Usage, from the repo root:
#   Rscript scripts/pull_phenology.R            # skips if the output already exists
#   Rscript scripts/pull_phenology.R --refresh  # pull again
#
# Needs: install.packages(c("httr2", "dplyr", "purrr", "tibble", "readr"))

suppressPackageStartupMessages({
  library(httr2)
  library(dplyr)
  library(purrr)
  library(tibble)
  library(readr)
})

API   <- "https://api.inaturalist.org/v1"
UA    <- "mid-atlantic-atlas/0.1 (personal portfolio project)"
OUT   <- file.path("data", "processed", "phenology_annotations.csv")
PAUSE <- 1.1   # seconds between calls; the API asks for about 1 request/sec

`%||%` <- function(x, y) if (is.null(x)) y else x

if (file.exists(OUT) && !("--refresh" %in% commandArgs(trailingOnly = TRUE))) {
  message("Output exists: ", OUT, " (use --refresh to pull again)")
  quit(save = "no")
}

species <- tribble(
  ~name,                          ~status,
  "Claytonia virginica",          "native",
  "Sanguinaria canadensis",       "native",
  "Mertensia virginica",          "native",
  "Cercis canadensis",            "native",
  "Cornus florida",               "native",
  "Asclepias syriaca",            "native",
  "Rudbeckia hirta",              "native",
  "Solidago canadensis",          "native",
  "Symphyotrichum novae-angliae", "native",
  "Alliaria petiolata",           "invasive",
  "Ficaria verna",                "invasive",
  "Lonicera japonica",            "invasive",
  "Daucus carota",                "introduced",
  "Taraxacum officinale",         "introduced"
)
states <- c("Maryland", "Pennsylvania", "District of Columbia")

api_get <- function(path, query = list()) {
  Sys.sleep(PAUSE)
  request(paste0(API, "/", path)) |>
    req_url_query(!!!query) |>
    req_user_agent(UA) |>
    req_retry(max_tries = 5,
              is_transient = \(r) resp_status(r) %in% c(429, 500, 502, 503, 504)) |>
    req_perform() |>
    resp_body_json()
}

resolve_place <- function(name) {
  res <- api_get("places/autocomplete", list(q = name))$results
  exact <- keep(res, \(p) identical(p$name, name))
  state_level <- keep(exact, \(p) isTRUE(p$admin_level == 10))
  hit <- if (length(state_level)) state_level else exact
  if (!length(hit)) stop("Could not find place: ", name)
  message("Place: ", hit[[1]]$display_name, " (id ", hit[[1]]$id, ")")
  hit[[1]]$id
}

resolve_taxon <- function(name) {
  res <- api_get("taxa/autocomplete", list(q = name, per_page = 10))$results
  hit <- keep(res, \(t) identical(tolower(t$name), tolower(name)))
  if (!length(hit)) {
    message("No exact match for ", name, "; skipping")
    return(NULL)
  }
  list(id = hit[[1]]$id, common = hit[[1]]$preferred_common_name %||% NA_character_)
}

# Find the plant phenology annotation term instead of hardcoding its ID
terms <- api_get("controlled_terms")$results
pheno <- keep(terms, \(t) grepl("Phenology", t$label))
if (!length(pheno)) stop("Could not find a phenology controlled term")
term_id <- pheno[[1]]$id
message("Annotation term: ", pheno[[1]]$label, " (id ", term_id, ")")

parse_obs <- function(o) {
  anns <- keep(o$annotations %||% list(), \(a) {
    isTRUE(a$controlled_attribute$id == term_id) && (a$vote_score %||% 0) >= 0
  })
  if (!length(anns)) return(NULL)
  tibble(
    inat_id     = o$id,
    observed_on = o$observed_on %||% NA_character_,
    phenophase  = map_chr(anns, \(a) a$controlled_value$label)
  )
}

pull_one <- function(taxon_id, place_id) {
  rows <- list()
  last_id <- 0
  repeat {
    d <- api_get("observations", list(
      taxon_id = taxon_id, place_id = place_id, term_id = term_id,
      verifiable = "true", order_by = "id", order = "asc",
      id_above = last_id, per_page = 200
    ))
    res <- d$results
    if (!length(res)) break
    rows <- c(rows, map(res, parse_obs))
    last_id <- res[[length(res)]]$id
    if (length(res) < 200) break
  }
  bind_rows(rows)
}

place_ids <- set_names(map_int(states, resolve_place), states)

out <- list()
for (i in seq_len(nrow(species))) {
  tx <- resolve_taxon(species$name[i])
  if (is.null(tx)) next
  for (st in states) {
    message(species$name[i], " / ", st)
    d <- pull_one(tx$id, place_ids[[st]])
    if (nrow(d)) {
      out[[length(out) + 1]] <- d |>
        mutate(species = species$name[i], common_name = tx$common,
               status = species$status[i], state = st)
    }
  }
}

result <- bind_rows(out)
dir.create(dirname(OUT), showWarnings = FALSE, recursive = TRUE)
write_csv(result, OUT)
message("Wrote ", nrow(result), " annotated observations to ", OUT)
