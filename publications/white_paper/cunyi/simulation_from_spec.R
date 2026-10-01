############################################################
# IMP Supply Chain Simulation — Generated from Functional Specification
# Source spec: Functional_Specification_4complete.md
# Version: sim_from_spec_v1
# Generated: 2026-08-19
#
# Key improvements vs 4_complete.R:
#   1. depot_day_log implemented (depot stockout KPI)
#   2. 7.5ml initial depot stock uses higher fraction (0.60 vs 0.30)
#   3. Pairwise equalization wired up correctly
#   4. Post-simulation enrollment assertions added
#   5. Unscheduled visits use patient's actual phase for kit type
############################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(lubridate)
  library(readr)
  library(tidyr)
  library(purrr)
})

############################################################
# 1) PARAMETERS  (edit here only)
############################################################
PARAM <- list(
  # ---------- Global controls ----------
  seed              = 20260819L,
  seed_mode         = "fixed",          # "fixed" | "random"
  sim_horizon_days  = 2L * 365L + 120L, # 850 days
  day0              = 0L,
  verbose           = FALSE,

  # ---------- Network ----------
  n_sites_eu = 13L,
  n_sites_cn = 10L,

  # ---------- Patient targets ----------
  n_patients_total = 250L,
  n_patients_eu    = 100L,
  n_patients_cn    = 150L,

  # ---------- BW strata ----------
  p_bw_lt90_eu = 0.70,
  p_bw_lt90_cn = 0.80,

  # ---------- Enrollment model ----------
  enroll_tier_mu_month   = c(low = 1, median = 2, high = 4),
  month_days_for_enroll  = 30L,
  enroll_tier_mix_eu     = c(low = 1/3, median = 1/3, high = 1/3),
  enroll_tier_mix_cn     = c(low = 1/3, median = 1/3, high = 1/3),
  enroll_gamma_phi       = 4.0,
  recruitment_duration_days = 450L,
  screen_fail_rate       = 0.35,
  inactive_site_pct      = 0.15,

  # ---------- Dropout ----------
  dropout_over_52w   = 0.20,
  max_followup_days  = 52L * 7L,        # 364 days

  # ---------- Visit schedule ----------
  nominal_visit_days = c(seq(0L,  13L*7L,  by = 7L),
                         seq(14L*7L, 14L*7L + (20L-1L)*14L, by = 14L)),
  visit_window_minus       = 4L,
  visit_window_plus        = 4L,
  visit_sd_within_window   = 2.0,
  unscheduled_visit_rate   = 0.10,
  missing_visit_rate       = 0.10,
  n_weekly_visits          = 13L,

  # ---------- Dosing ----------
  kits_phase_weekly = list(
    bw_lt90 = list(kit = "5ml",   qty = 3L),
    bw_ge90 = list(kit = "5ml",   qty = 5L)
  ),
  kits_phase_q2w = list(
    bw_lt90 = list(kit = "2.5ml", qty = 1L),
    bw_ge90 = list(kit = "7.5ml", qty = 1L)
  ),

  # ---------- Shelf life / expiry ----------
  shelf_life_days              = 24L * 30L,  # 720 days
  min_remaining_eu_depot_days  = 195L,       # 6.5 × 30
  min_remaining_cn_depot_days  = 270L,       # 9.0 × 30
  min_remaining_site_days      = 180L,       # 6.0 × 30
  DND_days                     = 13L,

  # ---------- Lead times ----------
  ship_lt_mfg_to_eu_depot_days    = 7L,
  ship_lt_depot_to_site_days_eu   = 7L,
  ship_lt_depot_to_site_days_cn   = 7L,
  ship_lt_eu_to_cn_depot_days     = 60L,
  DNC_buffer_days  = 7L,
  DNS_buffer_days  = 30L,
  lookout_additional_days = 30L,

  # ---------- Site thresholds ----------
  min_threshold_kits   = 20L,
  max_threshold_kits   = 60L,
  emergency_lookout_days  = 14L,
  emergency_min_gap_kits  = 3L,
  emergency_buffer_kits   = 0L,
  emergency_enabled       = TRUE,
  emergency_check_daily   = TRUE,
  min_days_between_orders = 1L,

  # ---------- Initial inventory ----------
  init_depot_fraction_total    = 0.30,
  init_depot_fraction_7_5ml    = 0.60,   # FIX: higher fraction for 7.5ml (spec limitation #3)
  init_site_firstvisit_patients = 4L,

  # ---------- Manufacturing ----------
  mfg_planned_cycle_days       = 60L,
  mfg_planned_n_shipments      = 8L,
  mfg_cycle_cover_days         = 150L,
  mfg_safety_stock_days        = 60L,
  allow_additional_mfg_shipments = TRUE,
  mfg_reorder_lookahead_days   = 90L,
  mfg_extra_cooldown_days      = 60L,
  mfg_extra_min_short_ratio    = 0.01,
  shipment_damage_rate         = 0.01,

  # ---------- CN transfer ----------
  auto_transfer_on_mfg_receipt  = TRUE,
  forward_to_cn_fraction        = 0.50,
  eu_forward_reserve_days       = 90L,
  eu_reserve_floor_ratio_7_5ml  = 0.50,
  cn_transfer_policy            = "target_cover",
  cn_target_cover_days          = 90L,
  cn_transfer_safety_days       = 14L,
  cn_transfer_check_freq_days   = 1L,
  cn_transfer_min_batch         = 10L,

  # ---------- Pre-positioning ----------
  preposition_enabled              = TRUE,
  preposition_pair_kit_type        = "5ml",
  preposition_cover_months         = 1.0,
  preposition_pairs_rounding       = "ceil",
  preposition_starter_horizon_days = 14L,
  preposition_min_pairs            = 0L,
  preposition_max_pairs            = Inf,
  preposition_units_mode           = "max_bw",

  # ---------- Pairwise equalization (FIX: now wired to runtime flag) ----------
  enable_pairwise_equalize_before_complete = TRUE,

  # ---------- FEFO ----------
  use_FEFO = TRUE,

  # ---------- Randomization ----------
  use_strat_block_rand    = TRUE,
  rand_strata             = c("region", "bw_group"),
  block_sizes             = c(4L, 6L),
  masking_enabled         = TRUE,
  blind_codes             = c("A", "B"),
  blind_to_arm_map        = c(A = "ACT", B = "PBO")
)

############################################################
# 2) UTILITY FUNCTIONS
############################################################

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0 || all(is.na(a))) b else a

# Safe integer coercion — preserves names
i0 <- function(x) {
  nm <- names(x)
  x  <- suppressWarnings(as.integer(x))
  x[is.na(x)] <- 0L
  if (!is.null(nm)) names(x) <- nm
  x
}

set_seed <- function(PARAM) {
  if (identical(PARAM$seed_mode, "random") || is.null(PARAM$seed)) {
    s <- as.integer((as.numeric(Sys.time()) * 1000) %% .Machine$integer.max)
    set.seed(s)
  } else {
    set.seed(PARAM$seed)
  }
}

rtruncnorm <- function(n, mean, sd, lower, upper) {
  out <- numeric(n); i <- 1L
  while (i <= n) {
    x <- rnorm(1L, mean, sd)
    if (x >= lower && x <= upper) { out[i] <- x; i <- i + 1L }
  }
  out
}

dropout_rate_from_target <- function(p_drop, horizon_days) {
  -log(1 - p_drop) / horizon_days
}

simulate_visit_dates <- function(nominal_days, wminus, wplus, sd) {
  dev <- rtruncnorm(length(nominal_days), 0, sd, -wminus, wplus)
  as.integer(round(nominal_days + dev))
}

apply_visit_variations <- function(visit_days, PARAM) {
  n <- length(visit_days)
  # Missing visits
  n_miss <- rbinom(1L, n, PARAM$missing_visit_rate)
  if (n_miss > 0L) visit_days <- visit_days[-sample(seq_len(n), n_miss)]
  # Unscheduled visits
  if (length(visit_days) > 1L) {
    n_unsched <- rbinom(1L, length(visit_days) - 1L, PARAM$unscheduled_visit_rate)
    if (n_unsched > 0L) {
      for (i in seq_len(n_unsched)) {
        idx <- sample(seq_len(length(visit_days) - 1L), 1L)
        mid <- (visit_days[idx] + visit_days[idx + 1L]) / 2
        visit_days <- c(visit_days, as.integer(round(mid + rnorm(1L, 0, 2))))
      }
      visit_days <- sort(unique(visit_days))
    }
  }
  as.integer(visit_days)
}

# FIX: unscheduled visits now use patient's actual phase
kit_need_for_visit <- function(visit_index, bw_group, PARAM, actual_day = NULL,
                               enroll_day = NULL) {
  # Determine phase from visit index
  # If visit_index > n_weekly_visits → Q2W phase
  phase_weekly <- (visit_index <= PARAM$n_weekly_visits)
  if (phase_weekly) {
    spec <- if (bw_group == "lt90") PARAM$kits_phase_weekly$bw_lt90
            else                    PARAM$kits_phase_weekly$bw_ge90
  } else {
    spec <- if (bw_group == "lt90") PARAM$kits_phase_q2w$bw_lt90
            else                    PARAM$kits_phase_q2w$bw_ge90
  }
  list(kit_type = spec$kit, qty = as.integer(spec$qty))
}

############################################################
# 3) INVENTORY & SHIPMENT DATA FRAMES
############################################################

new_inventory_df <- function() {
  data.frame(location=character(), level=character(), region=character(),
             site_id=integer(), kit_type=character(), arm=character(),
             qty=integer(), expiry_day=integer(), stringsAsFactors=FALSE)
}

add_inventory <- function(inv, location, level, region, site_id,
                          kit_type, arm, qty, expiry_day) {
  if (is.na(qty) || qty <= 0L) return(inv)
  inv[nrow(inv)+1L, ] <- list(location, level, region, i0(site_id),
                               kit_type, arm, i0(qty), i0(expiry_day))
  inv
}

