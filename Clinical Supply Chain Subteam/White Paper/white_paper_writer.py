#!/usr/bin/env python3
"""
white_paper_writer.py

Dependency-aware iterative white paper drafting loop.

Execution order:
  Pass 1 (independent body sections, run in sequence):
      S2 → S3 → S4 → S5
  Pass 2 (depend on Pass 1):
      S6 (Discussion)   — sees final S3, S4
      S7 (Conclusion)   — sees final S3, S4, S5, S6
  Pass 3 (framing, written last):
      S1 (Introduction) — sees ALL final sections

For each section:
  1. GPT writes initial draft (with upstream context injected)
  2. GPT-5.6-sol reviews: grades clarity / accuracy / audience_fit / overall
  3. If any grade < PASS_THRESHOLD, GPT rewrites incorporating feedback
  4. Repeat up to MAX_ITER times
  5. Accept best version and move on

Outputs:
  white_paper_draft.md   — final assembled paper
  white_paper_log.json   — full iteration log with grades and feedback
"""

import json
import os
import time
from openai import AzureOpenAI

# ── Azure OpenAI config ───────────────────────────────────────────────────────
ENDPOINT   = "https://sds-open-ai.openai.azure.com/"
API_KEY    = "245d8e4e596f499692f0d25821f9ac9e"
API_VER    = "2025-04-01-preview"
DEPLOYMENT = "gpt-5.6-sol"

client = AzureOpenAI(
    azure_endpoint=ENDPOINT,
    api_key=API_KEY,
    api_version=API_VER,
)

MAX_ITER       = 3    # max review-rewrite cycles per section
PASS_THRESHOLD = 8    # grade >= 8 on all dimensions → accept

# ── Shared paper context (injected into every prompt) ────────────────────────
PAPER_CONTEXT = """
You are helping write a ~10-page white paper titled:

  "Simulation-Based Optimization of Clinical Trial Drug Supply Chains:
   A Practical Framework with AI-Assisted Implementation"

AUDIENCE: Cross-functional clinical trial professionals — supply chain
managers, clinical operations leads, study managers, and statisticians.
The paper must bridge the knowledge gap between these disciplines: supply
chain teams are fluent in depot hierarchy, replenishment triggers, and lead
time variability but may be less familiar with simulation methodology;
statisticians understand stochastic processes but may lack operational
supply chain knowledge; clinical operations teams understand trial design
but may not see how visit schedule changes propagate through inventory.
Write so all three groups can follow without assuming deep expertise in
the others' domains. Explain cross-discipline terms at first use.

TONE & STYLE RULES (strictly enforced):
- Plain English. No jargon without a plain-language explanation in parentheses.
- Short sentences and active voice.
- No equations or code snippets in the main text.
- Use concrete examples rather than abstract descriptions.
- Use tables and bullet points for findings and comparisons.
- Each section should read like a practitioner article, not an academic paper.

PAPER STRUCTURE (for orientation — write only the assigned section):
  Executive Summary
  1. Introduction
  2. Clinical Trial Supply Chain: Structure and Challenges
  3. Stochastic Simulation Framework
  4. Sensitivity Analysis and Parameter Optimization
  5. AI-Assisted Implementation: The SKILL Approach
  6. Discussion
  7. Conclusion
  Glossary
  Appendix A
"""

# ── Section definitions ───────────────────────────────────────────────────────
# Each section has:
#   id, title, target_length, brief, depends_on (list of section ids)
#
# depends_on controls what upstream finalized text gets injected
# into the writing and review prompts.

