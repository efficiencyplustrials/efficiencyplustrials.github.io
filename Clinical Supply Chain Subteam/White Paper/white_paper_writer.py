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

AUDIENCE: Clinical trial operationalists — supply chain managers, clinical
operations leads, study managers. Non-technical readers. No statistics or
coding background assumed.

TONE & STYLE RULES (strictly enforced):
- Plain English. No jargon without a plain-language explanation in parentheses.
- Short sentences and active voice.
- No equations or code snippets in the main text.
- Use concrete examples and analogies rather than abstract descriptions.
- Use tables and bullet points for findings and comparisons.
- Each section should read like a practitioner article, not an academic paper.

PAPER STRUCTURE (for orientation — write only the assigned section):
  1. Introduction
  2. Clinical Trial Supply Chain: Structure and Challenges
  3. Stochastic Simulation Framework
  4. Sensitivity Analysis and Parameter Optimization
  5. AI-Assisted Implementation: The SKILL Approach
  6. Discussion
  7. Conclusion
"""

# ── Section definitions ───────────────────────────────────────────────────────
# Each section has:
#   id, title, target_length, brief, depends_on (list of section ids)
#
# depends_on controls what upstream finalized text gets injected
# into the writing and review prompts.

SECTIONS = {
    "s2": {
        "id": "s2",
        "title": "2. Clinical Trial Supply Chain: Structure and Challenges",
        "target_length": "~1.75 pages (~850 words)",
        "depends_on": [],
        "brief": """
Write Section 2. Cover all of the following — integrate them into flowing
prose with tables where useful, not as a bullet dump:

SUPPLY CHAIN STRUCTURE
- How the supply chain is structured: manufacturer → EU central depot →
  regional depots (e.g., China) → clinical sites → patients. The flow is
  one-way. Customs clearance can take weeks to months, which is why regional
  depots exist close to where patients are.

MANUFACTURING CONTEXT
- Drug is manufactured in "runs" or batches — a batch is designed to produce
  a set amount regardless of how much is immediately needed.
- Early in development (Phase 1/2), the Product Development team manufactures
  small batches in-house. As Phase 3 approaches, production shifts to large
  commercial manufacturers who will eventually supply approved product to
  pharmacies. This shift affects batch sizing flexibility and lead times.
- Whether manufactured in small or large batches, production is planned
  ahead of demand, which creates inherent waste risk if enrollment is slower
  than expected.

THREE-TIER INVENTORY SYSTEM AND OPERATIONAL RULES
- Explain the three inventory tiers (EU central depot, regional depot,
  clinical site) and their roles.
- Initial stock: at study start, a defined quantity of drug is sent to each
  depot, and at site initiation (when a site first opens), a starting stock
  is sent to the site. Choosing this initial quantity is a distinct planning
  decision — too little risks an early stock-out before resupply arrives;
  too much risks expiry if the site recruits slowly.
- Ongoing resupply: sites use an automatic trigger — when usable stock falls
  below a set minimum, the site requests more from the depot. Explain FEFO
  (First Expired, First Out): sites dispense the drug with the earliest
  expiry date first. Explain DND (Do Not Dispense): drug expiring within
  13 days cannot be given to patients, even if it is physically on the shelf.
- IRT (Interactive Response Technology): IRT is the electronic system used
  in most clinical trials to manage randomization and drug supply. When a
  patient is randomized, the IRT assigns them to a treatment arm and
  identifies which kit to dispense. IRT also tracks site inventory and can
  trigger automatic resupply requests. The supply rules encoded in the IRT
  — minimum stock levels, kit assignment logic, resupply thresholds — must
  closely match the assumptions used in any supply simulation. A mismatch
  between the IRT configuration and the simulation model leads to predictions
  that do not reflect real trial operations.

WHAT MAKES SUPPLY HARD TO PLAN
- Enrollment is unpredictable: sites recruit faster or slower than expected.
- Randomization adds uncertainty: the required treatment arm cannot be
  predicted until the moment of randomization.
- Lead times vary: manufacturing, transport, customs, and site delivery all
  take longer than planned at times.
