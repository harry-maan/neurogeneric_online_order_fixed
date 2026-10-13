# ---- Pure functions (no Shiny) so they can be unit-tested and reused ----------------------------------------------
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0 || (length(a) == 1 && is.na(a))) b else a

inr <- function(x) paste0("\u20b9", formatC(x, format = "f", digits = 0, big.mark = ","))

haversine_km <- function(lat1, lon1, lat2, lon2) {
  r <- 6371; p <- pi / 180
  a <- sin((lat2 - lat1) * p / 2)^2 + cos(lat1 * p) * cos(lat2 * p) * sin((lon2 - lon1) * p / 2)^2
  2 * r * asin(pmin(1, sqrt(a)))
}

## ---- Image quality gate ---------------------------------------------------------------------------------------
# Variance of the Laplacian on an 800px-wide grayscale copy: low variance = few sharp edges = blurry.
blur_score <- function(path) {
  img <- magick::image_read(path) |> magick::image_orient() |>
    magick::image_resize("800x") |> magick::image_convert(colorspace = "gray")
  d <- magick::image_data(img, channels = "gray")
  m <- matrix(as.integer(d[1, , ]), nrow = dim(d)[2], ncol = dim(d)[3])  # width x height
  h <- ncol(m); w <- nrow(m)
  lap <- -4 * m[2:(w-1), 2:(h-1)] + m[1:(w-2), 2:(h-1)] + m[3:w, 2:(h-1)] + m[2:(w-1), 1:(h-2)] + m[2:(w-1), 3:h]
  stats::var(as.numeric(lap))
}
is_blurry <- function(path, thr = BLUR_THRESHOLD) {
  s <- blur_score(path); list(score = s, blurry = s < thr)
}

## ---- OCR (Tesseract). Works on printed text; handwriting needs a vision LLM instead (see README) ----------------
ocr_image <- function(path) {
  if (!requireNamespace("tesseract", quietly = TRUE)) stop("Package 'tesseract' is not installed.")
  img <- magick::image_read(path) |> magick::image_orient() |> magick::image_resize("1600x") |>
    magick::image_convert(colorspace = "gray") |> magick::image_normalize() |> magick::image_contrast(sharpen = 1)
  tmp <- tempfile(fileext = ".png"); magick::image_write(img, tmp)
  tesseract::ocr(tmp)
}

## ---- Drug-name matching (deterministic, no training -> nothing to over-fit except 2 documented thresholds) --------
build_aliases <- function(drugs) {
  stop_words <- c("sodium")
  rows <- lapply(seq_len(nrow(drugs)), function(i) {
    g <- strsplit(tolower(drugs$generic_name[i]), "\\s+")[[1]]
    a <- unique(c(tolower(drugs$brand_name[i]), g[!g %in% stop_words]))
    a <- a[nchar(a) >= 4]
    data.frame(alias = a, drug_id = drugs$drug_id[i], stringsAsFactors = FALSE)
  })
  do.call(rbind, rows)
}

.empty_match <- function() data.frame(drug_id = character(), token = character(), alias = character(), score = numeric(), stringsAsFactors = FALSE)

match_drugs <- function(text, aliases, thr = MATCH_THRESHOLD) {
  text <- text %||% ""
  tokens <- unique(unlist(strsplit(tolower(gsub("[^a-zA-Z ]", " ", text)), "\\s+")))
  tokens <- tokens[nchar(tokens) >= 4]
  if (!length(tokens)) return(.empty_match())
  hits <- lapply(tokens, function(tk) {
    s <- stringdist::stringsim(tk, aliases$alias, method = "osa")   # 1 - edit distance / max length
    i <- which.max(s)
    if (s[i] >= thr) data.frame(drug_id = aliases$drug_id[i], token = tk, alias = aliases$alias[i],
                                score = round(s[i], 3), stringsAsFactors = FALSE)
  })
  hits <- do.call(rbind, hits)
  if (is.null(hits)) return(.empty_match())
  hits <- hits[order(-hits$score), ]
  hits[!duplicated(hits$drug_id), ]
}

## ---- Optional LLM extraction (opt-in; sends OCR TEXT ONLY to the API). Output is re-validated against the catalogue
llm_extract_drugs <- function(text, api_key = Sys.getenv("ANTHROPIC_API_KEY"),
                              model = Sys.getenv("LLM_MODEL", "claude-sonnet-5-5")) {
  if (!nzchar(api_key) || !nzchar(text %||% "")) return(NULL)
  sys <- paste("You extract medicine names (brand or generic) from OCR text of a prescription.",
               "Return ONLY a JSON array of strings. Never add names that are not present in the text.",
               "Fix an OCR typo only when you are confident. Ignore doses, doctor names and instructions.")
  req <- httr2::request("https://api.anthropic.com/v1/messages") |>
    httr2::req_headers(`x-api-key` = api_key, `anthropic-version` = "2023-06-01") |>
    httr2::req_body_json(list(model = model, max_tokens = 400, system = sys,
                              messages = list(list(role = "user", content = text)))) |>
    httr2::req_timeout(20)
  resp <- tryCatch(httr2::req_perform(req), error = function(e) NULL)
  if (is.null(resp)) return(NULL)
  txt <- tryCatch(httr2::resp_body_json(resp)$content[[1]]$text, error = function(e) NULL)
  if (is.null(txt)) return(NULL)
  tryCatch(as.character(jsonlite::fromJSON(gsub("```json|```", "", txt))), error = function(e) NULL)
}