SECTIONS = {
    "sex": {
        "id": "sex",
        "title": "Executive Summary",
        "target_length": "~0.5 page (~250 words)",
        "depends_on": ["s2", "s3", "s4", "s5", "s6", "s7"],
        "brief": """
Write a concise Executive Summary — written LAST after all sections are
finalized, so it accurately reflects the paper's actual content.

Cover these four points in 4–5 short paragraphs:

1. THE PROBLEM: Clinical trial supply teams must balance three competing
   goals — minimize drug waste, control logistics costs, and prevent
   stock-outs that could interrupt patient treatment. No single supply
   policy wins on all three. This challenge grows harder as trials become
   more global and complex.

2. THE APPROACH: This paper presents a stochastic simulation framework
   applied to a hypothetical but realistic Phase 2b/3 trial design
   (250 patients, 23 global sites, two treatment arms, weight-based dosing).
   The simulation runs 100 replications to quantify how supply policies
   affect waste, stock-outs, and logistics cost under uncertainty.

3. KEY FINDING: Reducing the EU site reorder target from 105 to 70 kits
   cuts full-chain waste from 43.5% to ~40% while keeping the stock-out
   rate at ~1.4% — well within the 5% planning threshold. The EU inventory
   protection buffer (EU_PROTECT) is the most critical setting for China
   supply continuity.

4. THE SKILL APPROACH: A structured six-step AI-assisted workflow
   (the SKILL approach, using Amazon Kiro) translates protocol and supply
   specification documents into a working simulation in days rather than
   weeks. Human review checkpoints at every step ensure the model reflects
   actual trial operations before results are used for supply decisions.

The Executive Summary should be self-contained and readable without the
full paper. Do not use abbreviations that are not spelled out here.
"""
    },

    "sgl": {
        "id": "sgl",
        "title": "Glossary",
        "target_length": "~0.6 page (~250 words)",
        "depends_on": ["s2", "s3", "s4", "s5"],
        "brief": """
Write a Glossary of key terms. Present as a two-column table: Term | Definition.
Keep each definition to 1–2 plain-English sentences. Alphabetical order.
Explicitly flag sponsor/system-specific terms (DND, DNS, DNC) as such.
Include ALL of the following terms:

- DNC (Do Not Count): sponsor/system-specific status for inventory that
  physically exists but is excluded from usable stock counts. Typically
  includes kits in the DND window or quarantined pending quality review.
  Terminology and exact scope vary by IRT/RTSM system.
- DND (Do Not Dispense): sponsor-defined rule preventing dispensing of a kit
  expiring within a set period (13 days in this paper). These kits remain
  physically on the shelf but cannot be given to patients. Some systems also
  apply DND until RTSM receipt confirmation is complete. Duration and triggers
  are sponsor-configured, not universal industry standards.
- DNS (Do Not Ship): sponsor/system-specific rule preventing shipment when
  a kit's remaining shelf life at expected arrival would fall below a minimum
  threshold. Thresholds are trial-specific (180 days at site, 270 days at
  regional depot in this paper's example).
- EU_PROTECT: the number of days of expected EU demand that the EU central
  depot reserves before transferring stock to the China regional depot. Set
  to 90 days at baseline. The most sensitive tested parameter for China supply
  continuity in this analysis.
- FEFO (First Expired, First Out): dispensing rule requiring the kit with
  the earliest expiry date to be used first, to minimize avoidable expiry.
- Full-chain waste rate: drug that expires or is damaged at any supply chain
  location (central depot, regional depots, or clinical sites), expressed as
  a percentage of total drug produced.
- IMP (Investigational Medicinal Product): the drug being studied in a
  clinical trial.
- IRT / RTSM (Interactive Response Technology / Randomization and Trial
  Supply Management): the electronic system managing patient randomization
  and drug supply in clinical trials.
- Long window: an extended look-ahead period used to forecast demand for
  resupply planning. Typically 60–90 days in this paper; a configurable
  parameter.
- Operational waste ratio: kits shipped minus kits used, divided by kits
  used. A common industry measure using a shipped-based denominator. Published
  planning ranges of 30–50% typically use this definition.
- Replication: one complete simulated version of a trial, run with a
  different random draw for enrollment, visit timing, and discontinuation.
  Running many replications produces a range of outcomes. This paper uses
  100 replications, acknowledged as a lower bound.
- Short window: a near-term look-ahead period for detecting urgent resupply
  needs. Typically 7–37 days in this paper; a configurable parameter.
- SKILL: the structured six-step AI-assisted workflow described in Section 5.
  It provides a repeatable process for translating protocol and supply
  documents into a working simulation, with mandatory human confirmation at
  each step. The acronym refers to the structured instructions given to the
  AI assistant that encode domain knowledge as a reusable workflow.
- Stochastic simulation: a model including random variation that runs many
  independent replications to produce a range of outcomes rather than a
  single fixed forecast.
- Stock-out: a situation where a clinical site has no usable kit of the
  correct treatment arm when a patient visit is scheduled.
- THRESH (Reorder target): the stock level a site aims to restore after a
  resupply order. Set to 105 kits per kit type per treatment arm at baseline,
  tested at 70 kits. This is the replenishment target, not the order trigger.
"""
    },

    "s2": {
        "id": "s2",
        "title": "2. Clinical Trial Supply Chain: Structure and Challenges",
        "target_length": "~1.75 pages (~850 words)",
        "depends_on": [],
        "brief": """
Write Section 2. Cover all of the following — integrate into flowing prose
with tables where useful, not as a bullet dump:

SUPPLY CHAIN STRUCTURE
- Manufacturer → EU central depot → regional depots (e.g., China) →
  clinical sites → patients. One-way flow. Customs clearance weeks to months.

MANUFACTURING CONTEXT
- Drug produced in batches (set quantity, regardless of immediate need).
- Phase 1/2: small in-house batches by Product Development team.
- Phase 3: shifts to large commercial manufacturer (eventual pharmacy supplier).
  Larger minimum batches, longer planning cycles, less flexibility.
- Production starts before demand is known — inherent waste risk.

THREE-TIER INVENTORY SYSTEM AND OPERATIONAL RULES
- Three tiers: EU central depot, regional depot, clinical site.
- Initial stock: defined quantity sent to each depot at study start; starting
  stock sent to each site at initiation. Distinct decision from ongoing
  resupply — too little risks early stock-out, too much risks expiry at slow
  sites. Note that initial site stock was not varied in the sensitivity
  analysis described in Section 4, and represents a candidate for future
  optimization work.
- Ongoing resupply: automatic trigger when usable stock falls below minimum.
- FEFO (First Expired, First Out): dispense earliest-expiry kit first.
- DND (Do Not Dispense): drug expiring within 13 days cannot be dispensed,
  even if physically on the shelf. This 13-day window is a sponsor-defined
  quality threshold reflecting the minimum usable life needed to support
  patient visits and dispensing safety checks. Note that in practice, kits
  arriving at a site are also not eligible for dispensing until the site
  pharmacist completes receipt confirmation in the RTSM system — including
  verification of quantity, packaging integrity, labeling, temperature logs,
  and shelf life. This paper models the shelf-life DND rule; the receipt
  confirmation step is an additional operational layer not captured here.
- DNS (Do Not Ship): a related rule that prevents shipping a kit whose
  remaining shelf life at the expected arrival time would fall below the
  minimum required for that tier. In this paper this is implemented as the
  minimum remaining shelf life at site/depot receipt (see Appendix A).
- DNC (Do Not Count): kits that are physically present but excluded from
  usable inventory counts — for example kits inside the DND window.
- IRT (Interactive Response Technology) / RTSM (Randomization and Trial
  Supply Management): the electronic system managing randomization and drug
  supply. Assigns treatment arm, identifies kit to dispense, tracks inventory,
  triggers resupply. IRT rules must closely match simulation assumptions — a
  mismatch means simulation results will not reflect actual trial operations.

WHAT MAKES SUPPLY HARD TO PLAN
- Enrollment unpredictable; randomization uncertain; lead times variable;
  limited shelf life. Together: shelf-life-constrained supply chain.

FIXED VS. VARIABLE WASTE DRIVERS
- Fixed (outside team's control): number of countries, depots, label
  languages, customs requirements, drug shelf life.
- Variable (adjustable): initial stock quantities, resupply thresholds.
  Optimization effort should focus here.

WASTE DEFINITIONS — TWO DISTINCT METRICS
This paper uses two waste measures that must not be confused:

1. Operational waste ratio (common industry measure):
   (kits shipped minus kits used) divided by kits used, expressed as a
   percentage. For example, 140 kits shipped and 100 used = 40% by this
   measure. Industry planning ranges of 30–50% cited in the literature
   (Anisimov 2010; Peterson et al. 2004) typically use this shipped-based
   definition.

2. Full-chain waste rate (used as the primary metric in this paper):
   All drug that expired or was damaged at any location in the supply chain
   (central depot, regional depots, and clinical sites), expressed as a
   percentage of total drug produced. This denominator differs from the
   shipped-based measure. Both are reported and compared in this paper;
   Section 4 explains why full-chain waste is the more useful primary metric.

LOGISTICS COST
- Smaller, more frequent shipments reduce expiry but raise freight and
  packaging costs. If the smallest shipping carton holds 4 kits, sending
  1 kit per shipment costs approximately 4× more than sending all 4 together.
  Cold-chain requirements (temperature-controlled transport/storage) amplify
  this further — some biologics require ultra-cold conditions, making each
  shipment extremely expensive.
- This paper uses "logistics cost" to mean shipping, packaging, and handling
  costs only. It does not include IMP (Investigational Medicinal Product)
  manufacturing costs, which are a separate and often much larger cost driver.
  Quantified logistics cost modeling requires study-specific freight rates and
  packaging costs, and is beyond the scope of the current analysis; it is
  presented as a future extension in Section 6.

STOCK-OUT CONSEQUENCES AND TOLERANCE
- Missed visits, extended timelines, patent exclusivity erosion.
- Many teams target a 0–5% stock-out tolerance (a common sponsor planning
  convention), depending on disease severity, patient vulnerability, and
  available treatment alternatives.

SUSTAINABILITY
- Drug expiry has both financial and environmental costs. Discarded kits
  represent wasted manufacturing materials, packaging, energy, and disposal
  burden. Environmental impact is not directly modeled in this paper but
  represents an additional motivation — beyond cost — to minimize waste.

KPI DEFINITIONS
- Stock-out rate: percentage of scheduled patient visits where no usable
  kit of the correct treatment arm was available (target: below 5%)
- Full-chain waste rate: drug expired or damaged at ALL locations, as a
  percentage of total drug produced (industry planning range: 30–50%,
  using the full-chain denominator)
- Logistics cost: driven by shipment frequency, size, and cold-chain
  requirements (qualitative in this paper; quantification is future work)

- Reference Anisimov (2010) and Lefew, Ninh & Anisimov (2021) as the
  academic foundation for the statistical modeling approach used later.
"""
    },

    "s3": {
        "id": "s3",
        "title": "3. Stochastic Simulation Framework",
        "target_length": "~2 pages (~950 words)",
        "depends_on": ["s2"],
        "brief": """
Write Section 3. Open with a brief paragraph introducing the hypothetical
trial design used to demonstrate the framework. State clearly that this is
a hypothetical but realistic design — not a specific approved or ongoing
study. Describe it as a Phase 2b/3 confirmatory study with weight-based
dosing (patients are stratified by body weight and receive different kit
quantities accordingly, which is a common design feature in late-stage
development — note: stratification is by body weight, not BMI). This type
of design is common in oncology, metabolic, and rare disease indications.
Refer readers to Appendix A for the full parameter list.

Then cover:

3.1 Modeling patient enrollment
- Sites do not all recruit at the same pace. The simulation assigns each
  site an enrollment rate drawn from three tiers: low (1/month), medium
  (2/month), high (4/month). These rates describe successful enrollment
  after the screening process — not the number screened.
- 35% of screened patients fail screening and are not enrolled.
- 15% of sites never enroll a single patient. They still receive initial
  stock, which can expire unused.
- 20% of enrolled patients discontinue treatment over the 52-week period.
  Modeling discontinuation explicitly is important: omitting it overestimates
  total drug demand by about 10–15%, leading to unnecessary production.

3.2 How the simulation runs day by day
- Daily time-step over ~850-day horizon.
- Sequence each day: enrollment, visit attendance, kit dispensing (FEFO,
  DND applied first), weekly inventory review and resupply ordering,
  depot processing and shipping, manufacturing batch arrivals, expiry sweep.
- Kit-level tracking: each kit has a type (5ml/2.5ml/7.5ml), treatment arm
  (A or B), expiry date, and location.
- Sites review stock once weekly and order to target level including
  in-transit stock. Weekly review prevents over-ordering from daily triggers.

3.3 Manufacturing and replenishment policy
- 8 batches at 60-day intervals. Each batch sized for ~210 days of expected
  demand (150-day coverage + 60-day safety stock).
- EU_PROTECT: EU depot reserves 90 days of its own demand before
  transferring to China. China also has a daily top-up trigger at 7 days.

3.4 What the simulation produces
- 100 independent replications, each with different random draws for
  enrollment, visit timing, and treatment discontinuation. Results are
  summarized as means across replications.
- The stock-out rate is defined as the percentage of scheduled patient
  visits where no usable kit of the correct treatment arm was available
  at the dispensing site on the visit day.
- 100 replications are used here as a computationally feasible lower bound.
  Analysts in simulation-intensive fields typically use 1,000 or more
  replications for greater precision, particularly for low-probability events.
  With more computational resources, increasing to 1,000+ replications would
  reduce the uncertainty in reported means. The baseline results showed low
  variance across replications (stock-out rates ranged from ~0% to 2%;
  waste rates from ~38% to 49%), suggesting the 100-replication means are
  reasonably stable for this study design.
- All waste results use the full-chain definition: expired and damaged kits
  at all locations, as a percentage of total drug produced.
- Baseline (250 patients, 23 sites, 2 arms): stock-out 0.68%,
  full-chain waste 43.5%.
"""
    },

    "s4": {
        "id": "s4",
        "title": "4. Sensitivity Analysis and Parameter Optimization",
        "target_length": "~2 pages (~950 words)",
        "depends_on": ["s2", "s3"],
        "brief": """
Write Section 4. Cover:

4.1 What sensitivity analysis means here
- Change one parameter at a time, run 100 replications per setting,
  compare stock-out and waste against baseline.
- Trial context: 250 patients, 23 sites (13 EU, 10 China), 2-arm
  double-blind, ~27-month operations within an 850-day simulation.
  Baseline: stock-out 0.68%, full-chain waste 43.5%.
- All waste results use the full-chain definition from Section 2:
  expired and damaged kits at ALL locations / total produced.
- Where available, also report the operational waste ratio (kits shipped
  but not used / kits used) alongside full-chain waste, so readers can
  compare against the industry planning range introduced in Section 2.

4.2 The four parameters that matter most

THRESH top — the site reorder target:
- Default: 105 kits. Lowering to 70 kits reduces full-chain waste from
  43.5% to ~40% while keeping stock-out at ~1.4% — well within the 5% limit.
- Strongest single waste-reduction lever identified.
- Recommendation: reduce EU site target to 70 kits.

MIN_SHELF — minimum remaining shelf life accepted at site receipt:
- Tightening does NOT reduce full-chain waste. Near-expiry kits rejected
  by sites accumulate and expire at the regional depot instead. Full-chain
  waste barely changes — the location of waste shifts, not the total.
- Recommendation: keep 30-day default. Quality control parameter only.

EU_PROTECT — days of EU demand reserved before transferring to China:
- At 90 days (default): China stock-out 0.08%.
- At 30 days: China stock-out rises to 3.0% — a more than 37-fold increase
  (3.0 / 0.08 = 37.5), while full-chain waste barely changes.
- The mechanism: a lower EU buffer means less stock remains available for
  China transfers. Because international lead times to China are long
  (weeks to months), once the buffer is depleted, there is not enough time
  to correct the shortage before site stock-outs occur.
- Recommendation: never go below 60 days. Keep 90-day default.

MFG batch frequency (total production volume held fixed):
- 4 large batches: stock-out 0.08%, waste 56%. Large batches front-load
  supply, creating a large early buffer that protects against even peak
  demand — but much of the drug then sits at depots and expires before
  patients need it. The low stock-out rate is achieved at the cost of a
  large increase in waste.
- 8 batches / 60-day interval: stock-out 0.68%, waste 43.5% — best balance.
- 15 small batches: stock-out 3.8%, waste approximately 43% (similar to
  baseline — frequent small deliveries do not materially reduce waste but
  leave less protection between arrivals, raising stock-out risk).
- Recommendation: keep 8-batch schedule.

4.3 Why the right waste metric matters
- Site-only waste: counts expiry at sites only. Can mislead — tightening
  shelf-life rules reduces site expiry but raises depot expiry. Total unchanged.
- Full-chain waste: counts expiry and damage at ALL locations / total
  produced. Always use full-chain as the primary metric.
- Note: the industry planning range of 30–50% cited in Section 2 uses the
  shipped-based operational waste ratio. The full-chain metric used in
  this paper uses total produced as the denominator and is not directly
  comparable to that benchmark. This paper reports both definitions where
  relevant and makes clear which applies.

4.4 Recommended operating configuration
Present as a summary table. Note that initial site stock was not varied
in this analysis; it represents a candidate for future sensitivity work.

4.5 Connection to the academic literature
- Anisimov (2010): overage rises steeply as stock-out → 0. Confirmed here
  (4-batch scenario: 0.08% stock-out, 56% waste).
- Center-stratified randomization requires less overage than unstratified.
- More depots and treatment arms increase required overage.
"""
    },

    "s5": {
        "id": "s5",
        "title": "5. AI-Assisted Implementation: The SKILL Approach",
        "target_length": "~2.5 pages (~1200 words)",
        "depends_on": ["s2", "s3", "s4"],
        "brief": """
Write Section 5. Cover:

5.1 The challenge of building a simulation from scratch
- A faithful IMP supply chain simulation is 500-1,000 lines of code.
  Writing manually takes weeks; debugging edge cases takes longer.
- Domain knowledge is scattered across protocol, supply spec, IRT/RTSM
  documents, emails, meeting notes — hard to translate into code without
  mistakes. A small misunderstanding about how in-transit stock is counted
  in a reorder calculation can produce results that look plausible but are
  operationally wrong.

5.2 What the SKILL approach is and what makes it different
- A "skill" is a structured set of instructions given to Amazon Kiro (an AI
  coding assistant) that encodes domain expertise as a reusable workflow.
- Most approaches to AI-assisted simulation ask the AI to generate code from
  a prompt. The SKILL is different in two ways: (1) it defines a mandatory
  sequence of human-confirmation steps BEFORE any code is written, so the
  model is built on agreed and documented assumptions rather than AI guesses;
  (2) it encodes hard-won domain rules (FEFO, weekly review, depot-pull logic,
  full-chain waste reporting) as non-negotiable coding requirements rather
  than hoping the AI infers them. The result is not just faster drafting — it
  is a more reliable translation of operational knowledge into simulation logic.
- The AI produces an initial code draft quickly, but that draft is not
  the same as a validated simulation. It still requires human testing,
  review, verification, validation, and approval under the sponsor's
  procedures before any results can inform supply decisions.

5.3 The six-step workflow in practice
(Use the clean 1-6 step numbering, not 0/0.5/0.7/1/2/3.)

Step 1 — Read the study: AI reads full protocol and supply spec before
writing any code. Checks persistent context file from prior sessions.

Step 2 — Confirm every assumption: AI presents a table of every major
modeling decision and waits for explicit analyst approval. Nothing assumed
silently.

Step 3 — Verify dispensing scenarios: Dedicated checklist of 10+ scenarios
(missed visits, mid-visit stock-out, patient discontinuation, DND-window
kits, partial fills, etc.). All must be confirmed before coding.

Step 4 — Generate the model: AI writes R code following mandatory rules
(FEFO dispensing, weekly review, depot-pull logic, enrollment validation,
full-chain waste reporting).

Step 5 — Run and interpret: Analyst runs code in approved environment,
shares output. AI explains results in plain English, flags anomalies.

Step 6 — Produce a structured report: KPI summary, comparisons, prioritized
recommendations, open questions for human decision.

5.4 What the AI handles well — and where humans must stay involved

AI strengths: initial code draft from a detailed specification; parameter
sweeps without fatigue; logical consistency checks; institutional memory via
persistent context file.

Human responsibilities: deciding clinically acceptable stock-out tolerance;
interpreting ambiguous protocol language; approving any change affecting
patient safety; all verification, validation, and sign-off steps.

5.5 Hard lessons — and how the SKILL fixed them
Frame as practical lessons, not debugging notes.

Over-enrollment: early model enrolled 3–4× too many patients. All outputs
were meaningless despite looking plausible. Fix: mandatory enrollment
validation before any result is interpreted.

Phantom drug: model created new kit records when shipping instead of pulling
from depot stock. Depot inventory never fell. Fix: explicit depot-pull logic
is a non-negotiable coding rule.

Wrong waste metric: early reports counted only site expiry, missing all
depot expiry. Waste appeared artificially low. Fix: full-chain waste is
the only reported primary metric.

Lesson: AI-generated code can be wrong even when it runs without errors.
Human testing against known benchmarks is always required.
"""
    },

    "s6": {
        "id": "s6",
        "title": "6. Discussion",
        "target_length": "~0.75 page (~350 words)",
        "depends_on": ["s3", "s4"],
        "brief": """
Write Section 6. Reference specific findings from Sections 3 and 4.

Cover:
- Supply chain optimization is a strategic capability, not a logistics
  back-office task. Right configuration protects patent exclusivity and
  reduces per-patient costs. Wrong configuration delays trials and wastes drug.
- Simulation vs. formula-based methods: complementary. Formulas (Anisimov)
  give fast scenario comparison at design stage. Simulation gives operational
  fidelity (FEFO, zero-enrolling sites, weekly review, dynamic thresholds,
  kit-level expiry tracking) during planning and execution.
- Limitations — state all of the following honestly:
    * Model represents one trial design; every new study needs its own
      calibrated parameters.
    * SKILL approach requires AI tools and an analyst willing to iterate.
    * Results depend on input quality — wrong enrollment or dropout
      assumptions produce wrong supply plans.
    * Model has not been validated against historical trial data. This is
      a known limitation. Retrospective validation against actual trial
      supply records would strengthen confidence in the framework. Such
      validation requires a completed trial with available supply records,
      which was not available for this hypothetical design. Teams applying
      the framework to real trials should plan a validation step.
    * 100 replications provide stable mean estimates but do not capture
      all possible tail outcomes; teams should review the replication range,
      not only the mean.
    * Logistics cost in this analysis covers shipping, packaging, and handling
      only. IMP manufacturing cost — often the largest cost component — is
      excluded because it requires study-specific bill-of-materials and
      manufacturing cost data that were not available. Future work can layer
      IMP cost on top of the logistics analysis.
- Broader applicability: the SKILL workflow applies to other complex
  clinical simulation tasks — recruitment forecasting, adaptive trial
  scenario testing, biomarker-driven randomization.
- Quantified logistics cost modeling including IMP manufacturing cost is a
  natural next step for future work.
"""
    },

    "s7": {
        "id": "s7",
        "title": "7. Conclusion",
        "target_length": "~0.5 page (~230 words)",
        "depends_on": ["s3", "s4", "s5", "s6"],
        "brief": """
Write a three-paragraph conclusion. Reference specific findings concretely.

Paragraph 1 — The supply problem and what simulation reveals:
Three-way tension (waste/cost/stock-out). Key finding: lowering site reorder
target from 105 to 70 kits reduces full-chain waste from 43.5% to ~40% while
keeping stock-out well below 5%. EU_PROTECT is the most critical parameter
for China supply continuity — reducing it from 90 to 30 days raises China
stock-out more than 37-fold with almost no waste benefit.

Paragraph 2 — The AI-assisted contribution:
SKILL compressed protocol-to-simulation from weeks to days. Human-in-the-loop
checkpoints at every stage. Three hard lessons (over-enrollment, phantom drug,
wrong waste metric) are now permanent guardrails, making future simulations
safer and faster — but human testing and approval remain essential.

Paragraph 3 — Call to action:
Supply teams should treat simulation-based planning as a standard operational
tool. Rigorous modeling combined with structured AI assistance and human
oversight is ready for operational use today.
"""
    },

    "s1": {
        "id": "s1",
        "title": "1. Introduction",
        "target_length": "~0.75 page (~350 words)",
        "depends_on": ["s2", "s3", "s4", "s5", "s6", "s7"],
        "brief": """
Write the Introduction — LAST, after all other sections are finalized.
You have the full paper text available as context.

Cover:
- Open with the core tension: clinical trial supply teams must deliver the
  right drug to the right patient at the right time — but three competing
  goals make this hard: minimize drug waste, control logistics costs, and
  avoid stock-outs. No single setting wins on all three simultaneously.
- Acknowledge the cross-functional challenge: effective supply planning sits
  at the intersection of supply chain operations, clinical trial management,
  and statistical modeling. These disciplines use different mental models and
  vocabularies. This paper is written to bridge that gap — it explains supply
  chain concepts for readers with a statistics or clinical background, and
  statistical concepts for readers with a supply chain or operations background.
- Why this is getting harder: trials are increasingly global and complex —
  adaptive designs, multiple dosing arms, cold-chain biologics, unpredictable
  enrollment. Sponsors also face scrutiny over the environmental footprint
  of discarded drug.
- The gap: most supply teams still rely on fixed overages and rules of thumb.
- What this paper delivers: (1) a practical simulation framework applied to
  a hypothetical Phase 2b/3 trial (weight-based dosing, global sites) that
  quantifies the waste/stock-out trade-off under uncertainty; and (2) the
  SKILL approach — the paper's central methodological contribution — a
  structured six-step AI-assisted workflow that translates protocol and supply
  specification documents into a working simulation in days, not weeks, while
  keeping human judgment, testing, and approval central at every step.
- End with a one-sentence roadmap: "Section 2 describes the supply chain
  structure and challenges; Section 3 presents the simulation framework;
  Section 4 reports sensitivity analysis findings; Section 5 describes the
  AI-assisted implementation approach; Sections 6 and 7 discuss implications
  and conclusions."
"""
    },
}