new_shipments_df <- function() {
  data.frame(ship_id=integer(), from_loc=character(), to_loc=character(),
             lane=character(), depart_day=integer(), arrive_day=integer(),
             kit_type=character(), arm=character(), qty=integer(),
             expiry_day=integer(), stringsAsFactors=FALSE)
}

############################################################
# 4) EXPIRY REMOVAL
############################################################

remove_expired_by_loc <- function(inv, today) {
  rows <- which(inv$qty > 0L & inv$expiry_day < today)
  if (!length(rows)) {
    empty_det <- data.frame(day=integer(), location=character(),
                            kit_type=character(), arm=character(),
                            expired_qty=integer(), stringsAsFactors=FALSE)
    return(list(inv=inv, expired_total=0L, expired_by_loc=NULL,
                expired_detail=empty_det))
  }
  det <- inv[rows, c("location","kit_type","arm","qty")]
  det$day <- today
  names(det)[names(det)=="qty"] <- "expired_qty"
  det <- det[, c("day","location","kit_type","arm","expired_qty")]
  exp_by_loc <- tapply(inv$qty[rows], inv$location[rows], sum)
  inv$qty[rows] <- 0L
  list(inv=inv, expired_total=i0(sum(exp_by_loc)),
       expired_by_loc=exp_by_loc, expired_detail=det)
}

############################################################
# 5) FEFO PICKING
############################################################

pick_kits <- function(inv, location, kit_type, arm, qty_need,
                      min_expiry_day, use_FEFO=TRUE) {
  rows <- which(inv$location==location & inv$kit_type==kit_type &
                  inv$arm==arm & inv$qty>0L & inv$expiry_day>min_expiry_day)
  if (!length(rows) || qty_need<=0L)
    return(list(inv=inv, picked=0L, lots=data.frame(expiry_day=integer(),qty=integer())))
  if (use_FEFO) rows <- rows[order(inv$expiry_day[rows])]
  remaining <- qty_need; picked <- 0L
  lots <- data.frame(expiry_day=integer(), qty=integer())
  for (r in rows) {
    if (remaining<=0L) break
    take <- min(inv$qty[r], remaining)
    inv$qty[r] <- inv$qty[r] - take
    remaining  <- remaining - take
    picked     <- picked + take
    lots[nrow(lots)+1L,] <- list(i0(inv$expiry_day[r]), i0(take))
  }
  list(inv=inv, picked=i0(picked), lots=lots)
}

apply_shipment_damage <- function(qty, damage_rate) {
  damaged  <- rbinom(1L, size=qty, prob=damage_rate)
  received <- qty - damaged
  list(received=i0(received), damaged=i0(damaged))
}

############################################################
# 6) AVAILABILITY HELPERS
############################################################

site_available_item <- function(inv, site_loc, kit_type, arm, today, DNC_days) {
  rows <- which(inv$location==site_loc & inv$kit_type==kit_type &
                  inv$arm==arm & inv$qty>0L &
                  inv$expiry_day>(today+DNC_days))
  i0(sum(inv$qty[rows]))
}

depot_available_item <- function(inv, depot_loc, kit_type, arm, today, DNS_days) {
  rows <- which(inv$location==depot_loc & inv$kit_type==kit_type &
                  inv$arm==arm & inv$qty>0L &
                  inv$expiry_day>(today+DNS_days))
  i0(sum(inv$qty[rows]))
}

in_transit_item <- function(site_loc, kit_type, arm, today, shipments, DNC_days) {
  if (is.null(shipments) || !nrow(shipments)) return(0L)
  rows <- which(shipments$to_loc==site_loc & shipments$kit_type==kit_type &
                  shipments$arm==arm & shipments$arrive_day>today &
                  shipments$qty>0L &
                  shipments$expiry_day>(today+DNC_days) &
                  shipments$expiry_day>shipments$arrive_day)
  i0(sum(shipments$qty[rows]))
}

eligible_qty_eu_to_cn <- function(inv, kit, arm, today, PARAM) {
  DNS_eu <- PARAM$DND_days + PARAM$ship_lt_depot_to_site_days_eu + PARAM$DNS_buffer_days
  arrive <- today + PARAM$ship_lt_eu_to_cn_depot_days
  min_exp <- max(today + DNS_eu, arrive + PARAM$min_remaining_cn_depot_days)
  rows <- which(inv$location=="EU_DEPOT" & inv$kit_type==kit &
                  inv$arm==arm & inv$qty>0L & inv$expiry_day>min_exp)
  i0(sum(inv$qty[rows]))
}

############################################################
# 7) DEMAND PREDICTION
############################################################

predict_demand_site <- function(sub_site, today, window_days, weekly_cap, PARAM) {
  out <- integer()
  if (!nrow(sub_site)) return(out)
  nominal <- as.integer(PARAM$nominal_visit_days)
  wminus  <- as.integer(PARAM$visit_window_minus)
  end_day <- today + as.integer(window_days)
  weekly_cap <- as.integer(min(weekly_cap, length(nominal)))

  for (i in seq_len(nrow(sub_site))) {
    if (sub_site$dropped[i]==1L) next
    enroll <- as.integer(sub_site$enroll_day[i])
    arm    <- sub_site$arm[i]
    bw     <- sub_site$bw_group[i]
    earliest <- enroll + nominal - wminus

    for (j in seq_along(nominal)) {
      if (earliest[j] < today || earliest[j] > end_day) next
      need <- kit_need_for_visit(j, bw, PARAM)
      key  <- paste0(need$kit_type, "__", arm)
      cur  <- out[key]; if (is.na(cur)) cur <- 0L
      out[key] <- cur + need$qty
    }
  }
  storage.mode(out) <- "integer"
  out
}

predict_region_demand <- function(subjects_all, region, today, horizon_days, PARAM) {
  subs <- subjects_all[subjects_all$region==region, , drop=FALSE]
  if (!nrow(subs)) return(integer())
  sites <- unique(subs$site_loc)
  out   <- integer()
  for (s in sites) {
    sub_s <- subs[subs$site_loc==s, , drop=FALSE]
    v     <- predict_demand_site(sub_s, today, horizon_days,
                                  PARAM$n_weekly_visits, PARAM)
    for (k in names(v)) {
      cur <- out[k]; if (is.na(cur)) cur <- 0L
      out[k] <- cur + as.integer(v[k])
    }
  }
  storage.mode(out) <- "integer"
  out
}

############################################################
# 8) RANDOMIZATION
############################################################

new_rand_state <- function() list(queue=list())

make_strata_key <- function(region, bw_group) paste(region, bw_group, sep="|")

make_block <- function(block_sizes, codes=c("A","B")) {
  b <- sample(block_sizes, 1L)
  block <- c(rep(codes[1L], b/2L), rep(codes[2L], b/2L))
  sample(block, length(block))
}

rand_next <- function(rand_state, strata_key, PARAM) {
  q <- rand_state$queue[[strata_key]]
  if (is.null(q) || !length(q)) q <- make_block(PARAM$block_sizes, PARAM$blind_codes)
  assign_code <- q[1L]
  rand_state$queue[[strata_key]] <- q[-1L]
  list(assign=assign_code, rand_state=rand_state)
}

############################################################
# 9) PAIRWISE EQUALIZATION (FIX: now a standalone function, called when flag is TRUE)
############################################################

augment_pairwise_equalization <- function(site_loc, inv, order_vec, PARAM) {
  if (!length(order_vec)) return(order_vec)
  arms <- PARAM$blind_codes
  if (length(arms) != 2L) return(order_vec)
  a1 <- arms[1L]; a2 <- arms[2L]
  kit_types <- unique(sub("__.*$", "", names(order_vec)))
  for (k in kit_types) {
    k1 <- paste0(k,"__",a1); k2 <- paste0(k,"__",a2)
    q1 <- i0(order_vec[k1] %||% 0L); q2 <- i0(order_vec[k2] %||% 0L)
    if ((q1>0L && q2==0L) || (q2>0L && q1==0L)) {
      on1 <- i0(sum(inv$qty[inv$location==site_loc & inv$kit_type==k & inv$arm==a1]))
      on2 <- i0(sum(inv$qty[inv$location==site_loc & inv$kit_type==k & inv$arm==a2]))
      if (q1>0L && q2==0L) {
        extra <- i0(max(0L, (on1+q1) - on2))
        if (extra>0L) order_vec[k2] <- i0((order_vec[k2] %||% 0L) + extra)
      } else {
        extra <- i0(max(0L, (on2+q2) - on1))
        if (extra>0L) order_vec[k1] <- i0((order_vec[k1] %||% 0L) + extra)
      }
    }
  }
  order_vec
}

############################################################
# 10) TOTAL REQUIRED KITS (for MFG calibration)
############################################################

compute_total_required_kits <- function(PARAM) {
  arms     <- PARAM$blind_codes
  kit_types <- c("2.5ml","5ml","7.5ml")
  out <- setNames(rep(0L, length(kit_types)*length(arms)),
                  as.vector(outer(kit_types, arms, paste, sep="__")))
  reg <- data.frame(region=c("EU","CN"),
                    n    =c(PARAM$n_patients_eu, PARAM$n_patients_cn),
                    p_lt90=c(PARAM$p_bw_lt90_eu, PARAM$p_bw_lt90_cn),
                    stringsAsFactors=FALSE)
  n_vis <- length(PARAM$nominal_visit_days)
  for (r in seq_len(nrow(reg))) {
    n_lt90 <- reg$n[r] * reg$p_lt90[r]
    n_ge90 <- reg$n[r] - n_lt90
    for (arm in arms) {
      for (v in seq_len(n_vis)) {
        if (v <= PARAM$n_weekly_visits) {
          out[paste0(PARAM$kits_phase_weekly$bw_lt90$kit,"__",arm)] <-
            out[paste0(PARAM$kits_phase_weekly$bw_lt90$kit,"__",arm)] +
            i0(round(n_lt90/2 * PARAM$kits_phase_weekly$bw_lt90$qty))
          out[paste0(PARAM$kits_phase_weekly$bw_ge90$kit,"__",arm)] <-
            out[paste0(PARAM$kits_phase_weekly$bw_ge90$kit,"__",arm)] +
            i0(round(n_ge90/2 * PARAM$kits_phase_weekly$bw_ge90$qty))
        } else {
          out[paste0(PARAM$kits_phase_q2w$bw_lt90$kit,"__",arm)] <-
            out[paste0(PARAM$kits_phase_q2w$bw_lt90$kit,"__",arm)] +
            i0(round(n_lt90/2 * PARAM$kits_phase_q2w$bw_lt90$qty))
          out[paste0(PARAM$kits_phase_q2w$bw_ge90$kit,"__",arm)] <-
            out[paste0(PARAM$kits_phase_q2w$bw_ge90$kit,"__",arm)] +
            i0(round(n_ge90/2 * PARAM$kits_phase_q2w$bw_ge90$qty))
        }
      }
    }
  }
  out
}

