############################################################
# Multi-iteration simulation runner
# Wraps the main simulation code for repeated execution
############################################################

run_single_simulation <- function(params, iteration_id = 1, output_dir = "sim_results") {
  
  # Override seed for this iteration
  if (params$seed_mode == "random") {
    params$seed <- as.integer((as.numeric(Sys.time()) * 1000 + iteration_id) %% .Machine$integer.max)
  } else {
    params$seed <- params$seed + iteration_id - 1
  }
  
  # Create output directory for this iteration
  iter_dir <- file.path(output_dir, sprintf("iter_%03d", iteration_id))
  dir.create(iter_dir, recursive = TRUE, showWarnings = FALSE)
  
  # Source the main simulation
  PARAM <- params
  source("src/simulation_core.R", local = TRUE)
  
  # Save outputs with iteration prefix
  saveRDS(OUT, file.path(iter_dir, "simulation_output.rds"))
  
  # Save key CSVs
  readr::write_csv(OUT$site_kpi, file.path(iter_dir, "site_kpi.csv"))
  readr::write_csv(OUT$patient_visit_schedule, file.path(iter_dir, "patient_visit_schedule.csv"))
  readr::write_csv(OUT$patient_kit_usage, file.path(iter_dir, "patient_kit_usage.csv"))
  readr::write_csv(OUT$site_kit_day_inventory, file.path(iter_dir, "site_kit_day_inventory.csv"))
  readr::write_csv(OUT$stockout_log, file.path(iter_dir, "stockout_log.csv"))
  readr::write_csv(OUT$site_enrollment_summary, file.path(iter_dir, "site_enrollment_summary.csv"))
  
  # Return summary metrics
  list(
    iteration = iteration_id,
    seed = params$seed,
    total_enrolled = nrow(OUT$subjects),
    total_stockouts = OUT$counters$stockout_site,
    total_expired = OUT$counters$expired_total,
    total_damaged = OUT$counters$damaged_total,
    mfg_shipments = OUT$counters$ship_mfg_to_eu_depot
  )
}

run_multiple_simulations <- function(base_params, n_iterations = 10, output_dir = "sim_results", parallel = FALSE) {
  
  cat(sprintf("\n========== Running %d simulations ==========\n", n_iterations))
  
  if (parallel && requireNamespace("parallel", quietly = TRUE)) {
    n_cores <- min(parallel::detectCores() - 1, n_iterations)
    cat(sprintf("Using %d cores for parallel execution\n", n_cores))
    
    cl <- parallel::makeCluster(n_cores)
    on.exit(parallel::stopCluster(cl))
    
    results <- parallel::parLapply(cl, 1:n_iterations, function(i) {
      run_single_simulation(base_params, i, output_dir)
    })
  } else {
    results <- lapply(1:n_iterations, function(i) {
      cat(sprintf("\n--- Iteration %d/%d ---\n", i, n_iterations))
      run_single_simulation(base_params, i, output_dir)
    })
  }
  
  # Combine summary results
  summary_df <- do.call(rbind, lapply(results, as.data.frame))
  readr::write_csv(summary_df, file.path(output_dir, "simulation_summary.csv"))
  
  cat(sprintf("\n========== Completed %d simulations ==========\n", n_iterations))
  cat(sprintf("Results saved to: %s\n", output_dir))
  
  invisible(summary_df)
}

# Example usage:
# source("run_simulation.R")
# results <- run_multiple_simulations(PARAM, n_iterations = 100, output_dir = "sim_results")