# Execution order — respects dependencies
EXECUTION_ORDER = ["s2", "s3", "s4", "s5", "s6", "s7", "s1", "sex", "sgl"]

# Final assembly order
ASSEMBLY_ORDER = ["sex", "s1", "s2", "s3", "s4", "s5", "s6", "s7", "sgl"]

# ── Reviewer system prompt ────────────────────────────────────────────────────
REVIEWER_SYSTEM = """
You are a senior medical writer and clinical trial supply chain expert.
Your job is to review a draft section of a white paper and return structured
feedback as valid JSON.

AUDIENCE: Clinical trial operationalists — non-technical readers.
Plain English is mandatory. No equations, no code.

Return ONLY valid JSON with this exact structure — no preamble, no markdown:
{
  "grades": {
    "clarity": <integer 1-10>,
    "accuracy": <integer 1-10>,
    "audience_fit": <integer 1-10>
  },
  "overall": <integer 1-10>,
  "feedback": "<concise bullet-point list of issues to fix>",
  "revised_draft": "<full revised section text — the complete section, not just changes>"
}

Grading rubric:
- clarity (1-10): Clear, jargon-free, easy to follow sentence by sentence?
- accuracy (1-10): Facts, numbers, and logic correct and internally consistent?
- audience_fit (1-10): Tone and depth appropriate for a non-technical
  clinical operations practitioner?
- overall (1-10): Holistic quality.

If all scores >= 8, the section is accepted. revised_draft may equal the
input draft if no changes are needed.
If any score < 8, revised_draft must incorporate your feedback fully.
The revised_draft must always be the COMPLETE section text.
"""

