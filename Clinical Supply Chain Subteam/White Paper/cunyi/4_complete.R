############################################################
# RTSM-Like Supply Chain Simulation (EU + China)
# Clean, runnable, operationally realistic version
#
# Features:
#  1) Stratified block randomization (region x BW), masked A/B
#  2) Masked inventory balancing (A/B 1:1 within each kit_type)
#  3) CN transfer by target coverage (predictive demand based, optional)
#  4) Weekly routine ordering + emergency ordering rules
#  5) Site-level KPI outputs (stockouts, pipeline, expiry, orders)
#  6) NEW: Patient visit & kit usage logs; Site-kit daily inventory
#
# Author: (generated) M365 Copilot
############################################################
suppressPackageStartupMessages({
  library(dplyr)
  library(lubridate)
  library(readr)
  library(tidyr)
  library(purrr)
})
############################################################
# 1) PARAMETERS (EDIT HERE ONLY)
############################################################
PARAM <- list(
  # ---------- Global simulation controls ----------
  seed                   = 20260206,
  seed_mode              = "fixed",      # "fixed" or "random"
  sim_horizon_days       = 2 * 365 + 120,
  day0                   = 0,
  verbose                = FALSE,
  
  # ---------- Network structure ----------
  n_sites_eu             = 13,
  n_sites_cn             = 10,
  
  # ---------- Patient targets ----------
  n_patients_total       = 250,
  n_patients_eu          = 100,
  n_patients_cn          = 150,
  
  # ---------- BW strata distribution ----------
  p_bw_lt90_eu           = 0.70,
  p_bw_lt90_cn           = 0.80,
  
  # ---------- Recruitment model (Gamma-Poisson per site) ----------
  enroll_gamma_shape     = 2.0,
  enroll_gamma_rate  = 40.0,
  
  # ---------- Pre-position for FUTURE enrollments (dynamic pairwise A/B) ----------
  preposition_enabled                = TRUE,   # Only active before global enrollment completes
  preposition_pair_kit_type          = "5ml",  # Kit type to pre-position pairwise (default weekly kit)
  preposition_cover_months           = 1.0,    # Target pairs = monthly enrollment forecast * cover_months
  preposition_pairs_rounding         = "ceil", # Rounding for target pairs: ceil/round/floor
  preposition_starter_horizon_days   = 14,     # Starter horizon (days) to derive units per arm per pair
  preposition_min_pairs              = 0L,     # Lower bound on pairs
  preposition_max_pairs              = Inf,    # Upper bound on pairs (use Inf if not needed)
  
  # NEW: how to convert the starter horizon into "units per arm per pair"
  # "max_bw"   -> assume GE90 dose for all weekly visits (5x5ml each visit)
  # "mixed_bw" -> use region-level BW mix (your previous behavior)
  preposition_units_mode             = "max_bw",
  
  # ---------- Recruitment model (Gamma-Poisson per site, Tiered) ----------
  # Tier means are per MONTH; code converts to per day internally
  enroll_tier_mu_month   = c(low = 1, median = 2, high = 4),
  month_days_for_enroll  = 30,      # per-month -> per-day conversion
  
  # Site mix by tier (choose ONE of mix OR counts for each region)
  # Option A: proportions (sum to 1)
  enroll_tier_mix_eu     = c(low = 1/3, median = 1/3, high = 1/3),
  enroll_tier_mix_cn     = c(low = 1/3, median = 1/3, high = 1/3),
  
  # Gamma shape φ for site-level heterogeneity (bigger φ -> closer to Poisson)
  enroll_gamma_phi       = 4.0,
  
  
  recruitment_duration_days = 450,
  screen_fail_rate       = 0.35,
  inactive_site_pct      = 0.15,
  
  # ---------- Dropout ----------
  dropout_over_52w       = 0.20,
  max_followup_days      = 52 * 7,
  
  # ---------- Visit schedule ----------
  nominal_visit_days     = c(seq(0, 13*7, by = 7),
                             seq(14*7, 14*7 + (20-1)*14, by = 14)),
  visit_window_minus     = 4,
  visit_window_plus      = 4,
  visit_sd_within_window = 2.0,
  
  # ---------- Visit variations ----------
  unscheduled_visit_rate = 0.10,    # 10% probability of unscheduled visits
  missing_visit_rate     = 0.10,    # 10% probability of missing visits
  
  # ---------- Dosing / kit requirements ----------
  kits_phase_weekly = list(
    bw_lt90 = list(kit = "5ml",   qty = 3),
    bw_ge90 = list(kit = "5ml",   qty = 5)
  ),
  kits_phase_q2w = list(
    bw_lt90 = list(kit = "2.5ml", qty = 1),
    bw_ge90 = list(kit = "7.5ml", qty = 1)
  ),
  n_weekly_visits          = 13,
  
  # ---------- Shelf life / expiry ----------
  shelf_life_days          = 24 * 30,     # ~720 days
  min_remaining_eu_depot_days = 6.5 * 30,
  min_remaining_cn_depot_days = 9.0 * 30,
  min_remaining_site_days  = 6.0 * 30,
  
  # ---------- DNX / Lookout ----------
  DND_days                 = 13,
  ship_lt_depot_to_site_days_eu = 7,
  ship_lt_depot_to_site_days_cn = 7,
  ship_lt_mfg_to_eu_depot_days   = 7,
  ship_lt_eu_to_cn_depot_days    = 60,
  
  DNC_buffer_days          = 7,
  DNS_buffer_days          = 30,
  
  lookout_additional_days  = 30,
  
  # ---------- Site thresholds (per item kit__arm) ----------
  min_threshold_kits       = 20,
  max_threshold_kits       = 60,
  
  # ---------- Initial inventories ----------
  init_site_firstvisit_patients = 4,
  init_depot_fraction_total = 0.3,
  
  # ---------- Manufacturing plan ----------
  mfg_planned_cycle_days   = 60,
  mfg_planned_n_shipments  = 8,
  mfg_cycle_cover_days     = 150,
  mfg_safety_stock_days    = 60,
  # EU depot reserve horizon for forwarding (days)
  eu_forward_reserve_days = 90,
  # Additional manufacturing (stabilized)
  allow_additional_mfg_shipments = TRUE,
  mfg_reorder_lookahead_days     = 90,
  mfg_extra_cooldown_days        = 60,
  mfg_extra_min_short_ratio      = 0.01,
  
  # ---------- Shipment damage ----------
  shipment_damage_rate     = 0.01,
  
  # ---------- FEFO selection ----------
  use_FEFO                 = TRUE,
  
  # ---------- Randomization / masking (RTSM-like) ----------
  use_strat_block_rand     = TRUE,
  rand_strata              = c("region","bw_group"),
  block_sizes              = c(4, 6),
  masking_enabled          = TRUE,
  blind_codes              = c("A","B"),
  blind_to_arm_map         = c(A="ACT", B="PBO"),
  # Deprecated in routine path; do not use the old "fixed-total redistribution" any more
  enforce_site_balance     = FALSE,
  
  # ---------- New activation & pairwise equalization controls ----------
  activation_initial_stock = list(kit = "5ml", qty = 0, split_evenly_across_arms = TRUE),
  enable_activation_drop = FALSE,  #active site will be resupply is closed
  enable_pairwise_equalize_before_complete = TRUE,
  
  # ---------- CN transfer policy (target coverage) ----------
  cn_transfer_policy       = "target_cover",   # (currently disabled in loop; see step 8)
  cn_target_cover_days     = 90,
  cn_transfer_safety_days  = 14,
  cn_transfer_check_freq_days = 1,
  cn_transfer_min_batch    = 10,
  
  # ---------- Operational ordering cadence ----------
  site_order_cycle_days      = 1,
  site_order_weekday0        = 0,     # routine order when (today %% 7) == 1
  min_days_between_orders    = 1,
  emergency_enabled          = TRUE,
  emergency_check_daily      = TRUE,
  emergency_lookout_days     = 14,
  emergency_buffer_kits      = 0,
  emergency_min_gap_kits     = 3,
  
  # Controls for instant EU -> CN forwarding upon MFG receipt
  auto_transfer_on_mfg_receipt = TRUE,
  forward_to_cn_fraction       = 0.50
)

############################################################
# 2) FUNCTIONS
############################################################

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0 || all(is.na(a))) b else a

set_seed <- function(PARAM) {
  if (identical(PARAM$seed_mode, "random") || is.null(PARAM$seed)) {
    s <- as.integer((as.numeric(Sys.time()) * 1000) %% .Machine$integer.max)
    set.seed(s)
  } else {
    set.seed(PARAM$seed)
  }
}

rtruncnorm <- function(n, mean, sd, lower, upper) {
  out <- numeric(n)
  i <- 1
  while (i <= n) {
    x <- rnorm(1, mean, sd)
    if (x >= lower && x <= upper) { out[i] <- x; i <- i + 1 }
  }
  out
}

make_site_rates <- function(n_sites, shape, rate) rgamma(n_sites, shape = shape, rate = rate)

daily_site_enrollments <- function(lambdas, remaining, inactive_flags) {
  draws <- ifelse(inactive_flags, 0L, rpois(length(lambdas), lambdas))
  total <- sum(draws)
  if (total <= remaining) return(as.integer(draws))
  if (remaining <= 0) return(rep(0L, length(draws)))
  idx <- rep(seq_along(draws), draws)
  keep <- sample(idx, remaining)
  tab <- tabulate(keep, nbins = length(draws))
  as.integer(tab)
}


# =========================
# DAILY routine + preposition helpers
# =========================

# Build site_loc -> lambda map for quick lookup
build_site_lambda_map <- function(site_locs_eu, site_locs_cn, lambda_eu, lambda_cn) {
  stopifnot(length(site_locs_eu) == length(lambda_eu))
  stopifnot(length(site_locs_cn) == length(lambda_cn))
  v <- c(lambda_eu, lambda_cn)
  names(v) <- c(site_locs_eu, site_locs_cn)
  v
}

# Predict expected number of newly randomized patients at a site in the next 'lookahead_days'
# We use the site's daily lambda (post-screen), multiply by horizon, then round by policy.
# Split to BW by region-level probability.
predict_new_enrollments_by_bw <- function(site_loc, region, lookahead_days,
                                          lambda_map, PARAM) {
  lambda_day <- as.numeric(lambda_map[[site_loc]])
  if (is.na(lambda_day) || !is.finite(lambda_day)) lambda_day <- 0
  
  # Expected randomized (after screen-fail)
  mu_raw <- lambda_day * lookahead_days
  mu_eff <- mu_raw * (1 - PARAM$screen_fail_rate)
  
  # Rounding policy
  round_mode <- tolower(PARAM$preposition_rounding %||% "ceil")
  n_total <- switch(round_mode,
                    "floor" = floor(mu_eff),
                    "round" = round(mu_eff),
                    "ceil"  = ceiling(mu_eff),
                    ceiling(mu_eff))
  
  if (n_total <= 0) return(c(lt90 = 0L, ge90 = 0L))
  
  p_lt90 <- if (region == "EU") PARAM$p_bw_lt90_eu else PARAM$p_bw_lt90_cn
  n_lt90 <- as.integer(round(n_total * p_lt90))
  n_ge90 <- as.integer(n_total - n_lt90)
  c(lt90 = n_lt90, ge90 = n_ge90)
}

# Compute pre-position kit vector (named integer "kit__arm" -> qty)
# For each predicted incoming LT90, send 5ml * 3; for GE90, send 5ml * 5 (weekly phase),
# and mirror equally to A and B (masking).
compute_preposition_kits <- function(region, predicted_bw_counts, PARAM) {
  if (!isTRUE(PARAM$preposition_enabled)) return(integer())
  
  n_lt90 <- as.integer(predicted_bw_counts[["lt90"]] %||% 0L)
  n_ge90 <- as.integer(predicted_bw_counts[["ge90"]] %||% 0L)
  if ((n_lt90 + n_ge90) <= 0) return(integer())
  
  # Weekly-phase "first-visit coverage" per-patient kit needs (5ml)
  q_lt90 <- as.integer(PARAM$kits_phase_weekly$bw_lt90$qty)  # e.g., 3
  q_ge90 <- as.integer(PARAM$kits_phase_weekly$bw_ge90$qty)  # e.g., 5
  
  # Total "first-visit coverage" kits to stage per BW group (kit type is 5ml for both)
  kits_5ml_total <- as.integer(n_lt90 * q_lt90 + n_ge90 * q_ge90)
  if (kits_5ml_total <= 0) return(integer())
  
  arms <- if (PARAM$masking_enabled) PARAM$blind_codes else c("ACT","PBO")
  stopifnot(length(arms) == 2)
  
  # Symmetric staging to A and B (NOT pairwise equalization for orders;
  # this is proactive staging for unknown future enrollees)
  out <- integer()
  out[paste0("5ml__", arms[1])] <- kits_5ml_total
  out[paste0("5ml__", arms[2])] <- kits_5ml_total
  storage.mode(out) <- "integer"
  out
}
dropout_rate_from_target <- function(p_drop, horizon_days) -log(1 - p_drop) / horizon_days

simulate_visit_dates <- function(nominal_days, wminus, wplus, sd) {
  dev <- rtruncnorm(length(nominal_days), mean = 0, sd = sd, lower = -wminus, upper = wplus)
  as.integer(round(nominal_days + dev))
}

# Generate visit variations (unscheduled and missing)
apply_visit_variations <- function(visit_days, PARAM) {
  n_visits <- length(visit_days)
  
  # 1) Missing visits: randomly remove 10% of visits
  n_missing <- rbinom(1, n_visits, PARAM$missing_visit_rate)
  if (n_missing > 0) {
    missing_idx <- sample(seq_len(n_visits), n_missing)
    visit_days <- visit_days[-missing_idx]
  }
  
  # 2) Unscheduled visits: add 10% extra visits between scheduled ones
  if (length(visit_days) > 1) {
    n_unscheduled <- rbinom(1, length(visit_days) - 1, PARAM$unscheduled_visit_rate)
    if (n_unscheduled > 0) {
      # Insert unscheduled visits between consecutive scheduled visits
      for (i in seq_len(n_unscheduled)) {
        # Pick a random interval between visits
        interval_idx <- sample(seq_len(length(visit_days) - 1), 1)
        # Add visit at midpoint (with some random variation)
        midpoint <- (visit_days[interval_idx] + visit_days[interval_idx + 1]) / 2
        unscheduled_day <- as.integer(round(midpoint + rnorm(1, 0, 2)))
        visit_days <- c(visit_days, unscheduled_day)
      }
      visit_days <- sort(unique(visit_days))  # Remove duplicates and sort
    }
  }
  
  as.integer(visit_days)
}