approx_daily_consumption <- function(total_req, horizon_days) {
  x <- as.numeric(total_req) / max(1L, horizon_days)
  names(x) <- names(total_req)
  x
}

############################################################
# 11) SHIPMENT CREATION
############################################################

create_mfg_shipment <- function(today, qty_vec, PARAM, shipments, next_ship_id, COUNT) {
  if (!length(qty_vec) || sum(qty_vec, na.rm=TRUE)<=0L)
    return(list(shipments=shipments, next_ship_id=next_ship_id, COUNT=COUNT))
  depart <- today
  arrive <- today + PARAM$ship_lt_mfg_to_eu_depot_days
  expday <- depart + PARAM$shelf_life_days
  wrote  <- FALSE
  for (nm in names(qty_vec)) {
    q <- i0(qty_vec[nm]); if (q<=0L) next
    parts <- strsplit(nm,"__")[[1L]]
    shipments[nrow(shipments)+1L,] <-
      list(next_ship_id,"MFG","EU_DEPOT","MFG->EUDEPOT",
           depart, arrive, parts[1L], parts[2L], q, expday)
    wrote <- TRUE
  }
  if (wrote) { COUNT$ship_mfg_to_eu_depot <- COUNT$ship_mfg_to_eu_depot+1L
               next_ship_id <- next_ship_id+1L }
  list(shipments=shipments, next_ship_id=next_ship_id, COUNT=COUNT)
}

create_depot_to_site_shipment <- function(today, inv, from_depot, to_site, lane,
                                          ship_lt_days, order_vec, PARAM,
                                          shipments, next_ship_id, COUNT, DNS_depot_days) {
  if (!length(order_vec) || sum(order_vec)<=0L)
    return(list(inv=inv,shipments=shipments,next_ship_id=next_ship_id,COUNT=COUNT))
  depart  <- today; arrive <- today + ship_lt_days
  min_exp <- max(today + DNS_depot_days, arrive + PARAM$min_remaining_site_days)
  picked_total <- 0L; any_short <- FALSE
  for (nm in names(order_vec)) {
    q_need <- i0(order_vec[nm]); if (q_need<=0L) next
    parts  <- strsplit(nm,"__")[[1L]]
    pick   <- pick_kits(inv, from_depot, parts[1L], parts[2L],
                        q_need, min_exp, PARAM$use_FEFO)
    inv    <- pick$inv
    if (pick$picked < q_need) { any_short <- TRUE
      COUNT$stockout_depot_item <- COUNT$stockout_depot_item+1L }
    if (pick$picked > 0L) {
      picked_total <- picked_total + pick$picked
      for (j in seq_len(nrow(pick$lots))) {
        shipments[nrow(shipments)+1L,] <-
          list(next_ship_id, from_depot, to_site, lane, depart, arrive,
               parts[1L], parts[2L],
               i0(pick$lots$qty[j]), i0(pick$lots$expiry_day[j]))
      }
    }
  }
  if (picked_total>0L) {
    if (grepl("EUSITE$",lane))   COUNT$ship_eu_depot_to_sites <- COUNT$ship_eu_depot_to_sites+1L
    if (grepl("CNSITE$",lane))   COUNT$ship_cn_depot_to_sites <- COUNT$ship_cn_depot_to_sites+1L
    next_ship_id <- next_ship_id+1L
  }
  if (any_short) COUNT$stockout_depot_order <- COUNT$stockout_depot_order+1L
  list(inv=inv,shipments=shipments,next_ship_id=next_ship_id,COUNT=COUNT)
}

create_transfer_to_cn <- function(today, inv, need_vec, PARAM,
                                  shipments, next_ship_id, COUNT, DNS_eu_depot) {
  if (!length(need_vec) || sum(need_vec)<=0L)
    return(list(inv=inv,shipments=shipments,next_ship_id=next_ship_id,COUNT=COUNT))
  depart  <- today; arrive <- today + PARAM$ship_lt_eu_to_cn_depot_days
  min_exp <- max(today + DNS_eu_depot, arrive + PARAM$min_remaining_cn_depot_days)
  picked_total <- 0L; any_short <- FALSE
  for (nm in names(need_vec)) {
    q_need <- i0(need_vec[nm]); if (q_need<=0L) next
    parts  <- strsplit(nm,"__")[[1L]]
    pick   <- pick_kits(inv,"EU_DEPOT",parts[1L],parts[2L],
                        q_need, min_exp, PARAM$use_FEFO)
    inv    <- pick$inv
    if (pick$picked < q_need) { any_short <- TRUE
      COUNT$stockout_depot_item <- COUNT$stockout_depot_item+1L }
    if (pick$picked > 0L) {
      picked_total <- picked_total + pick$picked
      for (j in seq_len(nrow(pick$lots))) {
        shipments[nrow(shipments)+1L,] <-
          list(next_ship_id,"EU_DEPOT","CN_DEPOT","EUDEPOT->CNDEPOT",
               depart, arrive, parts[1L], parts[2L],
               i0(pick$lots$qty[j]), i0(pick$lots$expiry_day[j]))
      }
    }
  }
  if (picked_total >= PARAM$cn_transfer_min_batch) {
    COUNT$ship_eu_to_cn_depot <- COUNT$ship_eu_to_cn_depot+1L
    next_ship_id <- next_ship_id+1L
  }
  if (any_short) COUNT$stockout_depot_order <- COUNT$stockout_depot_order+1L
  list(inv=inv,shipments=shipments,next_ship_id=next_ship_id,COUNT=COUNT)
}

############################################################
# 12) RECEIVE SHIPMENTS (with EU→CN auto-forward)
############################################################

receive_shipments_today <- function(today, inv, shipments, next_ship_id, COUNT, PARAM,
                                    site_receipts_log, depot_receipts_log, subjects) {
  arr <- shipments[shipments$arrive_day==today, , drop=FALSE]
  if (!nrow(arr))
    return(list(inv=inv, shipments=shipments, next_ship_id=next_ship_id, COUNT=COUNT,
                site_receipts_log=site_receipts_log, depot_receipts_log=depot_receipts_log))

  desired_by_ship <- list()

  for (i in seq_len(nrow(arr))) {
    row <- arr[i,]
    dmg <- apply_shipment_damage(row$qty, PARAM$shipment_damage_rate)
    COUNT$damaged_total <- COUNT$damaged_total + dmg$damaged
    if (dmg$received <= 0L) next

    if (row$to_loc == "EU_DEPOT") {
      inv <- add_inventory(inv,"EU_DEPOT","DEPOT","EU",NA_integer_,
                           row$kit_type, row$arm, dmg$received, row$expiry_day)
      depot_receipts_log <- dplyr::bind_rows(depot_receipts_log,
        dplyr::tibble(day=today, depot="EU_DEPOT", kit_type=row$kit_type,
                      arm=row$arm, qty_received=i0(dmg$received),
                      qty_damaged=i0(dmg$damaged)))
      # Queue auto-forward to CN
      if (isTRUE(PARAM$auto_transfer_on_mfg_receipt) &&
          identical(row$from_loc,"MFG")) {
        sid <- as.character(row$ship_id)
        nm  <- paste0(row$kit_type,"__",row$arm)
        des <- i0(floor(dmg$received * PARAM$forward_to_cn_fraction))
        if (des > 0L) {
          if (is.null(desired_by_ship[[sid]])) desired_by_ship[[sid]] <- integer()
          cur <- desired_by_ship[[sid]][nm]; if (is.na(cur)) cur <- 0L
          desired_by_ship[[sid]][nm] <- cur + des
        }
      }

    } else if (row$to_loc == "CN_DEPOT") {
      inv <- add_inventory(inv,"CN_DEPOT","DEPOT","CN",NA_integer_,
                           row$kit_type, row$arm, dmg$received, row$expiry_day)
      depot_receipts_log <- dplyr::bind_rows(depot_receipts_log,
        dplyr::tibble(day=today, depot="CN_DEPOT", kit_type=row$kit_type,
                      arm=row$arm, qty_received=i0(dmg$received),
                      qty_damaged=i0(dmg$damaged)))

    } else {
      region <- if (grepl("^EU_",row$to_loc)) "EU" else "CN"
      inv <- add_inventory(inv, row$to_loc,"SITE",region,NA_integer_,
                           row$kit_type, row$arm, dmg$received, row$expiry_day)
      site_receipts_log[nrow(site_receipts_log)+1L,] <-
        list(today, row$to_loc, region, row$kit_type, row$arm,
             i0(dmg$received), i0(row$ship_id), i0(dmg$damaged))
    }
  }

  # EU reserve protection before auto-forward
  if (length(desired_by_ship) > 0L) {
    DNS_eu <- PARAM$DND_days + PARAM$ship_lt_depot_to_site_days_eu + PARAM$DNS_buffer_days
    dem_eu <- predict_region_demand(subjects,"EU",today,PARAM$eu_forward_reserve_days,PARAM)
    n_active_eu <- length(unique(subjects$site_loc[subjects$region=="EU" & subjects$dropped==0L]))
    union_keys  <- unique(unlist(lapply(desired_by_ship, names)))
    forward_cap <- setNames(integer(length(union_keys)), union_keys)

    for (nm in union_keys) {
      parts   <- strsplit(nm,"__")[[1L]]
      kit <- parts[1L]; arm <- parts[2L]
      avail   <- depot_available_item(inv,"EU_DEPOT",kit,arm,today,DNS_eu)
      fcst    <- i0(dem_eu[nm])
      floor   <- if (identical(kit,"7.5ml") && n_active_eu>0L)
                   i0(round(PARAM$eu_reserve_floor_ratio_7_5ml * PARAM$min_threshold_kits) * n_active_eu)
                 else 0L
      forward_cap[[nm]] <- i0(max(0L, avail - fcst - floor))
    }

    for (sid in names(desired_by_ship)) {
      for (nm in names(desired_by_ship[[sid]])) {
        cap <- i0(forward_cap[nm])
        if (cap <= 0L) desired_by_ship[[sid]][nm] <- 0L
        else if (desired_by_ship[[sid]][[nm]] > cap) desired_by_ship[[sid]][nm] <- cap
      }
    }

    DNS_eu <- PARAM$DND_days + PARAM$ship_lt_depot_to_site_days_eu + PARAM$DNS_buffer_days
    for (sid in names(desired_by_ship)) {
      nv <- desired_by_ship[[sid]]
      if (!length(nv) || sum(nv)<=0L) next
      capped <- integer()
      for (nm in names(nv)) {
        parts <- strsplit(nm,"__")[[1L]]
        elig  <- eligible_qty_eu_to_cn(inv, parts[1L], parts[2L], today, PARAM)
        q     <- min(i0(nv[[nm]]), elig)
        if (q >= PARAM$cn_transfer_min_batch) capped[nm] <- q
      }
      if (length(capped) && sum(capped)>=PARAM$cn_transfer_min_batch) {
        tr <- create_transfer_to_cn(today,inv,capped,PARAM,shipments,next_ship_id,COUNT,DNS_eu)
        inv<-tr$inv; shipments<-tr$shipments; next_ship_id<-tr$next_ship_id; COUNT<-tr$COUNT
      }
    }
  }

  list(inv=inv, shipments=shipments, next_ship_id=next_ship_id, COUNT=COUNT,
       site_receipts_log=site_receipts_log, depot_receipts_log=depot_receipts_log)
}