# ── API call ──────────────────────────────────────────────────────────────────
def call_gpt(messages, max_tokens=4096):
    """Call gpt-5.6-sol via the responses API."""
    response = client.responses.create(
        model=DEPLOYMENT,
        input=messages,
        max_output_tokens=max_tokens,
    )
    return response.output_text.strip()


# ── Build upstream context block ──────────────────────────────────────────────
def build_upstream_context(section, finalized):
    """
    Return a formatted string of all upstream sections that this section
    depends on, using their finalized text.
    """
    deps = section["depends_on"]
    if not deps:
        return ""
    parts = ["The following sections have already been finalized. "
             "Use them for consistency and to avoid repetition:\n"]
    for dep_id in deps:
        if dep_id in finalized:
            dep = SECTIONS[dep_id]
            parts.append(f"--- {dep['title']} ---\n{finalized[dep_id]}\n")
    return "\n".join(parts)


# ── Write initial draft ───────────────────────────────────────────────────────
def write_draft(section, finalized):
    upstream = build_upstream_context(section, finalized)
    upstream_block = (
        f"\n\nCONTEXT FROM PREVIOUSLY FINALIZED SECTIONS:\n{upstream}\n"
        if upstream else ""
    )
    prompt = f"""{PAPER_CONTEXT}{upstream_block}
---

Now write the following section:

SECTION: {section['title']}
TARGET LENGTH: {section['target_length']}

CONTENT BRIEF:
{section['brief']}

Output only the section text. Start directly with the section heading.
Do not add any meta-commentary before or after.
"""
    return call_gpt([{"role": "user", "content": prompt}], max_tokens=4096)