kit_need_for_visit <- function(visit_index, bw_group, PARAM) {
  if (visit_index <= PARAM$n_weekly_visits) {
    spec <- if (bw_group == "lt90") PARAM$kits_phase_weekly$bw_lt90 else PARAM$kits_phase_weekly$bw_ge90
  } else {
    spec <- if (bw_group == "lt90") PARAM$kits_phase_q2w$bw_lt90 else PARAM$kits_phase_q2w$bw_ge90
  }
  list(kit_type = spec$kit, qty = spec$qty)
}

# ---------- Inventory ----------
new_inventory_df <- function() {
  data.frame(
    location   = character(),
    level      = character(),
    region     = character(),
    site_id    = integer(),
    kit_type   = character(),
    arm        = character(),   # masked code if masking_enabled (A/B)
    qty        = integer(),
    expiry_day = integer(),
    stringsAsFactors = FALSE
  )
}

add_inventory <- function(inv, location, level, region, site_id, kit_type, arm, qty, expiry_day) {
  if (is.na(qty) || qty <= 0) return(inv)
  inv[nrow(inv) + 1, ] <- list(location, level, region, site_id, kit_type, arm,
                               as.integer(qty), as.integer(expiry_day))
  inv
}
# ---------- Grant activation initial stock to a site ----------
grant_activation_initial_stock <- function(inv, site_loc, region, today, PARAM) {
  if (!isTRUE(PARAM$enable_activation_drop)) return(inv)
  kit0 <- PARAM$activation_initial_stock$kit
  q0   <- as.integer(PARAM$activation_initial_stock$qty)
  if (is.na(q0) || q0 <= 0) return(inv)
  
  arms <- if (PARAM$masking_enabled) PARAM$blind_codes else c("ACT","PBO")
  exp_day <- today + PARAM$shelf_life_days
  
  if (isTRUE(PARAM$activation_initial_stock$split_evenly_across_arms) && length(arms) == 2) {
    q_each <- as.integer(floor(q0 / 2))
    rem    <- q0 - 2L * q_each
    inv <- add_inventory(inv, site_loc, "SITE", region, NA_integer_, kit0, arms[1], q_each + (rem > 0), exp_day)
    inv <- add_inventory(inv, site_loc, "SITE", region, NA_integer_, kit0, arms[2], q_each,               exp_day)
  } else {
    inv <- add_inventory(inv, site_loc, "SITE", region, NA_integer_, kit0, arms[1], q0, exp_day)
  }
  inv
}

# ---------- Pairwise equalization for ROUTINE orders before enrollment completes ----------
# If a routine order requests exactly ONE arm of a kit_type, add enough counterpart arm
# so that on-hand (AFTER receipt) for that kit_type becomes 1:1 across arms.
augment_with_pairwise_equalization <- function(site_loc, inv, order_vec, PARAM) {
  if (is.null(order_vec) || length(order_vec) == 0) return(order_vec)
  arms <- if (PARAM$masking_enabled) PARAM$blind_codes else c("ACT","PBO")
  if (length(arms) != 2) return(order_vec)
  arm1 <- arms[1]; arm2 <- arms[2]
  
  kit_types <- unique(sub("__.*$", "", names(order_vec)))
  for (k in kit_types) {
    k1 <- paste0(k, "__", arm1)
    k2 <- paste0(k, "__", arm2)
    q1 <- as.integer(order_vec[k1] %||% 0L)
    q2 <- as.integer(order_vec[k2] %||% 0L)
    
    # Only when exactly one arm is being ordered
    if ((q1 > 0L && q2 == 0L) || (q2 > 0L && q1 == 0L)) {
      # Use gross on-hand (not DNC-filtered) to match "site balance" semantics
      on1 <- sum(inv$qty[inv$location == site_loc & inv$kit_type == k & inv$arm == arm1])
      on2 <- sum(inv$qty[inv$location == site_loc & inv$kit_type == k & inv$arm == arm2])
      
      if (q1 > 0L && q2 == 0L) {
        target <- on1 + q1
        extra  <- as.integer(max(0L, target - on2))  # add to arm2 to reach 1:1 on-hand after receipt
        if (extra > 0L) order_vec[k2] <- (as.integer(order_vec[k2] %||% 0L) + extra)
      } else if (q2 > 0L && q1 == 0L) {
        target <- on2 + q2
        extra  <- as.integer(max(0L, target - on1))
        if (extra > 0L) order_vec[k1] <- (as.integer(order_vec[k1] %||% 0L) + extra)
      }
    }
  }
  order_vec
}
# ---------- Enhanced expiry removal (adds kit-level detail) ----------
remove_expired_by_loc <- function(inv, today) {
  rows <- which(inv$qty > 0 & inv$expiry_day < today)
  if (!length(rows)) {
    return(list(inv = inv,
                expired_total = 0L,
                expired_by_loc = NULL,
                expired_detail = data.frame(day = integer(), location = character(),
                                            kit_type = character(), arm = character(),
                                            expired_qty = integer(), stringsAsFactors = FALSE)))
  }
  # Capture detail BEFORE zeroing
  det <- inv[rows, c("location","kit_type","arm","qty")]
  det$day <- today
  names(det)[names(det) == "qty"] <- "expired_qty"
  det <- det[, c("day","location","kit_type","arm","expired_qty")]
  
  exp_by_loc <- tapply(inv$qty[rows], inv$location[rows], sum)
  inv$qty[rows] <- 0L
  
  list(inv = inv,
       expired_total = as.integer(sum(exp_by_loc)),
       expired_by_loc = exp_by_loc,
       expired_detail = det)
}

# ---------- FEFO picking with DNX constraints ----------
pick_kits <- function(inv, location, kit_type, arm, qty_need, min_expiry_day, use_FEFO = TRUE) {
  rows <- which(inv$location == location &
                  inv$kit_type == kit_type &
                  inv$arm == arm &
                  inv$qty > 0 &
                  inv$expiry_day > min_expiry_day)
  if (!length(rows) || qty_need <= 0) return(list(inv = inv, picked = 0L, lots = NULL))
  
  if (use_FEFO) rows <- rows[order(inv$expiry_day[rows])]
  
  remaining <- qty_need
  picked <- 0L
  lots <- data.frame(expiry_day = integer(), qty = integer())
  
  for (r in rows) {
    if (remaining <= 0) break
    take <- min(inv$qty[r], remaining)
    inv$qty[r] <- inv$qty[r] - take
    remaining <- remaining - take
    picked <- picked + take
    lots[nrow(lots) + 1, ] <- list(as.integer(inv$expiry_day[r]), as.integer(take))
  }
  list(inv = inv, picked = as.integer(picked), lots = lots)
}

apply_shipment_damage <- function(qty, damage_rate) {
  damaged <- rbinom(1, size = qty, prob = damage_rate)
  received <- qty - damaged
  list(received = as.integer(received), damaged = as.integer(damaged))
}

# ---------- Site-level availability under DNC ----------
site_available_item <- function(inv, site_loc, kit_type, arm, today, DNC_days) {
  rows <- which(inv$location == site_loc &
                  inv$kit_type == kit_type &
                  inv$arm == arm &
                  inv$qty > 0 &
                  inv$expiry_day > (today + DNC_days))
  as.integer(sum(inv$qty[rows]))
}

# ---------- Pipeline under DNC ----------
in_transit_item <- function(site_loc, kit_type, arm, today, shipments, DNC_days) {
  if (is.null(shipments) || !nrow(shipments)) return(0L)
  rows <- which(shipments$to_loc == site_loc &
                  shipments$kit_type == kit_type &
                  shipments$arm == arm &
                  shipments$arrive_day > today &
                  shipments$qty > 0 &
                  shipments$expiry_day > (today + DNC_days) &
                  shipments$expiry_day > shipments$arrive_day)
  if (!length(rows)) return(0L)
  as.integer(sum(shipments$qty[rows]))
}

# ---------- Demand prediction ----------
# ---------- Demand prediction (RTSM forecast; NO peeking future actual visit days) ----------
predictive_demand <- function(subjects_df, today, window_days, PARAM) {
  # Return: a list keyed by site_loc; each element is a named integer vector
  #         of item keys "kit_type__arm" -> quantity demand within [today, today+window_days]
  # Principle:
  #   - DO NOT use realized visit days (no vdays).
  #   - Use nominal plan relative to enroll_day.
  #   - Window inclusion uses the earliest possible day:
  #       earliest_j = enroll_day + nominal_visit_days[j] - visit_window_minus
  #   - Include visit j if earliest_j ∈ [today, today + window_days].
  #   - Skip subject if dropped==1.
  #   - Map each visit index j to kit need via kit_need_for_visit(j, bw_group, PARAM).
  
  demand <- list()
  if (!nrow(subjects_df)) return(demand)
  
  # Pre-bind for speed/readability
  nominal <- as.integer(PARAM$nominal_visit_days)
  wminus  <- as.integer(PARAM$visit_window_minus)
  # NOTE: we do not use window_plus in the trigger/inclusion test; we use "earliest" only,
  #       which is conservative to supply risk (the policy you selected).
  end_day <- today + as.integer(window_days)
  
  # Sanity on required columns
  req <- c("site_loc","arm","bw_group","enroll_day","dropped")
  miss <- setdiff(req, names(subjects_df))
  if (length(miss)) stop("subjects_df missing columns: ", paste(miss, collapse=", "))
  
  for (i in seq_len(nrow(subjects_df))) {
    if (subjects_df$dropped[i] == 1L) next
    
    site_loc   <- subjects_df$site_loc[i]
    arm        <- subjects_df$arm[i]       # masked A/B (or ACT/PBO if masking off)
    bw_group   <- subjects_df$bw_group[i]  # "lt90"/"ge90"
    enroll_day <- as.integer(subjects_df$enroll_day[i])
    
    # Earliest inclusion days for all visits of this subject
    # earliest_j = enroll_day + nominal_j - wminus
    earliest <- enroll_day + nominal - wminus
    
    # Visits whose earliest falls inside [today, end_day]
    idx <- which(earliest >= today & earliest <= end_day)
    if (!length(idx)) next
    
    # Accumulate kit demand per visit j (A/B separated)
    for (j in idx) {
      need <- kit_need_for_visit(j, bw_group, PARAM)  # returns list(kit_type, qty)
      key  <- paste0(need$kit_type, "__", arm)
      
      if (is.null(demand[[site_loc]])) demand[[site_loc]] <- integer()
      cur <- demand[[site_loc]][key]
      cur <- if (is.na(cur)) 0L else cur
      demand[[site_loc]][key] <- cur + as.integer(need$qty)
    }
  }
  demand
}