detect_drugs <- function(text, aliases, thr = MATCH_THRESHOLD, use_llm = FALSE) {
  fuzzy <- match_drugs(text, aliases, thr)
  if (!use_llm) { fuzzy$source <- if (nrow(fuzzy)) "fuzzy" else character(); return(fuzzy) }
  llm <- llm_extract_drugs(text)
  if (is.null(llm)) { fuzzy$source <- if (nrow(fuzzy)) "fuzzy (LLM unavailable)" else character(); return(fuzzy) }
  llm_m <- match_drugs(paste(llm, collapse = " "), aliases, thr)       # anti-hallucination: must exist in catalogue
  all <- rbind(fuzzy, llm_m); all <- all[order(-all$score), ]; all <- all[!duplicated(all$drug_id), ]
  all$source <- ifelse(all$drug_id %in% fuzzy$drug_id & all$drug_id %in% llm_m$drug_id, "fuzzy + LLM",
                ifelse(all$drug_id %in% llm_m$drug_id, "LLM", "fuzzy"))
  all
}

## ---- Store ranking + savings ----------------------------------------------------------------------------------
# qty: named numeric vector (drug_id -> packs). A drug counts as "available" only if stock >= packs wanted.
rank_stores <- function(inv, stores, drugs, ids, qty, lat, lon) {
  ids <- unique(ids); if (!length(ids)) return(NULL)
  q <- data.frame(drug_id = ids, packs = as.numeric(qty[ids] %||% 1), stringsAsFactors = FALSE)
  q$packs[is.na(q$packs)] <- 1
  x <- merge(merge(inv[inv$drug_id %in% ids, ], q, by = "drug_id"), drugs[, c("drug_id", "brand_mrp_inr")], by = "drug_id")
  x$ok <- x$stock_packs >= x$packs
  agg <- do.call(rbind, lapply(split(x, x$store_id), function(d) {
    d <- d[d$ok, ]
    data.frame(store_id = d$store_id[1] %||% NA, n_available = nrow(d),
               generic_cost = sum(d$generic_price_inr * d$packs),
               brand_cost = sum(d$brand_mrp_inr * d$packs), stringsAsFactors = FALSE)
  }))
  agg <- agg[!is.na(agg$store_id), , drop = FALSE]
  out <- merge(stores, agg, by = "store_id", all.x = TRUE)
  out$n_available[is.na(out$n_available)] <- 0; out$generic_cost[is.na(out$generic_cost)] <- 0; out$brand_cost[is.na(out$brand_cost)] <- 0
  out$n_requested <- length(ids)
  out$saving <- out$brand_cost - out$generic_cost
  out$saving_pct <- ifelse(out$brand_cost > 0, 100 * out$saving / out$brand_cost, 0)
  out$distance_km <- round(haversine_km(lat, lon, out$lat, out$lon), 1)
  out[order(-out$n_available, out$distance_km), ]       # most complete basket first, then nearest
}

store_basket <- function(inv, drugs, store_id, ids, qty) {
  b <- drugs[drugs$drug_id %in% ids, c("drug_id", "brand_name", "generic_name", "strength", "pack_size", "brand_mrp_inr")]
  s <- inv[inv$store_id == store_id, c("drug_id", "generic_price_inr", "stock_packs")]
  b <- merge(b, s, by = "drug_id", all.x = TRUE)
  b$packs <- as.numeric(qty[b$drug_id]); b$packs[is.na(b$packs)] <- 1
  b$status <- ifelse(is.na(b$stock_packs), "Not stocked",
              ifelse(b$stock_packs == 0, "Out of stock",
              ifelse(b$stock_packs < b$packs, paste("Only", b$stock_packs, "packs"),
              ifelse(b$stock_packs < 5, "Low stock", "In stock"))))
  b$buyable <- b$status %in% c("In stock", "Low stock")
  b$brand_total <- b$brand_mrp_inr * b$packs
  b$generic_total <- ifelse(b$buyable, b$generic_price_inr * b$packs, NA)
  b$saving <- ifelse(b$buyable, b$brand_total - b$generic_total, NA)
  b
}
