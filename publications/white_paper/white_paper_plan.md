# White Paper Plan

**Working title:** *Simulation-Based Optimization of Clinical Trial Drug Supply Chains: A Practical Framework with AI-Assisted Implementation*

**Target length:** ~10 pages, journal/industry white paper style

**Date drafted:** 2026-10-01

**Audience & tone:** Clinical trial operationalists — supply chain managers, clinical operations leads, study managers. Non-technical readers. Language throughout should be:
- Plain English; avoid statistical jargon (e.g., say "spread in recruitment rates" not "Gamma-distributed rates")
- Explain any technical term the first time it appears, in parentheses or a short phrase
- Use concrete examples and analogies rather than formulas
- Equations and code snippets should be absent from the main text; if needed, confine them to a sidebar or appendix
- Favor short sentences and active voice
- Use tables and bullet points to present parameter findings rather than dense prose

---

## Section 1 — Introduction (~0.75 page)

**Purpose:** Frame the problem and the paper's contribution.

- The three-way tension at the heart of clinical supply management: minimize IMP waste, control logistics costs, avoid stock-outs. These objectives are in fundamental conflict — no single policy optimizes all three simultaneously.
- Growing complexity: globalized trials, cold-chain biologics, adaptive designs, enrollment uncertainty.
- The gap: industry still relies largely on rules-of-thumb and deterministic overages. The case for simulation-based, data-driven supply planning.
- This paper's two contributions: (1) a working simulation framework for discrete-event IMP supply chain modeling; (2) a demonstration of AI-assisted coding (Amazon Kiro/SKILL approach) as the method of implementation.

---

## Section 2 — Clinical Trial Supply Chain: Structure and Challenges (~1.25 pages)

**Purpose:** Ground the reader in the operational reality. Draw from Christi's draft outline + Anisimov 2010 PharmaOutsourcing.

- Supply chain structure: manufacturer → EU central depot → regional depots (e.g., CN) → sites → patients. Unidirectional flow; customs delays 2–3 months.
- The three-tier inventory system; site resupply triggers; FEFO dispensing; DND rules.
- Sources of stochasticity:
  - Enrollment uncertainty: Poisson-Gamma model for patient recruitment rates (Anisimov & Fedorov 2007; Lefew, Ninh & Anisimov 2021)
  - Randomization scheme uncertainty: center-stratified vs. unstratified randomization produce different supply overages (Anisimov 2010)
  - Logistics variability: lead times, transit damage, shelf-life expiry
- KPI definitions: stockout rate (visit-level), full-chain waste rate (V2 definition), cost drivers (shipping frequency, cold-chain logistics)
- The shelf-life-constrained regime: why classical inventory intuition (more buffer = fewer stock-outs) can break down in IMP supply chains.

---

## Section 3 — Stochastic Simulation Framework (~2 pages)

**Purpose:** Describe the modeling approach, grounded in academic literature and implemented in the trial simulation.

### 3.1 Recruitment modeling
- Poisson-Gamma model (Anisimov & Fedorov 2007; Lefew et al. 2021): site-level Poisson arrivals with Gamma-distributed rates, capturing inter-site heterogeneity.
- Tiered site enrollment (low/median/high tier sites), screen failure rate, inactive sites, stratified block randomization by region × body weight.
- Dropout modeled via exponential hazard — critical; omitting it overestimates demand by 10–15%.

### 3.2 Discrete-event simulation structure
- Daily time-step simulation over the full trial horizon (~850 days).
- Inventory states: EU depot, CN depot, per-site stock (per kit_key = kit_type × arm).
- Events: patient enrollment, visit (scheduled/unscheduled/missed), kit dispensing (FEFO, DND filter), site order (weekly review cycle), depot resupply, inter-depot EU→CN transfer, manufacturing batch arrivals, expiry sweep.
- Key design choices and why they matter (learned from iterative development):
  - Position-based weekly review vs. daily event-trigger (prevents under-ordering at high-tier sites)
  - Dynamic site thresholds scaled by patient count
  - Pre-emptive biweekly kit ordering

### 3.3 Manufacturing and resupply policy
- Planned batch schedule (8 batches × 60-day interval); MFG_QTY calibration formula.
- EU→CN transfer logic: 50% of surplus per batch arrival + daily emergency top-up; EU_PROTECT parameter.
- Additional manufacturing: when and why to disable it.

---

## Section 4 — Sensitivity Analysis and Parameter Optimization (~2 pages)

**Purpose:** Show what the simulation reveals about the system. Draw from SKILL.md SA findings and SA_comparison_report.

### 4.1 The four key parameters

| Parameter | Default | Recommended | Key finding |
|---|---|---|---|
| THRESH top (EU sites) | 105 | **70** | Largest lever: waste 43%→40%, stockout stays <2% |
| MIN_SHELF | 30 days | 30 days | Does NOT reduce total waste — only shifts expiry from site to CN depot |
| EU_PROTECT | 90 days | **90 days** | At 30d, CN stockout is 39× higher; waste unaffected |
| MFG batch frequency | 8 × 60d | **8 × 60d** | Fewer large batches → higher depot expiry (56% waste); more small batches → stock-outs (3.8%) |