# ---------- Demand prediction for any window, split by weekly/Q2W via an input 'weekly_cap' ----------
predictive_demand_split_by_phase <- function(subjects_df, today, window_days, weekly_cap, PARAM) {
  # Returns: list(site_loc -> named integer vector "kit__arm" -> qty)
  # Rule:
  #   - Window = [today, today + window_days]
  #   - For each subject, compute earliest day for each nominal visit:
  #       earliest_j = enroll_day + nominal_visit_days[j] - visit_window_minus
  #   - Split by weekly_cap (visit index): 
  #       * Part A: j <= weekly_cap  and earliest_j in window --> weekly kits (5 ml)
  #       * Part B: j >  weekly_cap  and earliest_j in window --> Q2W kits (2.5/7.5)
  #   - Skip dropped subjects. Do NOT peek realized visit days.
  
  demand <- list()
  if (!nrow(subjects_df)) return(demand)
  
  # Inputs & guards
  nominal <- as.integer(PARAM$nominal_visit_days)
  wminus  <- as.integer(PARAM$visit_window_minus)
  end_day <- today + as.integer(window_days)
  if (!is.finite(weekly_cap) || weekly_cap <= 0) {
    # fallback to configured weekly length if caller passed invalid value
    weekly_cap <- as.integer(PARAM$n_weekly_visits)
  } else {
    weekly_cap <- as.integer(weekly_cap)
  }
  weekly_cap <- min(weekly_cap, length(nominal))  # clamp to nominal length
  
  # Local helper: choose kit by phase boundary defined by 'weekly_cap'
  need_with_cap <- function(j, bw_group, PARAM, weekly_cap) {
    if (j <= weekly_cap) {
      # weekly-phase kits (always 5 ml in your spec)
      if (bw_group == "lt90") {
        list(kit = PARAM$kits_phase_weekly$bw_lt90$kit,
             qty = as.integer(PARAM$kits_phase_weekly$bw_lt90$qty))
      } else {
        list(kit = PARAM$kits_phase_weekly$bw_ge90$kit,
             qty = as.integer(PARAM$kits_phase_weekly$bw_ge90$qty))
      }
    } else {
      # Q2W-phase kits (2.5 / 7.5 ml)
      if (bw_group == "lt90") {
        list(kit = PARAM$kits_phase_q2w$bw_lt90$kit,
             qty = as.integer(PARAM$kits_phase_q2w$bw_lt90$qty))
      } else {
        list(kit = PARAM$kits_phase_q2w$bw_ge90$kit,
             qty = as.integer(PARAM$kits_phase_q2w$bw_ge90$qty))
      }
    }
  }
  
  for (i in seq_len(nrow(subjects_df))) {
    if (subjects_df$dropped[i] == 1L) next
    
    site_loc <- subjects_df$site_loc[i]
    arm      <- subjects_df$arm[i]       # masked A/B (or ACT/PBO if masking off)
    bw_group <- subjects_df$bw_group[i]  # "lt90"/"ge90"
    enroll   <- as.integer(subjects_df$enroll_day[i])
    
    # earliest inclusion day for each nominal visit
    earliest <- enroll + nominal - wminus
    
    # ---- Part A: weekly portion (j <= weekly_cap) within window ----
    idx_weekly <- which(seq_along(nominal) <= weekly_cap &
                          earliest >= today & earliest <= end_day)
    if (length(idx_weekly)) {
      for (j in idx_weekly) {
        need <- need_with_cap(j, bw_group, PARAM, weekly_cap)   # 5 ml
        key  <- paste0(need$kit, "__", arm)
        if (is.null(demand[[site_loc]])) demand[[site_loc]] <- integer()
        cur <- demand[[site_loc]][key]; cur <- if (is.na(cur)) 0L else as.integer(cur)
        demand[[site_loc]][key] <- cur + as.integer(need$qty)
      }
    }
    
    # ---- Part B: Q2W portion (j > weekly_cap) within window ----
    idx_q2w <- which(seq_along(nominal) > weekly_cap &
                       earliest >= today & earliest <= end_day)
    if (length(idx_q2w)) {
      for (j in idx_q2w) {
        need <- need_with_cap(j, bw_group, PARAM, weekly_cap)   # 2.5 / 7.5 ml
        key  <- paste0(need$kit, "__", arm)
        if (is.null(demand[[site_loc]])) demand[[site_loc]] <- integer()
        cur <- demand[[site_loc]][key]; cur <- if (is.na(cur)) 0L else as.integer(cur)
        demand[[site_loc]][key] <- cur + as.integer(need$qty)
      }
    }
  }
  
  demand
}
# Compute "units per arm per pair" dynamically from a starter horizon in the weekly phase.
# It estimates how many 5ml kits a NEW subject would consume within the first N days,
# mixing BW groups by the region-level distribution, and rounds up to integer units per arm.
compute_starter_units_per_arm <- function(region, PARAM) {
  horizon <- as.integer(PARAM$preposition_starter_horizon_days %||% 14)
  kit     <- PARAM$preposition_pair_kit_type %||% "5ml"
  
  # Approximation assumes the pre-positioned kit is the weekly-phase kit (5ml).
  # If a different kit is used, extend this function accordingly.
  nominal <- as.integer(PARAM$nominal_visit_days)
  n_week  <- as.integer(PARAM$n_weekly_visits)
  idx_week <- which(seq_along(nominal) <= n_week & nominal <= horizon)
  n_vis   <- length(idx_week)
  if (n_vis <= 0) return(0L)
  
  # Weekly-phase per-visit consumption (5ml) by BW group
  q_lt90 <- as.integer(PARAM$kits_phase_weekly$bw_lt90$qty)  # e.g., 3
  q_ge90 <- as.integer(PARAM$kits_phase_weekly$bw_ge90$qty)  # e.g., 5
  
  # Region-level BW split
  p_lt90 <- if (region == "EU") as.numeric(PARAM$p_bw_lt90_eu) else as.numeric(PARAM$p_bw_lt90_cn)
  if (!is.finite(p_lt90)) p_lt90 <- 0.5
  
  # Expected kits for one new subject within the horizon (weekly phase only)
  expected_per_patient <- n_vis * (p_lt90 * q_lt90 + (1 - p_lt90) * q_ge90)
  units <- as.integer(ceiling(expected_per_patient))  # symmetric A/B units per pair
  units
}


# Compute "units per arm per pair" under MAX-BW assumption for the weekly phase.
# For FUTURE pre-positioning only, we assume every weekly visit consumes GE90 dose (5 x 5ml).
# Starter horizon only counts weekly-phase nominal visits that fall within the horizon window.
compute_starter_units_per_arm_maxBW <- function(region, PARAM) {
  horizon <- as.integer(PARAM$preposition_starter_horizon_days %||% 14)
  kit     <- PARAM$preposition_pair_kit_type %||% "5ml"
  
  # We assume preposition uses weekly-phase kit (5ml). If you change kit type,
  # extend this function accordingly.
  nominal <- as.integer(PARAM$nominal_visit_days)
  n_week  <- as.integer(PARAM$n_weekly_visits)
  
  # Count weekly-phase visits whose nominal day <= horizon
  idx_week <- which(seq_along(nominal) <= n_week & nominal <= horizon)
  n_vis    <- length(idx_week)
  if (n_vis <= 0) return(0L)
  
  # MAX-BW assumption: each weekly visit needs 5 units of 5ml
  units_per_visit <- 5L
  
  units <- as.integer(ceiling(n_vis * units_per_visit))
  units
}
# FUTURE-enrollment pairwise pre-positioning: compute A/B symmetric top-up under DNC.
# Target pairs = site monthly enrollment forecast * cover_months, with chosen rounding.
# Per-pair units per arm are derived from the starter horizon consumption model above.
compute_preposition_pairs_topup <- function(site_loc, region, today, inv, shipments,
                                            ship_lt_days, lambda_map, PARAM,
                                            debug = FALSE) {
  if (!isTRUE(PARAM$preposition_enabled)) return(integer())
  
  # 1) Site-level monthly enrollment forecast (day lambda -> month; apply screen-fail)
  lambda_day <- as.numeric(lambda_map[[site_loc]])
  if (!is.finite(lambda_day) || is.na(lambda_day) || lambda_day < 0) lambda_day <- 0
  month_days <- as.integer(PARAM$month_days_for_enroll %||% 30)
  lambda_month <- lambda_day * (1 - PARAM$screen_fail_rate) * month_days
  
  # 2) Target number of pairs
  cover_m   <- as.numeric(PARAM$preposition_cover_months %||% 1.0)
  raw_pairs <- lambda_month * cover_m
  n_pairs <- switch(tolower(PARAM$preposition_pairs_rounding %||% "ceil"),
                    "floor" = floor(raw_pairs),
                    "round" = round(raw_pairs),
                    "ceil"  = ceiling(raw_pairs),
                    ceiling(raw_pairs))
  n_pairs <- max(as.integer(PARAM$preposition_min_pairs %||% 0L), as.integer(n_pairs))
  if (is.finite(PARAM$preposition_max_pairs)) n_pairs <- min(n_pairs, as.integer(PARAM$preposition_max_pairs))
  if (n_pairs <= 0L) return(integer())
  
  
  # 3) Units per arm per pair, selected by mode:
  #    - "max_bw": assume GE90 dose for all weekly visits (5 units per visit)
  #    - "mixed_bw": region-level BW mix (legacy behavior)
  mode <- tolower(PARAM$preposition_units_mode %||% "max_bw")
  units <- switch(mode,
                  "max_bw"   = as.integer(compute_starter_units_per_arm_maxBW(region, PARAM)),
                  "mixed_bw" = as.integer(compute_starter_units_per_arm(region, PARAM)),
                  as.integer(compute_starter_units_per_arm_maxBW(region, PARAM)))  # default to max_bw
  
  if (units <= 0L) return(integer())
  
  # 4) DNC target per arm = n_pairs * units; top-up any shortfall (A/B symmetric)
  kit   <- PARAM$preposition_pair_kit_type %||% "5ml"
  arms  <- if (PARAM$masking_enabled) PARAM$blind_codes else c("ACT","PBO")
  stopifnot(length(arms) == 2)
  
  DNC_days <- PARAM$DND_days + ship_lt_days + PARAM$DNC_buffer_days
  out <- integer()
  
  for (a in arms) {
    key <- paste0(kit, "__", a)
    on  <- site_available_item(inv, site_loc, kit, a, today, DNC_days)
    tr  <- in_transit_item(site_loc, kit, a, today, shipments, DNC_days)
    avail <- on + tr
    target <- as.integer(n_pairs * units)
    gap <- as.integer(max(0L, target - avail))
    if (gap > 0L) out[key] <- gap
  }
  storage.mode(out) <- "integer"
  
  if (debug && length(out)) {
    message(sprintf("[PRE-PAIR] day=%d site=%s region=%s target_pairs=%d units_per_arm=%d topup_sum=%d",
                    today, site_loc, region, n_pairs, units, sum(out)))
  }
  out
}
# ---------- Masked balancing (keeps totals fixed) ----------
balance_1to1_fixed_total <- function(site_loc, inv, ship_vec) {
  if (is.null(ship_vec) || !length(ship_vec)) return(ship_vec)
  keys <- names(ship_vec)
  kit_types <- unique(sub("__.*$", "", keys))
  
  arms_present <- unique(sub("^.*__", "", keys))
  if (length(arms_present) != 2) return(ship_vec)
  arm1 <- arms_present[1]; arm2 <- arms_present[2]
  
  for (k in kit_types) {
    k1 <- paste0(k, "__", arm1)
    k2 <- paste0(k, "__", arm2)
    o1 <- ship_vec[k1] %||% 0L
    o2 <- ship_vec[k2] %||% 0L
    tot <- o1 + o2
    if (tot <= 0) next
    
    on1 <- sum(inv$qty[inv$location == site_loc & inv$kit_type == k & inv$arm == arm1])
    on2 <- sum(inv$qty[inv$location == site_loc & inv$kit_type == k & inv$arm == arm2])
    
    diff <- (on1 - on2)
    arm1_des <- round(tot/2 - diff/2)
    arm1_des <- max(0, min(tot, arm1_des))
    arm2_des <- tot - arm1_des
    
    ship_vec[k1] <- as.integer(arm1_des)
    ship_vec[k2] <- as.integer(arm2_des)
  }
  ship_vec
}

# ---------- Order computation per item (kit__arm) ----------
# ---------- Order computation per item (kit__arm) ----------
compute_site_order_itemwise <- function(site_loc, inv, shipments, demS, demL, today, PARAM, ship_lt_days,
                                        enforce_balance_flag) {
  DNC_days <- PARAM$DND_days + ship_lt_days + PARAM$DNC_buffer_days
  ds <- demS[[site_loc]] %||% integer()
  dl <- demL[[site_loc]] %||% integer()
  
  all_keys <- union(names(ds), names(dl))
  
  # ALWAYS ensure threshold-only check covers 2.5ml/5ml/7.5ml for both arms
  arms <- if (PARAM$masking_enabled) PARAM$blind_codes else c("ACT","PBO")
  default_kits  <- c("2.5ml","5ml","7.5ml")
  default_keys  <- as.vector(outer(default_kits, arms, paste, sep="__"))
  
  # Union default keys with demand keys so we will also check inventory thresholds for missing items
  all_keys <- union(all_keys, default_keys)
  
  # Fill zeros for missing keys in ds and dl
  missingS <- setdiff(all_keys, names(ds)); if (length(missingS)) ds[missingS] <- 0L
  missingL <- setdiff(all_keys, names(dl)); if (length(missingL)) dl[missingL] <- 0L
  
  order <- integer()
  triggered_any <- FALSE
  
  for (key in all_keys) {
    kit <- sub("__.*$", "", key)
    arm <- sub("^.*__", "", key)
    
    dS <- as.integer(ds[key] %||% 0L)
    dL <- as.integer(dl[key] %||% 0L)
    
    onhand  <- site_available_item(inv, site_loc, kit, arm, today, DNC_days)
    transit <- in_transit_item(site_loc, kit, arm, today, shipments, DNC_days)
    avail   <- onhand + transit
    
    trigger_item <- (dS + PARAM$min_threshold_kits) > avail
    if (!trigger_item) next
    
    triggered_any <- TRUE
    q <- (dL + PARAM$max_threshold_kits) - avail
    q <- max(0L, as.integer(ceiling(q)))
    order[key] <- q
  }
  
  if (!triggered_any || sum(order) <= 0) return(list(trigger = FALSE, order = NULL))
  
  # <<< balance only if the runtime flag is TRUE >>>
  if (isTRUE(enforce_balance_flag)) {
    order <- balance_1to1_fixed_total(site_loc, inv, order)
  }
  list(trigger = TRUE, order = order)
}

# ---------- Shipments ----------
new_shipments_df <- function() {
  data.frame(
    ship_id     = integer(),
    from_loc    = character(),
    to_loc      = character(),
    lane        = character(),
    depart_day  = integer(),
    arrive_day  = integer(),
    kit_type    = character(),
    arm         = character(),
    qty         = integer(),
    expiry_day  = integer(),
    stringsAsFactors = FALSE
  )
}

# ---------- Manufacturing shipments ----------
create_mfg_shipment <- function(today, qty_vec, PARAM, shipments, next_ship_id, COUNT) {
  
  
  if (is.null(qty_vec) || length(qty_vec) == 0 ||
      all(is.na(qty_vec)) || sum(qty_vec, na.rm = TRUE) <= 0) {
    return(list(shipments=shipments, next_ship_id=next_ship_id, COUNT=COUNT))
  }
  
  if (sum(qty_vec) <= 0) return(list(shipments=shipments, next_ship_id=next_ship_id, COUNT=COUNT))
  depart <- today
  arrive <- today + PARAM$ship_lt_mfg_to_eu_depot_days
  expday <- depart + PARAM$shelf_life_days
  
  wrote <- FALSE
  for (nm in names(qty_vec)) {
    q <- as.integer(unname(qty_vec[nm]))
    if (is.na(q) || q <= 0) next
    parts <- strsplit(nm, "__")[[1]]
    kit <- parts[1]; arm <- parts[2]
    shipments[nrow(shipments)+1,] <- list(next_ship_id, "MFG", "EU_DEPOT", "MFG->EUDEPOT",
                                          depart, arrive, kit, arm, q, expday)
    wrote <- TRUE
  }
  
  if (wrote) {
    COUNT$ship_mfg_to_eu_depot <- COUNT$ship_mfg_to_eu_depot + 1L
    next_ship_id <- next_ship_id + 1L
  }
  list(shipments=shipments, next_ship_id=next_ship_id, COUNT=COUNT)
}

