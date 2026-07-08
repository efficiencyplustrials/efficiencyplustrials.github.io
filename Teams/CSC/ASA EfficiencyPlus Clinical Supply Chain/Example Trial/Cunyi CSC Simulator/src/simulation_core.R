############################################################
# RTSM-Like Supply Chain Simulation - Core Logic
# This file expects PARAM to be defined before sourcing
############################################################

# Ensure PARAM exists
if (!exists("PARAM")) {
  stop("PARAM must be defined before sourcing simulation_core.R")
}

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

dropout_rate_from_target <- function(p_drop, horizon_days) -log(1 - p_drop) / horizon_days

simulate_visit_dates <- function(nominal_days, wminus, wplus, sd) {
  dev <- rtruncnorm(length(nominal_days), mean = 0, sd = sd, lower = -wminus, upper = wplus)
  as.integer(round(nominal_days + dev))
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
  if (length(all_keys) == 0) return(list(trigger = FALSE, order = NULL))
  
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
                                    site_receipts_log) {
  arr <- shipments[shipments$arrive_day == today, , drop = FALSE]
  if (!nrow(arr)) {
    return(list(inv = inv, shipments = shipments, next_ship_id = next_ship_id, COUNT = COUNT,
                site_receipts_log = site_receipts_log))
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
      
    } else {
      # Site receipt
      region <- if (grepl("^EU_", row$to_loc)) "EU" else "CN"
      inv <- add_inventory(inv, row$to_loc, "SITE", region, NA_integer_,
                           row$kit_type, row$arm, dmg$received, row$expiry_day)
      # Log site receipt
      site_receipts_log[nrow(site_receipts_log)+1, ] <- list(today, row$to_loc, region,
                                                             row$kit_type, row$arm,
                                                             as.integer(dmg$received),as.integer(dmg$damaged))
    }
  }
  
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
       site_receipts_log = site_receipts_log)
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
predict_region_demand <- function(subjects_all, region, today, horizon_days, PARAM) {
  subs <- subjects_all[subjects_all$region == region, , drop=FALSE]
  dem <- predictive_demand(subs, today, horizon_days, PARAM)  # site->vec
  out <- integer()
  if (!length(dem)) return(out)
  for (site_loc in names(dem)) {
    v <- dem[[site_loc]]
    for (k in names(v)) out[k] <- (out[k] %||% 0L) + as.integer(v[[k]])
  }
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

# ---------- Operational ordering (weekly routine + emergency) ----------
process_site_orders_operational <- function(today, site_loc, region,
                                            inv, shipments, next_ship_id, COUNT,
                                            subjects_all, PARAM,
                                            DNS_depot_days, ship_lt_days,
                                            last_order_day, order_type_log,enforce_balance_flag,enrollment_complete,enable_pairwise_equalization) {
  
  routine_day <- (today %% PARAM$site_order_cycle_days) == PARAM$site_order_weekday0
  cooldown_ok <- (today - last_order_day[[site_loc]]) >= PARAM$min_days_between_orders
  
  # Routine weekly
  if (routine_day && cooldown_ok) {
    sub_site <- subjects_all[subjects_all$site_loc == site_loc, , drop=FALSE]
    shortLW <- ship_lt_days + PARAM$lookout_additional_days
    longLW  <- shortLW + PARAM$lookout_additional_days
    
    demS <- predictive_demand(sub_site, today, shortLW, PARAM)
    demL <- predictive_demand(sub_site, today, longLW,  PARAM)
    
    ord <- compute_site_order_itemwise(site_loc, inv, shipments, demS, demL, today, PARAM, ship_lt_days,enforce_balance_flag = FALSE)
    
    if (isTRUE(ord$trigger)) {
      
      # 原始订单（逐 item：site×kit×arm）
      order_vec_pre <- ord$order
      
      # 仅在“未完成入组 & 开启补齐”时，对‘本次订单’做补齐
      if (PARAM$enable_pairwise_equalize_before_complete && !enrollment_complete) {
        ord$order <- augment_with_pairwise_equalization(site_loc, inv, ord$order, PARAM)
      }
      
      from_depot <- if (region=="EU") "EU_DEPOT" else "CN_DEPOT"
      lane <- if (region=="EU") "EUDEPOT->EUSITE" else "CNDEPOT->CNSITE"
      
      prev_next_id <- next_ship_id
      res <- create_depot_to_site_shipment(today, inv, from_depot, site_loc, lane, ship_lt_days,
                                           ord$order, PARAM, shipments, next_ship_id, COUNT,
                                           DNS_depot_days = DNS_depot_days)
      inv <- res$inv; shipments <- res$shipments; next_ship_id <- res$next_ship_id; COUNT <- res$COUNT
      
      # record: shipped vs attempted
      if (res$next_ship_id != prev_next_id) {
        last_order_day[[site_loc]] <- today
        order_type_log[nrow(order_type_log)+1,] <- list(today, site_loc, region, "ROUTINE")
      } else {
        last_order_day[[site_loc]] <- today
        order_type_log[nrow(order_type_log)+1,] <- list(today, site_loc, region, "ROUTINE_ATTEMPTED")
      }
      return(list(inv=inv, shipments=shipments, next_ship_id=next_ship_id, COUNT=COUNT,
                  last_order_day=last_order_day, order_type_log=order_type_log))
    }
  }
  
  # Emergency daily check
  if (PARAM$emergency_enabled && PARAM$emergency_check_daily && cooldown_ok) {
    sub_site <- subjects_all[subjects_all$site_loc == site_loc, , drop=FALSE]
    demE <- predictive_demand(sub_site, today, PARAM$emergency_lookout_days, PARAM)
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
        from_depot <- if (region=="EU") "EU_DEPOT" else "CN_DEPOT"
        lane <- if (region=="EU") "EUDEPOT->EUSITE" else "CNDEPOT->CNSITE"
        
        prev_next_id <- next_ship_id
        res <- create_depot_to_site_shipment(today, inv, from_depot, site_loc, lane, ship_lt_days,
                                             need_vec, PARAM, shipments, next_ship_id, COUNT,
                                             DNS_depot_days = DNS_depot_days)
        inv <- res$inv; shipments <- res$shipments; next_ship_id <- res$next_ship_id; COUNT <- res$COUNT
        
        last_order_day[[site_loc]] <- today
        # record: shipped vs attempted
        if (res$next_ship_id != prev_next_id) {
          order_type_log[nrow(order_type_log)+1,] <- list(today, site_loc, region, "EMERGENCY")
        } else {
          order_type_log[nrow(order_type_log)+1,] <- list(today, site_loc, region, "EMERGENCY_ATTEMPTED")
        }
      }
    }
  }
  
  list(inv=inv, shipments=shipments, next_ship_id=next_ship_id, COUNT=COUNT,
       last_order_day=last_order_day, order_type_log=order_type_log)
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