- Drugs have a limited shelf life: inventory loses usability over time.
- Together these create the shelf-life-constrained regime: unlike commercial
  supply chains, ordering too much too early can make performance worse
  because drug expires before patients arrive.

FIXED VS. VARIABLE WASTE DRIVERS
- Some parameters that drive waste are fixed and outside the team's control:
  number of languages required on the drug label (which can force separate
  kit productions per region), number of countries, number of depots,
  customs requirements, and the drug's shelf life.
- Other parameters are variable — the team can adjust them: the initial
  stock sent to each depot and site at study start, and the resupply
  thresholds that trigger ongoing orders.
- Understanding this distinction focuses optimization effort where it can
  actually make a difference.

WASTE DEFINITION AND COST MECHANICS
- Drug wastage is commonly expressed as a percentage:
  (kits shipped − kits used) / kits used × 100%.
  A 30–50% waste rate is the typical industry planning range for clinical
  trials — this is expected given the need to protect patients against
  uncertain demand, not a sign of failure.
- There is a fundamental trade-off between shipping cost and waste. Shipping
  smaller, more frequent quantities reduces waste but increases cost
  dramatically. For example, if the smallest shipping carton holds 4 kits,
  sending 1 kit per shipment costs 4× more in packaging and freight than
  sending all 4 together. Cold-chain requirements (temperature-controlled
  transport and storage) amplify this effect further — some biologics
  require ultra-cold storage, making every shipment extremely expensive.
  Teams willing to accept somewhat higher waste may consolidate shipments
  and substantially reduce logistics costs.
- Stock-out consequences: missed patient visits, extended recruitment
  timelines, and additional operational costs. Supply delays can also
  consume patent exclusivity time, reducing the commercial window after
  approval.

SUSTAINABILITY DIMENSION
- Drug expiry is not only a financial loss — it also represents an
  environmental cost. Discarded investigational product consumes the
  resources used to manufacture, package, and ship it, then adds to
  pharmaceutical waste streams. As trials grow more global and complex,
  the environmental footprint of wasted drug is an increasing concern
  for sponsors alongside cost.

KPI DEFINITIONS
- Define the three KPIs used throughout the paper:
    * Stock-out rate: the percentage of patient visits where no usable drug
      was available for the patient's assigned treatment (target: below 5%)
    * Full-chain waste rate: all drug that expired or was damaged anywhere
      in the supply chain — central depot, regional depots, and sites —
      as a percentage of total drug produced (industry norm: 30–50%)
    * Logistics cost: driven mainly by shipping frequency, shipment size,
      and cold-chain requirements

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
Write Section 3. Cover:

3.1 Modeling patient enrollment
- Sites do not all recruit at the same pace. Some are fast, some slow, some
  never enroll a single patient. The simulation captures this by giving each
  site its own enrollment rate, drawn from a realistic distribution across
  three tiers: low (1 patient/month), medium (2/month), high (4/month).
  35% of screened patients fail screening and are not enrolled. 15% of sites
  never enroll anyone.
- Patients drop out: 20% over the 52-week treatment period. This is modeled
  explicitly — omitting dropout overestimates total drug demand by 10-15%,
  which would cause over-production.

3.2 How the simulation runs day by day
- The simulation advances one day at a time over an ~850-day trial horizon.
- Each day, in sequence: new patients may enroll; existing patients may
  attend visits; drug is dispensed (oldest stock first, subject to DND
  rule); sites check their stock and place orders if needed; depots process
  and ship pending orders; manufacturing batches may arrive at the EU depot;
  expired drug is removed and logged.
- Drug is tracked at the individual kit level: each kit has a type (5ml,
  2.5ml, or 7.5ml), a treatment arm (A or B), and an expiry date.
- Sites review their stock once a week and order enough to reach a target
  level, accounting for drug already on its way. This weekly review prevents
  the over-ordering that daily triggers can cause.

3.3 Manufacturing and replenishment policy
- Manufacturing runs on a fixed schedule: 8 batches, one every 60 days,
  starting at Day 0. Each batch is sized to cover approximately 210 days
  of expected demand — a 150-day coverage window plus 60 days of safety
  stock.