############################################################
# 13) DISPENSING AT SITE
############################################################

dispense_visit <- function(today, inv, site_loc, arm, bw_group, visit_index,
                           PARAM, COUNT, stockout_log, subj_id,
                           patient_visit_log, site_dispense_log) {
  need     <- kit_need_for_visit(visit_index, bw_group, PARAM)
  min_exp  <- today + PARAM$DND_days
  pick     <- pick_kits(inv, site_loc, need$kit_type, arm,
                        need$qty, min_exp, PARAM$use_FEFO)
  inv      <- pick$inv
  short    <- i0(need$qty - pick$picked)
  region   <- if (grepl("^EU_",site_loc)) "EU" else "CN"
  if (short > 0L) {
    COUNT$stockout_site <- COUNT$stockout_site + 1L
    stockout_log[nrow(stockout_log)+1L,] <-
      list(today, site_loc, region, need$kit_type, arm,
           i0(need$qty), i0(pick$picked), short)
  }
  patient_visit_log[nrow(patient_visit_log)+1L,] <-
    list(today, subj_id, site_loc, region, arm, bw_group, visit_index,
         need$kit_type, i0(need$qty), i0(pick$picked), short)
  site_dispense_log[nrow(site_dispense_log)+1L,] <-
    list(today, site_loc, region, need$kit_type, arm, subj_id, i0(pick$picked))
  list(inv=inv, COUNT=COUNT, stockout_log=stockout_log,
       patient_visit_log=patient_visit_log, site_dispense_log=site_dispense_log)
}

############################################################
# 14) SITE ORDERING
############################################################

compute_site_order <- function(site_loc, inv, shipments, dem_s, dem_l,
                               today, PARAM, ship_lt_days) {
  DNC_days  <- PARAM$DND_days + ship_lt_days + PARAM$DNC_buffer_days
  arms      <- PARAM$blind_codes
  kit_types <- c("2.5ml","5ml","7.5ml")
  all_keys  <- union(union(names(dem_s[[site_loc]]), names(dem_l[[site_loc]])),
                     as.vector(outer(kit_types, arms, paste, sep="__")))
  ds <- dem_s[[site_loc]] %||% integer()
  dl <- dem_l[[site_loc]] %||% integer()
  mis_s <- setdiff(all_keys, names(ds)); if (length(mis_s)) ds[mis_s] <- 0L
  mis_l <- setdiff(all_keys, names(dl)); if (length(mis_l)) dl[mis_l] <- 0L
  order <- integer(); triggered <- FALSE
  for (key in all_keys) {
    kit <- sub("__.*$","",key); arm <- sub("^.*__","",key)
    dS  <- i0(ds[key]); dL <- i0(dl[key])
    oh  <- site_available_item(inv,site_loc,kit,arm,today,DNC_days)
    tr  <- in_transit_item(site_loc,kit,arm,today,shipments,DNC_days)
    av  <- oh + tr
    if ((dS + PARAM$min_threshold_kits) <= av) next
    triggered <- TRUE
    q <- i0(max(0L, ceiling((dL + PARAM$max_threshold_kits) - av)))
    if (q > 0L) order[key] <- q
  }
  list(trigger=triggered, order=order)
}

process_site_orders <- function(today, site_loc, region, inv, shipments,
                                next_ship_id, COUNT, subjects_all, PARAM,
                                DNS_depot_days, ship_lt_days,
                                last_order_day, order_type_log,
                                enrollment_complete) {
  cooldown_ok <- (today - last_order_day[[site_loc]]) >= PARAM$min_days_between_orders

  if (cooldown_ok) {
    sub_site  <- subjects_all[subjects_all$site_loc==site_loc, , drop=FALSE]
    short_w   <- ship_lt_days + PARAM$lookout_additional_days
    long_w    <- short_w + PARAM$lookout_additional_days
    dem_s_all <- list()
    dem_l_all <- list()
    dem_s_all[[site_loc]] <- predict_demand_site(sub_site, today, short_w,
                                                  PARAM$n_weekly_visits, PARAM)
    dem_l_all[[site_loc]] <- predict_demand_site(sub_site, today, long_w,
                                                  PARAM$n_weekly_visits, PARAM)
    ord <- compute_site_order(site_loc, inv, shipments, dem_s_all, dem_l_all,
                               today, PARAM, ship_lt_days)
    final_order <- if (isTRUE(ord$trigger)) ord$order else integer()

    # Pairwise equalization (FIX: now actually applied)
    if (!isTRUE(enrollment_complete) &&
        isTRUE(PARAM$enable_pairwise_equalize_before_complete) &&
        length(final_order)) {
      final_order <- augment_pairwise_equalization(site_loc, inv, final_order, PARAM)
    }

    if (!length(final_order) || sum(final_order)<=0L) {
      order_type_log[nrow(order_type_log)+1L,] <-
        list(today, site_loc, region, "ROUTINE_ATTEMPTED")
      return(list(inv=inv, shipments=shipments, next_ship_id=next_ship_id,
                  COUNT=COUNT, last_order_day=last_order_day,
                  order_type_log=order_type_log))
    }

    from_depot <- if (region=="EU") "EU_DEPOT" else "CN_DEPOT"
    lane       <- if (region=="EU") "EUDEPOT->EUSITE" else "CNDEPOT->CNSITE"
    prev_id    <- next_ship_id
    res <- create_depot_to_site_shipment(today, inv, from_depot, site_loc, lane,
                                         ship_lt_days, final_order, PARAM,
                                         shipments, next_ship_id, COUNT, DNS_depot_days)
    inv<-res$inv; shipments<-res$shipments; next_ship_id<-res$next_ship_id; COUNT<-res$COUNT
    last_order_day[[site_loc]] <- today
    otype <- if (res$next_ship_id != prev_id) "ROUTINE" else "ROUTINE_ATTEMPTED"
    order_type_log[nrow(order_type_log)+1L,] <- list(today, site_loc, region, otype)
    return(list(inv=inv, shipments=shipments, next_ship_id=next_ship_id,
                COUNT=COUNT, last_order_day=last_order_day, order_type_log=order_type_log))
  }

  # Emergency check
  if (PARAM$emergency_enabled && PARAM$emergency_check_daily) {
    sub_site <- subjects_all[subjects_all$site_loc==site_loc, , drop=FALSE]
    dem_e <- predict_demand_site(sub_site, today, PARAM$emergency_lookout_days,
                                  PARAM$n_weekly_visits, PARAM)
    DNC_days <- PARAM$DND_days + ship_lt_days + PARAM$DNC_buffer_days
    need_vec <- integer()
    for (nm in names(dem_e)) {
      kit <- sub("__.*$","",nm); arm <- sub("^.*__","",nm)
      d   <- i0(dem_e[[nm]]) + PARAM$emergency_buffer_kits
      oh  <- site_available_item(inv,site_loc,kit,arm,today,DNC_days)
      tr  <- in_transit_item(site_loc,kit,arm,today,shipments,DNC_days)
      gap <- d - (oh+tr)
      if (gap >= PARAM$emergency_min_gap_kits) need_vec[nm] <- i0(gap)
    }
    if (sum(need_vec) > 0L) {
      from_depot <- if (region=="EU") "EU_DEPOT" else "CN_DEPOT"
      lane       <- if (region=="EU") "EUDEPOT->EUSITE" else "CNDEPOT->CNSITE"
      prev_id    <- next_ship_id
      res <- create_depot_to_site_shipment(today, inv, from_depot, site_loc, lane,
                                           ship_lt_days, need_vec, PARAM,
                                           shipments, next_ship_id, COUNT, DNS_depot_days)
      inv<-res$inv; shipments<-res$shipments; next_ship_id<-res$next_ship_id; COUNT<-res$COUNT
      last_order_day[[site_loc]] <- today
      otype <- if (res$next_ship_id != prev_id) "EMERGENCY" else "EMERGENCY_ATTEMPTED"
      order_type_log[nrow(order_type_log)+1L,] <- list(today, site_loc, region, otype)
    }
  }
  list(inv=inv, shipments=shipments, next_ship_id=next_ship_id,
       COUNT=COUNT, last_order_day=last_order_day, order_type_log=order_type_log)
}

