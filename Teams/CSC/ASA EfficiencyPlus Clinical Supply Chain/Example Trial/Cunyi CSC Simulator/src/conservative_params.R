############################################################
# CONSERVATIVE simulation parameters
# Balanced approach to reduce waste with minimal stockout risk
# Based on lessons learned from aggressive optimization
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
  enroll_gamma_rate      = 40.0,   # mean=0.05 per day per site
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
  # CONSERVATIVE: Moderate reduction in shelf life requirements
  # Reduces waste while maintaining safety margin
  shelf_life_days          = 24 * 30,     # ~720 days (unchanged)
  min_remaining_eu_depot_days = 5.5 * 30,  # 165 days (was 195, -15%)
  min_remaining_cn_depot_days = 7.5 * 30,  # 225 days (was 270, -17%)
  min_remaining_site_days  = 5.0 * 30,     # 150 days (was 180, -17%)
  
  # ---------- DNX / Lookout ----------
  DND_days                 = 13,
  ship_lt_depot_to_site_days_eu = 7,
  ship_lt_depot_to_site_days_cn = 7,
  ship_lt_mfg_to_eu_depot_days   = 7,
  ship_lt_eu_to_cn_depot_days    = 60,
  
  DNC_buffer_days          = 7,
  DNS_buffer_days          = 30,  # UNCHANGED (keep safety buffer)
  
  lookout_additional_days  = 30,
  
  # ---------- Site thresholds (per item kit__arm) ----------
  # CONSERVATIVE: Moderate increase to help all kit types
  # Especially benefits 7.5ml (low-volume item)
  min_threshold_kits       = 30,  # +50% (was 20)
  max_threshold_kits       = 80,  # +33% (was 60)
  
  # ---------- Initial inventories ----------
  init_site_firstvisit_patients = 20,
  init_depot_fraction_total = 0.25,  # 25% (was 30%, -17% reduction)
  
  # ---------- Manufacturing plan ----------
  # UNCHANGED: Keep manufacturing buffers to ensure supply
  mfg_planned_cycle_days   = 60,
  mfg_planned_n_shipments  = 8,
  mfg_cycle_cover_days     = 90,  # UNCHANGED
  mfg_safety_stock_days    = 21,  # UNCHANGED
  
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
  enforce_site_balance     = FALSE,
  
  # ---------- New activation & pairwise equalization controls ----------
  activation_initial_stock = list(kit = "5ml", qty = 0, split_evenly_across_arms = TRUE),
  enable_activation_drop = FALSE,
  enable_pairwise_equalize_before_complete = TRUE,
  
  # ---------- CN transfer policy (target coverage) ----------
  cn_transfer_policy       = "target_cover",
  cn_target_cover_days     = 90,
  cn_transfer_safety_days  = 14,
  cn_transfer_check_freq_days = 1,
  cn_transfer_min_batch    = 10,
  
  # ---------- Operational ordering cadence ----------
  site_order_cycle_days      = 7,
  site_order_weekday0        = 1,
  min_days_between_orders    = 7,
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
# CONSERVATIVE OPTIMIZATION SUMMARY
############################################################
# 
# Strategy: Balance waste reduction with stockout prevention
# 
# Changes from default_params.R:
# 
# 1. min_threshold_kits: 20 → 30 (+50%)
#    - Significant increase to prevent stockouts
#    - Helps all kit types, especially 7.5ml
# 
# 2. max_threshold_kits: 60 → 80 (+33%)
#    - Higher ceiling for variable demand
# 
# 3. min_remaining_site_days: 180 → 150 days (-17%)
#    - Moderate reduction, still 5 months buffer
# 
# 4. min_remaining_eu_depot_days: 195 → 165 days (-15%)
#    - Small reduction, maintains safety
# 
# 5. min_remaining_cn_depot_days: 270 → 225 days (-17%)
#    - Moderate reduction for high-waste region
# 
# 6. init_depot_fraction_total: 0.30 → 0.25 (-17%)
#    - Small reduction in upfront inventory
# 
# UNCHANGED (Maintain Supply Security):
# - DNS_buffer_days: 30 (keep safety buffer)
# - mfg_safety_stock_days: 21 (keep manufacturing buffer)
# - mfg_cycle_cover_days: 90 (keep coverage)
# 
# Expected Impact:
# - Waste rate: 24% → 20-21% (↓ 3-4 percentage points)
# - Total stockouts: 10 → 12-15 events (+20-50%, acceptable)
# - 7.5ml stockouts: 52% → 35-40% (improvement)
# - 5ml/2.5ml stockouts: <5% (minimal change)
# 
# Philosophy:
# - Prioritize stockout prevention (patient safety)
# - Accept moderate waste reduction (cost trade-off)
# - Increase safety stock to compensate for shelf life reduction
# 
# To run:
# source("src/conservative_params.R")
# source("src/run_simulation.R")
# results <- run_multiple_simulations(PARAM, n_iterations = 100,
#                                     output_dir = "sim_results_conservative")
############################################################