- When a batch arrives at the EU depot, the system automatically calculates
  how much China needs and transfers accordingly. The EU depot always keeps
  enough stock to cover its own next 90 days before sending anything to
  China (this is the EU_PROTECT parameter, explained further in Section 4).
- A daily check also tops up China's depot if it drops below 7 days of
  supply, providing a safety net between batch transfers.

3.4 What the simulation produces
- The simulation runs 100 independent replications, each with a different
  random draw of enrollment rates, visit timing, and dropout. This produces
  a distribution of outcomes rather than a single number, capturing
  real-world uncertainty.
- Key outputs: stock-out rate (visit-level), full-chain waste rate,
  kits dispensed, kits expired at each supply chain level, and kits
  damaged in transit (assumed 1% damage rate per shipment).
- Baseline result for this trial (250 patients, 23 sites, 2 arms):
  stock-out rate 0.68%, full-chain waste 43.5% — both within acceptable
  ranges.
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
- Explain plainly: run the simulation hundreds of times, changing one
  parameter at a time, to find out which settings matter most and by
  how much.
- Trial context: 250 patients, 23 sites (13 EU, 10 China), 2-arm
  double-blind, ~27-month horizon. Baseline: stock-out 0.68%,
  full-chain waste 43.5%.

4.2 The four parameters that matter most

THRESH top — the site reorder target (how much stock a site aims to hold):
- Default: 105 kits. Lowering to 70 kits reduces waste from 43.5% to ~40%
  while keeping stock-out at ~1.4% — still well within the 5% limit.
- This is the single most powerful lever for reducing waste without
  increasing stock-out risk.
- Recommendation: reduce EU site target to 70 kits.

MIN_SHELF — minimum remaining shelf life accepted when drug arrives at a site:
- Intuition says: accept only fresh drug → less expiry at sites.
- Reality: tightening this rule does NOT reduce total waste. It only moves
  expiry from sites to the China depot, where rejected near-expiry kits
  accumulate. Full-chain waste barely changes.
- Recommendation: keep the default (30 days). This is a quality control
  parameter, not a waste-reduction lever.

EU_PROTECT — how many days of EU demand to reserve before transferring
stock to China:
- At 90 days (default): China stock-out rate is 0.08%.
- At 30 days: China stock-out rate jumps to 3.0% — a 39-fold increase —
  while waste barely changes.
- Recommendation: never go below 60 days. The 90-day default is the
  safe operating point.

MFG batch frequency (with total supply volume held fixed):
- 4 large batches: lowest stock-out (0.08%) but waste jumps to 56% —
  drug sits in the depot too long and expires.
- 15 small batches: stock-out rises to 3.8% — too many small deliveries
  create gaps in supply between arrivals.
- 8 batches / 60-day interval is the optimal balance.

4.3 Why the right waste metric matters
- Site-only waste (V1) measures expiry at clinical sites only.
- Full-chain waste (V2) includes expiry at both depots as well.
- V1 misleads: tightening shelf-life filters looks like it reduces
  waste in V1, but V2 shows it just moved the waste to the depot.
  Supply teams relying on V1 alone risk making the wrong call.
- Always use full-chain (V2) waste as the primary metric.

4.4 Recommended operating configuration
Present as a summary table:
| Parameter          | Default | Recommended | Expected outcome                        |
|--------------------|---------|-------------|------------------------------------------|
| THRESH top (EU)    | 105     | 70          | Waste 43% → 40%, stock-out 0.7% → 1.4% |
| MIN_SHELF          | 30 days | 30 days     | No change needed                        |
| EU_PROTECT         | 90 days | 90 days     | No change needed                        |
| MFG batch schedule | 8 × 60d | 8 × 60d     | No change needed                        |

4.5 Connection to the academic literature
- Anisimov (2010) showed analytically that overage grows steeply as
  stock-out risk approaches zero — confirmed by our simulation.
- Center-stratified randomization requires less overage than unstratified
  randomization — both the formulas and the simulation agree.
- More depots and more treatment arms always increase required overage.
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
  Writing it manually takes weeks; debugging edge cases takes longer.