# Compute the maximum eligible qty for EU->CN (no mutation)
eligible_qty_eu_to_cn <- function(inv, kit, arm, today, PARAM) {
  DNS_eu_depot <- PARAM$DND_days + PARAM$ship_lt_depot_to_site_days_eu + PARAM$DNS_buffer_days
  arrive       <- today + PARAM$ship_lt_eu_to_cn_depot_days
  min_exp      <- max(today + DNS_eu_depot, arrive + PARAM$min_remaining_cn_depot_days)
  
  rows <- which(inv$location == "EU_DEPOT" &
                  inv$kit_type == kit &
                  inv$arm == arm &
                  inv$qty > 0 &
                  inv$expiry_day > min_exp)
  if (!length(rows)) return(0L)
  as.integer(sum(inv$qty[rows]))
}

# ---------- Depot availability under DNS ----------
depot_available_item <- function(inv, depot_loc, kit_type, arm, today, DNS_days) {
  rows <- which(inv$location == depot_loc &
                  inv$kit_type == kit_type &
                  inv$arm == arm &
                  inv$qty > 0 &
                  inv$expiry_day > (today + DNS_days))
  as.integer(sum(inv$qty[rows]))
}

# ---------- Depot -> Site shipment ----------
create_depot_to_site_shipment <- function(today, inv, from_depot, to_site, lane, ship_lt_days,
                                          order_vec, PARAM, shipments, next_ship_id, COUNT,
                                          DNS_depot_days) {
  
  if (is.null(order_vec) || sum(order_vec) <= 0) {
    return(list(inv=inv, shipments=shipments, next_ship_id=next_ship_id, COUNT=COUNT))
  }
  
  depart <- today
  arrive <- today + ship_lt_days
  min_exp <- max(today + DNS_depot_days, arrive + PARAM$min_remaining_site_days)
  
  picked_total <- 0L
  any_short <- FALSE
  
  for (nm in names(order_vec)) {
    q_need <- as.integer(unname(order_vec[nm]))
    if (is.na(q_need) || q_need <= 0) next
    
    parts <- strsplit(nm, "__")[[1]]
    kit <- parts[1]; arm <- parts[2]
    
    pick <- pick_kits(inv, from_depot, kit, arm, q_need, min_exp, PARAM$use_FEFO)
    inv <- pick$inv
    
    if (pick$picked < q_need) {
      any_short <- TRUE
      COUNT$stockout_depot_item <- COUNT$stockout_depot_item + 1L
    }
    
    if (pick$picked > 0) {
      picked_total <- picked_total + pick$picked
      lots <- pick$lots
      for (j in seq_len(nrow(lots))) {
        shipments[nrow(shipments)+1,] <- list(next_ship_id, from_depot, to_site, lane,
                                              depart, arrive, kit, arm,
                                              as.integer(lots$qty[j]), as.integer(lots$expiry_day[j]))
      }
    }
  }
  
  # count a consignment only if something shipped
  if (picked_total > 0) {
    if (lane == "EUDEPOT->EUSITE") COUNT$ship_eu_depot_to_sites <- COUNT$ship_eu_depot_to_sites + 1L
    if (lane == "CNDEPOT->CNSITE") COUNT$ship_cn_depot_to_sites <- COUNT$ship_cn_depot_to_sites + 1L
    next_ship_id <- next_ship_id + 1L
  }
  
  if (any_short) COUNT$stockout_depot_order <- COUNT$stockout_depot_order + 1L
  
  list(inv=inv, shipments=shipments, next_ship_id=next_ship_id, COUNT=COUNT)
}

# ---------- EUDEPOT -> CNDEPOT transfer ----------
create_transfer_to_cn <- function(today, inv, need_vec, PARAM, shipments, next_ship_id, COUNT,
                                  DNS_eu_depot) {
  
  if (is.null(need_vec) || sum(need_vec) <= 0) {
    return(list(inv=inv, shipments=shipments, next_ship_id=next_ship_id, COUNT=COUNT))
  }
  
  depart <- today
  arrive <- today + PARAM$ship_lt_eu_to_cn_depot_days
  min_exp <- max(today + DNS_eu_depot, arrive + PARAM$min_remaining_cn_depot_days)
  
  picked_total <- 0L
  any_short <- FALSE
  
  for (nm in names(need_vec)) {
    q_need <- as.integer(unname(need_vec[nm]))
    if (is.na(q_need) || q_need <= 0) next
    
    parts <- strsplit(nm, "__")[[1]]
    kit <- parts[1]; arm <- parts[2]
    
    pick <- pick_kits(inv, "EU_DEPOT", kit, arm, q_need, min_exp, PARAM$use_FEFO)
    inv <- pick$inv
    
    if (pick$picked < q_need) {
      any_short <- TRUE
      COUNT$stockout_depot_item <- COUNT$stockout_depot_item + 1L
    }
    
    if (pick$picked > 0) {
      picked_total <- picked_total + pick$picked
      lots <- pick$lots
      for (j in seq_len(nrow(lots))) {
        shipments[nrow(shipments)+1,] <- list(next_ship_id, "EU_DEPOT", "CN_DEPOT", "EUDEPOT->CNDEPOT",
                                              depart, arrive, kit, arm,
                                              as.integer(lots$qty[j]), as.integer(lots$expiry_day[j]))
      }
    }
  }
  
  # count transfer only if meaningful batch shipped
  if (picked_total >= PARAM$cn_transfer_min_batch) {
    COUNT$ship_eu_to_cn_depot <- COUNT$ship_eu_to_cn_depot + 1L
    next_ship_id <- next_ship_id + 1L
  }
  
  if (any_short) COUNT$stockout_depot_order <- COUNT$stockout_depot_order + 1L
  
  list(inv=inv, shipments=shipments, next_ship_id=next_ship_id, COUNT=COUNT)
}

# ---------- Receive shipments arriving today (ENHANCED: logs site receipts) ----------
receive_shipments_today <- function(today, inv, shipments, next_ship_id, COUNT, PARAM,
                                    site_receipts_log, depot_receipts_log) {
  arr <- shipments[shipments$arrive_day == today, , drop = FALSE]
  if (!nrow(arr)) {
    return(list(inv = inv, shipments = shipments, next_ship_id = next_ship_id, COUNT = COUNT,
                site_receipts_log = site_receipts_log,depot_receipts_log = depot_receipts_log))
  }
  
  # Buffer transfer intents per MFG ship_id
  desired_by_ship <- list()
  
  for (i in seq_len(nrow(arr))) {
    row <- arr[i, ]
    
    # Apply damage upon receipt
    dmg <- apply_shipment_damage(row$qty, PARAM$shipment_damage_rate)
    COUNT$damaged_total <- COUNT$damaged_total + dmg$damaged
    if (dmg$received <= 0) next
    
    if (row$to_loc == "EU_DEPOT") {
      inv <- add_inventory(inv, "EU_DEPOT", "DEPOT", "EU", NA_integer_,
                           row$kit_type, row$arm, dmg$received, row$expiry_day)
      
      # Log depot receipt at EU depot (with damage at receipt)
      depot_receipts_log <- dplyr::bind_rows(
        depot_receipts_log,
        dplyr::tibble(
          day          = today,
          depot        = "EU_DEPOT",
          kit_type     = row$kit_type,
          arm          = row$arm,
          qty_received = as.integer(dmg$received),  # net received at depot
          qty_damaged  = as.integer(dmg$damaged)    # damaged upon depot receipt
        )
      )
      if (isTRUE(PARAM$auto_transfer_on_mfg_receipt) &&
          (identical(row$from_loc, "MFG") || identical(row$lane, "MFG->EUDEPOT"))) {
        ship_id <- row$ship_id
        nm      <- paste0(row$kit_type, "__", row$arm)
        desired <- as.integer(floor(dmg$received * PARAM$forward_to_cn_fraction))
        if (desired > 0) {
          if (is.null(desired_by_ship[[as.character(ship_id)]])) {
            desired_by_ship[[as.character(ship_id)]] <- integer()
          }
          cur <- desired_by_ship[[as.character(ship_id)]][nm]
          cur <- if (is.na(cur)) 0L else cur
          desired_by_ship[[as.character(ship_id)]][nm] <- cur + desired
        }
      }
      
    } else if (row$to_loc == "CN_DEPOT") {
      inv <- add_inventory(inv, "CN_DEPOT", "DEPOT", "CN", NA_integer_,
                           row$kit_type, row$arm, dmg$received, row$expiry_day)
      # Log depot receipt at CN depot (with damage at receipt)
      depot_receipts_log <- dplyr::bind_rows(
        depot_receipts_log,
        dplyr::tibble(
          day          = today,
          depot        = "CN_DEPOT",
          kit_type     = row$kit_type,
          arm          = row$arm,
          qty_received = as.integer(dmg$received),  # net received at depot
          qty_damaged  = as.integer(dmg$damaged)    # damaged upon depot receipt
        )
      )
    } else {
      # Site receipt
      region <- if (grepl("^EU_", row$to_loc)) "EU" else "CN"
      inv <- add_inventory(inv, row$to_loc, "SITE", region, NA_integer_,
                           row$kit_type, row$arm, dmg$received, row$expiry_day)
      # Log site receipt
      site_receipts_log[nrow(site_receipts_log)+1, ] <- list(today, row$to_loc, region,
                                                             row$kit_type, row$arm,
                                                             as.integer(dmg$received),as.integer(row$ship_id),as.integer(dmg$damaged))
    }
  }
  
  # ----- EU reserve protection BEFORE auto-forwarding to CN (with regional floor for 7.5ml) -----
  if (length(desired_by_ship) > 0) {
    
    # 0) Parameters to control the floor (tune as needed)
    eu_reserve_days <- as.integer(PARAM$eu_forward_reserve_days %||% 90)
    # Floor per site (per arm) for 7.5ml, expressed as a fraction of site min threshold.
    # Example: 0.5 * 20 = 10 units per EU active site per arm.
    floor_ratio_7_5ml <- as.numeric(PARAM$eu_reserve_floor_ratio_7_5ml %||% 0.5)
    
    # 1) Predict EU regional demand for the reserve horizon (split-by-phase)
    dem_eu <- predict_region_demand(
      subjects_all = subjects, region = "EU",
      today = today, horizon_days = eu_reserve_days, PARAM = PARAM
    )
    
    DNS_eu_depot <- PARAM$DND_days + PARAM$ship_lt_depot_to_site_days_eu + PARAM$DNS_buffer_days
    
    # 2) Determine # of active EU sites (any non-dropped subject)
    n_active_eu_sites <- 0L
    if (nrow(subjects)) {
      eu_act <- unique(subjects$site_loc[subjects$region == "EU" & subjects$dropped == 0L])
      n_active_eu_sites <- as.integer(length(eu_act))
    }
    
    # 3) Union of keys across ship_ids
    union_keys <- character()
    for (sid in names(desired_by_ship)) {
      union_keys <- union(union_keys, names(desired_by_ship[[sid]]))
    }
    
    forward_cap_by_key <- setNames(integer(length(union_keys)), union_keys)
    
    for (nm in union_keys) {
      parts <- strsplit(nm, "__")[[1]]
      kit <- parts[1]; arm <- parts[2]
      
      # DNS-eligible availability at EU depot
      eu_dns_avail <- depot_available_item(inv, "EU_DEPOT", kit, arm, today, DNS_eu_depot)
      
      # SAFE read forecast; if missing -> 0
      eu_need_fcst <- as.integer(dem_eu[nm]); if (is.na(eu_need_fcst)) eu_need_fcst <- 0L
      
      # 4) Add a regional safety floor for 7.5ml only (protect phase-switch scatter)
      eu_floor <- 0L
      if (identical(kit, "7.5ml") && n_active_eu_sites > 0L && floor_ratio_7_5ml > 0) {
        per_site_floor <- as.integer(round(floor_ratio_7_5ml * PARAM$min_threshold_kits))
        eu_floor <- as.integer(per_site_floor * n_active_eu_sites)  # per arm
      }
      
      # 5) Effective protected need = forecast + floor
      eu_need_eff <- eu_need_fcst + eu_floor
      
      cap <- as.integer(max(0L, eu_dns_avail - eu_need_eff))
      forward_cap_by_key[[nm]] <- cap
    }
    
    # 6) Apply caps to desired forwarding (per ship_id)
    for (sid in names(desired_by_ship)) {
      v <- desired_by_ship[[sid]]; if (!length(v)) next
      for (nm in names(v)) {
        cap <- as.integer(forward_cap_by_key[nm]); if (is.na(cap)) cap <- 0L
        if (cap <= 0L) {
          desired_by_ship[[sid]][nm] <- 0L
        } else if (v[[nm]] > cap) {
          desired_by_ship[[sid]][nm] <- cap
        }
      }
    }
    
    # Optional debug:
    # msg <- paste(sprintf("%s=%d", names(forward_cap_by_key), as.integer(forward_cap_by_key)), collapse=", ")
    # message(sprintf("[EU-RESERVE+FLOOR] day=%d caps: %s | activeEU=%d", today, msg, n_active_eu_sites))
  }
  # ----- END EU reserve protection -----
  # ----- END EU reserve protection -----
  # Auto-transfer by MFG ship_id
  if (length(desired_by_ship) > 0) {
    DNS_eu_depot <- PARAM$DND_days + PARAM$ship_lt_depot_to_site_days_eu + PARAM$DNS_buffer_days
    ship_ids <- as.integer(names(desired_by_ship))
    ship_ids <- ship_ids[order(ship_ids)]
    for (sid in ship_ids) {
      need_vec <- desired_by_ship[[as.character(sid)]]
      if (length(need_vec) == 0 || sum(need_vec) <= 0) next
      
      capped <- integer()
      for (nm in names(need_vec)) {
        parts <- strsplit(nm, "__")[[1]]
        kit <- parts[1]; arm <- parts[2]
        elig <- eligible_qty_eu_to_cn(inv, kit, arm, today, PARAM)
        q <- min(as.integer(need_vec[[nm]]), elig)
        if (q >= PARAM$cn_transfer_min_batch) capped[nm] <- q
      }
      if (length(capped) > 0 && sum(capped) >= PARAM$cn_transfer_min_batch) {
        tr <- create_transfer_to_cn(today, inv, capped, PARAM, shipments, next_ship_id, COUNT,
                                    DNS_eu_depot = DNS_eu_depot)
        inv <- tr$inv; shipments <- tr$shipments; next_ship_id <- tr$next_ship_id; COUNT <- tr$COUNT
      }
    }
  }
  
  list(inv = inv, shipments = shipments, next_ship_id = next_ship_id, COUNT = COUNT,
       site_receipts_log = site_receipts_log, depot_receipts_log = depot_receipts_log)
}