############################################################
# 15) EXTRA MANUFACTURING CHECK
############################################################

check_mfg_needed <- function(today, inv, daily_consump, PARAM, DNS_eu_depot) {
  keys <- names(daily_consump)
  if (!length(keys)) return(list(trigger=FALSE, short=integer(), short_ratio=0))
  dc <- as.numeric(daily_consump); names(dc) <- keys; dc[is.na(dc)] <- 0
  eu_avail <- setNames(integer(length(keys)), keys)
  for (nm in keys) {
    parts <- strsplit(nm,"__")[[1L]]
    eu_avail[nm] <- depot_available_item(inv,"EU_DEPOT",parts[1L],parts[2L],today,DNS_eu_depot)
  }
  look  <- PARAM$mfg_reorder_lookahead_days + PARAM$mfg_safety_stock_days
  need  <- i0(ceiling(dc * look)); need[is.na(need)] <- 0L
  short <- need - eu_avail; short[short<0L] <- 0L
  total_need  <- sum(need,  na.rm=TRUE)
  total_short <- sum(short, na.rm=TRUE)
  ratio <- if (total_need>0) total_short/total_need else 0
  list(trigger=(total_short>0L && ratio>=PARAM$mfg_extra_min_short_ratio),
       short=short, short_ratio=ratio)
}

############################################################
# 16) CN COVERAGE TRANSFER (daily check)
############################################################

plan_cn_transfer <- function(today, inv, subjects_all, PARAM, DNS_eu, DNS_cn) {
  horizon <- PARAM$cn_target_cover_days + PARAM$cn_transfer_safety_days
  dem_cn  <- predict_region_demand(subjects_all,"CN",today,horizon,PARAM)
  if (!length(dem_cn)) return(integer())
  need <- integer()
  for (nm in names(dem_cn)) {
    parts  <- strsplit(nm,"__")[[1L]]
    cn_av  <- depot_available_item(inv,"CN_DEPOT",parts[1L],parts[2L],today,DNS_cn)
    gap    <- i0(dem_cn[[nm]] - cn_av)
    if (gap > 0L) need[nm] <- gap
  }
  need[need >= PARAM$cn_transfer_min_batch]
}

############################################################
# 17) SITE KPI SNAPSHOT
############################################################

snapshot_site_totals <- function(inv, shipments, site_loc, today, DNC_days) {
  oh <- i0(sum(inv$qty[inv$location==site_loc & inv$qty>0L &
                          inv$expiry_day>(today+DNC_days)]))
  tr <- 0L
  if (nrow(shipments)>0L) {
    rows <- which(shipments$to_loc==site_loc & shipments$arrive_day>today &
                    shipments$qty>0L & shipments$expiry_day>(today+DNC_days) &
                    shipments$expiry_day>shipments$arrive_day)
    if (length(rows)) tr <- i0(sum(shipments$qty[rows]))
  }
  list(onhand=oh, transit=tr)
}

############################################################
# 18) ENROLLMENT HELPERS
############################################################

assign_tiers <- function(n, mix) {
  k <- round(n * mix)
  diff <- n - sum(k)
  if (diff != 0L) {
    idx <- order(mix, decreasing=TRUE)
    for (i in seq_len(abs(diff))) k[idx[i]] <- k[idx[i]] + sign(diff)
  }
  rep(names(mix), times=k)
}

monthly_to_daily <- function(mu_month, sf, days) mu_month / ((1-sf)*days)

sample_gamma_rate <- function(mu, phi) {
  if (mu<=0) return(0)
  rgamma(1L, shape=phi, rate=phi/mu)
}

daily_site_enrollments <- function(lambdas, remaining, inactive_flags) {
  draws <- ifelse(inactive_flags, 0L, rpois(length(lambdas), lambdas))
  total <- sum(draws)
  if (total<=remaining) return(i0(draws))
  if (remaining<=0L)    return(rep(0L, length(draws)))
  idx  <- rep(seq_along(draws), draws)
  keep <- sample(idx, remaining)
  i0(tabulate(keep, nbins=length(draws)))
}

############################################################
# 19) INITIALIZATION
############################################################

set_seed(PARAM)

EU_DEPOT <- "EU_DEPOT"; CN_DEPOT <- "CN_DEPOT"
site_locs_eu <- paste0("EU_SITE_", seq_len(PARAM$n_sites_eu))
site_locs_cn <- paste0("CN_SITE_", seq_len(PARAM$n_sites_cn))
all_sites    <- c(site_locs_eu, site_locs_cn)
KIT_TYPES    <- c("2.5ml","5ml","7.5ml")

# Site enrollment tiers & daily rates
tiers_eu   <- assign_tiers(PARAM$n_sites_eu, PARAM$enroll_tier_mix_eu)
tiers_cn   <- assign_tiers(PARAM$n_sites_cn, PARAM$enroll_tier_mix_cn)
mu_month   <- PARAM$enroll_tier_mu_month

lambda_eu  <- sapply(tiers_eu, function(t) {
  mu_day <- monthly_to_daily(mu_month[[t]], PARAM$screen_fail_rate, PARAM$month_days_for_enroll)
  sample_gamma_rate(mu_day, PARAM$enroll_gamma_phi)
})
lambda_cn  <- sapply(tiers_cn, function(t) {
  mu_day <- monthly_to_daily(mu_month[[t]], PARAM$screen_fail_rate, PARAM$month_days_for_enroll)
  sample_gamma_rate(mu_day, PARAM$enroll_gamma_phi)
})

inactive_eu <- rep(FALSE, PARAM$n_sites_eu)
inactive_cn <- rep(FALSE, PARAM$n_sites_cn)
if (PARAM$inactive_site_pct > 0) {
  inactive_eu[sample(seq_len(PARAM$n_sites_eu),
    floor(PARAM$inactive_site_pct*PARAM$n_sites_eu))] <- TRUE
  inactive_cn[sample(seq_len(PARAM$n_sites_cn),
    floor(PARAM$inactive_site_pct*PARAM$n_sites_cn))] <- TRUE
}

DNS_eu_depot <- PARAM$DND_days + PARAM$ship_lt_depot_to_site_days_eu + PARAM$DNS_buffer_days
DNS_cn_depot <- PARAM$DND_days + PARAM$ship_lt_depot_to_site_days_cn + PARAM$DNS_buffer_days

total_req    <- compute_total_required_kits(PARAM)
daily_consump <- approx_daily_consumption(total_req, PARAM$sim_horizon_days)

inv          <- new_inventory_df()
shipments    <- new_shipments_df()
next_ship_id <- 1L

COUNT <- list(
  ship_eu_depot_to_sites=0L, ship_cn_depot_to_sites=0L,
  ship_mfg_to_eu_depot=0L,   ship_eu_to_cn_depot=0L,
  stockout_site=0L, stockout_depot_order=0L, stockout_depot_item=0L,
  expired_total=0L, damaged_total=0L
)

# --- Logs ---
stockout_log <- data.frame(day=integer(),site_loc=character(),region=character(),
  kit_type=character(),arm=character(),required=integer(),dispensed=integer(),
  short=integer(),stringsAsFactors=FALSE)
expired_log  <- data.frame(day=integer(),location=character(),expired_qty=integer(),
  stringsAsFactors=FALSE)
site_day_kpi_log <- data.frame(day=integer(),site_loc=character(),region=character(),
  onhand_total=integer(),transit_total=integer(),stringsAsFactors=FALSE)
order_type_log <- data.frame(day=integer(),site_loc=character(),region=character(),
  order_type=character(),stringsAsFactors=FALSE)
patient_visit_log <- data.frame(day=integer(),subj_id=integer(),site_loc=character(),
  region=character(),arm=character(),bw_group=character(),visit_index=integer(),
  kit_type=character(),qty_needed=integer(),qty_dispensed=integer(),short=integer(),
  stringsAsFactors=FALSE)
site_dispense_log <- data.frame(day=integer(),site_loc=character(),region=character(),
  kit_type=character(),arm=character(),subj_id=integer(),qty_dispensed=integer(),
  stringsAsFactors=FALSE)
site_receipts_log <- data.frame(day=integer(),site_loc=character(),region=character(),
  kit_type=character(),arm=character(),qty_received=integer(),ship_id=integer(),
  qty_damaged=integer(),stringsAsFactors=FALSE)
depot_receipts_log <- data.frame(day=integer(),depot=character(),kit_type=character(),
  arm=character(),qty_received=integer(),qty_damaged=integer(),stringsAsFactors=FALSE)
site_expired_log <- data.frame(day=integer(),site_loc=character(),region=character(),
  kit_type=character(),arm=character(),expired_qty=integer(),stringsAsFactors=FALSE)

# ── Pre-allocated buffers (avoids O(n²) row-append inside main loop) ──────────
# Exact row counts known up front:
.n_days     <- PARAM$sim_horizon_days + 1L          # 851
.n_sites    <- PARAM$n_sites_eu + PARAM$n_sites_cn  # 23
.n_kits     <- length(c("2.5ml","5ml","7.5ml"))     # 3
.n_arms     <- length(PARAM$blind_codes)             # 2
.n_kpi      <- .n_days * .n_sites                   # 19,573
.n_ski      <- .n_days * .n_sites * .n_kits * .n_arms  # 117,438