# ── Review a draft ────────────────────────────────────────────────────────────
def review_draft(section, draft, iteration, finalized):
    upstream = build_upstream_context(section, finalized)
    upstream_block = (
        f"\nPREVIOUSLY FINALIZED SECTIONS (for consistency checking):\n{upstream}\n"
        if upstream else ""
    )
    prompt = f"""You are reviewing iteration {iteration} of a white paper section.

PAPER CONTEXT:
{PAPER_CONTEXT}
{upstream_block}
SECTION BEING REVIEWED: {section['title']}

CONTENT BRIEF (what this section must cover):
{section['brief']}

---
DRAFT TO REVIEW:
{draft}
---

Review carefully for clarity, accuracy, audience fit, and consistency with
upstream sections. Return valid JSON only — no preamble, no markdown fences.
"""
    messages = [
        {"role": "system", "content": REVIEWER_SYSTEM},
        {"role": "user",   "content": prompt},
    ]
    raw = call_gpt(messages, max_tokens=4096)

    # Strip markdown code fences if present
    if "```" in raw:
        parts = raw.split("```")
        for part in parts:
            part = part.strip()
            if part.startswith("json"):
                part = part[4:].strip()
            try:
                return json.loads(part)
            except json.JSONDecodeError:
                continue

    try:
        return json.loads(raw)
    except json.JSONDecodeError as e:
        print(f"    [WARN] JSON parse error: {e}")
        print(f"    [WARN] Raw (first 400 chars): {raw[:400]}")
        return {
            "grades": {"clarity": 5, "accuracy": 5, "audience_fit": 5},
            "overall": 5,
            "feedback": f"JSON parse error on iteration {iteration} — retrying.",
            "revised_draft": draft,
        }