# ---------- Dispensing at site (ENHANCED: logs patient & site dispensing) ----------
dispense_visit <- function(today, inv, site_loc, arm, bw_group, visit_index, PARAM,
                           COUNT, stockout_log,
                           subj_id, patient_visit_log, site_dispense_log) {
  need <- kit_need_for_visit(visit_index, bw_group, PARAM)
  kit  <- need$kit_type
  qty_need <- need$qty
  min_exp  <- today + PARAM$DND_days
  
  pick <- pick_kits(inv, site_loc, kit, arm, qty_need, min_exp, PARAM$use_FEFO)
  inv  <- pick$inv
  
  short <- as.integer(qty_need - pick$picked)
  if (short > 0) {
    COUNT$stockout_site <- COUNT$stockout_site + 1L
    region <- if (grepl("^EU_", site_loc)) "EU" else "CN"
    stockout_log[nrow(stockout_log)+1, ] <- list(today, site_loc, region, kit, arm,
                                                 as.integer(qty_need), as.integer(pick$picked), short)
  }
  
  # Log visit-level dispensing
  region <- if (grepl("^EU_", site_loc)) "EU" else "CN"
  patient_visit_log[nrow(patient_visit_log)+1, ] <- list(today, subj_id, site_loc, region, arm,
                                                         bw_group, visit_index, kit,
                                                         as.integer(qty_need), as.integer(pick$picked),
                                                         as.integer(short))
  # Site dispense log
  site_dispense_log[nrow(site_dispense_log)+1, ] <- list(today, site_loc, region, kit, arm,
                                                         subj_id, as.integer(pick$picked))
  
  list(inv = inv, COUNT = COUNT, stockout_log = stockout_log,
       patient_visit_log = patient_visit_log, site_dispense_log = site_dispense_log)
}

# ---------- Total expected kits (rough) ----------
compute_total_required_kits <- function(PARAM) {
  kit_types <- c("2.5ml","5ml","7.5ml")
  arms <- if (PARAM$masking_enabled) PARAM$blind_codes else c("ACT","PBO")
  
  out <- setNames(rep(0L, length(kit_types)*length(arms)),
                  as.vector(outer(kit_types, arms, paste, sep="__")))
  
  reg <- data.frame(region=c("EU","CN"),
                    n=c(PARAM$n_patients_eu, PARAM$n_patients_cn),
                    p_lt90=c(PARAM$p_bw_lt90_eu, PARAM$p_bw_lt90_cn),
                    stringsAsFactors = FALSE)
  
  n_vis <- length(PARAM$nominal_visit_days)
  
  for (r in 1:nrow(reg)) {
    n_pat <- reg$n[r]
    n_lt90 <- n_pat * reg$p_lt90[r]
    n_ge90 <- n_pat - n_lt90
    
    for (arm in arms) {
      for (v in seq_len(n_vis)) {
        if (v <= PARAM$n_weekly_visits) {
          out[paste0(PARAM$kits_phase_weekly$bw_lt90$kit, "__", arm)] <- out[paste0(PARAM$kits_phase_weekly$bw_lt90$kit, "__", arm)] +
            as.integer(round(n_lt90/2 * PARAM$kits_phase_weekly$bw_lt90$qty))
          out[paste0(PARAM$kits_phase_weekly$bw_ge90$kit, "__", arm)] <- out[paste0(PARAM$kits_phase_weekly$bw_ge90$kit, "__", arm)] +
            as.integer(round(n_ge90/2 * PARAM$kits_phase_weekly$bw_ge90$qty))
        } else {
          out[paste0(PARAM$kits_phase_q2w$bw_lt90$kit, "__", arm)] <- out[paste0(PARAM$kits_phase_q2w$bw_lt90$kit, "__", arm)] +
            as.integer(round(n_lt90/2 * PARAM$kits_phase_q2w$bw_lt90$qty))
          out[paste0(PARAM$kits_phase_q2w$bw_ge90$kit, "__", arm)] <- out[paste0(PARAM$kits_phase_q2w$bw_ge90$kit, "__", arm)] +
            as.integer(round(n_ge90/2 * PARAM$kits_phase_q2w$bw_ge90$qty))
        }
      }
    }
  }
  out
}

approx_daily_consumption <- function(total_req, horizon_days) {
  x <- as.numeric(total_req) / max(1, horizon_days)
  names(x) <- names(total_req)
  x
}

# ---------- Stratified block randomization ----------
new_rand_state <- function() list(queue = list())

make_strata_key <- function(region, bw_group) paste(region, bw_group, sep="|")

make_block <- function(block_sizes, codes=c("A","B")) {
  b <- sample(block_sizes, 1)
  half <- b/2
  block <- c(rep(codes[1], half), rep(codes[2], half))
  sample(block, length(block))
}

rand_next <- function(rand_state, strata_key, PARAM) {
  q <- rand_state$queue[[strata_key]]
  if (is.null(q) || length(q) == 0) {
    q <- make_block(PARAM$block_sizes, PARAM$blind_codes)
  }
  assign <- q[1]
  rand_state$queue[[strata_key]] <- q[-1]
  list(assign = assign, rand_state = rand_state)
}

# ---------- Region demand aggregation ----------
# ---------- Region demand aggregation (split-by-phase, consistent with site logic) ----------
predict_region_demand <- function(subjects_all, region, today, horizon_days, PARAM) {
  # Select subjects in the target region
  subs <- subjects_all[subjects_all$region == region, , drop = FALSE]
  if (!nrow(subs)) return(integer())
  
  # Use the same weekly cap as sites (e.g., 13); you can pass a different integer if needed
  weekly_cap <- as.integer(PARAM$n_weekly_visits)
  
  # Predict demand per site within [today, today + horizon_days], split by phase
  dem_site <- predictive_demand_split_by_phase(subs, today, horizon_days, weekly_cap, PARAM)
  
  # Aggregate site-level vectors into a single region-level vector
  out <- integer()
  if (!length(dem_site)) return(out)
  
  for (site_loc in names(dem_site)) {
    v <- dem_site[[site_loc]]
    if (!length(v)) next
    for (k in names(v)) {
      out[k] <- (out[k] %||% 0L) + as.integer(v[[k]])
    }
  }
  storage.mode(out) <- "integer"
  out
}

# ---------- CN target coverage transfer planning ----------
plan_cn_transfer_target_cover <- function(today, inv, subjects_all, PARAM, DNS_eu_depot, DNS_cn_depot) {
  horizon <- PARAM$cn_target_cover_days + PARAM$cn_transfer_safety_days
  dem_cn <- predict_region_demand(subjects_all, region="CN", today, horizon, PARAM)
  if (length(dem_cn) == 0) return(integer())
  
  need <- integer()
  for (nm in names(dem_cn)) {
    parts <- strsplit(nm, "__")[[1]]
    kit <- parts[1]; arm <- parts[2]
    cn_avail <- depot_available_item(inv, "CN_DEPOT", kit, arm, today, DNS_cn_depot)
    gap <- as.integer(dem_cn[[nm]] - cn_avail)
    if (gap > 0) need[nm] <- gap
  }
  need <- need[need >= PARAM$cn_transfer_min_batch]
  need
}

# ---------- Extra manufacturing trigger ----------
check_mfg_needed <- function(today, inv, daily_consump, PARAM, DNS_eu_depot) {
  # 1) Normalize keys and sanitize inputs
  keys <- names(daily_consump)
  if (is.null(keys) || length(keys) == 0) {
    return(list(trigger = FALSE, short = integer(), short_ratio = 0))
  }
  # Force numeric & replace NA with 0 for daily_consump
  dc <- as.numeric(daily_consump)
  names(dc) <- keys
  dc[is.na(dc)] <- 0
  
  # 2) Compute EU depot availability for each key (NA -> 0)
  eu_avail <- setNames(integer(length(keys)), keys)
  for (nm in keys) {
    parts <- strsplit(nm, "__")[[1]]
    kit <- parts[1]; arm <- parts[2]
    val <- depot_available_item(inv, "EU_DEPOT", kit, arm, today, DNS_eu_depot)
    if (is.na(val) || !is.finite(val)) val <- 0L
    eu_avail[nm] <- as.integer(val)
  }
  
  # 3) Lookahead demand and shortage
  look <- PARAM$mfg_reorder_lookahead_days + PARAM$mfg_safety_stock_days
  need <- ceiling(dc * look)
  need[is.na(need)] <- 0L
  storage.mode(need) <- "integer"
  
  short <- need - eu_avail
  short[is.na(short)] <- 0L
  short[short < 0] <- 0L
  storage.mode(short) <- "integer"
  
  # 4) Safe ratio
  total_need  <- sum(need,  na.rm = TRUE)
  total_short <- sum(short, na.rm = TRUE)
  short_ratio <- if (total_need > 0) total_short / total_need else 0
  
  list(trigger = (total_short > 0 && short_ratio >= PARAM$mfg_extra_min_short_ratio),
       short = short,
       short_ratio = short_ratio)
}

# ---------- Site snapshot totals (for KPI) ----------
snapshot_site_totals <- function(inv, shipments, site_loc, today, DNC_days) {
  onhand <- sum(inv$qty[inv$location==site_loc & inv$qty>0 & inv$expiry_day>(today + DNC_days)])
  transit <- 0L
  if (nrow(shipments) > 0) {
    rows <- which(shipments$to_loc==site_loc &
                    shipments$arrive_day>today &
                    shipments$qty>0 &
                    shipments$expiry_day>(today + DNC_days) &
                    shipments$expiry_day>shipments$arrive_day)
    if (length(rows)) transit <- sum(shipments$qty[rows])
  }
  list(onhand=as.integer(onhand), transit=as.integer(transit))
}

process_site_orders_operational <- function(today, site_loc, region,
                                            inv, shipments, next_ship_id, COUNT,
                                            subjects_all, PARAM,
                                            DNS_depot_days, ship_lt_days,
                                            last_order_day, order_type_log,
                                            enrollment_complete,
                                            site_lambda_by_loc) {
  # Always allow a routine opportunity daily (still honor cooldown)
  cooldown_ok <- (today - last_order_day[[site_loc]]) >= PARAM$min_days_between_orders
  
  # -------------------------
  # 1) ROUTINE (daily attempt)
  # -------------------------
  if (cooldown_ok) {
    sub_site <- subjects_all[subjects_all$site_loc == site_loc, , drop = FALSE]
    
    shortLW <- ship_lt_days + PARAM$lookout_additional_days
    longLW  <- shortLW + PARAM$lookout_additional_days
    
    # >>> NEW: choose the cap you want (e.g., 13)
    weekly_cap <- as.integer(PARAM$n_weekly_visits)   # or any number you pass per study
    
    # Use the split-by-phase predictor for BOTH short and long windows
    demS <- predictive_demand_split_by_phase(sub_site, today, shortLW, weekly_cap, PARAM)
    demL <- predictive_demand_split_by_phase(sub_site, today, longLW,  weekly_cap, PARAM)
    
    # Pure item-wise order (no pairwise)
    ord <- compute_site_order_itemwise(site_loc, inv, shipments, demS, demL, today, PARAM,
                                       ship_lt_days, enforce_balance_flag = FALSE)
    
    
    # 2) FUTURE enrollments: pairwise top-up only before global enrollment completes
    pre_pairs <- integer()
    if (!isTRUE(enrollment_complete) && isTRUE(PARAM$preposition_enabled)) {
      pre_pairs <- compute_preposition_pairs_topup(
        site_loc     = site_loc, region = region, today = today,
        inv          = inv, shipments = shipments, ship_lt_days = ship_lt_days,
        lambda_map   = site_lambda_by_loc, PARAM = PARAM
      )
    }
    
    # 3) Merge into final_order (sum by item key). Enrolled demand + FUTURE pairwise top-up.
    final_order <- integer()
    if (isTRUE(ord$trigger) && length(ord$order)) final_order <- ord$order
    if (length(pre_pairs)) {
      keys <- union(names(final_order), names(pre_pairs))
      merged <- setNames(integer(length(keys)), keys)
      for (k in names(final_order)) merged[[k]] <- as.integer(merged[[k]] %||% 0L) + as.integer(final_order[[k]])
      for (k in names(pre_pairs))  merged[[k]]  <- as.integer(merged[[k]]  %||% 0L) + as.integer(pre_pairs[[k]])
      final_order <- merged
    }
    
    # 4) If nothing to ship today, exit early; otherwise create the shipment as usual
    if (length(final_order) == 0 || sum(final_order) <= 0) {
      return(list(inv = inv, shipments = shipments, next_ship_id = next_ship_id, COUNT = COUNT,
                  last_order_day = last_order_day, order_type_log = order_type_log))
    }
    
    # Ship from region depot
    from_depot <- if (region == "EU") "EU_DEPOT" else "CN_DEPOT"
    lane       <- if (region == "EU") "EUDEPOT->EUSITE" else "CNDEPOT->CNSITE"
    
    prev_next_id <- next_ship_id
    res <- create_depot_to_site_shipment(today, inv, from_depot, site_loc, lane, ship_lt_days,
                                         final_order, PARAM, shipments, next_ship_id, COUNT,
                                         DNS_depot_days = DNS_depot_days)
    inv <- res$inv; shipments <- res$shipments; next_ship_id <- res$next_ship_id; COUNT <- res$COUNT
    
    last_order_day[[site_loc]] <- today
    if (res$next_ship_id != prev_next_id) {
      order_type_log[nrow(order_type_log) + 1, ] <- list(today, site_loc, region, "ROUTINE")
    } else {
      order_type_log[nrow(order_type_log) + 1, ] <- list(today, site_loc, region, "ROUTINE_ATTEMPTED")
    }
    return(list(inv = inv, shipments = shipments, next_ship_id = next_ship_id, COUNT = COUNT,
                last_order_day = last_order_day, order_type_log = order_type_log))
  }
  
  # -------------------------
  # 2) EMERGENCY (unchanged, still daily check; no pairwise)
  # -------------------------
  if (PARAM$emergency_enabled && PARAM$emergency_check_daily ) {
    sub_site <- subjects_all[subjects_all$site_loc == site_loc, , drop = FALSE]
    weekly_cap <- as.integer(PARAM$n_weekly_visits)
    demE <- predictive_demand_split_by_phase(sub_site, today, PARAM$emergency_lookout_days,
                                             weekly_cap, PARAM)
    ds <- demE[[site_loc]] %||% integer()
    
    if (length(ds) > 0) {
      DNC_days <- PARAM$DND_days + ship_lt_days + PARAM$DNC_buffer_days
      need_vec <- integer()
      
      for (nm in names(ds)) {
        parts <- strsplit(nm, "__")[[1]]
        kit <- parts[1]; arm <- parts[2]
        d <- as.integer(ds[[nm]] + PARAM$emergency_buffer_kits)
        on <- site_available_item(inv, site_loc, kit, arm, today, DNC_days)
        tr <- in_transit_item(site_loc, kit, arm, today, shipments, DNC_days)
        gap <- d - (on + tr)
        if (gap >= PARAM$emergency_min_gap_kits) need_vec[nm] <- as.integer(gap)
      }
      
      if (sum(need_vec) > 0) {
        from_depot <- if (region == "EU") "EU_DEPOT" else "CN_DEPOT"
        lane       <- if (region == "EU") "EUDEPOT->EUSITE" else "CNDEPOT->CNSITE"
        
        prev_next_id <- next_ship_id
        res <- create_depot_to_site_shipment(today, inv, from_depot, site_loc, lane, ship_lt_days,
                                             need_vec, PARAM, shipments, next_ship_id, COUNT,
                                             DNS_depot_days = DNS_depot_days)
        inv <- res$inv; shipments <- res$shipments; next_ship_id <- res$next_ship_id; COUNT <- res$COUNT
        
        last_order_day[[site_loc]] <- today
        
        if (res$next_ship_id != prev_next_id) {
          order_type_log[nrow(order_type_log) + 1, ] <- list(today, site_loc, region, "EMERGENCY")
        } else {
          order_type_log[nrow(order_type_log) + 1, ] <- list(today, site_loc, region, "EMERGENCY_ATTEMPTED")
        }
      }
    }
  }
  
  list(inv = inv, shipments = shipments, next_ship_id = next_ship_id, COUNT = COUNT,
       last_order_day = last_order_day, order_type_log = order_type_log)
}
############################################################
# 3) INITIALIZATION
############################################################