lambda_eu <- make_site_rates(PARAM$n_sites_eu, PARAM$enroll_gamma_shape, PARAM$enroll_gamma_rate)
lambda_cn <- make_site_rates(PARAM$n_sites_cn, PARAM$enroll_gamma_shape, PARAM$enroll_gamma_rate)

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
  qty_damaged = integer(),
  stringsAsFactors = FALSE
)

site_expired_log <- data.frame(
  day = integer(), site_loc = character(), region = character(),
  kit_type = character(), arm = character(), expired_qty = integer(),
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
  rec <- receive_shipments_today(today, inv, shipments, next_ship_id, COUNT, PARAM, site_receipts_log)
  inv <- rec$inv; shipments <- rec$shipments; next_ship_id <- rec$next_ship_id; COUNT <- rec$COUNT
  site_receipts_log <- rec$site_receipts_log
  
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
                                                PARAM$visit_window_minus, PARAM$visit_window_plus,
                                                PARAM$visit_sd_within_window)
          
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
                                                PARAM$visit_window_minus, PARAM$visit_window_plus,
                                                PARAM$visit_sd_within_window)
          
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
        disp <- dispense_visit(today, inv,
                               subjects$site_loc[i],
                               subjects$arm[i],
                               subjects$bw_group[i],
                               v, PARAM, COUNT, stockout_log,
                               subj_id = subjects$subj_id[i],
                               patient_visit_log = patient_visit_log,
                               site_dispense_log = site_dispense_log)
        inv <- disp$inv; COUNT <- disp$COUNT; stockout_log <- disp$stockout_log
        patient_visit_log <- disp$patient_visit_log
        site_dispense_log <- disp$site_dispense_log
      }
    }
  }
  
  # 8) CN transfer policy (target coverage) — optional (currently disabled)
  # if (PARAM$cn_transfer_policy == "target_cover" && (today %% PARAM$cn_transfer_check_freq_days) == 0) {
  #   need_cn <- plan_cn_transfer_target_cover(today, inv, subjects, PARAM, DNS_eu_depot, DNS_cn_depot)
  #   if (length(need_cn) > 0) {
  #     tr <- create_transfer_to_cn(today, inv, need_cn, PARAM, shipments, next_ship_id, COUNT, DNS_eu_depot)
  #     inv <- tr$inv; shipments <- tr$shipments; next_ship_id <- tr$next_ship_id; COUNT <- tr$COUNT
  #   }
  # }
  # At the beginning of each day in the loop, after any enrollments for the day:
  # Correct: trial completion is based on ever-randomized count (includes dropped/completed subjects)
  total_ever_randomized <- nrow(subjects)
  enrollment_complete <- total_ever_randomized >= PARAM$n_patients_total
  
  # Old balancing is deprecated for routine path; keep it off to avoid conflicts with new rule
  enforce_balance_flag <- FALSE
  # 9) Operational ordering: weekly routine + emergency (EU sites)
  for (loc in site_locs_eu) {
    rr <- process_site_orders_operational(today, loc, "EU",
                                          inv, shipments, next_ship_id, COUNT,
                                          subjects, PARAM,
                                          DNS_depot_days = DNS_eu_depot,
                                          ship_lt_days  = PARAM$ship_lt_depot_to_site_days_eu,
                                          last_order_day, order_type_log,enforce_balance_flag = FALSE,
                                          enrollment_complete = enrollment_complete,
                                          enable_pairwise_equalization = PARAM$enable_pairwise_equalize_before_complete)
    inv <- rr$inv; shipments <- rr$shipments; next_ship_id <- rr$next_ship_id; COUNT <- rr$COUNT
    last_order_day <- rr$last_order_day; order_type_log <- rr$order_type_log
  }
  
  # 10) Operational ordering: weekly routine + emergency (CN sites)
  for (loc in site_locs_cn) {
    rr <- process_site_orders_operational(today, loc, "CN",
                                          inv, shipments, next_ship_id, COUNT,
                                          subjects, PARAM,
                                          DNS_depot_days = DNS_cn_depot,
                                          ship_lt_days  = PARAM$ship_lt_depot_to_site_days_cn,
                                          last_order_day, order_type_log,enforce_balance_flag = FALSE,
                                          enrollment_complete = enrollment_complete,
                                          enable_pairwise_equalization = PARAM$enable_pairwise_equalize_before_complete)
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

# ---------- Site-level kit inventory (closing, ordered) ----------
site_kit_day_inventory <- site_kit_day_inventory[order(site_kit_day_inventory$day,
                                                       site_kit_day_inventory$site_loc,
                                                       site_kit_day_inventory$kit_type,
                                                       site_kit_day_inventory$arm),]

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
  site_expired_log       = site_expired_log
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
site_enrollment_summary <- site_master %>%
  left_join(enr_by_site, by = "site_loc") %>%
  mutate(
    enrolled_n    = replace_na(enrolled_n, 0L),
    no_enrollment = enrolled_n == 0L
  ) %>%
  arrange(region, site_loc)

# Subsets
inactive_and_no_enrollment <- site_enrollment_summary %>% filter(inactive & no_enrollment)
active_but_no_enrollment   <- site_enrollment_summary %>% filter(!inactive & no_enrollment)

# Write CSVs (main summary)

# Console prints for quick view
cat("\n==================== SITE ENROLLMENT SUMMARY ====================\n")
print(head(site_enrollment_summary, 20))

# Attach to OUT list for programmatic access
OUT$site_enrollment_summary    <- site_enrollment_summary