# ── Check if section passes ───────────────────────────────────────────────────
def passes(review):
    g = review["grades"]
    return (
        g["clarity"]      >= PASS_THRESHOLD and
        g["accuracy"]     >= PASS_THRESHOLD and
        g["audience_fit"] >= PASS_THRESHOLD and
        review["overall"] >= PASS_THRESHOLD
    )


# ── Process one section ───────────────────────────────────────────────────────
def process_section(section, finalized):
    print(f"\n{'='*60}")
    print(f"SECTION: {section['title']}")
    if section["depends_on"]:
        print(f"  Dependencies: {section['depends_on']}")
    print('='*60)

    log = {
        "section_id":  section["id"],
        "title":       section["title"],
        "iterations":  [],
    }

    print("  Writing initial draft...")
    draft = write_draft(section, finalized)
    print(f"  Draft written ({len(draft.split())} words)")

    review = None
    for i in range(1, MAX_ITER + 1):
        print(f"\n  [Review {i}/{MAX_ITER}]")
        review = review_draft(section, draft, i, finalized)

        g = review["grades"]
        print(f"  Grades → clarity={g['clarity']}  "
              f"accuracy={g['accuracy']}  "
              f"audience_fit={g['audience_fit']}  "
              f"overall={review['overall']}")
        print(f"  Feedback: {str(review['feedback'])[:180]}...")

        log["iterations"].append({
            "iteration":   i,
            "draft":       draft,
            "grades":      g,
            "overall":     review["overall"],
            "feedback":    review["feedback"],
        })

        if passes(review):
            print(f"  ✅ Accepted at iteration {i}.")
            draft = review["revised_draft"]
            break

        if i < MAX_ITER:
            print(f"  Rewriting with feedback...")
            draft = review["revised_draft"]
        else:
            print(f"  ⚠️  Max iterations reached. Using best available draft.")
            draft = review["revised_draft"]

    log["final_draft"]   = draft
    log["final_grades"]  = review["grades"] if review else {}
    log["final_overall"] = review["overall"] if review else 0
    return log