set_seed(PARAM)

EU_DEPOT <- "EU_DEPOT"
CN_DEPOT <- "CN_DEPOT"

site_ids_eu  <- seq_len(PARAM$n_sites_eu)
site_ids_cn  <- seq_len(PARAM$n_sites_cn)
site_locs_eu <- paste0("EU_SITE_", site_ids_eu)
site_locs_cn <- paste0("CN_SITE_", site_ids_cn)

# Track whether a site has become ACTIVE (first enrollment)
site_activated <- setNames(rep(FALSE, length(c(site_locs_eu, site_locs_cn))),
                           c(site_locs_eu, site_locs_cn))


# ================================
# Simple Scheme A: tier-based site rates
# ================================

# Assign tiers according to mix (e.g., 1/3 low, 1/3 median, 1/3 high)
assign_tiers <- function(n, mix) {
  # mix must sum to 1, e.g. c(low=1/3, median=1/3, high=1/3)
  k <- round(n * mix)
  # fix rounding issues so sum(k)=n
  diff <- n - sum(k)
  if (diff != 0) {
    idx <- order(mix, decreasing = TRUE)
    for (i in seq_len(abs(diff))) {
      k[idx[i]] <- k[idx[i]] + sign(diff)
    }
  }
  rep(names(mix), times = k)
}

# Convert monthly mean (after screen fail) into daily rate before screening
monthly_to_daily <- function(mu_month, sf, days) {
  mu_month / ((1 - sf) * days)
}

# Gamma sampling with mean = mu and shape = phi
sample_gamma <- function(mu, phi) {
  if (mu <= 0) return(0)
  rgamma(1, shape = phi, rate = phi / mu)
}

# 1) Assign tiers for EU and CN
tiers_eu <- assign_tiers(PARAM$n_sites_eu, PARAM$enroll_tier_mix_eu)
tiers_cn <- assign_tiers(PARAM$n_sites_cn, PARAM$enroll_tier_mix_cn)

# 2) Generate lambda per site using tier-specific monthly means
mu_month <- PARAM$enroll_tier_mu_month  # e.g., c(low=1, median=2, high=4)

lambda_eu <- sapply(tiers_eu, function(tier) {
  mu_day <- monthly_to_daily(mu_month[[tier]], PARAM$screen_fail_rate, PARAM$month_days_for_enroll)
  sample_gamma(mu_day, PARAM$enroll_gamma_phi)
})

lambda_cn <- sapply(tiers_cn, function(tier) {
  mu_day <- monthly_to_daily(mu_month[[tier]], PARAM$screen_fail_rate, PARAM$month_days_for_enroll)
  sample_gamma(mu_day, PARAM$enroll_gamma_phi)
})

# Map site_loc -> daily lambda (EU + CN)
site_lambda_by_loc <- build_site_lambda_map(site_locs_eu, site_locs_cn, lambda_eu, lambda_cn)

inactive_eu <- rep(FALSE, PARAM$n_sites_eu)
inactive_cn <- rep(FALSE, PARAM$n_sites_cn)
if (PARAM$inactive_site_pct > 0) {
  inactive_eu[sample(site_ids_eu, size = floor(PARAM$inactive_site_pct * PARAM$n_sites_eu))] <- TRUE
  inactive_cn[sample(site_ids_cn, size = floor(PARAM$inactive_site_pct * PARAM$n_sites_cn))] <- TRUE
}

# Derived DNX
DNS_eu_depot <- PARAM$DND_days + PARAM$ship_lt_depot_to_site_days_eu + PARAM$DNS_buffer_days
DNS_cn_depot <- PARAM$DND_days + PARAM$ship_lt_depot_to_site_days_cn + PARAM$DNS_buffer_days

# Demand baseline for supply planning
total_req <- compute_total_required_kits(PARAM)
daily_consump <- approx_daily_consumption(total_req, PARAM$sim_horizon_days)

inv <- new_inventory_df()
shipments <- new_shipments_df()
next_ship_id <- 1L

COUNT <- list(
  ship_eu_depot_to_sites = 0L,
  ship_cn_depot_to_sites = 0L,
  ship_mfg_to_eu_depot   = 0L,
  ship_eu_to_cn_depot    = 0L,
  stockout_site          = 0L,
  stockout_depot_order   = 0L,
  stockout_depot_item    = 0L,
  expired_total          = 0L,
  damaged_total          = 0L
)

# Logs for KPI
stockout_log <- data.frame(day=integer(), site_loc=character(), region=character(),
                           kit_type=character(), arm=character(),
                           required=integer(), dispensed=integer(), short=integer(),
                           stringsAsFactors=FALSE)

expired_log <- data.frame(day=integer(), location=character(), expired_qty=integer(),
                          stringsAsFactors=FALSE)

site_day_kpi_log <- data.frame(day=integer(), site_loc=character(), region=character(),
                               onhand_total=integer(), transit_total=integer(),
                               stringsAsFactors=FALSE)

order_type_log <- data.frame(day=integer(), site_loc=character(), region=character(),
                             order_type=character(), stringsAsFactors=FALSE)

# ---------- NEW LOGS ----------
patient_visit_log <- data.frame(
  day = integer(), subj_id = integer(), site_loc = character(), region = character(),
  arm = character(), bw_group = character(), visit_index = integer(),
  kit_type = character(), qty_needed = integer(), qty_dispensed = integer(), short = integer(),
  stringsAsFactors = FALSE
)

site_dispense_log <- data.frame(
  day = integer(), site_loc = character(), region = character(),
  kit_type = character(), arm = character(), subj_id = integer(),
  qty_dispensed = integer(), stringsAsFactors = FALSE
)

site_receipts_log <- data.frame(
  day = integer(), site_loc = character(), region = character(),
  kit_type = character(), arm = character(), qty_received = integer(),
  ship_id = integer(), 
  qty_damaged = integer(),
  stringsAsFactors = FALSE
)

# Logs depot-level receipts (net and damaged) for EU_DEPOT and CN_DEPOT
depot_receipts_log <- data.frame(
  day = integer(),          # simulation day when the shipment arrived
  depot = character(),      # "EU_DEPOT" or "CN_DEPOT"
  kit_type = character(),   # e.g., "5ml", "2.5ml", "7.5ml"
  arm = character(),        # "A" / "B" (masked) or "ACT"/"PBO" if unblinded
  qty_received = integer(), # received at depot after damage is applied
  qty_damaged  = integer(), # units damaged upon depot receipt
  stringsAsFactors = FALSE
)
site_expired_log <- data.frame(
  day = integer(), site_loc = character(), region = character(),
  kit_type = character(), arm = character(), expired_qty = integer(),
  stringsAsFactors = FALSE
)

# Depot daily on-hand snapshot (for depot stockout rate calculation)
# Depot Stockout Rate = days with zero onhand / total simulation days * 100
depot_day_log <- data.frame(
  day       = integer(),   # simulation day
  eu_onhand = integer(),   # total EU_DEPOT on-hand (all kits, all arms, qty > 0)
  cn_onhand = integer(),   # total CN_DEPOT on-hand (all kits, all arms, qty > 0)
  stringsAsFactors = FALSE
)


site_kit_day_inventory <- data.frame(
  day = integer(), site_loc = character(), region = character(),
  kit_type = character(), arm = character(), arm_label = character(),
  # existing columns
  onhand_closing = integer(),
  qty_damaged_today = integer(),
  qty_dispensed_today = integer(),
  qty_expired_today = integer(),
  onhand_dnc = integer(),
  intransit_dnc = integer(),
  # NEW: depot -> site logistics (daily)
  qty_shipped_from_depot_today = integer(),   # depart_day == today
  qty_received_at_site_today = integer(),      # arrive_day == today (post-damage)
  stringsAsFactors = FALSE
)




# Helper: kit types to track
KIT_TYPES <- c("2.5ml","5ml","7.5ml")

# Randomization state
rand_state <- new_rand_state()

# ---------- Initialize depots ----------
init_depot_qty <- ceiling(total_req * PARAM$init_depot_fraction_total)
storage.mode(init_depot_qty) <- "integer"
exp0 <- PARAM$day0 + PARAM$shelf_life_days

for (nm in names(init_depot_qty)) {
  parts <- strsplit(nm, "__")[[1]]
  kit <- parts[1]; arm <- parts[2]
  q <- as.integer(unname(init_depot_qty[nm]))
  
  inv <- add_inventory(inv, EU_DEPOT, "DEPOT", "EU", NA_integer_, kit, arm, q, exp0)
  inv <- add_inventory(inv, CN_DEPOT, "DEPOT", "CN", NA_integer_, kit, arm, q, exp0)
}

# Hard assertions: depots must exist
stopifnot(any(inv$location == EU_DEPOT))
stopifnot(any(inv$location == CN_DEPOT))

# ---------- Initialize sites ----------
init_site_stock <- function(region, site_loc, PARAM) {
  n <- PARAM$init_site_firstvisit_patients
  p_lt90 <- if (region == "EU") PARAM$p_bw_lt90_eu else PARAM$p_bw_lt90_cn
  n_lt90 <- round(n * p_lt90)
  n_ge90 <- n - n_lt90
  
  n1 <- ceiling(n/2)
  n2 <- floor(n/2)
  arms <- if (PARAM$masking_enabled) PARAM$blind_codes else c("ACT","PBO")
  arm1 <- arms[1]; arm2 <- arms[2]
  
  lt90_a1 <- ceiling(n_lt90 * n1 / n)
  lt90_a2 <- n_lt90 - lt90_a1
  ge90_a1 <- n1 - lt90_a1
  ge90_a2 <- n2 - lt90_a2
  
  exp_day <- PARAM$day0 + PARAM$shelf_life_days
  inv_add <- new_inventory_df()
  
  inv_add <- add_inventory(inv_add, site_loc, "SITE", region, NA_integer_, "5ml", arm1,
                           lt90_a1 * PARAM$kits_phase_weekly$bw_lt90$qty, exp_day)
  inv_add <- add_inventory(inv_add, site_loc, "SITE", region, NA_integer_, "5ml", arm2,
                           lt90_a2 * PARAM$kits_phase_weekly$bw_lt90$qty, exp_day)
  inv_add <- add_inventory(inv_add, site_loc, "SITE", region, NA_integer_, "5ml", arm1,
                           ge90_a1 * PARAM$kits_phase_weekly$bw_ge90$qty, exp_day)
  inv_add <- add_inventory(inv_add, site_loc, "SITE", region, NA_integer_, "5ml", arm2,
                           ge90_a2 * PARAM$kits_phase_weekly$bw_ge90$qty, exp_day)
  inv_add
}

for (loc in site_locs_eu) inv <- rbind(inv, init_site_stock("EU", loc, PARAM))
for (loc in site_locs_cn) inv <- rbind(inv, init_site_stock("CN", loc, PARAM))

# Subjects
subjects <- data.frame(
  subj_id    = integer(),
  region     = character(),
  site_id    = integer(),
  site_loc   = character(),
  enroll_day = integer(),
  arm        = character(),   # masked code if masking_enabled
  bw_group   = character(),   # lt90/ge90
  dropout_day= integer(),
  dropped    = integer(),
  stringsAsFactors = FALSE
)
subjects$visit_days <- list()

# Manufacturing schedule
planned_mfg_depart_days <- PARAM$day0 + (0:(PARAM$mfg_planned_n_shipments-1)) * PARAM$mfg_planned_cycle_days
planned_mfg_used <- rep(FALSE, length(planned_mfg_depart_days))
last_extra_mfg_day <- -999999L

