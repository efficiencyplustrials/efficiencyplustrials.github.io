############################################################
# OPTIMIZED simulation parameters
# Implements recommendations to reduce waste and stockouts
# Based on analysis of 100 baseline iterations
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
  # OPTIMIZED: Reduced from 6-9 months to 4-6 months
  # Rationale: Better kit utilization, shelf life is 24 months
  shelf_life_days          = 24 * 30,     # ~720 days (unchanged)
  min_remaining_eu_depot_days = 5.0 * 30,  # 150 days (was 195, -23%)
  min_remaining_cn_depot_days = 6.0 * 30,  # 180 days (was 270, -33%)
  min_remaining_site_days  = 4.0 * 30,     # 120 days (was 180, -33%)
  
  # ---------- DNX / Lookout ----------
  DND_days                 = 13,
  ship_lt_depot_to_site_days_eu = 7,
  ship_lt_depot_to_site_days_cn = 7,
  ship_lt_mfg_to_eu_depot_days   = 7,
  ship_lt_eu_to_cn_depot_days    = 60,
  
  DNC_buffer_days          = 7,
  DNS_buffer_days          = 21,  # OPTIMIZED: 21 days (was 30, -30%)
  
  lookout_additional_days  = 30,
  
  # ---------- Site thresholds (per item kit__arm) ----------
  # OPTIMIZED: Kit-specific thresholds for low-volume items
  # Note: If simulation doesn't support kit-specific, use weighted average
  # For now, using compromise values that help 7.5ml without hurting others
  min_threshold_kits       = 25,  # OPTIMIZED: 25 (was 20, +25%)
  max_threshold_kits       = 70,  # OPTIMIZED: 70 (was 60, +17%)
  
  # ---------- Initial inventories ----------
  init_site_firstvisit_patients = 20,
  init_depot_fraction_total = 0.20,  # OPTIMIZED: 20% (was 30%, -33%)
  
  # ---------- Manufacturing plan ----------
  mfg_planned_cycle_days   = 60,
  mfg_planned_n_shipments  = 8,
  mfg_cycle_cover_days     = 75,  # OPTIMIZED: 75 days (was 90, -17%)
  mfg_safety_stock_days    = 14,  # OPTIMIZED: 14 days (was 21, -33%)
  
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
# OPTIMIZATION SUMMARY
############################################################
# 
# Changes from default_params.R:
# 
# 1. min_remaining_site_days: 180 → 120 days (-33%)
#    - Better kit utilization, less waste from short shelf life rejection
# 
# 2. min_remaining_eu_depot_days: 195 → 150 days (-23%)
#    - Allows older kits to be deployed, reduces depot waste
# 
# 3. min_remaining_cn_depot_days: 270 → 180 days (-33%)
#    - Significant reduction in CN waste (highest waste region)
# 
# 4. DNS_buffer_days: 30 → 21 days (-30%)
#    - Faster inventory turnover, less holding time
# 
# 5. min_threshold_kits: 20 → 25 (+25%)
#    - Compromise increase to help 7.5ml without kit-specific support
# 
# 6. max_threshold_kits: 60 → 70 (+17%)
#    - Allows higher buffer for variable demand items
# 
# 7. init_depot_fraction_total: 0.30 → 0.20 (-33%)
#    - Less upfront inventory, reduces initial waste
# 
# 8. mfg_cycle_cover_days: 90 → 75 days (-17%)
#    - Leaner manufacturing, less over-production
# 
# 9. mfg_safety_stock_days: 21 → 14 days (-33%)
#    - With responsive manufacturing, can be more aggressive
# 
# Expected Impact:
# - Waste rate: 27% → 18-20% (↓ 7-9 percentage points)
# - 7.5ml stockouts: 52% → 25-30% (↓ 22-27 percentage points)
#   Note: Without kit-specific thresholds, improvement is partial
# - Total kits used: ↓ 7-9%
# 
# To run with these parameters:
# source("src/optimized_params.R")
# source("src/run_simulation.R")
# results <- run_multiple_simulations(PARAM, n_iterations = 100)
############################################################