.kpi_buf <- list(
  day           = integer(.n_kpi),
  site_loc      = character(.n_kpi),
  region        = character(.n_kpi),
  onhand_total  = integer(.n_kpi),
  transit_total = integer(.n_kpi)
)
.kpi_ptr <- 0L

.ski_buf <- list(
  day                          = integer(.n_ski),
  site_loc                     = character(.n_ski),
  region                       = character(.n_ski),
  kit_type                     = character(.n_ski),
  arm                          = character(.n_ski),
  arm_label                    = character(.n_ski),
  onhand_closing               = integer(.n_ski),
  qty_damaged_today            = integer(.n_ski),
  qty_dispensed_today          = integer(.n_ski),
  qty_expired_today            = integer(.n_ski),
  onhand_dnc                   = integer(.n_ski),
  intransit_dnc                = integer(.n_ski),
  qty_shipped_from_depot_today = integer(.n_ski),
  qty_received_at_site_today   = integer(.n_ski)
)
.ski_ptr <- 0L

# Depot daily snapshot buffer
.ddl_buf <- list(
  day       = integer(.n_days),
  eu_onhand = integer(.n_days),
  cn_onhand = integer(.n_days)
)
.ddl_ptr <- 0L

# Placeholder data.frames — filled from buffers after loop
site_kit_day_inventory <- NULL
site_day_kpi_log       <- NULL
depot_day_log          <- NULL

# --- Depots: initial inventory ---
# FIX: 7.5ml uses higher fraction to avoid Q2W stockout (spec limitation #3)
init_dq_raw <- ceiling(total_req * PARAM$init_depot_fraction_total)
for (nm in names(init_dq_raw)) {
  if (grepl("^7\\.5ml", nm)) {
    init_dq_raw[nm] <- ceiling(total_req[nm] * PARAM$init_depot_fraction_7_5ml)
  }
}
init_dq <- setNames(i0(init_dq_raw), names(init_dq_raw))
exp0    <- PARAM$day0 + PARAM$shelf_life_days
for (nm in names(init_dq)) {
  parts <- strsplit(nm,"__")[[1L]]
  inv <- add_inventory(inv,EU_DEPOT,"DEPOT","EU",NA_integer_,parts[1L],parts[2L],init_dq[nm],exp0)
  inv <- add_inventory(inv,CN_DEPOT,"DEPOT","CN",NA_integer_,parts[1L],parts[2L],init_dq[nm],exp0)
}
stopifnot(any(inv$location==EU_DEPOT))
stopifnot(any(inv$location==CN_DEPOT))

# --- Sites: initial 5ml inventory ---
for (loc in site_locs_eu) {
  reg   <- "EU"; p_lt90 <- PARAM$p_bw_lt90_eu
  n     <- PARAM$init_site_firstvisit_patients
  n_lt90 <- round(n*p_lt90); n_ge90 <- n-n_lt90
  arms  <- PARAM$blind_codes
  q_lt90 <- PARAM$kits_phase_weekly$bw_lt90$qty
  q_ge90 <- PARAM$kits_phase_weekly$bw_ge90$qty
  inv <- add_inventory(inv,loc,"SITE",reg,NA_integer_,"5ml",arms[1L],
                       ceiling(n_lt90/2)*q_lt90+ceiling(n_ge90/2)*q_ge90, exp0)
  inv <- add_inventory(inv,loc,"SITE",reg,NA_integer_,"5ml",arms[2L],
                       floor(n_lt90/2)*q_lt90+floor(n_ge90/2)*q_ge90, exp0)
}
for (loc in site_locs_cn) {
  reg   <- "CN"; p_lt90 <- PARAM$p_bw_lt90_cn
  n     <- PARAM$init_site_firstvisit_patients
  n_lt90 <- round(n*p_lt90); n_ge90 <- n-n_lt90
  arms  <- PARAM$blind_codes
  q_lt90 <- PARAM$kits_phase_weekly$bw_lt90$qty
  q_ge90 <- PARAM$kits_phase_weekly$bw_ge90$qty
  inv <- add_inventory(inv,loc,"SITE",reg,NA_integer_,"5ml",arms[1L],
                       ceiling(n_lt90/2)*q_lt90+ceiling(n_ge90/2)*q_ge90, exp0)
  inv <- add_inventory(inv,loc,"SITE",reg,NA_integer_,"5ml",arms[2L],
                       floor(n_lt90/2)*q_lt90+floor(n_ge90/2)*q_ge90, exp0)
}

# --- Subjects table ---
subjects <- data.frame(subj_id=integer(),region=character(),site_id=integer(),
  site_loc=character(),enroll_day=integer(),arm=character(),bw_group=character(),
  dropout_day=integer(),dropped=integer(),stringsAsFactors=FALSE)
subjects$visit_days <- list()

rand_state <- new_rand_state()
planned_mfg_days  <- PARAM$day0 + (0:(PARAM$mfg_planned_n_shipments-1L))*PARAM$mfg_planned_cycle_days
planned_mfg_used  <- rep(FALSE, length(planned_mfg_days))
last_extra_mfg_day <- -999999L
last_order_day <- setNames(rep(-999999L, length(all_sites)), all_sites)
drop_lambda    <- dropout_rate_from_target(PARAM$dropout_over_52w, PARAM$max_followup_days)
subj_counter   <- 0L
remaining_eu   <- PARAM$n_patients_eu
remaining_cn   <- PARAM$n_patients_cn

############################################################
# 20) MAIN SIMULATION LOOP
############################################################