### 4.2 Full-chain vs. site-only waste (V1 vs. V2)
- Why V1 misleads: changing MIN_SHELF appears to reduce waste but only moves expiry from site to CN depot. V2 (full-chain) is the correct metric.

### 4.3 The stock-out/waste/cost trilemma visualized
- Recommended operating point: stockout ~1.4%, full-chain waste ~40%, within industry norms (30–50% V2 waste is expected).

### 4.4 Insight from Anisimov's analytic framework
- Overage grows steeply as stockout risk → 0% (Figure 1 from Anisimov 2010 referenced).
- Center-stratified randomization requires less overage than unstratified (consistently supported by theory and SA).
- Number of depots and number of treatment arms increase required overage — quantified.

---

## Section 5 — AI-Assisted Implementation: The SKILL Approach (~2.5 pages)

**Purpose:** The novel methodological contribution. Document the workflow that produced the simulation code and what it teaches about AI-assisted statistical programming.

### 5.1 Motivation
- A fully faithful discrete-event IMP supply chain simulation is ~500–1,000 lines of R. Writing, testing, and iterating this manually is slow and error-prone.
- The SKILL framework: an Amazon Kiro AI "skill" (structured prompt + workflow specification) that encodes domain knowledge and generates, debugs, and iterates simulation code interactively with the analyst.

### 5.2 The SKILL workflow
Walk through the phases defined in SKILL.md:
- Phase 0: gather context, read spec, identify analysis type, write `supply_chain_context.md`
- Phase 0.5: human-in-the-loop decision confirmation (structured table before any code is written)
- Phase 0.7: dispensing scenario verification — the most critical pre-coding step (table of 10 scenarios, all ❓ must be resolved)
- Phase 1: generate analysis code following code principles (safe integer helper, FEFO, weekly review, etc.)
- Phase 2/2.5: user runs code, pastes output back, AI interprets results
- Phase 3: structured analysis report with KPIs and recommendations

### 5.3 Lessons encoded in the SKILL
Hardest-won lessons from iterative development — framed as "what simulation-building with AI teaches you":
- Scope bugs in enrollment closures: `<<-` in R closures silently misfires, causing 3–4× over-enrollment — enrollment count assertions are mandatory
- Phantom kit creation vs. FEFO pull from depot
- `i0()` helper drops vector names — names must be explicitly restored
- The importance of the V2 waste definition for cross-scenario comparability
- Stockout rate definition alignment between codebases when doing comparative SA

### 5.4 Human-AI collaboration pattern
- What the AI does well: generating boilerplate, translating spec tables into parameterized R code, running SA parameter sweeps, producing structured KPI summaries.
- What requires human judgment: choosing the stockout tolerance, interpreting whether 1.4% is clinically acceptable, deciding whether to reduce EU_PROTECT, setting trial design parameters from protocol.
- The iterative spec-code-test-fix loop accelerated by persistent `supply_chain_context.md` knowledge file that survives across sessions.

---

## Section 6 — Discussion (~0.75 page)

- Supply optimization is a strategic capability, not a back-office logistics function.
- Simulation-based optimization vs. analytic bounds (Anisimov): complementary, not competing. Analytics give fast scenario comparison; simulation gives operational fidelity (FEFO, site heterogeneity, dynamic thresholds).
- Limitations: simulation is calibrated to one trial design; parameters must be re-estimated per study. The SKILL approach requires an AI coding assistant.
- Generalizability of the SKILL workflow to other complex statistical programming tasks.

---

## Section 7 — Conclusion (~0.5 page)

- Three-paragraph close: (1) the supply problem and what simulation reveals, (2) the AI-assisted coding approach and its efficiency gains, (3) recommendation to adopt structured AI skills for complex simulation work in clinical operations.

---

## References

1. Anisimov VV. *Drug supply modelling in clinical trials.* Pharmaceutical Outsourcing, May/Jun 2010.
2. Lefew M, Ninh A, Anisimov V. *End-to-end drug supply management in multicenter trials.* Methodology and Computing in Applied Probability, 2021. https://doi.org/10.1007/s11009-020-09776-z
3. Anisimov VV, Fedorov VV. *Modelling, prediction and adaptive adjustment of recruitment in multicentre trials.* Statistics in Medicine, 26(27):4958–4975, 2007.
4. Anisimov VV, Fedorov VV, Heiberger R, Saha S, Kothapalli M. *Drug Supply Modeling Software: User Manual.* GSK DDS Technical Report 2010-01, 2010.
5. Peterson M, Byrom B, Dowlman N, McEntegart D. *Optimizing clinical trial supply requirements: simulation of computer-controlled supply chain management.* Clinical Trials, 1(4):399–412, 2004.

---

## Source Material Notes

| Section | Primary sources |
|---|---|
| 1, 2, 6 | `christi/White Paper_Clinical Trials Supplies_Draft Outline_2Sept2026.docx` |
| 2, 4.4 | `vlad/` — Anisimov papers (PharmaOutsourcing 2010, Lefew et al. 2021, GSK TR 2010-01) |
| 3, 4 | `cunyi/SKILL.md` (SA findings), `cunyi/4_complete.R`, `cunyi/simulation_from_spec.R`, `cunyi/New spec.docx` |
| 5 | `cunyi/SKILL.md` (workflow), `cunyi/SA_comparison_report.html` |