- The bigger problem: domain knowledge (FEFO rules, DND windows,
  EU_PROTECT logic, blinding requirements) is scattered across protocol
  documents, supply specs, and team emails — hard to translate into code
  reliably without mistakes.

5.2 What the SKILL approach is
- A "skill" is a structured set of instructions given to an AI coding
  assistant (Amazon Kiro) that encodes domain expertise as a reusable,
  repeatable workflow.
- Rather than asking the AI to "write a simulation," the SKILL defines
  a step-by-step process: read the spec, confirm assumptions with the
  analyst, generate code, interpret results, record lessons. The AI
  follows this process every time.
- The result: the AI behaves less like a code generator and more like a
  junior analyst who has read the operations manual.

5.3 The workflow in practice — six phases

Phase 0 — Read before writing: The AI reads the full trial protocol and
supply specification before writing a single line of code. It identifies
the analysis type and checks for a persistent context file from previous
sessions.

Phase 0.5 — Confirm every assumption: Before coding, the AI presents a
table of every major decision it will make (e.g., "I will model dropout
using an exponential hazard rate") and waits for explicit analyst sign-off.
Nothing is assumed silently.

Phase 0.7 — Verify dispensing edge cases: A dedicated checklist covers
the scenarios that are easiest to get wrong: what happens if a patient
misses a visit? If stock runs out mid-visit? If a patient discontinues?
All 10+ scenarios must be explicitly confirmed before any code is written.

Phase 1 — Generate code: Only after all decisions are confirmed does the
AI write code, following built-in coding rules (FEFO dispensing, weekly
review cycle, mandatory enrollment count validation, etc.).

Phase 2 — Run and interpret: The analyst runs the code and shares the
output. The AI interprets results in plain English, flags anomalies, and
identifies whether the KPIs are within acceptable ranges.

Phase 3 — Structured report: The AI produces a KPI summary table and
prioritized recommendations, ready to share with the supply team.

5.4 What the AI handles well — and where humans must stay involved

AI strengths:
- Translates a 13-page supply specification into working R code in minutes.
- Runs sensitivity analysis across dozens of parameter combinations
  without fatigue or transcription errors.
- Catches logical inconsistencies in its own outputs when reviewing results.
- Retains institutional knowledge across sessions via a persistent context
  file (supply_chain_context.md) that records confirmed decisions and
  lessons learned.

Where human judgment is irreplaceable:
- Deciding what stock-out rate is clinically acceptable depends on the
  disease, patient population, and regulatory context — no AI can make
  that call.
- Interpreting ambiguous protocol language requires someone who knows
  the study.
- Any supply strategy that affects patient safety requires human
  review and sign-off before implementation.

5.5 Hard lessons from building the simulation — and how the SKILL fixed them
(Frame these as practical lessons for teams adopting AI-assisted simulation,
not as debugging notes.)

Over-enrollment bug: An early version enrolled 3-4 times too many patients,
making all outputs meaningless. The simulation looked plausible but was
completely wrong. The fix: always validate enrollment totals before
interpreting any results. This is now a mandatory step in the SKILL.

Phantom drug bug: The simulation was creating new drug records when shipping
to sites instead of pulling from existing depot stock — so depot inventory
never decreased. The fix: explicit depot-pull logic is now a non-negotiable
coding rule in the SKILL.

Wrong waste metric: Early reports showed a low waste rate that looked
encouraging. It was measuring site-only expiry and missing all depot expiry.
The fix: full-chain (V2) waste is now the only reported metric.

These bugs were found and fixed through the iterative human-AI review loop —
a reminder that AI-generated simulation code always needs validation against
known benchmarks before it is trusted.
"""
    },

    "s6": {
        "id": "s6",
        "title": "6. Discussion",
        "target_length": "~0.75 page (~350 words)",
        "depends_on": ["s3", "s4"],
        "brief": """
Write Section 6. Reference specific findings from the simulation (Section 3)
and sensitivity analysis (Section 4) to ground the discussion.

Cover:
- Supply chain optimization is a strategic capability, not a logistics
  back-office task. The right supply configuration protects patent exclusivity
  timelines and reduces per-patient costs. The wrong one delays trials and
  wastes drug.
- Simulation and analytic methods are complementary, not competing:
  Anisimov's analytic formulas (referenced in Section 4) give fast scenario
  comparisons at the study design stage; simulation gives operational fidelity
  (FEFO, site heterogeneity, dynamic thresholds) during trial execution.
- Limitations to state honestly:
    * The simulation is calibrated to one trial design. Every new study needs
      its own parameter calibration.
    * The SKILL approach requires access to an AI coding assistant and an
      analyst willing to iterate.
    * Results are only as good as the input assumptions. If enrollment rate
      estimates are wrong, the supply plan will be wrong too.
- Broader applicability: the SKILL workflow is not limited to supply chains.
  Any complex simulation task in clinical operations — patient recruitment
  modeling, adaptive design scenario analysis, biomarker-driven randomization
  — can be approached using the same structured human-AI collaboration pattern.
"""
    },

    "s7": {
        "id": "s7",
        "title": "7. Conclusion",
        "target_length": "~0.5 page (~230 words)",
        "depends_on": ["s3", "s4", "s5", "s6"],
        "brief": """
Write a three-paragraph conclusion. Reference specific findings from earlier
sections to make it concrete, not generic.

Paragraph 1 — The supply problem and what simulation reveals:
Summarize the three-way tension (waste / cost / stock-out) and the key
finding that it can be navigated deliberately. Cite the specific result:
lowering the site reorder target from 105 to 70 kits reduces full-chain
waste from 43.5% to ~40% while keeping stock-out well below the 5% threshold.
Mention that EU_PROTECT is the single most critical parameter for China supply
continuity.

Paragraph 2 — The AI-assisted coding contribution:
The SKILL approach compressed the time from protocol to working simulation
from weeks to days, with human-in-the-loop checkpoints ensuring the
simulation faithfully reflects the trial design. The hard lessons
(over-enrollment, phantom drug, wrong waste metric) are now encoded as
permanent guardrails in the SKILL, making each future simulation safer
and faster.

Paragraph 3 — Call to action:
Supply teams should treat simulation-based planning as a standard tool, not
a research exercise. The combination of rigorous modeling and structured
AI-assisted implementation is ready for operational use today.
"""
    },

    "s1": {
        "id": "s1",
        "title": "1. Introduction",
        "target_length": "~0.75 page (~350 words)",
        "depends_on": ["s2", "s3", "s4", "s5", "s6", "s7"],
        "brief": """
Write the Introduction — LAST, after all other sections are finalized.
You have the full paper text available as context. Use it to write an
introduction that accurately previews what the paper actually delivers.

Cover:
- Open with the core tension: clinical trial supply teams must deliver the
  right drug to the right patient at the right time — but three competing
  goals make this hard: minimize drug waste, control shipping costs, and
  avoid stock-outs. No single setting wins on all three simultaneously.
- Why this is getting harder: trials are increasingly global and complex —
  many now involve adaptive designs that change in response to accumulating
  data, multiple dosing arms, cold-chain biologics, and patient enrollment
  that is impossible to predict precisely. Sponsors also face mounting
  scrutiny over the environmental footprint of discarded drug product:
  every kit that expires unused represents both wasted investment and
  wasted manufacturing resources.
- The gap: most supply teams still rely on fixed overages and rules of
  thumb. This paper shows a better way.
- What this paper delivers: (1) a practical simulation framework that
  quantifies the waste/cost/stock-out trade-offs for a real trial design,
  and (2) the SKILL approach — a structured AI-assisted coding workflow
  that makes building and running the simulation accessible to clinical
  operations teams without a dedicated programming resource.
- End with a one-sentence roadmap: "Section 2 describes the supply chain
  structure and challenges; Section 3 presents the simulation framework;
  Section 4 reports sensitivity analysis findings; Section 5 describes the
  AI-assisted implementation approach; Sections 6 and 7 discuss implications
  and conclusions."
"""
    },
}

# Execution order — respects dependencies
EXECUTION_ORDER = ["s2", "s3", "s4", "s5", "s6", "s7", "s1"]

# Final assembly order
ASSEMBLY_ORDER = ["s1", "s2", "s3", "s4", "s5", "s6", "s7"]

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