# Operational ordering last order day per site
last_order_day <- setNames(rep(-999999L, PARAM$n_sites_eu + PARAM$n_sites_cn),
                           c(site_locs_eu, site_locs_cn))

############################################################
# 4) SIMULATION LOOP
############################################################

drop_lambda <- dropout_rate_from_target(PARAM$dropout_over_52w, PARAM$max_followup_days)

subj_counter <- 0L
remaining_eu <- PARAM$n_patients_eu
remaining_cn <- PARAM$n_patients_cn

for (today in 0:PARAM$sim_horizon_days) {
  
  # 1) Expiry removal + log (enhanced with kit-level site expiry)
  exp_res <- remove_expired_by_loc(inv, today)
  inv <- exp_res$inv
  COUNT$expired_total <- COUNT$expired_total + exp_res$expired_total
  
  # Existing aggregate-by-location log
  if (!is.null(exp_res$expired_by_loc)) {
    for (loc in names(exp_res$expired_by_loc)) {
      expired_log[nrow(expired_log)+1, ] <- list(today, loc, as.integer(exp_res$expired_by_loc[[loc]]))
    }
  }
  # NEW: site-level kit expiry log
  if (nrow(exp_res$expired_detail) > 0) {
    det <- exp_res$expired_detail
    det_site_rows <- grepl("^EU_SITE_|^CN_SITE_", det$location)
    if (any(det_site_rows)) {
      dets <- det[det_site_rows, , drop = FALSE]
      dets$region <- ifelse(grepl("^EU_", dets$location), "EU", "CN")
      names(dets)[names(dets) == "location"] <- "site_loc"
      dets <- dets[, c("day","site_loc","region","kit_type","arm","expired_qty")]
      site_expired_log <- rbind(site_expired_log, dets)
    }
  }
  
  # 2) Receive shipments arriving today (damage applied) + log site receipts
  rec <- receive_shipments_today(today, inv, shipments, next_ship_id, COUNT, PARAM, site_receipts_log,depot_receipts_log)
  inv <- rec$inv; shipments <- rec$shipments; next_ship_id <- rec$next_ship_id; COUNT <- rec$COUNT
  site_receipts_log <- rec$site_receipts_log
  depot_receipts_log <-rec$depot_receipts_log
  # 3) Planned manufacturing (covers cycle + safety)
  if (today %in% planned_mfg_depart_days) {
    idx <- which(planned_mfg_depart_days == today)[1]
    if (!planned_mfg_used[idx]) {
      planned_mfg_used[idx] <- TRUE
      qty <- ceiling(daily_consump * (PARAM$mfg_cycle_cover_days + PARAM$mfg_safety_stock_days))
      qty[is.na(qty)] <- 0L
      storage.mode(qty) <- "integer"
      mfg <- create_mfg_shipment(today, qty, PARAM, shipments, next_ship_id, COUNT)
      shipments <- mfg$shipments; next_ship_id <- mfg$next_ship_id; COUNT <- mfg$COUNT
    }
  }
  
  # 4) Extra manufacturing (cooldown + meaningful shortage)
  if (PARAM$allow_additional_mfg_shipments && (today - last_extra_mfg_day) >= PARAM$mfg_extra_cooldown_days) {
    chk <- check_mfg_needed(today, inv, daily_consump, PARAM, DNS_eu_depot)
    if (isTRUE(chk$trigger)) {
      qty <- chk$short
      qty[is.na(qty)] <- 0L
      storage.mode(qty) <- "integer"
      mfg <- create_mfg_shipment(today, qty, PARAM, shipments, next_ship_id, COUNT)
      if (mfg$next_ship_id != next_ship_id) last_extra_mfg_day <- today
      shipments <- mfg$shipments; next_ship_id <- mfg$next_ship_id; COUNT <- mfg$COUNT
    }
  }
  
  # 5) Enrollment (stratified block randomization on region x BW; masked A/B)
  if (today <= PARAM$recruitment_duration_days) {
    
    # EU
    if (remaining_eu > 0) {
      draws_eu <- daily_site_enrollments(lambda_eu, remaining_eu, inactive_eu)
      if (PARAM$screen_fail_rate > 0) draws_eu <- rbinom(length(draws_eu), draws_eu, 1 - PARAM$screen_fail_rate)
      
      for (s in seq_along(draws_eu)) {
        if (draws_eu[s] <= 0) next
        for (k in seq_len(draws_eu[s])) {
          if (remaining_eu <= 0) break
          
          subj_counter <- subj_counter + 1L
          remaining_eu <- remaining_eu - 1L
          
          site_loc <- site_locs_eu[s]
          bw <- ifelse(runif(1) < PARAM$p_bw_lt90_eu, "lt90", "ge90")
          
          if (PARAM$use_strat_block_rand) {
            strata_key <- make_strata_key("EU", bw)
            rr <- rand_next(rand_state, strata_key, PARAM)
            assign_code <- rr$assign
            rand_state <- rr$rand_state
          } else {
            assign_code <- sample(PARAM$blind_codes, 1)
          }
          
          arm_code <- if (PARAM$masking_enabled) assign_code else PARAM$blind_to_arm_map[[assign_code]]
          
          tdrop <- rexp(1, rate = drop_lambda)
          dropout_day <- as.integer(min(today + ceiling(tdrop), today + PARAM$max_followup_days))
          
          vdays <- today + simulate_visit_dates(PARAM$nominal_visit_days,
                                                PARAM$visit_window_minus, 
                                                PARAM$visit_window_plus,
                                                PARAM$visit_sd_within_window)
          
          # Apply visit variations (missing and unscheduled)
          vdays <- apply_visit_variations(vdays, PARAM)
          
          subjects[nrow(subjects)+1,] <- list(subj_counter, "EU", s, site_loc, today, arm_code, bw, dropout_day, 0L)
          subjects$visit_days[[nrow(subjects)]] <- vdays
          
          
          # Activation initial drop (50 x 5ml) on the day the site becomes active
          #if (PARAM$enable_activation_drop && !isTRUE(site_activated[[site_loc]])) {
          #  inv <- grant_activation_initial_stock(inv, site_loc, "EU", today, PARAM)
          #  site_activated[[site_loc]] <- TRUE
          #}
          
        }
      }
    }
    
    # CN
    if (remaining_cn > 0) {
      draws_cn <- daily_site_enrollments(lambda_cn, remaining_cn, inactive_cn)
      if (PARAM$screen_fail_rate > 0) draws_cn <- rbinom(length(draws_cn), draws_cn, 1 - PARAM$screen_fail_rate)
      
      for (s in seq_along(draws_cn)) {
        if (draws_cn[s] <= 0) next
        for (k in seq_len(draws_cn[s])) {
          if (remaining_cn <= 0) break
          
          subj_counter <- subj_counter + 1L
          remaining_cn <- remaining_cn - 1L
          
          site_loc <- site_locs_cn[s]
          bw <- ifelse(runif(1) < PARAM$p_bw_lt90_cn, "lt90", "ge90")
          
          if (PARAM$use_strat_block_rand) {
            strata_key <- make_strata_key("CN", bw)
            rr <- rand_next(rand_state, strata_key, PARAM)
            assign_code <- rr$assign
            rand_state <- rr$rand_state
          } else {
            assign_code <- sample(PARAM$blind_codes, 1)
          }
          
          arm_code <- if (PARAM$masking_enabled) assign_code else PARAM$blind_to_arm_map[[assign_code]]
          
          tdrop <- rexp(1, rate = drop_lambda)
          dropout_day <- as.integer(min(today + ceiling(tdrop), today + PARAM$max_followup_days))
          
          vdays <- today + simulate_visit_dates(PARAM$nominal_visit_days,
                                                PARAM$visit_window_minus, 
                                                PARAM$visit_window_plus,
                                                PARAM$visit_sd_within_window)
          
          # Apply visit variations (missing and unscheduled)
          vdays <- apply_visit_variations(vdays, PARAM)
          
          subjects[nrow(subjects)+1,] <- list(subj_counter, "CN", s, site_loc, today, arm_code, bw, dropout_day, 0L)
          subjects$visit_days[[nrow(subjects)]] <- vdays
          
          # Activation initial drop (50 x 5ml) on the day the site becomes active
          if (PARAM$enable_activation_drop && !isTRUE(site_activated[[site_loc]])) {
            inv <- grant_activation_initial_stock(inv, site_loc, "CN", today, PARAM)
            site_activated[[site_loc]] <- TRUE
          }
        }
      }
    }
  }
  
  # 6) Update dropout flags
  if (nrow(subjects)) {
    subjects$dropped <- ifelse(today >= subjects$dropout_day, 1L, 0L)
  }
  
  # 7) Dispense visits scheduled today (ENHANCED call)
  if (nrow(subjects)) {
    for (i in seq_len(nrow(subjects))) {
      if (subjects$dropped[i] == 1) next
      hits <- which(subjects$visit_days[[i]] == today)
      if (!length(hits)) next
      for (v in hits) {
        # Determine visit index (handle unscheduled visits)
        visit_index <- if (v <= length(PARAM$nominal_visit_days)) v else PARAM$n_weekly_visits
        
        disp <- dispense_visit(today, inv,
                               subjects$site_loc[i],
                               subjects$arm[i],
                               subjects$bw_group[i],
                               visit_index, PARAM, COUNT, stockout_log,
                               subj_id = subjects$subj_id[i],
                               patient_visit_log = patient_visit_log,
                               site_dispense_log = site_dispense_log)
        inv <- disp$inv; COUNT <- disp$COUNT; stockout_log <- disp$stockout_log
        patient_visit_log <- disp$patient_visit_log
        site_dispense_log <- disp$site_dispense_log
      }
    }
  }
  
  
  # 8) CN transfer policy (target coverage) — ENABLED
  if (identical(PARAM$cn_transfer_policy, "target_cover") &&
      ((today - PARAM$day0) %% as.integer(PARAM$cn_transfer_check_freq_days)) == 0) {
    
    # Horizon for coverage: target_cover_days + safety_days
    need_cn <- plan_cn_transfer_target_cover(
      today, inv, subjects_all = subjects, PARAM,
      DNS_eu_depot = DNS_eu_depot, DNS_cn_depot = DNS_cn_depot
    )
    
    if (length(need_cn) > 0) {
      tr <- create_transfer_to_cn(
        today, inv, need_cn, PARAM, shipments, next_ship_id, COUNT,
        DNS_eu_depot = DNS_eu_depot
      )
      inv          <- tr$inv
      shipments    <- tr$shipments
      next_ship_id <- tr$next_ship_id
      COUNT        <- tr$COUNT
    }
  }
  
  # At the beginning of each day in the loop, after any enrollments for the day:
  # Correct: trial completion is based on ever-randomized count (includes dropped/completed subjects)
  total_ever_randomized <- nrow(subjects)
  enrollment_complete <- total_ever_randomized >= PARAM$n_patients_total
  
  # Old balancing is deprecated for routine path; keep it off to avoid conflicts with new rule
  enforce_balance_flag <- FALSE
  # 9) EU sites
  for (loc in site_locs_eu) {
    rr <- process_site_orders_operational(today, loc, "EU",
                                          inv, shipments, next_ship_id, COUNT,
                                          subjects, PARAM,
                                          DNS_depot_days = DNS_eu_depot,
                                          ship_lt_days  = PARAM$ship_lt_depot_to_site_days_eu,
                                          last_order_day, order_type_log,
                                          enrollment_complete = enrollment_complete,
                                          site_lambda_by_loc  = site_lambda_by_loc)
    inv <- rr$inv; shipments <- rr$shipments; next_ship_id <- rr$next_ship_id; COUNT <- rr$COUNT
    last_order_day <- rr$last_order_day; order_type_log <- rr$order_type_log
  }
  
  # 10) CN sites
  for (loc in site_locs_cn) {
    rr <- process_site_orders_operational(today, loc, "CN",
                                          inv, shipments, next_ship_id, COUNT,
                                          subjects, PARAM,
                                          DNS_depot_days = DNS_cn_depot,
                                          ship_lt_days  = PARAM$ship_lt_depot_to_site_days_cn,
                                          last_order_day, order_type_log,
                                          enrollment_complete = enrollment_complete,
                                          site_lambda_by_loc  = site_lambda_by_loc)
    inv <- rr$inv; shipments <- rr$shipments; next_ship_id <- rr$next_ship_id; COUNT <- rr$COUNT
    last_order_day <- rr$last_order_day; order_type_log <- rr$order_type_log
  }
  
  # 11) Site KPI snapshot (total on-hand + pipeline)
  DNC_eu <- PARAM$DND_days + PARAM$ship_lt_depot_to_site_days_eu + PARAM$DNC_buffer_days
  for (loc in site_locs_eu) {
    s <- snapshot_site_totals(inv, shipments, loc, today, DNC_eu)
    site_day_kpi_log[nrow(site_day_kpi_log)+1,] <- list(today, loc, "EU", s$onhand, s$transit)
  }
  DNC_cn <- PARAM$DND_days + PARAM$ship_lt_depot_to_site_days_cn + PARAM$DNC_buffer_days
  for (loc in site_locs_cn) {
    s <- snapshot_site_totals(inv, shipments, loc, today, DNC_cn)
    site_day_kpi_log[nrow(site_day_kpi_log)+1,] <- list(today, loc, "CN", s$onhand, s$transit)
  }
  
  
  
  # 11b) Site x kit daily closing inventory (by arm)
  ARMS_VEC <- if (PARAM$masking_enabled) PARAM$blind_codes else c("ACT","PBO")
  
  for (loc in c(site_locs_eu, site_locs_cn)) {
    region <- if (grepl("^EU_", loc)) "EU" else "CN"
    ship_lt_site <- if (region == "EU") PARAM$ship_lt_depot_to_site_days_eu else PARAM$ship_lt_depot_to_site_days_cn
    DNC_days <- PARAM$DND_days + ship_lt_site + PARAM$DNC_buffer_days
    
    # lanes per region
    lane_to_site <- if (region == "EU") "EUDEPOT->EUSITE" else "CNDEPOT->CNSITE"
    from_depot   <- if (region == "EU") "EU_DEPOT" else "CN_DEPOT"
    
    for (k in KIT_TYPES) {
      for (a in ARMS_VEC) {
        
        # 1) Gross end-of-day on-hand
        rows <- which(inv$location == loc & inv$kit_type == k & inv$arm == a & inv$qty > 0)
        qty_close <- if (length(rows)) sum(inv$qty[rows]) else 0L
        
        # 2) Damaged upon receipt today at site (already tracked)
        if (nrow(site_receipts_log)) {
          dmg_today <- sum(site_receipts_log$qty_damaged[
            site_receipts_log$day == today &
              site_receipts_log$site_loc == loc &
              site_receipts_log$kit_type == k &
              site_receipts_log$arm == a
          ])
        } else dmg_today <- 0L
        
        # 3) Dispensed today (already tracked)
        if (nrow(site_dispense_log)) {
          disp_today <- sum(site_dispense_log$qty_dispensed[
            site_dispense_log$day == today &
              site_dispense_log$site_loc == loc &
              site_dispense_log$kit_type == k &
              site_dispense_log$arm == a
          ])
        } else disp_today <- 0L
        
        # 4) Expired at site today (already tracked)
        if (nrow(site_expired_log)) {
          exp_today <- sum(site_expired_log$expired_qty[
            site_expired_log$day == today &
              site_expired_log$site_loc == loc &
              site_expired_log$kit_type == k &
              site_expired_log$arm == a
          ])
        } else exp_today <- 0L
        
        # 5) DNC-view availability & pipeline
        onhand_dnc    <- site_available_item(inv, loc, k, a, today, DNC_days)
        intransit_dnc <- in_transit_item(loc, k, a, today, shipments, DNC_days)
        
        # 6) Logistics: depot -> site shipped today (depart_day == today), not DNC-filtered
        shipped_today <- 0L
        if (nrow(shipments)) {
          sel_ship <- shipments$from_loc == from_depot &
            shipments$to_loc   == loc &
            shipments$lane     == lane_to_site &
            shipments$depart_day == today &
            shipments$kit_type == k &
            shipments$arm      == a &
            shipments$qty      > 0
          if (any(sel_ship)) shipped_today <- sum(as.integer(shipments$qty[sel_ship]))
        }
        
        # 7) Logistics: site received today (arrive_day == today), post-damage (as logged)
        received_today <- 0L
        if (nrow(site_receipts_log)) {
          sel_recv <- site_receipts_log$day == today &
            site_receipts_log$site_loc == loc &
            site_receipts_log$kit_type == k &
            site_receipts_log$arm == a &
            site_receipts_log$qty_received > 0
          if (any(sel_recv)) received_today <- sum(as.integer(site_receipts_log$qty_received[sel_recv]))
        }
        
        # 8) Arm label
        arm_label <- if (PARAM$masking_enabled) {
          as.character(PARAM$blind_to_arm_map[[a]])
        } else {
          a
        }
        
        # 9) Append the record
        site_kit_day_inventory[nrow(site_kit_day_inventory)+1, ] <-
          list(today, loc, region, k, a, arm_label,
               as.integer(qty_close),
               as.integer(dmg_today),
               as.integer(disp_today),
               as.integer(exp_today),
               as.integer(onhand_dnc),
               as.integer(intransit_dnc),
               as.integer(shipped_today),
               as.integer(received_today))
      }
    }
  }
  
  if (PARAM$verbose && today %% 30 == 0) {
    cat("Day", today,
        "Remaining EU/CN:", remaining_eu, remaining_cn,
        "Ship rows:", nrow(shipments), "\n")
  }

  # Step 12: Depot daily on-hand snapshot
  eu_oh <- as.integer(sum(inv$qty[inv$location == "EU_DEPOT" & inv$qty > 0L]))
  cn_oh <- as.integer(sum(inv$qty[inv$location == "CN_DEPOT" & inv$qty > 0L]))
  depot_day_log[nrow(depot_day_log) + 1L, ] <- list(today, eu_oh, cn_oh)
}

