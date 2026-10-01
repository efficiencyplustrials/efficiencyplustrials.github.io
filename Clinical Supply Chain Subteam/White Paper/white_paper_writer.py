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
  patient visits and dispensing safety checks.
- IRT (Interactive Response Technology): electronic system managing
  randomization and drug supply. Assigns treatment arm, identifies kit to
  dispense, tracks inventory, triggers resupply. IRT rules must closely match
  simulation assumptions — a mismatch means simulation results will not
  reflect actual trial operations.

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
- This paper describes the cost trade-off qualitatively. Quantified cost
  modeling requires study-specific freight rates and packaging costs, and
  is beyond the scope of the current analysis; it is presented as a future
  extension in Section 6.

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
Write Section 3. Cover:

3.1 Modeling patient enrollment
- Sites do not all recruit at the same pace. The simulation assigns each
  site an enrollment rate drawn from three tiers: low (1/month), medium
  (2/month), high (4/month). These rates describe successful enrollment
  after the screening process — not the number screened.
- 35% of screened patients fail screening and are not enrolled.
- 15% of sites never enroll a single patient. They still receive initial
  stock, which can expire unused.
- 20% of enrolled patients drop out over the 52-week treatment period.
  Modeling dropout explicitly is important: omitting it overestimates
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
  enrollment, visit timing, and dropout. Results are summarized as means
  across replications.
- The stock-out rate is defined as the percentage of scheduled patient
  visits where no usable kit of the correct treatment arm was available
  at the dispensing site on the visit day.
- 100 replications were chosen to provide stable mean estimates; results
  showed low variance across replications for the main KPIs at baseline
  (stock-out rates ranged from approximately 0% to 2% across replications,
  waste rates from approximately 38% to 49%).
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

4.2 The four parameters that matter most

THRESH top — the site reorder target:
- Default: 105 kits. Lowering to 70 kits reduces waste from 43.5% to
  ~40% while keeping stock-out at ~1.4% — well within the 5% limit.
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
- Site-only waste (V1): counts expiry at sites only. Can mislead — tightening
  shelf-life rules reduces site expiry but raises depot expiry. Total unchanged.
- Full-chain waste (V2): counts expiry and damage at ALL locations / total
  produced. Always use V2 as the primary metric.
- Note: the industry planning range of 30–50% cited in Section 2 uses the
  shipped-based operational definition. The full-chain (V2) metric used in
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
- Domain knowledge is scattered across protocol, supply spec, IRT documents,
  emails, meeting notes — hard to translate into code without mistakes.

5.2 What the SKILL approach is
- A "skill" is a structured set of instructions given to Amazon Kiro (an AI
  coding assistant) that encodes domain expertise as a reusable workflow.
- The SKILL defines a step-by-step process the AI follows every time:
  read the spec, confirm assumptions, generate code, interpret results,
  record lessons. It prevents the AI from filling gaps with silent assumptions.
- The AI produces an initial code draft quickly, but that draft is not
  the same as a validated simulation. It still requires human testing,
  review, and approval before any results can be trusted.

5.3 The workflow in practice — six phases

The SKILL uses six phases, numbered 0, 0.5, 0.7, 1, 2, and 3. The
non-standard numbering reflects the iterative way this workflow was
developed: phases 0.5 and 0.7 are intermediate checkpoints added after
practical experience revealed that early confirmation prevents errors that
are expensive to find later. Think of them as mandatory quality gates that
were inserted between the reading and coding stages.

Phase 0 — Read before writing: AI reads full protocol and supply spec.
Identifies analysis type. Checks persistent context file from prior sessions.

Phase 0.5 — Confirm every assumption: AI presents a table of every major
modeling decision and waits for explicit analyst approval. Nothing assumed
silently.

Phase 0.7 — Verify dispensing edge cases: Dedicated checklist of 10+
scenarios (missed visits, mid-visit stock-out, patient discontinuation,
DND-window kits, partial fills, etc.). All must be confirmed before coding.

Phase 1 — Generate code: AI writes R code following mandatory rules
(FEFO dispensing, weekly review, depot-pull logic, enrollment validation,
full-chain waste reporting).

Phase 2 — Run and interpret: Analyst runs code in approved environment,
shares output. AI explains results in plain English, flags anomalies.

Phase 3 — Structured report: KPI summary, comparisons, prioritized
recommendations, open questions for human decision.

5.4 What the AI handles well — and where humans must stay involved

AI strengths: initial code draft from a 13-page spec; parameter sweeps
without fatigue; logical consistency checks; institutional memory via
persistent context file.

Human responsibilities: deciding clinically acceptable stock-out tolerance;
interpreting ambiguous protocol language; approving any change affecting
patient safety.

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
      supply records would strengthen confidence in the framework.
    * 100 replications provide stable mean estimates but do not capture
      all possible tail outcomes; teams should review the replication range,
      not only the mean.
- Broader applicability: the SKILL workflow applies to other complex
  clinical simulation tasks — recruitment forecasting, adaptive trial
  scenario testing, biomarker-driven randomization.
- Quantified logistics cost modeling is a natural next step. This paper
  describes cost trade-offs qualitatively; a future extension could
  incorporate study-specific freight and packaging costs to complete
  the three-KPI optimization framework.
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
