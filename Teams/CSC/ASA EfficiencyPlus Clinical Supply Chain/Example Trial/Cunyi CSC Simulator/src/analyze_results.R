############################################################
# Analyze simulation results across iterations
############################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
})

analyze_simulation_results <- function(results_dir = "sim_results") {
  
  # Read summary
  summary_file <- file.path(results_dir, "simulation_summary.csv")
  if (!file.exists(summary_file)) {
    stop("No simulation_summary.csv found in ", results_dir)
  }
  
  results <- read_csv(summary_file, show_col_types = FALSE)
  
  cat("\n========== SIMULATION RESULTS ANALYSIS ==========\n")
  cat(sprintf("Total iterations: %d\n", nrow(results)))
  cat(sprintf("Results directory: %s\n\n", results_dir))
  
  # Summary statistics
  cat("--- Key Metrics ---\n")
  metrics <- c("total_enrolled", "total_stockouts", "total_expired", "total_damaged", "mfg_shipments")
  
  for (metric in metrics) {
    if (metric %in% names(results)) {
      cat(sprintf("%s:\n", metric))
      cat(sprintf("  Mean: %.2f\n", mean(results[[metric]], na.rm = TRUE)))
      cat(sprintf("  SD:   %.2f\n", sd(results[[metric]], na.rm = TRUE)))
      cat(sprintf("  Min:  %.0f\n", min(results[[metric]], na.rm = TRUE)))
      cat(sprintf("  Max:  %.0f\n", max(results[[metric]], na.rm = TRUE)))
      cat("\n")
    }
  }
  
  # Stockout analysis
  cat("--- Stockout Analysis ---\n")
  cat(sprintf("Iterations with zero stockouts: %d (%.1f%%)\n", 
              sum(results$total_stockouts == 0),
              100 * mean(results$total_stockouts == 0)))
  cat(sprintf("Iterations with stockouts: %d (%.1f%%)\n", 
              sum(results$total_stockouts > 0),
              100 * mean(results$total_stockouts > 0)))
  
  if (any(results$total_stockouts > 0)) {
    cat(sprintf("Among iterations with stockouts:\n"))
    cat(sprintf("  Mean: %.2f\n", mean(results$total_stockouts[results$total_stockouts > 0])))
    cat(sprintf("  Max:  %.0f\n", max(results$total_stockouts[results$total_stockouts > 0])))
  }
  cat("\n")
  
  # Expiry analysis
  cat("--- Expiry Analysis ---\n")
  cat(sprintf("Mean expired kits: %.2f\n", mean(results$total_expired)))
  cat(sprintf("Total expired across all iterations: %.0f\n", sum(results$total_expired)))
  cat("\n")
  
  # Manufacturing
  cat("--- Manufacturing ---\n")
  cat(sprintf("Mean shipments: %.2f\n", mean(results$mfg_shipments)))
  cat(sprintf("Range: %.0f - %.0f\n", min(results$mfg_shipments), max(results$mfg_shipments)))
  cat("\n")
  
  invisible(results)
}

# Load and aggregate site-level KPIs across iterations
aggregate_site_kpis <- function(results_dir = "sim_results") {
  
  iter_dirs <- list.dirs(results_dir, recursive = FALSE, full.names = TRUE)
  iter_dirs <- iter_dirs[grepl("iter_\\d+", basename(iter_dirs))]
  
  if (length(iter_dirs) == 0) {
    stop("No iteration directories found in ", results_dir)
  }
  
  all_kpis <- list()
  
  for (iter_dir in iter_dirs) {
    iter_num <- as.integer(sub("iter_", "", basename(iter_dir)))
    kpi_file <- file.path(iter_dir, "site_kpi.csv")
    
    if (file.exists(kpi_file)) {
      kpi <- read_csv(kpi_file, show_col_types = FALSE)
      kpi$iteration <- iter_num
      all_kpis[[length(all_kpis) + 1]] <- kpi
    }
  }
  
  combined <- bind_rows(all_kpis)
  
  # Aggregate by site
  site_summary <- combined %>%
    group_by(site_loc, region) %>%
    summarise(
      n_iterations = n(),
      mean_stockout_days = mean(stockout_days, na.rm = TRUE),
      mean_short_kits = mean(short_kits_total, na.rm = TRUE),
      mean_expired = mean(expired_qty, na.rm = TRUE),
      mean_orders = mean(n_orders_total, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    arrange(desc(mean_stockout_days))
  
  cat("\n========== SITE-LEVEL AGGREGATION ==========\n")
  cat(sprintf("Sites with highest mean stockout days:\n"))
  print(head(site_summary, 10))
  
  invisible(site_summary)
}

# Example usage:
# results <- analyze_simulation_results("sim_results")
# site_kpis <- aggregate_site_kpis("sim_results")