############################################################
############################################################
# 5) OUTPUTS (Global + Site-level KPI + NEW patient/site logs)
############################################################

library(dplyr)
library(tidyr)
library(readr)

# ---------- Global summary table by location ----------
final_by_loc <- inv %>%
  group_by(location) %>%
  summarise(qty = sum(qty), .groups = "drop")

# ---------- Site-level KPI components (dplyr-safe) ----------
# Stockout totals by site
stockout_by_site <- stockout_log %>%
  group_by(site_loc, region) %>%
  summarise(short_kits_total = sum(short), .groups = "drop")

# Stockout days by site
stockout_days_by_site <- stockout_log %>%
  group_by(site_loc, region) %>%
  summarise(stockout_days = n_distinct(day), .groups = "drop")

# Expired by location -> transform to site-level (exclude depots)
expired_by_loc <- expired_log %>%
  group_by(location) %>%
  summarise(expired_qty = sum(expired_qty), .groups = "drop") %>%
  transmute(
    site_loc = location,
    region = case_when(
      grepl("^EU_", site_loc) ~ "EU",
      grepl("^CN_", site_loc) ~ "CN",
      TRUE ~ "DEPOT"
    ),
    expired_qty
  ) %>%
  filter(region != "DEPOT")

# Average on-hand and in-transit coverage
avg_cov <- site_day_kpi_log %>%
  group_by(site_loc, region) %>%
  summarise(
    onhand_total  = mean(onhand_total),
    transit_total = mean(transit_total),
    .groups = "drop"
  )

# Order counts (total / routine / emergency)
order_counts <- order_type_log %>%
  count(site_loc, region, name = "n_orders_total")

order_rt <- order_type_log %>%
  filter(grepl("^ROUTINE", order_type)) %>%    # 如需仅统计真正发货, 改为 order_type == "ROUTINE"
  count(site_loc, region, name = "n_routine_orders")

order_em <- order_type_log %>%
  filter(order_type == "EMERGENCY") %>%
  count(site_loc, region, name = "n_emergency_orders")

# Union of sites from all sources (avoid dropping sites lacking in one source)
all_sites <- bind_rows(
  site_day_kpi_log %>% distinct(site_loc, region),
  stockout_log %>% distinct(site_loc, region),
  order_type_log %>% distinct(site_loc, region),
  expired_by_loc %>% distinct(site_loc, region)
) %>% distinct()

# ---------- Assemble site_kpi ----------
site_kpi <- all_sites %>%
  left_join(avg_cov,              by = c("site_loc","region")) %>%
  left_join(stockout_days_by_site,by = c("site_loc","region")) %>%
  left_join(stockout_by_site,     by = c("site_loc","region")) %>%
  left_join(expired_by_loc,       by = c("site_loc","region")) %>%
  left_join(order_counts,         by = c("site_loc","region")) %>%
  left_join(order_rt,             by = c("site_loc","region")) %>%
  left_join(order_em,             by = c("site_loc","region")) %>%
  mutate(
    across(
      .cols = c(onhand_total, transit_total,
                stockout_days, short_kits_total, expired_qty,
                n_orders_total, n_routine_orders, n_emergency_orders),
      .fns = ~ replace_na(., 0)
    )
  )

# ---------- Patient-level outputs ----------
# Visit schedule with realized dispensing; add enroll_day for context
patient_visit_schedule <- if (nrow(patient_visit_log)) {
  sched <- patient_visit_log[order(patient_visit_log$subj_id, patient_visit_log$visit_index), ]
  base  <- subjects[, c("subj_id","enroll_day")]
  base  <- base[!duplicated(base$subj_id), ]
  merge(sched, base, by = "subj_id", all.x = TRUE)
} else {
  data.frame(subj_id=integer(), day=integer(), site_loc=character(), region=character(),
             arm=character(), bw_group=character(), visit_index=integer(), kit_type=character(),
             qty_needed=integer(), qty_dispensed=integer(), short=integer(), enroll_day=integer(),
             stringsAsFactors = FALSE)
}
write_csv(patient_visit_schedule,  "patient_visit_schedule.csv")

# Total kits used per subject (sum of 'qty_dispensed' across visits)
patient_kit_usage <- if (nrow(patient_visit_log)) {
  agg  <- patient_visit_log %>%
    group_by(subj_id) %>%
    summarise(total_kits_dispensed = sum(qty_dispensed), .groups = "drop")
  base <- subjects[, c("subj_id","site_loc","region","arm","bw_group","enroll_day")]
  base <- base[!duplicated(base$subj_id), ]
  merge(base, agg, by = "subj_id", all.x = TRUE)
} else {
  data.frame(subj_id=integer(), site_loc=character(), region=character(),
             arm=character(), bw_group=character(), enroll_day=integer(),
             total_kits_dispensed=integer(), stringsAsFactors = FALSE)
}
write_csv(patient_kit_usage,  "patient_kit_usage.csv")

# ---------- Site-level kit inventory (closing, ordered) ----------
site_kit_day_inventory <- site_kit_day_inventory[order(site_kit_day_inventory$day,
                                                       site_kit_day_inventory$site_loc,
                                                       site_kit_day_inventory$kit_type,
                                                       site_kit_day_inventory$arm),]
write_csv(site_kit_day_inventory,  "site_kit_day_inventory.csv")

# ---------- Depot daily inventory ----------
# Compute depot stockout KPIs
total_sim_days <- PARAM$sim_horizon_days + 1L
eu_so_days <- as.integer(sum(depot_day_log$eu_onhand == 0L))
cn_so_days <- as.integer(sum(depot_day_log$cn_onhand == 0L))
eu_so_days_pct <- round(eu_so_days / total_sim_days * 100, 4)
cn_so_days_pct <- round(cn_so_days / total_sim_days * 100, 4)

cat("\n--- Depot Stockout Summary ---\n")
cat("EU Depot zero-stock days:", eu_so_days, "/", total_sim_days,
    sprintf("(%.2f%%)\n", eu_so_days_pct))
cat("CN Depot zero-stock days:", cn_so_days, "/", total_sim_days,
    sprintf("(%.2f%%)\n", cn_so_days_pct))

write_csv(depot_day_log, "depot_day_log.csv")

# ---------- OUT list ----------
OUT <- list(
  parameters = PARAM,
  counters   = COUNT,
  remaining_targets = list(EU = remaining_eu, CN = remaining_cn),
  shipments_df = shipments,
  final_inventory = inv,
  final_inventory_by_location = final_by_loc,
  subjects = subjects,
  
  # logs & KPIs
  site_kpi = site_kpi,
  stockout_log = stockout_log,
  expired_log = expired_log,
  order_type_log = order_type_log,
  site_day_kpi_log = site_day_kpi_log,
  
  # NEW outputs
  patient_visit_schedule = patient_visit_schedule,
  patient_kit_usage      = patient_kit_usage,
  site_kit_day_inventory = site_kit_day_inventory,
  site_dispense_log      = site_dispense_log,
  site_receipts_log      = site_receipts_log,
  site_expired_log       = site_expired_log,
  depot_receipts_log     = depot_receipts_log,

  # Depot daily inventory & stockout KPIs
  depot_day_log                  = depot_day_log,
  eu_depot_stockout_days         = eu_so_days,
  cn_depot_stockout_days         = cn_so_days,
  eu_depot_stockout_days_pct     = eu_so_days_pct,
  cn_depot_stockout_days_pct     = cn_so_days_pct
)

cat("\n==================== SUMMARY ====================\n")
cat("EU depot -> EU sites consignments:     ", COUNT$ship_eu_depot_to_sites, "\n")
cat("CN depot -> CN sites consignments:     ", COUNT$ship_cn_depot_to_sites, "\n")

############################################################
# 5.x) SITE INACTIVITY & ENROLLMENT SUMMARY (dplyr version)
############################################################

# Build site master table from initialization
site_master <- bind_rows(
  tibble(site_loc = paste0("EU_SITE_", seq_len(PARAM$n_sites_eu)), region = "EU", inactive = inactive_eu),
  tibble(site_loc = paste0("CN_SITE_", seq_len(PARAM$n_sites_cn)), region = "CN", inactive = inactive_cn)
)

# Enrollment counts per site from subjects table
enr_by_site <- subjects %>% count(site_loc, name = "enrolled_n")

# Join master with enrollment
# Add tier (low / median / high) based on monthly enrollment forecast
site_enrollment_summary <- site_master %>%
  left_join(enr_by_site, by = "site_loc") %>%
  mutate(
    enrolled_n    = replace_na(enrolled_n, 0L),
    no_enrollment = enrolled_n == 0L,
    
    # compute monthly forecast = daily lambda * (1 - screen_fail) * 30
    monthly_enroll_forecast = {
      lam_day <- site_lambda_by_loc[site_loc]
      lam_day[!is.finite(lam_day) | is.na(lam_day)] <- 0
      lam_day * (1 - PARAM$screen_fail_rate) * PARAM$month_days_for_enroll
    },
    
    # simple tier: thresholds = (low+median)/2, (median+high)/2
    tier = case_when(
      monthly_enroll_forecast < ( (PARAM$enroll_tier_mu_month["low"] + 
                                     PARAM$enroll_tier_mu_month["median"]) / 2 ) ~ "low",
      monthly_enroll_forecast < ( (PARAM$enroll_tier_mu_month["median"] + 
                                     PARAM$enroll_tier_mu_month["high"]) / 2 ) ~ "median",
      TRUE ~ "high"
    )
    
  ) %>%
  arrange(region, site_loc)

# Subsets
inactive_and_no_enrollment <- site_enrollment_summary %>% filter(inactive & no_enrollment)
active_but_no_enrollment   <- site_enrollment_summary %>% filter(!inactive & no_enrollment)

# Write CSVs (main summary)
readr::write_csv(site_enrollment_summary,    "site_enrollment_summary.csv")

# Console prints for quick view
cat("\n==================== SITE ENROLLMENT SUMMARY ====================\n")
print(head(site_enrollment_summary, 20))

# Attach to OUT list for programmatic access
OUT$site_enrollment_summary    <- site_enrollment_summary

write_csv(OUT$shipments_df,  "shipments_df.csv")


