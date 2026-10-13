# ---- Central configuration (single source of truth; edit here only) ----
SEED             <- 2026L      # every random step in the project uses this seed
MATCH_THRESHOLD  <- 0.85       # fuzzy-match cut-off; tuned on DEV split by tests/evaluate_matching.R
BLUR_THRESHOLD   <- 100        # variance-of-Laplacian cut-off (on 800px-wide grayscale); tune on your phone photos
DEFAULT_LAT      <- 26.9124    # Jaipur centre (fallback when GPS unavailable)
DEFAULT_LON      <- 75.7873
DATA_VERSION     <- "synthetic-v1"
