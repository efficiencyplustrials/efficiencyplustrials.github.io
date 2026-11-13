---
name: supply-chain-analysis
description: Use when analyzing clinical trial drug supply chain data, including demand forecasting, inventory optimization, lead time analysis, and discrete-event Monte Carlo simulation for IMP (Investigational Medicinal Product) supply. Generates R code for analysis and simulation, produces structured reports with KPIs, shortage/expiry risk flags, optimization recommendations, and summary-level simulation output. Also applies when the user asks about kit shortages, resupply strategy, site stock levels, FEFO dispensing, enrollment-driven supply planning, or waste reduction in a clinical trial context.
---

# Supply Chain Analysis Skill — Clinical Trial IMP Supply

## Purpose
Assist supply chain analysts and clinical operations teams in planning and evaluating IMP (Investigational Medicinal Product) supply chains for clinical trials using R. Covers demand forecasting, inventory optimization, lead time analysis, and discrete-event Monte Carlo simulation. Outputs include reproducible R code, KPI summaries, shortage/expiry risk flags, optimization recommendations, and simulation summary reports.

## Quick Reference

| Analysis Type | Identifying Features | Template to Read |
|---|---|---|
| Demand forecasting (time series, trend, seasonality) | Historical demand data; forecasting horizon needed; MAPE/RMSE evaluation | `templates/demand-forecast.R` |
| Inventory optimization (EOQ, safety stock, reorder point) | Current stock levels + cost parameters; stockout/overstock assessment | `templates/inventory-optimization.R` |
| Lead time analysis (distribution, variability, supplier comparison) | Order + receipt dates; supplier on-time rate evaluation | `templates/lead-time-analysis.R` |
| Monte Carlo simulation (IMP supply chain, FEFO, enrollment-driven) | Trial protocol; kit config; site/depot structure; shortage & expiry risk | `templates/simulation.R` + `templates/simulation-summary.R` |
| Sensitivity analysis (SA) — parameter sweep across simulation runs | Multiple scenario results (CSV); comparing stockout/waste across THRESH/MIN_SHELF/EU_PROTECT/MFG variants | `templates/simulation.R` (per scenario) + `compute_waste_v2.R` (full-chain waste) + SA report template |
| All analyses — output wrapper | Always required for consistent output delimiters | `templates/output-report.R` |

Always read `templates/output-report.R` for any non-simulation analysis.
For simulation, read `templates/simulation.R` (run) + `templates/simulation-summary.R` (summary).

### New Analysis Type Detection

When the request does not clearly match any row above, **do not guess a template and proceed silently**. Instead:

1. Describe what you observed to the user:
   - What input data is available?
   - What output is expected (KPIs, charts, recommendations)?
   - Which existing template is the closest match and where it falls short?

2. Flag it explicitly:

```
⚠️ NEW ANALYSIS TYPE DETECTED

This request does not match any existing template. Observed:
- Input: [describe data structure or request]
- Expected output: [describe what the user wants]

Closest existing template: [name] — but it does not cover [gap].

Suggested approach:
- Option A: Extend [template] with a new section for [new content]
- Option B: Create a new template `templates/[descriptive-name].R` covering [logic]

Recommended: [your recommendation with brief reason]

Please confirm before I generate code.
```

3. Do not proceed to Phase 0.5 or generate code until user confirms.

4. After completing the analysis, document the new type and handling in `supply_chain_context.md` under Lessons Learned.

---

## Phase 0: Gather Context

Perform in order:

1. **Check `supply_chain_context.md`** — if it exists in the working directory, read it first. It contains trial parameters, confirmed decisions, and lessons from previous sessions.
2. **Identify analysis type** — use the Quick Reference table above.
   - If it matches a known type → note which template(s) to load and continue.
   - If it does **not** clearly match → **stop and follow the New Analysis Type Detection protocol** before proceeding.
3. **Check available data files** — list files in the working directory; identify format (CSV, Excel, SAS dataset, protocol PDF).
4. **Understand data structure** — key fields typically needed:
   - Simulation: enrollment rate, arm ratios, visit schedule, kit config, site count, depot stock, resupply lead time
   - Demand forecast: date, SKU/kit type, quantity dispensed
   - Inventory: current stock, unit cost, reorder history
   - Lead time: order date, receipt date, supplier, site
5. **Clarify scope** — if protocol parameters are ambiguous, ask user before assuming defaults.
   - For simulation requests: while reading the protocol/spec, **actively flag dispensing ambiguities** as you encounter them (see Phase 0.7 checklist). Do not silently assume — collect all uncertain dispensing scenarios to present in Phase 0.7.