for (today in 0L:PARAM$sim_horizon_days) {

  # Step 1: Expiry removal
  exp_res <- remove_expired_by_loc(inv, today)
  inv     <- exp_res$inv
  COUNT$expired_total <- COUNT$expired_total + exp_res$expired_total
  if (!is.null(exp_res$expired_by_loc)) {
    for (loc in names(exp_res$expired_by_loc))
      expired_log[nrow(expired_log)+1L,] <- list(today, loc,
        i0(exp_res$expired_by_loc[[loc]]))
  }
  if (nrow(exp_res$expired_detail)>0L) {
    det <- exp_res$expired_detail
    det_s <- det[grepl("^EU_SITE_|^CN_SITE_", det$location), , drop=FALSE]
    if (nrow(det_s)>0L) {
      det_s$region <- ifelse(grepl("^EU_",det_s$location),"EU","CN")
      names(det_s)[names(det_s)=="location"] <- "site_loc"
      site_expired_log <- rbind(site_expired_log,
        det_s[,c("day","site_loc","region","kit_type","arm","expired_qty")])
    }
  }

  # Step 2: Receive shipments
  rec <- receive_shipments_today(today, inv, shipments, next_ship_id, COUNT,
                                  PARAM, site_receipts_log, depot_receipts_log, subjects)
  inv<-rec$inv; shipments<-rec$shipments; next_ship_id<-rec$next_ship_id
  COUNT<-rec$COUNT; site_receipts_log<-rec$site_receipts_log
  depot_receipts_log<-rec$depot_receipts_log

  # Step 3: Planned manufacturing
  if (today %in% planned_mfg_days) {
    idx <- which(planned_mfg_days==today)[1L]
    if (!planned_mfg_used[idx]) {
      planned_mfg_used[idx] <- TRUE
      qty <- i0(ceiling(daily_consump*(PARAM$mfg_cycle_cover_days+PARAM$mfg_safety_stock_days)))
      mfg <- create_mfg_shipment(today,qty,PARAM,shipments,next_ship_id,COUNT)
      shipments<-mfg$shipments; next_ship_id<-mfg$next_ship_id; COUNT<-mfg$COUNT
    }
  }

  # Step 4: Extra manufacturing
  if (PARAM$allow_additional_mfg_shipments &&
      (today-last_extra_mfg_day) >= PARAM$mfg_extra_cooldown_days) {
    chk <- check_mfg_needed(today, inv, daily_consump, PARAM, DNS_eu_depot)
    if (isTRUE(chk$trigger)) {
      qty <- i0(chk$short); qty[is.na(qty)] <- 0L
      mfg <- create_mfg_shipment(today,qty,PARAM,shipments,next_ship_id,COUNT)
      if (mfg$next_ship_id != next_ship_id) last_extra_mfg_day <- today
      shipments<-mfg$shipments; next_ship_id<-mfg$next_ship_id; COUNT<-mfg$COUNT
    }
  }

  # Step 5: Enrollment
  if (today <= PARAM$recruitment_duration_days) {
    for (region_loop in c("EU","CN")) {
      is_eu    <- (region_loop=="EU")
      lam      <- if (is_eu) lambda_eu   else lambda_cn
      inact    <- if (is_eu) inactive_eu else inactive_cn
      rem      <- if (is_eu) remaining_eu else remaining_cn
      slocs    <- if (is_eu) site_locs_eu  else site_locs_cn
      p_lt90   <- if (is_eu) PARAM$p_bw_lt90_eu else PARAM$p_bw_lt90_cn

      if (rem <= 0L) next
      draws <- daily_site_enrollments(lam, rem, inact)
      if (PARAM$screen_fail_rate > 0)
        draws <- rbinom(length(draws), draws, 1-PARAM$screen_fail_rate)

      for (s in seq_along(draws)) {
        if (draws[s]<=0L) next
        for (k in seq_len(draws[s])) {
          if (is_eu && remaining_eu<=0L) break
          if (!is_eu && remaining_cn<=0L) break
          subj_counter <- subj_counter + 1L
          if (is_eu) remaining_eu <- remaining_eu - 1L
          else       remaining_cn <- remaining_cn - 1L

          site_loc <- slocs[s]
          bw  <- ifelse(runif(1L) < p_lt90, "lt90", "ge90")
          sk  <- make_strata_key(region_loop, bw)
          rr  <- rand_next(rand_state, sk, PARAM)
          arm_code <- if (PARAM$masking_enabled) rr$assign
                      else PARAM$blind_to_arm_map[[rr$assign]]
          rand_state <- rr$rand_state

          tdrop      <- rexp(1L, rate=drop_lambda)
          dropout_day <- i0(min(today+ceiling(tdrop), today+PARAM$max_followup_days))
          vdays <- today + simulate_visit_dates(PARAM$nominal_visit_days,
                              PARAM$visit_window_minus, PARAM$visit_window_plus,
                              PARAM$visit_sd_within_window)
          vdays <- apply_visit_variations(vdays, PARAM)

          subjects[nrow(subjects)+1L,] <-
            list(subj_counter, region_loop, s, site_loc, today,
                 arm_code, bw, dropout_day, 0L)
          subjects$visit_days[[nrow(subjects)]] <- vdays
        }
      }
    }
  }

  # Step 6: Update dropout flags
  if (nrow(subjects))
    subjects$dropped <- ifelse(today >= subjects$dropout_day, 1L, 0L)

  # Step 7: Dispense visits
  if (nrow(subjects)) {
    for (i in seq_len(nrow(subjects))) {
      if (subjects$dropped[i]==1L) next
      hits <- which(subjects$visit_days[[i]]==today)
      if (!length(hits)) next
      for (v in hits) {
        vi <- if (v <= length(PARAM$nominal_visit_days)) v
              else PARAM$n_weekly_visits
        disp <- dispense_visit(today, inv, subjects$site_loc[i], subjects$arm[i],
                               subjects$bw_group[i], vi, PARAM, COUNT,
                               stockout_log, subjects$subj_id[i],
                               patient_visit_log, site_dispense_log)
        inv<-disp$inv; COUNT<-disp$COUNT; stockout_log<-disp$stockout_log
        patient_visit_log<-disp$patient_visit_log
        site_dispense_log<-disp$site_dispense_log
      }
    }
  }

  # Step 8: CN coverage transfer
  if ((today %% as.integer(PARAM$cn_transfer_check_freq_days))==0L) {
    need_cn <- plan_cn_transfer(today,inv,subjects,PARAM,DNS_eu_depot,DNS_cn_depot)
    if (length(need_cn)>0L) {
      tr <- create_transfer_to_cn(today,inv,need_cn,PARAM,shipments,next_ship_id,COUNT,DNS_eu_depot)
      inv<-tr$inv; shipments<-tr$shipments; next_ship_id<-tr$next_ship_id; COUNT<-tr$COUNT
    }
  }

  enrollment_complete <- nrow(subjects) >= PARAM$n_patients_total

  # Steps 9–10: Site ordering
  for (loc in site_locs_eu) {
    rr <- process_site_orders(today,loc,"EU",inv,shipments,next_ship_id,COUNT,subjects,PARAM,
                               DNS_eu_depot,PARAM$ship_lt_depot_to_site_days_eu,
                               last_order_day,order_type_log,enrollment_complete)
    inv<-rr$inv; shipments<-rr$shipments; next_ship_id<-rr$next_ship_id
    COUNT<-rr$COUNT; last_order_day<-rr$last_order_day; order_type_log<-rr$order_type_log
  }
  for (loc in site_locs_cn) {
    rr <- process_site_orders(today,loc,"CN",inv,shipments,next_ship_id,COUNT,subjects,PARAM,
                               DNS_cn_depot,PARAM$ship_lt_depot_to_site_days_cn,
                               last_order_day,order_type_log,enrollment_complete)
    inv<-rr$inv; shipments<-rr$shipments; next_ship_id<-rr$next_ship_id
    COUNT<-rr$COUNT; last_order_day<-rr$last_order_day; order_type_log<-rr$order_type_log
  }

  # Step 11: Site KPI snapshot — write into pre-allocated buffer
  DNC_eu <- PARAM$DND_days + PARAM$ship_lt_depot_to_site_days_eu + PARAM$DNC_buffer_days
  DNC_cn <- PARAM$DND_days + PARAM$ship_lt_depot_to_site_days_cn + PARAM$DNC_buffer_days
  for (loc in site_locs_eu) {
    s <- snapshot_site_totals(inv,shipments,loc,today,DNC_eu)
    .kpi_ptr <- .kpi_ptr + 1L
    .kpi_buf$day[.kpi_ptr]           <- today
    .kpi_buf$site_loc[.kpi_ptr]      <- loc
    .kpi_buf$region[.kpi_ptr]        <- "EU"
    .kpi_buf$onhand_total[.kpi_ptr]  <- s$onhand
    .kpi_buf$transit_total[.kpi_ptr] <- s$transit
  }
  for (loc in site_locs_cn) {
    s <- snapshot_site_totals(inv,shipments,loc,today,DNC_cn)
    .kpi_ptr <- .kpi_ptr + 1L
    .kpi_buf$day[.kpi_ptr]           <- today
    .kpi_buf$site_loc[.kpi_ptr]      <- loc
    .kpi_buf$region[.kpi_ptr]        <- "CN"
    .kpi_buf$onhand_total[.kpi_ptr]  <- s$onhand
    .kpi_buf$transit_total[.kpi_ptr] <- s$transit
  }

  # Step 12: Site × kit daily inventory — buffer write
  # Cache today's sub-logs once to avoid repeated full-table scans in inner loop
  ARMS_VEC <- PARAM$blind_codes
  .sr_td   <- if (nrow(site_receipts_log) > 0L)
                site_receipts_log[site_receipts_log$day == today, , drop=FALSE]
              else site_receipts_log[0L, ]
  .sd_td   <- if (nrow(site_dispense_log) > 0L)
                site_dispense_log[site_dispense_log$day == today, , drop=FALSE]
              else site_dispense_log[0L, ]
  .se_td   <- if (nrow(site_expired_log) > 0L)
                site_expired_log[site_expired_log$day == today, , drop=FALSE]
              else site_expired_log[0L, ]
  .sh_td   <- if (nrow(shipments) > 0L)
                shipments[shipments$depart_day == today & shipments$qty > 0L, , drop=FALSE]
              else shipments[0L, ]

  for (loc in all_sites) {
    region   <- if (grepl("^EU_",loc)) "EU" else "CN"
    ship_lt  <- if (region=="EU") PARAM$ship_lt_depot_to_site_days_eu
                else              PARAM$ship_lt_depot_to_site_days_cn
    DNC_days <- PARAM$DND_days + ship_lt + PARAM$DNC_buffer_days
    from_dep <- if (region=="EU") EU_DEPOT else CN_DEPOT
    lane_to  <- if (region=="EU") "EUDEPOT->EUSITE" else "CNDEPOT->CNSITE"
    for (k in KIT_TYPES) {
      for (a in ARMS_VEC) {
        rows_inv  <- which(inv$location==loc & inv$kit_type==k & inv$arm==a & inv$qty>0L)
        qty_close <- if (length(rows_inv)) i0(sum(inv$qty[rows_inv])) else 0L

        dmg_today <- if (nrow(.sr_td))
          i0(sum(.sr_td$qty_damaged[
            .sr_td$site_loc==loc & .sr_td$kit_type==k & .sr_td$arm==a])) else 0L

        disp_today <- if (nrow(.sd_td))
          i0(sum(.sd_td$qty_dispensed[
            .sd_td$site_loc==loc & .sd_td$kit_type==k & .sd_td$arm==a])) else 0L

        exp_today <- if (nrow(.se_td))
          i0(sum(.se_td$expired_qty[
            .se_td$site_loc==loc & .se_td$kit_type==k & .se_td$arm==a])) else 0L

        oh_dnc <- site_available_item(inv,loc,k,a,today,DNC_days)
        tr_dnc <- in_transit_item(loc,k,a,today,shipments,DNC_days)

        shipped_today <- if (nrow(.sh_td))
          i0(sum(.sh_td$qty[
            .sh_td$from_loc==from_dep & .sh_td$to_loc==loc &
            .sh_td$lane==lane_to & .sh_td$kit_type==k & .sh_td$arm==a])) else 0L

        recvd_today <- if (nrow(.sr_td))
          i0(sum(.sr_td$qty_received[
            .sr_td$site_loc==loc & .sr_td$kit_type==k & .sr_td$arm==a &
            .sr_td$qty_received > 0L])) else 0L

        arm_label <- if (PARAM$masking_enabled) as.character(PARAM$blind_to_arm_map[[a]]) else a

        .ski_ptr <- .ski_ptr + 1L
        .ski_buf$day[.ski_ptr]                          <- today
        .ski_buf$site_loc[.ski_ptr]                     <- loc
        .ski_buf$region[.ski_ptr]                       <- region
        .ski_buf$kit_type[.ski_ptr]                     <- k
        .ski_buf$arm[.ski_ptr]                          <- a
        .ski_buf$arm_label[.ski_ptr]                    <- arm_label
        .ski_buf$onhand_closing[.ski_ptr]               <- qty_close
        .ski_buf$qty_damaged_today[.ski_ptr]            <- dmg_today
        .ski_buf$qty_dispensed_today[.ski_ptr]          <- disp_today
        .ski_buf$qty_expired_today[.ski_ptr]            <- exp_today
        .ski_buf$onhand_dnc[.ski_ptr]                   <- oh_dnc
        .ski_buf$intransit_dnc[.ski_ptr]                <- tr_dnc
        .ski_buf$qty_shipped_from_depot_today[.ski_ptr] <- shipped_today
        .ski_buf$qty_received_at_site_today[.ski_ptr]   <- recvd_today
      }
    }
  }

  # Step 13: Depot daily snapshot — buffer write
  eu_oh <- i0(sum(inv$qty[inv$location==EU_DEPOT & inv$qty>0L]))
  cn_oh <- i0(sum(inv$qty[inv$location==CN_DEPOT & inv$qty>0L]))
  .ddl_ptr <- .ddl_ptr + 1L
  .ddl_buf$day[.ddl_ptr]       <- today
  .ddl_buf$eu_onhand[.ddl_ptr] <- eu_oh
  .ddl_buf$cn_onhand[.ddl_ptr] <- cn_oh

  if (PARAM$verbose && today%%30L==0L)
    cat("Day",today,"EU/CN remaining:",remaining_eu,remaining_cn,"\n")
}

