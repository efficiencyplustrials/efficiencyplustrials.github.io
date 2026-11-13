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

---

## Gap Analysis: Christi's Outline vs. Current Draft

*Reviewed 2026-10-01. Gaps to address before finalizing.*

### ✅ Well covered

- The three competing objectives (waste, cost, stock-out) — Sections 1 and 2
- Depot structure and customs/lead-time rationale — Section 2
- Site resupply algorithm (min-stock trigger, weekly review) — Section 3
- 0–5% stock-out tolerance as the benchmark — used throughout Section 4
- Commercial timing risk from supply delays — Section 6
- Cold-chain complexity — Section 1
- FEFO dispensing and DND rule — Sections 2 and 3
- Full-chain waste definition and rationale — Section 4

### ⚠️ Partially covered — needs strengthening

| Gap | Where it belongs | What to add |
|---|---|---|
| **Manufacturing context** | Section 2 or 3 | Christi distinguishes early-phase small-batch (Product Development) vs. Ph3 large commercial manufacturer batches. Paper only describes a fixed schedule without this context. Add 1–2 sentences on how manufacturing mode affects batch sizing and flexibility. |
| **Waste formula** | Section 2 (KPI definitions) | Christi gives an explicit formula: `(kits shipped − kits used) / kits used`. Paper states waste as % of production but never defines the formula. Add the formula in plain-language form. |
| **Fixed vs. variable waste parameters** | Section 2 | Christi explicitly lists *fixed* parameters (number of label languages, countries, depots, customs, shelf life) and *variable* parameters (initial stock, resupply thresholds). Paper conflates them. Add this taxonomy — it clarifies what teams can and cannot control. |
| **Shipment cost mechanics** | Section 2 or 6 | Christi explains packaging unit economics (e.g., 4 kits per box vs. 1 kit = 4× shipping cost). Paper mentions logistics costs qualitatively but not the cost structure. Add a brief concrete example. |
| **Initial stock at site initiation** | Section 3 | Christi calls out "initial stock" sent at site initiation as a distinct decision variable alongside resupply thresholds. Paper focuses on ongoing resupply (THRESH top) but never discusses the initiation shipment. Add a sentence or two. |

### ❌ Not covered — new content needed

| Gap | Where it belongs | What to add |
|---|---|---|
| **IRT (Interactive Response Technology)** | Section 2 and/or Section 5 | Christi explicitly names IRT configuration as a key planning and execution tool alongside simulation. It is absent from the paper entirely. Add a brief explanation of IRT's role in randomization, kit assignment, and resupply triggering, and note the relationship between IRT configuration and simulation assumptions. |
| **Sustainability / environmental framing of waste** | Section 1 and/or Section 6 | Christi frames drug expiry waste as both a financial and sustainability/environmental issue ("wasted scientific opportunity," "environmental footprint of discarded drug product"). Paper treats waste only in operational and financial terms. Add 1–2 sentences in the Introduction and/or Discussion on the sustainability dimension. |
| **Adaptive trials** | Section 1 and/or Section 6.3 | Christi lists adaptive designs as a driver of supply complexity. Section 6.3 mentions adaptive trials only as a future application of the SKILL approach. Acknowledge adaptive designs earlier (Section 1) as part of the complexity framing. |

---

## Gap Fixes Round 2 (from 2026-10-01 independent multi-model review)

*Four models reviewed independently: gpt-5.5, gpt-5.4, o3, o4-mini.*
*Items flagged by 3+ models marked 🔴 (must fix). 1–2 models marked 🟡 (significant improvement).*

### 🔴 Priority 1 — Must fix

| # | Section(s) | Issue | Action |
|---|---|---|---|
| 1 | S2, S4 | **Waste metric inconsistency**: S2 defines waste as `(kits shipped − kits used) / kits used`; full-chain waste uses `(expired + damaged) / total produced`. Two different denominators, used interchangeably. The 43.5% baseline and 30–50% range never state which applies. | Clearly label the two metrics. State which applies to each reported figure. Clarify which denominator the 30–50% industry range uses. |
| 2 | S2, S4 | **Logistics cost KPI declared but never reported**: Listed as one of three KPIs in S2 but absent from all sensitivity results. | Explicitly scope cost out as a future analysis in S2 and adjust the KPI framing accordingly. |
| 3 | S4 | **15-batch scenario missing waste figure**: Batch comparison reports stock-out (3.8%) for 15 small batches but not the waste rate. | Add the waste result for the 15-batch scenario (or state it was not materially different from baseline). |
| 4 | S4 | **"~39x" is mathematically ~37.5x**: 3.0% / 0.08% = 37.5. | Correct to "approximately 38-fold" or "more than 37-fold". |
| 5 | S3, S6 | **No model validation mentioned**: No back-testing, no SME face-validation, no convergence justification for 100 replications. Limitations section omits this. | Add brief justification for 100 replications in S3. Add model validation as an explicit limitation in S6. |
| 6 | S5 | **SKILL phase numbering (0, 0.5, 0.7, 1, 2, 3) unexplained**: Unconventional and confusing for a non-technical audience. | Add a one-sentence explanation (intermediate checkpoints added after practical experience), or renumber 1–6 with functional titles. |

### 🟡 Priority 2 — Significant improvement

| # | Section(s) | Issue | Action |
|---|---|---|---|
| 7 | S3 | **Stock-out rate unit not precisely defined**: Never states whether 0.68% is patient-level, visit-level, or site-level. | Add one sentence: "percentage of scheduled patient visits where no usable kit of the correct treatment arm was available." |
| 8 | S3 | **No uncertainty reported for 100-replication results**: Only point estimates; no ranges or confidence intervals. | Add a brief characterization of variability across replications for the main KPIs. |
| 9 | S4 | **EU_PROTECT causal pathway not explained**: Reducing EU buffer raises China stock-outs ~38-fold but the mechanism is never explained. | Add 2–3 sentences: lower EU buffer → less stock available for China transfers → shortage manifests at China sites after long lead times. |
| 10 | S4 | **4 large batches produce lower stock-out (0.08%) — counterintuitive, unexplained**: Fewer batches = less stock-out is non-obvious. | Explain: large batches front-load supply, creating a large buffer that covers even peak demand — at the cost of much higher expiry. |
| 11 | S2 | **DND 13-day threshold basis never stated**: Whether regulatory, IRT default, or sponsor policy is not mentioned. | Add a brief parenthetical clarifying the source. |
| 12 | S1, S2 | **Environmental cost mentioned but not integrated into any result**: Flagged qualitatively but not tied to any decision framework. | Acknowledge explicitly that it is a qualitative consideration not directly modeled in this paper. |
| 13 | S2 | **30–50% waste range and <5% stock-out tolerance not cited**: Presented as industry norms without references. | Attribute to Anisimov (2010) or Peterson et al. (2004); note stock-out tolerance is a common sponsor planning convention. |
| 14 | S2, S4 | **Initial site stock mentioned in S2 but never tested**: Called a distinct decision variable then dropped. | Add a note in S4 acknowledging initial site stock was not varied and is a candidate for future sensitivity work. |

### Re-run scope for Round 2

Fixes touch S2 (waste metric, DND basis, cost scoping, citations), S3 (stock-out definition, replication note), S4 (15-batch waste, ~38x correction, EU_PROTECT pathway, 4-batch explanation, cost note), S5 (phase numbering), S6 (validation limitation). Full re-run required: S2 → S3 → S4 → S5 → S6 → S7 → S1.