6. **Write/update `supply_chain_context.md`** ← **MANDATORY after steps 3–5 are complete**
   - Required every time trial parameters, protocol, or kit configuration are read or confirmed
   - Do not proceed to Phase 0.5 until this file has been written or updated
   - See [Session Memory & Learning](#session-memory--learning) for required format
   - If the file already exists, append or correct — never overwrite existing entries

---

## Phase 0.5: Decision Confirmation (Human-in-the-Loop)

Before generating code, present this summary and **wait for user confirmation**:

```
ANALYSIS DECISIONS FOR CONFIRMATION:
┌─────┬──────────────────────────────────────────┬──────────────────────────────┐
│  #  │ Decision                                 │ Planned Approach             │
├─────┼──────────────────────────────────────────┼──────────────────────────────┤
│  1  │ Analysis type(s)                         │ [demand / inventory / sim]   │
│  2  │ Trial / data scope                       │ [arm count, N patients, etc.]│
│  3  │ Time range / trial duration              │ [start ~ end or total days]  │
│  4  │ Kit configuration                        │ [kit types, qty per visit]   │
│  5  │ Simulation replications (if sim)         │ [N_SIM]                      │
│  6  │ Resupply strategy                        │ [min/max threshold, lead]    │
│  7  │ Anomaly / risk threshold                 │ [service level target, etc.] │
└─────┴──────────────────────────────────────────┴──────────────────────────────┘

LESSONS APPLIED FROM CONTEXT:
- [list which lessons from supply_chain_context.md are relevant]

Confirm all decisions, or specify which to override.
```

---

## Phase 0.7: Dispensing Scenario Verification (Simulation Only)

This step applies **only when generating simulation code**. It must be completed before Phase 1. The goal is to surface all dispensing ambiguities and get explicit user sign-off before writing a single line of simulation code.

### When to trigger this step

Trigger Phase 0.7 whenever **any** of the following is uncertain or not explicitly stated in the protocol/spec:

| Area | Ambiguous scenarios that require verification |
|------|----------------------------------------------|
| **Dispensing unit** | Is the kit a single unit, a bottle, a blister pack, or a course (e.g., 28-day supply)? |
| **Qty per visit** | Fixed qty per visit, or does it vary by visit number / visit type / arm? |
| **Re-dispensing on missed visits** | If a patient misses a visit, do they receive catch-up kits at the next visit? |
| **Partial dispensing** | If site stock is insufficient, can a partial kit be dispensed, or is it all-or-nothing? |
| **Unscheduled / extra visits** | Are kits dispensed at unscheduled visits? If yes, same qty as scheduled, or different? |
| **Screen failure / discontinuation** | Are kits returned at discontinuation? If yes, are returned kits re-entered into stock? |
| **Dropout rate** | What % of patients dropout over the treatment period? Model as exponential hazard. Default 15–25% for Phase III. If not specified, **do not assume zero** — ask. |
| **Blinding / double-dummy** | Do patients in arm A receive both active + placebo (double-dummy)? How many kits per arm per visit? |
| **Country-specific packaging** | Are kit types or quantities different by country / region? |
| **First-visit (Day 0) dispensing** | Is a kit dispensed at the randomization visit (Day 0), or does dispensing start at Visit 2? |
| **DND / expiry buffer** | What is the minimum remaining shelf life (days) required for a kit to be dispensed at site? |
| **FEFO vs. FIFO** | Is dispensing strictly FEFO (First Expired, First Out), or FIFO, or no rule specified? |

### How to present the verification

Present a dispensing scenario table and **wait for user confirmation before proceeding to Phase 1**:

```
DISPENSING SCENARIO — PLEASE VERIFY:
┌─────┬──────────────────────────────────────────────┬─────────────────────────────┬────────┐
│  #  │ Scenario / Decision                          │ AI's Assumption             │ Verify │
├─────┼──────────────────────────────────────────────┼─────────────────────────────┼────────┤
│  1  │ Dispensing unit                              │ [kit / bottle / course]     │ ❓      │
│  2  │ Qty per visit (Arm 1 / Arm 2)                │ [X kits / Y kits]           │ ❓      │
│  3  │ Day 0 (randomization visit) dispensing       │ [yes / no]                  │ ❓      │
│  4  │ Missed visit catch-up dispensing             │ [no catch-up assumed]       │ ❓      │
│  5  │ Partial dispensing if stock insufficient     │ [no — record as shortage]   │ ❓      │
│  6  │ Unscheduled visit dispensing                 │ [yes, same qty]             │ ❓      │
│  7  │ Discontinuation kit return / re-stocking     │ [no return assumed]         │ ❓      │
│  8  │ Double-dummy / blinding kit config           │ [single kit per arm]        │ ❓      │
│  9  │ DND window (min shelf life to dispense)      │ [90 days]                   │ ❓      │
│ 10  │ FEFO enforcement                             │ [yes, strictly FEFO]        │ ❓      │
└─────┴──────────────────────────────────────────────┴─────────────────────────────┴────────┘

ITEMS MARKED ❓ NEED YOUR CONFIRMATION.
Items clearly specified in protocol are pre-filled — override any that are incorrect.

Please confirm or correct each item before I generate simulation code.
```

### Rules for this step

- Only include rows that are genuinely uncertain or not explicitly covered by the protocol/spec already read. Pre-fill rows where the protocol is explicit and mark them ✅.
- If a scenario is known to vary by arm or visit type, split it into separate rows.
- Do not generate any simulation code until the user has responded and all ❓ are resolved.
- After user confirms, record all dispensing decisions in `supply_chain_context.md` under **Key Confirmed Decisions** before proceeding.
- If new dispensing rules are discovered mid-simulation (e.g., user clarifies catch-up logic after code is running), stop, update the decisions table and `supply_chain_context.md`, then revise the simulation code.

---

## Phase 1: Generate Analysis Code

### Code Principles
- Self-contained, re-runnable R script
- `readr::read_csv()` or `readxl::read_excel()` for data loading
- `dplyr`, `tidyr`, `purrr` for data manipulation
- `ggplot2` for visualization
- `forecast` or `fable` for time series
- Output summary-level results only — never print subject-level or patient-level data
- Comment each section clearly
- Include `sessionInfo()` at end

### Safe Integer Helper — Always Include in Simulation Code
```r
i0 <- function(x) { x <- suppressWarnings(as.integer(x)); ifelse(is.na(x), 0L, x) }
```
Apply to all `sum()`, `rbinom()`, comparisons, and array-index results in simulation code.

### Data Quality Checks (include for data-driven analyses)
```r
cat("=== DATA QUALITY CHECK ===\n")
cat("Date range:", format(min(df$date)), "to", format(max(df$date)), "\n")
cat("Missing values:\n"); print(colSums(is.na(df)))
cat("Duplicate rows:", sum(duplicated(df)), "\n")
```

### Anomaly Detection (include for inventory and demand analyses)
Flag anomalies using IQR method by default. Escalate to user if > 5% of records are flagged.

---

## Phase 2: User Runs Code

Instruct user: **"Run this script, then copy everything between `===BEGIN ANALYSIS OUTPUT===` and `===END ANALYSIS OUTPUT===` (or `===BEGIN QC OUTPUT===` / `===END QC OUTPUT===` for simulation summary) and paste it back here."**

If errors occur, troubleshoot and provide corrected code.

---

## Phase 2.5: Results Review (Human-in-the-Loop)

Present results as a structured summary table:

```
ANALYSIS RESULTS SUMMARY:
┌─────┬────────────────────────────────────────┬───────────────────┬──────────┐
│  #  │ Metric                                 │ Value             │ Status   │
├─────┼────────────────────────────────────────┼───────────────────┼──────────┤
│  1  │ Service Level (% reps, 0 shortages)    │ 97.2%             │ ✅ Good   │
│  2  │ Waste Rate (expired / total)           │ 4.1%              │ ✅ Good   │
│  3  │ P95 shortage events per replication    │ 3                 │ ⚠️ Check  │
│  4  │ Mean kits expired (site, per rep)      │ 8.4               │ ✅ Normal │
└─────┴────────────────────────────────────────┴───────────────────┴──────────┘

⚠️ ITEMS REQUIRING ATTENTION:
- [list flagged items with brief explanation and suggested action]
```

---

## Phase 3: Analysis Report

### Executive Summary
- Trial scope and simulation parameters
- Key findings (top 3)
- Overall supply chain risk assessment: 🟢 Low Risk / 🟡 Attention Needed / 🔴 Action Required

### Optimization Recommendations
1. **Immediate actions** (adjust parameters before next run)
2. **Short-term improvements** (resupply strategy, threshold tuning)
3. **Strategic suggestions** (manufacturing batch sizing, site stock targets)

---

## Issue Severity Classification
- **🔴 Critical**: Stockout rate ≥ 5% (shortage visits / total visits); shortage affects > 5% of patients in median replication
- **🟡 Warning**: Stockout rate 2–5%; additional manufacturing firing > 2 batches/rep on average
- **🟢 Normal**: Stockout rate < 2%; waste rate 30–50% (industry norm for IMP); no shortages in median replication

Note on waste rate: **30–50% waste is normal and expected** in clinical trial IMP supply chains due to shelf-life constraints, safety stock, and enrollment uncertainty. Only flag waste > 60% as a concern (indicates structural overproduction). Do not apply commercial supply chain waste thresholds (e.g., < 15%) to IMP supply chains.

---

## Sensitivity Analysis — Parameter Tuning Recommendations

Apply these conclusions whenever a user asks about parameter optimization, sensitivity analysis results, or how to reduce stockout/waste in a simulated IMP supply chain.

### THRESH top (site order-up-to level) — Group A findings

THRESH top is the **single most impactful parameter** controlling both stockout rate and waste rate simultaneously.

| Scenario | THRESH top (EU) | Stockout Rate | Full-Chain Waste | Recommendation |
|---|---|---|---|---|
| A1 (conservative) | 150 | ~0.3% | ~47% | Too much waste |
| A2 (default) | 105 | 0.68% | 43.5% | Good baseline |
| **A3 (recommended)** | **70** | **1.39%** | **40%** | **Best balance** |
| A4 (aggressive) | 50 | ~2.5% | ~37% | Approaching spec limit |

**Action**: Set EU THRESH top = 70 to reduce waste by ~3.5 pp while keeping stockout well below 5% spec.
CN THRESH top should remain higher (top=200) due to longer lead time (14d vs 7d EU).

### MIN_SHELF (minimum remaining shelf life at site intake) — Group B findings

MIN_SHELF is a **quality control parameter, not a waste reduction lever**.

| Scenario | MIN_SHELF | Stockout Rate | Full-Chain Waste | Site Expired | CN Depot Expired |
|---|---|---|---|---|---|
| B1 | 120d | ~0.7% | 43.1% | ~28% | High |
| B2 (default) | 30d | 0.68% | 43.5% | ~28% | Moderate |
| B3 | 10d | ~0.8% | 49.5% | ~37% | Low |
| B4 | 0d | ~0.8% | 49.4% | ~37% | Minimal |

**Key insight**: Tightening MIN_SHELF does NOT reduce total waste — it only moves expiry from site to CN depot.
Loosening MIN_SHELF pushes more near-expiry kits into sites, increasing site-level waste.
**Action**: Maintain default 30 days. If site-level quality is a concern, tighten to 60d — but communicate that total waste will not change, only its location.

### EU_PROTECT (EU→CN transfer protection window) — Group C findings

EU_PROTECT is the **primary driver of CN site stockout risk**.

| Scenario | EU_PROTECT | CN Stockout Rate | Full-Chain Waste |
|---|---|---|---|
| C1 | 150d | 0.08% | ~44% |
| **C2 (default)** | **90d** | **0.68%** | **43.5%** |
| C3 | 60d | ~1.5% | ~43% |
| C4 | 30d | **3.0%** | ~42% |

**Key insight**: EU_PROTECT almost exclusively affects CN site stockout. Waste is nearly constant across all EU_PROTECT values.
At 30 days, CN stockout is 39× higher than at 90 days (3.0% vs 0.08%).
**Action**: Do NOT reduce EU_PROTECT below 60d. Default 90d is the safe operating point.

### MFG batch frequency (fixed total volume) — Group D findings

With total production volume held constant, batch frequency controls the timing distribution of supply.

| Scenario | Batches | Interval | Stockout Rate | Full-Chain Waste |
|---|---|---|---|---|
| D1 | 4 | 140d | 0.08% | **56%** |
| **D2 (default)** | **8** | **60d** | **0.68%** | **43.5%** |
| D3 | 12 | 40d | ~1.5% | ~44% |
| D4 | 15 | 28d | **3.8%** | ~44% |

**Key insight**: Fewer, larger batches → kits sit in EU depot longer → more EU depot expiry → high waste.
More, smaller batches → supply gaps between deliveries → stockouts.
**Action**: Default 8-batch / 60-day schedule is optimal for a ~27-month trial. Do not change without re-calibrating MFG_QTY.

### Combined THRESH + MIN_SHELF optimization — Group E findings

| Scenario | THRESH top | MIN_SHELF | Stockout | Full-Chain Waste | Notes |
|---|---|---|---|---|---|
| E3 (Balanced) | 80 | 30d | 1.3% | 47.5% | Good balance |
| E5 (Ultra, site-only) | 50 | 60d | 3.4% | — | Site waste only 17%, but stockout near spec limit |
| **Recommended** | **70** | **30d** | **~1.4%** | **~40%** | Best overall profile |

**Recommended final configuration:**
```
THRESH top (EU sites) = 70   # Reduce from default 105
EU_PROTECT = 90              # Keep default — critical for CN
MFG batches = 8 × 60d       # Keep default
MIN_SHELF = 30               # Keep default
```
Expected: stockout ~1.4%, full-chain waste ~40%.

---

## Session Memory & Learning

### How It Works
Every analysis or simulation run leaves a record. Knowledge accumulates across sessions.

```
Session N:   Read context → apply lessons → run analysis → record new findings
Session N+1: Read updated context → avoid known errors → run analysis → ...
```

### `supply_chain_context.md` — Persistent Knowledge File ← REQUIRED, NOT OPTIONAL

`supply_chain_context.md` **must be created or updated** after reading trial parameters, protocol details, kit configuration, or site/depot setup. This is a blocking step — do not generate code before it is written.

**Location**: same directory as the analysis scripts / working directory. If path is unknown, create in current working directory and note the intended path at the top.

**Triggers for writing/updating:**
- First analysis for a trial → create the file
- Any new protocol/SAP parameter confirmed → update Parameters section
- Any new kit configuration read → update Kit Config section
- Any simulation run that reveals a new lesson → append to Lessons Learned

**Required structure:**
```markdown
# Supply Chain Context: [Trial ID / Project Name]

## Project Info
- Trial ID: [e.g., STUDY-001]
- Compound / IMP: [name]
- Phase / Design: [Phase III, 2-arm, double-blind, etc.]
- Data / script path: [path]
- Last updated: [YYYY-MM-DD]

## Trial Parameters
| Parameter | Value | Source |
|-----------|-------|--------|
| N patients planned | | [protocol] |
| N arms | | |
| Arm ratio | | |
| Enrollment period (days) | | |
| Trial duration (days) | | |
| Visit schedule (days from rand) | | |

## Kit Configuration
| Arm | Kit Type | Qty/Visit | Shelf Life (days) |
|-----|----------|-----------|-------------------|
| | | | |

## Site & Depot Setup
| Parameter | Value |
|-----------|-------|
| N sites | |
| Initial stock per site (per arm) | |
| Min threshold | |
| Max threshold | |
| Resupply lead time (days) | |
| Depot initial stock | |
| Manufacturing batch qty | |
| Manufacture lag (days) | |

## Key Confirmed Decisions
| Item | Value / Rule |
|------|-------------|
| [e.g., FEFO rule] | [always apply at site level] |
| [e.g., DND window] | [90 days] |

## Lessons Learned
| Date | Issue | Root Cause | Fix Applied |
|------|-------|------------|-------------|
| YYYY-MM-DD | [description] | [why it happened] | [what was changed] |
```

**Rules:**
- Create on first analysis if it doesn't exist; read at session start (Phase 0 Step 1) if it does
- Append lessons learned after each run that reveals something new
- Never delete existing content — only add or correct

---

## Simulation-Specific Rules (from learned lessons)

When building discrete-event IMP supply chain simulations in R, **always apply**:

1. **Site initial inventory** — Pre-seed 5ml (weekly phase) kits proportional to each site's actual patient count, not a fixed global value. Do NOT pre-seed bi-weekly kits (2.5ml/7.5ml) at Day 0 — they will expire before patients reach that phase. Instead seed bi-weekly kits at `min` threshold level so first orders arrive in time.

2. **Manufacturing quantity** — Calculate MFG_QTY per kit_key per batch as:
   `MFG_QTY = (total_demand_per_arm × safety_margin) / n_total_batch_equivalents`
   where `n_total_batch_equivalents = n_planned_batches + 1` (initial depot stock counts as one batch).
   **Critical**: there are 6 kit_keys (2 arms × 3 kit types) — do NOT multiply by 6. Each kit_key gets its own MFG_QTY. Over-inflating MFG_QTY causes 3–4x overproduction and 40–90% waste rates.

3. **Disable additional manufacturing by default** — If planned batches are calibrated to 1.2–1.3x demand, additional manufacturing is unnecessary and will cause severe overproduction (observed: 7 extra batches/rep = 3x total demand). Only enable additional manufacturing with a strict shortage threshold (>5% visit stockout rate) and a per-kit-key cap.

4. **Resupply logic — use position-based weekly review, not daily event-trigger** — Daily event-trigger with `in_transit == 0` causes shortages at high-tier sites because one order quantity is insufficient for the full lead-time period. Use weekly review cycle with: `order_qty = max(0, dyn_top - on_hand - in_transit_qty)`. This handles multiple in-transit orders correctly.

5. **Kit-specific and region-specific thresholds** — 5ml (weekly) is consumed 3–5x faster than biweekly kits. Use separate min/top per kit_type per region. Scale thresholds by actual site patient count vs regional median: `dyn_top = base_top × (np / median_np)`. Failure to do this causes shortages at high-tier sites even when global supply is adequate.

6. **CN depot supply** — CN depot must be actively replenished via two mechanisms:
   - Batch-triggered transfer: on mfg batch arrival at EU, transfer 50% of surplus above EU's 90-day demand
   - Daily emergency top-up: if CN < 7-day demand, pull 30-day supply from EU (protecting EU's own demand)
   Using only batch-triggered transfer leaves CN starved between batch arrivals.

7. **EU→CN transfer column names** — When joining visit_events demand to calculate EU protection, always use the actual column name in visit_events (e.g., `kk` not `kit_type`). Silent join failures cause EU to transfer 50% of ALL stock to CN, depleting EU depot.

8. **Depot→site shipment** — Always pull actual kit rows from depot using `fefo_dispense()` and transfer `res$dispensed` to site. Do NOT use `make_kits()` to create new kit records for site — this leaves depot stock unchanged while creating phantom kits with wrong expiry dates.

9. **Pre-emptive biweekly ordering** — Sites should place biweekly kit orders when the first biweekly visit is within `lead_time + 21 days`, not wait for stock to drop below min. This ensures kits are on-hand at transition from weekly to biweekly phase (around Day 98).

10. **Dropout must be modelled** — Always implement patient dropout using an exponential hazard model. Do NOT assume all patients complete the full treatment period. Typical dropout rate for Phase III trials is 15–25% over the treatment duration. Implementation:
   ```r
   DROPOUT_DAILY <- -log(1 - dropout_rate) / treatment_days
   days_to_dropout <- ceiling(rexp(1, rate = DROPOUT_DAILY))
   dropout_day <- enroll_day + min(days_to_dropout, treatment_days)
   # In visit generator: break if nom > dropout_day
   ```
   Omitting dropout overestimates total kit demand by 10–15%, causing miscalibrated MFG_QTY and thresholds.

11. **NA-safe integer arithmetic** — Always use `i0()` helper for integer coercions. Apply to all `sum()`, `rbinom()`, and comparison results.

12. **FEFO min_exp threshold** — Do not set `min_exp = arrive + 180` at site level — this rejects valid inventory. Use `arrive + DND_days + buffer` (e.g., `arrive + 30`).

13. **Report field names** — Always verify output list field names match exactly what the summary template references. Mismatched names cause silent NULL → row-count errors in `data.frame()`.

14. **THRESH top tuning** — THRESH top is the single most impactful parameter for both stockout and waste. Lowering EU site THRESH top from 105→70 reduces full-chain waste from 43%→40% while keeping stockout at 1.4% (well within <5% spec). Scale THRESH by region and kit type: CN sites need higher THRESH (e.g., top=200) due to longer lead time (14d vs 7d EU). Threshold formula: `dyn_top = base_top × (np / median_np)` to scale by site patient count.

15. **MIN_SHELF does not reduce total waste** — Tightening MIN_SHELF (e.g., from 30→120 days) only shifts where expiry occurs: stricter filter → more CN depot expiry, less site expiry. Full-chain waste changes by only ~6 pp across the full MIN_SHELF range (0→120 days). Do NOT use MIN_SHELF tightening as a waste reduction strategy. It is only a site-level quality control measure. Set `min_exp = arrive + DND_days + MIN_SHELF` (e.g., `arrive + 13 + 30 = arrive + 43`) at site intake; do NOT use `arrive + 180` which rejects valid inventory.

16. **EU_PROTECT is critical for CN supply continuity** — EU_PROTECT controls how many days of EU site demand to hold back before transferring surplus to CN depot. At EU_PROTECT=30d, CN stockout rate is ~3.0% (39× higher than at 90d). Waste rate is nearly unaffected by EU_PROTECT (42–45% across all scenarios). Default 90 days is the safe operating point; do not reduce below 60 days without careful analysis. When implementing: protect `EU_PROTECT` days of EU site demand before computing transferable surplus; transfer 50% of surplus per batch arrival plus daily emergency top-up if CN < 7-day demand.

17. **MFG batch frequency tradeoff** — With fixed total production volume, batch frequency drives a waste-vs-stockout tradeoff:
    - Fewer, larger batches (e.g., 4 batches × 140d interval): lowest stockout (0.08%) but highest waste (56%) — large batches sit in EU depot and expire
    - Default (8 batches × 60d): best balance — stockout 0.68%, waste 43.5%
    - More, smaller batches (e.g., 15 batches × 28d): highest stockout (3.8%), waste still 44% — too-frequent small deliveries overwhelm transport and create ordering gaps
    Default 8-batch schedule is optimal for this trial profile. Do not change without re-calibrating total MFG_QTY.

18. **Future SA directions** — When suggesting what sensitivity analyses to run next, prioritize:
    - 🔴 DROPOUT_52W (10/20/30/40%) — largest clinical uncertainty, directly affects total demand
    - 🔴 MFG_QTY multiplier (×0.75–1.5) — models batch failure / yield loss risk
    - 🔴 LEAD_CN + LEAD_XFER — CN supply chain is the most vulnerable link
    - 🟡 SCREEN_FAIL rate — affects enrollment speed and demand curve shape
    - 🟡 DAMAGE_RATE — cold-chain transit loss uncertainty
    - 🟡 MISS_PROB — visit compliance affects consumption pace

19. **i0() silently drops vector names — CRITICAL BUG PATTERN** — The `i0()` helper (`as.integer()` wrapper) removes `names` from named vectors. This causes any `for (nm in names(x))` loop over the result to silently skip all iterations. Always restore names after calling `i0()`:
    ```r
    # WRONG — names are lost, loop never executes:
    init_dq <- i0(ceiling(tot_req * PARAM$init_depot_fraction_total))
    for (nm in names(init_dq)) { ... }  # names(init_dq) is NULL → loop skipped

    # CORRECT — preserve names explicitly:
    init_dq_raw <- ceiling(tot_req * PARAM$init_depot_fraction_total)
    init_dq <- setNames(i0(init_dq_raw), names(init_dq_raw))
    for (nm in names(init_dq)) { ... }  # works correctly
    ```
    **Impact when missed**: depot initial inventory is never seeded → all site orders become ROUTINE_ATTEMPTED (depot empty) → systematic stockout from Day 1. This bug produces results that look plausible (orders are placed) but are completely wrong in magnitude.

20. **`<<-` scope in nested enrollment closures — CRITICAL BUG PATTERN** — When enrollment logic is wrapped in a helper function and uses `<<-` to decrement a counter, the `<<-` modifies the variable in the **calling environment by name**. If the outer variable is named `rem_eu` but the inner closure uses `rem <<- rem - 1L`, the assignment finds or creates a new `rem` in a parent frame rather than modifying `rem_eu`. This means the enrollment cap is never enforced.
    ```r
    # WRONG — rem <<- rem-1L does NOT modify rem_eu in the outer scope:
    enroll_one_region <- function(..., rem, ...) {
      rem <<- rem - 1L   # creates/modifies 'rem' somewhere, not 'rem_eu'
    }

    # CORRECT — return the updated counter and reassign in the outer scope:
    enroll_one_region <- function(..., rem, ...) {
      if (rem <= 0L) return(list(rows=list(), vis=list(), rem=0L))
      rem <- rem - 1L    # local decrement
      ...
      list(rows=..., vis=..., rem=rem)  # return updated value
    }
    eu_res <- enroll_one_region(..., rem=rem_eu, ...)
    rem_eu <- eu_res$rem  # reassign in outer scope
    ```
    **Impact when missed**: EU target 100 patients → actually enrolls 500+; CN target 150 → enrolls 340+. This inflates kit demand ~3–4× and makes all KPIs incomparable to reference code.

21. **Validate enrollment counts before any SA** — Always add a post-simulation assertion before using results:
    ```r
    stopifnot(nrow(subjects[subjects$region=="EU",]) == PARAM$n_patients_eu)
    stopifnot(nrow(subjects[subjects$region=="CN",]) == PARAM$n_patients_cn)
    ```
    If this fails, the simulation has a scoping or counter bug. Do not proceed to KPI analysis.

22. **Stockout rate definition alignment across code versions** — When comparing two simulation codebases, ensure both use the same stockout definition:
    - **Visit-level (recommended)**: `shortage_visit_events / total_visit_events × 100` — each visit where any shortage occurred counts once regardless of kit quantity short
    - **Kit-level (legacy)**: `short_kits / qty_needed × 100` — can exceed 100% if multiple kits are short per visit; not comparable across codes
    Always confirm which definition each codebase uses before comparing SA results. Mixing definitions makes patterns appear similar but magnitudes differ by 5–20×.

23. **Cross-code SA comparison workflow** — When running sensitivity analysis comparing two simulation codebases (e.g., simulation_combined.R vs 4_complete.R):
    1. First run both with identical default parameters and verify KPIs match within ±10% — if not, find and fix the root cause before running SA sweeps
    2. Use environment variables or a wrapper script to inject parameter overrides rather than editing the main script — prevents accidental permanent changes
    3. Run both codes on the same SGE cluster with matched random seeds where possible
    4. Always compute waste using V2 (full-chain) definition for cross-code comparison
    5. Output directory naming convention: `sim_results_{code}_{param}{value}` (e.g., `sim_results_simcomb_shelf720`, `sim_results_4c_xfer60`)

24. **SGE parallel job submission rules** — When submitting parallel simulation jobs on SGE clusters:
    - Job names **cannot start with a digit** — `4c_shelf` fails, use `shelf_4c` instead
    - Use `-t 1-100` for 100 parallel tasks; each task reads `$SGE_TASK_ID` as its rep index
    - simulation_combined.R: ~60–90 min per rep; 4_complete.R: ~30–45 min per rep
    - Monitor progress: `qstat -u $USER | grep jobname | wc -l`
    - Verify completion: `ls sim_results_xxx/iter_*/master_summary.csv | wc -l`

25. **4_complete.R additional MFG over-triggering** — In 4_complete.R, near-expiry kits in EU depot are excluded from "available inventory" by the DNS filter. This causes the system to perceive a shortage and trigger additional MFG batches even when total physical stock is adequate. Observed: 8 extra batches fired per replication → 3× total demand produced → CN depot waste 8,349 kits → full-chain waste rate 51–55%. Mitigation: set `mfg_extra_min_short_ratio` higher (e.g., 0.05) or disable additional MFG (`allow_additional_mfg_shipments = FALSE`) when planned batches already cover 1.2–1.3× demand.

---

## KPI Reference — Correct Definitions

### Service Level / Stockout Rate
**Spec-aligned definition (preferred):**
```
Stockout Rate % = shortage visit events / total visit events × 100
Target: < 5% (per typical clinical trial supply spec)
```
Do NOT use "% reps with zero shortages" as the primary KPI — this is too strict and not aligned with standard spec language.

### Waste Rate

Two definitions exist. Always clarify which is being used when reporting.

**V1 — Site-Only (legacy, for reference only):**
```
waste_v1 = expired_site / (expired_site + dispensed) × 100%
```
Problem: ignores EU and CN depot expiry (~4,800–5,100 kits/rep in multi-region trials). Under-estimates true waste by ~12–15 pp.

**V2 — Full-Chain (recommended, preferred):**
```
waste_v2 = (expired_total + damaged_total) / (expired_total + damaged_total + dispensed) × 100%
where: expired_total = expired_site + expired_eu + expired_cn
```
Use `compute_waste_v2.R` to recalculate V2 from `master_summary.csv` if not already computed.

**Why V1 misleads:**
- Depot expiry is excluded → changing MIN_SHELF appears to reduce waste in V1, but V2 shows it only moves waste from site to depot
- V1 omits kits rejected by MIN_SHELF filter (which expire at CN depot)
- Example: MIN_SHELF=120 vs MIN_SHELF=10 looks like 9 pp difference in V1, only 6 pp in V2 — and the direction of recommendation changes

**Typical V1 vs V2 comparison (from SA Group B):**

| Scenario | Site-Only (V1) | Full-Chain (V2) | Δ |
|---|---|---|---|
| MIN_SHELF=120 | 28.2% | 43.1% | +14.9 pp |
| MIN_SHELF=30 (default) | 28.3% | 43.5% | +15.2 pp |
| MIN_SHELF=10 | 37.3% | 49.5% | +12.2 pp |
| MIN_SHELF=0 | 37.2% | 49.4% | +12.2 pp |

**Industry norm: 30–50% (V2, full-chain) is typical for IMP supply chains** due to shelf-life constraints, enrollment uncertainty, and safety stock requirements. Do NOT flag 40% waste as a critical issue.

**Wrong definition (do not use):**
- `(expired + damaged) / (dispensed + expired + damaged)` — excludes end-of-trial leftover, inflates waste rate
- `(expired + damaged) / visit_count` — visit count ≠ kits dispensed (each visit dispenses 1–5 kits)

### Typical Benchmark Results (Default Parameters, 100 Replications)

These benchmarks are from a 250-patient, 23-site (EU=13, CN=10), 814-day, 2-arm double-blind trial:

| KPI | Mean | P95 | Status |
|---|---|---|---|
| Stockout Rate | 0.68% | 1.46% | ✅ Well within <5% spec |
| Full-Chain Waste Rate (V2) | 43.5% | ~44% | ✅ Within 30–50% norm |
| Kits dispensed | ~14,800 | — | — |
| CN depot expired | ~4,950 | — | ⚠️ Major waste source |
| Site expired | ~5,850 | — | — |
| Damaged (transit) | ~605 | — | — |

**Recommended optimized configuration** (SA Group A + E findings):
- THRESH top = 70 (reduced from default 105) → waste 43%→40%, stockout 0.68%→1.39% (still < 5% spec)
- EU_PROTECT = 90 days (default) — do NOT reduce below 60d; at 30d, CN stockout rises 39× (0.08%→3.0%)
- MFG = 8 batches / 60-day interval (default) — best balance of stockout vs waste
- MIN_SHELF = 30 days (default) — tightening only shifts waste from site to CN depot; total waste unchanged

### SA Parameter Sensitivity Summary

| Parameter | Default | Recommended | Key Finding |
|---|---|---|---|
| THRESH top (EU sites) | 105 | **70** | Biggest lever: waste 43%→40%, stockout stays <2% |
| MIN_SHELF (days) | 30 | 30–60 | Does NOT reduce total waste — only shifts location (site vs CN depot) |
| EU_PROTECT (days) | 90 | **90** | Critical for CN: <60d causes significant CN stockout; waste unaffected |
| MFG batches | 8 (×60d) | **8 (×60d)** | Fewer large batches → more depot expiry (56% waste); more small batches → shortages (3.8%) |

### Shelf Life SA — Confirmed Findings (simulation_combined.R vs 4_complete.R)

Tested values: 300 / 400 / 500 / 600 / 720 / 1000 days.

- **Waste rate trend**: Both codebases show the same direction — longer shelf life → lower waste rate. Pattern is consistent across codes.
- **Stockout rate**: After fixing the enrollment and depot-seeding bugs in simulation_combined.R, trends are comparable. Pre-fix results showed no sensitivity (systematic stockout masked the signal).
- **Key lesson**: Always verify enrollment counts and depot inventory are correct before interpreting SA results. A bug that causes 3–4× over-enrollment inflates demand and makes the code appear insensitive to supply parameters.

### EU→CN Transfer Lead Time SA — Confirmed Findings

Tested values (ship_lt_eu_to_cn_depot_days): 14 / 30 / 45 / 60 days.

- **CN Waste**: Both codes show consistent trend — longer transfer lead time → slightly higher CN waste (kits age in transit).
- **CN Stockout**: 4_complete.R is more sensitive to this parameter than simulation_combined.R (pre-fix). Post-fix comparison pending.
- **Implementation note**: 4_complete.R does not natively support `XFER_DAYS` environment variable. Must manually add to the parameter override block:
  ```r
  if (nchar(Sys.getenv("XFER_DAYS")) > 0)
    PARAM$ship_lt_eu_to_cn_depot_days <- as.integer(Sys.getenv("XFER_DAYS"))
  ```

### Shelf-Life-Constrained Regime
Clinical trial IMP supply chains operate in a **shelf-life-constrained regime**, not a demand-constrained regime. Classical inventory intuition (more buffer = fewer stockouts) can break down because:
- Kits ordered too early expire before demand arrives
- Enrollment ramp-up means early inventory outlasts its shelf life
- Large replenishment orders can paradoxically increase stockout risk

This explains why raising reorder points sometimes increases rather than decreases stockout rates.