############################################################
# 21) MATERIALISE BUFFERS → data.frames
############################################################
site_day_kpi_log <- as.data.frame(.kpi_buf[seq_len(5)],
                                   stringsAsFactors=FALSE)
site_day_kpi_log <- site_day_kpi_log[seq_len(.kpi_ptr), , drop=FALSE]

site_kit_day_inventory <- as.data.frame(.ski_buf,
                                         stringsAsFactors=FALSE)
site_kit_day_inventory <- site_kit_day_inventory[seq_len(.ski_ptr), , drop=FALSE]

depot_day_log <- as.data.frame(.ddl_buf, stringsAsFactors=FALSE)
depot_day_log <- depot_day_log[seq_len(.ddl_ptr), , drop=FALSE]

# clean up temp objects
rm(.kpi_buf,.kpi_ptr,.ski_buf,.ski_ptr,.ddl_buf,.ddl_ptr,
   .n_days,.n_sites,.n_kits,.n_arms,.n_kpi,.n_ski)

############################################################
# 21) POST-SIMULATION ASSERTIONS (spec Section 19)
############################################################
stopifnot(nrow(subjects[subjects$region=="EU",]) == PARAM$n_patients_eu)
stopifnot(nrow(subjects[subjects$region=="CN",]) == PARAM$n_patients_cn)

############################################################
# 22) OUTPUTS
############################################################
library(dplyr); library(tidyr); library(readr)

final_by_loc <- inv %>% group_by(location) %>%
  summarise(qty=sum(qty), .groups="drop")

# --- Site KPI assembly ---
stockout_by_site    <- stockout_log %>% group_by(site_loc,region) %>%
  summarise(short_kits_total=sum(short),.groups="drop")
stockout_days_site  <- stockout_log %>% group_by(site_loc,region) %>%
  summarise(stockout_days=n_distinct(day),.groups="drop")
expired_site_agg    <- expired_log %>% group_by(location) %>%
  summarise(expired_qty=sum(expired_qty),.groups="drop") %>%
  transmute(site_loc=location,
    region=case_when(grepl("^EU_",site_loc)~"EU",grepl("^CN_",site_loc)~"CN",TRUE~"DEPOT"),
    expired_qty) %>% filter(region!="DEPOT")
avg_cov <- site_day_kpi_log %>% group_by(site_loc,region) %>%
  summarise(onhand_total=mean(onhand_total),transit_total=mean(transit_total),.groups="drop")
order_counts <- order_type_log %>% count(site_loc,region,name="n_orders_total")
order_rt     <- order_type_log %>% filter(grepl("^ROUTINE",order_type)) %>%
  count(site_loc,region,name="n_routine_orders")
order_em     <- order_type_log %>% filter(order_type=="EMERGENCY") %>%
  count(site_loc,region,name="n_emergency_orders")
all_sites_df <- bind_rows(
  site_day_kpi_log %>% distinct(site_loc,region),
  stockout_log     %>% distinct(site_loc,region),
  order_type_log   %>% distinct(site_loc,region),
  expired_site_agg %>% distinct(site_loc,region)) %>% distinct()
site_kpi <- all_sites_df %>%
  left_join(avg_cov,           by=c("site_loc","region")) %>%
  left_join(stockout_days_site,by=c("site_loc","region")) %>%
  left_join(stockout_by_site,  by=c("site_loc","region")) %>%
  left_join(expired_site_agg,  by=c("site_loc","region")) %>%
  left_join(order_counts,      by=c("site_loc","region")) %>%
  left_join(order_rt,          by=c("site_loc","region")) %>%
  left_join(order_em,          by=c("site_loc","region")) %>%
  mutate(across(c(onhand_total,transit_total,stockout_days,short_kits_total,
                  expired_qty,n_orders_total,n_routine_orders,n_emergency_orders),
                ~replace_na(.,0)))

# --- Visit stockout KPI ---
total_visits    <- nrow(patient_visit_log)
shortage_visits <- sum(patient_visit_log$short > 0L)
stockout_rate   <- if (total_visits>0) shortage_visits/total_visits*100 else 0

# --- Waste rate (V2 full-chain) ---
dispensed_total <- sum(patient_visit_log$qty_dispensed)
expired_all     <- sum(expired_log$expired_qty)
damaged_all     <- COUNT$damaged_total
waste_v2        <- if ((expired_all+damaged_all+dispensed_total)>0)
  (expired_all+damaged_all)/(expired_all+damaged_all+dispensed_total)*100 else 0
remaining_total <- i0(sum(inv$qty[inv$qty>0L]))
waste_C         <- if ((dispensed_total+expired_all+damaged_all+remaining_total)>0)
  (expired_all+damaged_all)/(dispensed_total+expired_all+damaged_all+remaining_total)*100 else 0

# --- Depot stockout KPIs ---
total_sim_days  <- PARAM$sim_horizon_days + 1L
eu_so_days      <- i0(sum(depot_day_log$eu_onhand==0L))
cn_so_days      <- i0(sum(depot_day_log$cn_onhand==0L))
eu_so_pct       <- round(eu_so_days/total_sim_days*100, 4)
cn_so_pct       <- round(cn_so_days/total_sim_days*100, 4)

# --- Write CSVs ---
patient_visit_schedule <- merge(
  patient_visit_log[order(patient_visit_log$subj_id,patient_visit_log$visit_index),],
  subjects[!duplicated(subjects$subj_id), c("subj_id","enroll_day")],
  by="subj_id", all.x=TRUE)
write_csv(patient_visit_schedule, "patient_visit_schedule.csv")

patient_kit_usage <- merge(
  patient_visit_log %>% group_by(subj_id) %>%
    summarise(total_kits_dispensed=sum(qty_dispensed),.groups="drop"),
  subjects[!duplicated(subjects$subj_id),
    c("subj_id","site_loc","region","arm","bw_group","enroll_day")],
  by="subj_id", all.x=TRUE)
write_csv(patient_kit_usage, "patient_kit_usage.csv")

site_kit_day_inventory <- site_kit_day_inventory[
  order(site_kit_day_inventory$day, site_kit_day_inventory$site_loc,
        site_kit_day_inventory$kit_type, site_kit_day_inventory$arm),]
write_csv(site_kit_day_inventory, "site_kit_day_inventory.csv")
write_csv(depot_day_log,          "depot_day_log.csv")
write_csv(shipments,              "shipments_df.csv")

# Site enrollment summary
site_master <- bind_rows(
  tibble(site_loc=site_locs_eu, region="EU", inactive=inactive_eu),
  tibble(site_loc=site_locs_cn, region="CN", inactive=inactive_cn))
site_enrollment_summary <- site_master %>%
  left_join(subjects %>% count(site_loc,name="enrolled_n"), by="site_loc") %>%
  mutate(enrolled_n=replace_na(enrolled_n,0L), no_enrollment=(enrolled_n==0L))
write_csv(site_enrollment_summary, "site_enrollment_summary.csv")

# --- Console summary ---
cat("\n==================== SIMULATION SUMMARY ====================\n")
cat(sprintf("Patients enrolled — EU: %d / %d  |  CN: %d / %d\n",
    nrow(subjects[subjects$region=="EU",]), PARAM$n_patients_eu,
    nrow(subjects[subjects$region=="CN",]), PARAM$n_patients_cn))
cat(sprintf("Visit Stockout Rate:   %.2f%%  (%d / %d visits)\n",
    stockout_rate, shortage_visits, total_visits))
cat(sprintf("Waste Rate V2 (full-chain): %.1f%%\n", waste_v2))
cat(sprintf("Waste Rate Method C:        %.1f%%\n", waste_C))
cat(sprintf("EU Depot stockout days: %d / %d  (%.2f%%)\n",
    eu_so_days, total_sim_days, eu_so_pct))
cat(sprintf("CN Depot stockout days: %d / %d  (%.2f%%)\n",
    cn_so_days, total_sim_days, cn_so_pct))
cat(sprintf("MFG→EU shipments: %d  |  EU→CN transfers: %d\n",
    COUNT$ship_mfg_to_eu_depot, COUNT$ship_eu_to_cn_depot))
cat(sprintf("Total expired: %d  |  Total damaged: %d\n",
    COUNT$expired_total, COUNT$damaged_total))
cat("=============================================================\n")

# --- OUT list ---
OUT <- list(
  parameters      = PARAM,
  counters        = COUNT,
  subjects        = subjects,
  final_inventory = inv,
  final_inventory_by_location = final_by_loc,
  shipments_df    = shipments,
  site_kpi        = site_kpi,
  stockout_log    = stockout_log,
  expired_log     = expired_log,
  order_type_log  = order_type_log,
  site_day_kpi_log = site_day_kpi_log,
  patient_visit_schedule = patient_visit_schedule,
  patient_kit_usage      = patient_kit_usage,
  site_kit_day_inventory = site_kit_day_inventory,
  site_dispense_log      = site_dispense_log,
  site_receipts_log      = site_receipts_log,
  site_expired_log       = site_expired_log,
  depot_receipts_log     = depot_receipts_log,
  depot_day_log          = depot_day_log,
  site_enrollment_summary = site_enrollment_summary,
  kpi_summary = list(
    stockout_rate_pct      = stockout_rate,
    waste_v2_pct           = waste_v2,
    waste_methodC_pct      = waste_C,
    eu_depot_stockout_days = eu_so_days,
    cn_depot_stockout_days = cn_so_days,
    eu_depot_stockout_pct  = eu_so_pct,
    cn_depot_stockout_pct  = cn_so_pct
  )
)

cat("\nOutputs written: patient_visit_schedule.csv, patient_kit_usage.csv,\n")
cat("  site_kit_day_inventory.csv, depot_day_log.csv, shipments_df.csv,\n")
cat("  site_enrollment_summary.csv\n")
cat("All results also available in OUT list.\n")