# ── References ────────────────────────────────────────────────────────────────
REFERENCES = """
---

## References

1. Anisimov VV. Drug supply modelling in clinical trials (statistical methodology). *Pharmaceutical Outsourcing*. May/Jun 2010:17–20.

2. Lefew M, Ninh A, Anisimov V. End-to-end drug supply management in multicenter trials. *Methodology and Computing in Applied Probability*. 2021;23:695–709. https://doi.org/10.1007/s11009-020-09776-z

3. Anisimov VV, Fedorov VV. Modelling, prediction and adaptive adjustment of recruitment in multicentre trials. *Statistics in Medicine*. 2007;26(27):4958–4975.

4. Anisimov VV, Fedorov VV, Heiberger R, Saha S, Kothapalli M. Drug Supply Modeling Software: User Manual. GSK DDS Technical Report 2010-01. GlaxoSmithKline Pharmaceuticals; 2010.

5. Peterson M, Byrom B, Dowlman N, McEntegart D. Optimizing clinical trial supply requirements: simulation of computer-controlled supply chain management. *Clinical Trials*. 2004;1(4):399–412.

6. International Council for Harmonisation. ICH E6(R3): Guideline for Good Clinical Practice. ICH; 2025.

7. Holford N, Hale M, Ko HC, et al. Clinical trial simulation: a review. *Clinical Pharmacology & Therapeutics*. 2010;88(2):166–182. https://doi.org/10.1038/clpt.2010.114

8. European Medicines Agency. Guideline on the requirements for quality documentation concerning biological investigational medicinal products in clinical trials. EMA/CHMP/BWP/534898/2008; 2012.
"""


# ── Main ──────────────────────────────────────────────────────────────────────
def main():
    finalized = {}   # section_id → final draft text
    all_logs  = []

    for sec_id in EXECUTION_ORDER:
        section = SECTIONS[sec_id]
        log = process_section(section, finalized)
        finalized[sec_id] = log["final_draft"]
        all_logs.append(log)
        time.sleep(2)  # brief pause between sections

    # Assemble in reading order
    header = (
        "# Simulation-Based Optimization of Clinical Trial Drug Supply Chains:"
        " A Practical Framework with AI-Assisted Implementation\n\n---\n\n"
    )
    body = "\n\n---\n\n".join(finalized[sid] for sid in ASSEMBLY_ORDER)
    final_paper = header + body + REFERENCES

    # Write outputs
    out_dir    = os.path.dirname(os.path.abspath(__file__))
    paper_path = os.path.join(out_dir, "white_paper_draft.md")
    log_path   = os.path.join(out_dir, "white_paper_log.json")

    with open(paper_path, "w") as f:
        f.write(final_paper)

    # Append to log (preserve prior run history)
    existing_logs = []
    if os.path.exists(log_path):
        try:
            with open(log_path, "r") as f:
                existing_logs = json.load(f)
        except (json.JSONDecodeError, IOError):
            existing_logs = []
    combined_logs = existing_logs + all_logs
    with open(log_path, "w") as f:
        json.dump(combined_logs, f, indent=2)

    # Summary
    print(f"\n{'='*60}")
    print("COMPLETE")
    print(f"  Paper : {paper_path}")
    print(f"  Log   : {log_path}")
    print(f"{'='*60}")
    print(f"\n{'Section':<52} {'Clar':>4} {'Acc':>4} {'Aud':>4} {'Ovr':>4} {'Iter':>5}")
    print("-" * 72)
    for log in all_logs:
        g = log.get("final_grades", {})
        print(f"  {log['title'][:50]:<50} "
              f"{g.get('clarity','?'):>4} "
              f"{g.get('accuracy','?'):>4} "
              f"{g.get('audience_fit','?'):>4} "
              f"{log.get('final_overall','?'):>4} "
              f"{len(log['iterations']):>5}")


if __name__ == "__main__":
    main()
