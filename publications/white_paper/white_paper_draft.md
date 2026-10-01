# Simulation-Based Optimization of Clinical Trial Drug Supply Chains: A Practical Framework with AI-Assisted Implementation

---

## 1. Introduction

Clinical trial supply teams must deliver the right drug to the right patient at the right time. They must also balance three competing goals:

- Avoid stock-outs that could interrupt patient treatment
- Minimize drug waste from expiry or damage
- Control shipping and handling costs

No single supply setting performs best on all three goals. Sending more drug to sites can reduce stock-outs, but it can also increase expiry. Sending smaller or more frequent shipments can reduce local inventory, but it may increase shipping costs. Smaller manufacturing batches may also provide less protection against demand peaks or delivery delays. A supply plan must therefore find an acceptable balance rather than optimize one measure alone.

This task is becoming harder. Trials increasingly operate across countries and regions. International shipments may face uncertain transport and customs times. Many trial drugs require **cold-chain storage** (temperature-controlled storage and transport), which makes each shipment more expensive and complex. Patient enrollment also remains difficult to predict. Some sites recruit quickly, while others recruit slowly or never enroll a patient.

Despite this uncertainty, many supply teams still rely on fixed **overages** (drug produced above expected patient use), spreadsheet forecasts, and rules of thumb. These methods are useful for initial planning. However, they cannot easily show how enrollment variation, patient dropout, delivery delays, and drug expiry interact over time. A decision that protects against one risk may create another.

This paper presents a practical alternative. First, it describes a simulation framework that creates many realistic versions of a trial. The model follows patients, visits, individual drug kits, shipments, and expiry dates through an international supply network. For a 250-patient trial design, it quantifies the trade-off between waste and stock-outs. It also supports comparisons of inventory, manufacturing, and shipment policies that affect logistics cost. The analysis tests key planning settings to identify changes that improve performance without creating unacceptable patient risk.

Second, the paper presents the SKILL approach. This is a structured workflow for using an AI coding assistant to build, check, and report the simulation. The workflow helps clinical operations teams convert study rules into a working model without relying on a dedicated programming resource. It does not remove the need for oversight. An analyst must still confirm assumptions, run and test the model, review the results, and approve any operational decision.

Section 2 describes the supply chain structure and challenges; Section 3 presents the simulation framework; Section 4 reports sensitivity analysis findings; Section 5 describes the AI-assisted implementation approach; Sections 6 and 7 discuss implications and conclusions.

---

## 2. Clinical Trial Supply Chain: Structure and Challenges

In the model used in this paper, clinical trial drug follows a fixed, one-way path:

**Manufacturer → EU central depot → regional depot → clinical site → patient**

The manufacturer produces and packages the drug. The EU central depot holds the main study inventory. It ships supplies to regional depots, such as a depot in China. These depots serve clinical sites in their region. Sites then dispense the drug to patients during scheduled visits.

Drug generally cannot move backward through this chain. A site cannot simply return excess stock for use elsewhere. Transfers between sites may also be restricted or impractical. Each supply decision therefore affects all later stages.

Regional depots help manage long and uncertain import times. Customs clearance may take weeks or even months. A regional depot places inventory closer to patients and allows faster site resupply. However, it also creates another location where stock can wait, expire, or become damaged.

### A Three-Tier Inventory System

The supply network has three main inventory tiers:

| Tier | Main role | Typical planning concern |
|---|---|---|
| EU central depot | Holds the main supply and replenishes regions | How much drug to produce and when to ship |
| Regional depot | Holds stock close to sites | Customs delays and regional demand |
| Clinical site | Dispenses drug to patients | Avoiding missed visits and local expiry |

Clinical sites commonly use an automatic resupply rule. Each site has a set minimum stock level. When usable stock falls below that level, the site automatically requests more drug from its assigned depot. This works like replacing groceries when the cupboard becomes nearly empty.

The minimum level must balance two risks. If it is too low, the site may run out before the next shipment arrives. If it is too high, drug may sit unused and expire.

Sites must also manage stock by expiry date. They follow **First Expired, First Out (FEFO)**. This means they dispense the drug with the earliest expiry date first. The approach is similar to placing milk with the nearest expiry date at the front of a refrigerator.

A further rule is **Do Not Dispense (DND)**. In the setting used in this paper, a drug unit cannot be given to a patient if it will expire within 13 days. The unit may still appear in the site’s physical inventory, but it is no longer usable for dispensing. This distinction matters. A site can look well stocked and still be unable to treat a patient.

### Why Supply Is Difficult to Plan

Several sources of uncertainty act at the same time:

- **Enrollment varies.** Some sites recruit patients much faster than expected. Others recruit slowly or not at all.
- **Treatment assignment is unknown.** At randomization—the point when a patient is assigned to a treatment group—the required treatment cannot always be predicted in advance.
- **Lead times vary.** Manufacturing, transport, customs clearance, and site delivery can all take longer than planned.
- **Drug has a limited shelf life.** Inventory loses value over time and may expire before patients need it.

Together, these factors create a **shelf-life-constrained regime**. In plain terms, expiry limits every inventory decision. In a commercial supply chain, ordering extra stock early often provides useful protection. In a clinical trial, it can make performance worse. Drug may reach a slow-recruiting site months before patients arrive. By the time it is needed, it may have expired or entered the DND window.

The goal is therefore not to eliminate all waste or hold as much inventory as possible. The goal is to place enough usable drug in the right location at the right time.

### Key Performance Measures

This paper uses three measures to compare supply strategies:

| Measure | Plain-language definition | Practical benchmark |
|---|---|---|
| **Stock-out rate** | The percentage of patient visits where no usable drug was available for the patient’s assigned treatment | Target below 5% |
| **Full-chain waste rate** | Drug that expired or was damaged at the central depot, regional depots, or clinical sites, shown as a percentage of total drug produced | Common industry planning range of 30–50% |
| **Logistics cost** | The cost of moving and handling supplies | Driven mainly by shipment frequency, shipment size, and cold-chain requirements |

A 30–50% waste rate may appear high compared with commercial products. In trials, however, spare inventory protects patients against uncertain enrollment, treatment assignment, and delivery delays. Actual waste varies by study, but this range is often expected and does not necessarily indicate poor performance.

The simulation approach described later builds on the clinical trial enrollment and supply modeling work of Anisimov (2010) and Lefew, Ninh, and Anisimov (2021). Their work provides the statistical foundation for representing uncertain enrollment and testing supply decisions before they are used in a live study.

---

## 3. Stochastic Simulation Framework

A **stochastic simulation** is a model that includes random variation. It does not assume that enrollment, patient visits, or supply events will happen exactly as planned. Instead, it creates many realistic versions of the trial and tests the supply strategy in each one.

This approach works like a flight simulator. A pilot does not practice only in perfect weather. The simulator also creates delays, wind, and equipment problems. In the same way, the trial supply simulation tests the plan under both routine and difficult conditions.

### 3.1 Modeling Patient Enrollment

Clinical sites rarely recruit patients at the same pace. A large hospital may enroll several patients each month. A smaller site may enroll slowly. Some activated sites may never enroll anyone.

The simulation represents these differences by giving each site its own enrollment rate. Each site is drawn from a realistic mix of three tiers:

| Site tier | Average successful enrollment rate | Typical behavior |
|---|---:|---|
| Low | 1 patient per month | Enrolls occasionally |
| Medium | 2 patients per month | Enrolls steadily |
| High | 4 patients per month | Enrolls rapidly |

These rates are averages, not fixed monthly quotas. A medium-tier site does not enroll exactly two patients every month. It may enroll three patients one month and none the next.

The model also assumes that 15% of sites never enroll a patient. This reflects a common operational problem. A site may open late, face staffing constraints, lose investigator interest, or find that few patients meet the study criteria. These non-enrolling sites can still hold inventory. They may therefore create waste even though they generate no patient demand.

Not every screened patient enters the trial. **Screening** is the process used to confirm that a potential patient meets the study requirements. The model assumes that 35% of screened patients fail screening and are not enrolled. The site-tier rates describe successful enrollment after this screening loss. Only patients who pass screening create treatment demand.

The simulation also models patient dropout. Across the 52-week treatment period, about 20% of enrolled patients are expected to stop treatment early. Reasons may include side effects, lack of benefit, withdrawal of consent, or loss to follow-up.

Dropout has a meaningful effect on supply planning. A patient who leaves early does not need all the drug planned for a full year of treatment. If the model assumes that every patient completes treatment, it overestimates total drug demand by about 10–15%. That error can lead to excess manufacturing and expiry.

Each simulated patient therefore has an individual treatment path. The model tracks enrollment, planned visits, treatment assignment, and possible dropout. This creates a more realistic demand pattern than simply multiplying the target patient count by the number of planned doses.

### 3.2 How the Simulation Runs Day by Day

The simulation covers approximately 850 days. This period includes enrollment, treatment, remaining supply activity, and the final use or expiry of inventory.

The model advances one day at a time. On each day, it completes the following steps in sequence:

1. **New patients may enroll.** The number depends on each site's enrollment tier and random daily variation.
2. **Existing patients may attend visits.** Each visit creates demand for the patient's assigned treatment.
3. **Sites identify usable drug.** Kits that have expired or will expire within 13 days cannot be dispensed under the Do Not Dispense rule.
4. **Sites dispense drug.** From the eligible kits, the site uses the kit with the earliest expiry date first.
5. **Sites review inventory when scheduled.** If usable stock is below the required level, the site places an order.
6. **Depots process pending orders.** Available stock is packed and shipped to the requesting location.
7. **Manufacturing batches may arrive.** Completed batches enter inventory at the EU central depot.
8. **Expired drug is removed.** The model records the quantity and location of every expired kit.

The sequence matters. For example, a site may have ten physical kits on the shelf. If all ten are within the 13-day Do Not Dispense window, the site has no usable stock for that day's patient visit. A shipment arriving the next day cannot prevent that stock-out.

The model tracks every kit separately. Each kit has:

- A kit type: 5 mL, 2.5 mL, or 7.5 mL
- A treatment arm: A or B
- An expiry date
- A current location
- A shipment and dispensing history

This kit-level tracking allows the model to apply expiry rules correctly. It also prevents the model from treating one kit type or treatment arm as a substitute when the required item is unavailable.

Sites review their stock once a week. When a site orders, it requests enough drug to reach its target inventory level. The calculation counts both usable kits already at the site and kits that are on the way.

This weekly review avoids unnecessary orders. With daily order triggers, a site may place another order before the previous shipment arrives. This can create overlapping shipments and too much stock at the site. A weekly review acts like a regular household shopping day. It creates a controlled rhythm and gives open orders time to arrive.

### 3.3 Manufacturing and Replenishment Policy

Manufacturing follows a fixed schedule. The plan includes eight batches, with one batch every 60 days starting on Day 0.

The batch-size calculation uses approximately 210 days of expected demand. It includes:

- A 150-day planned coverage window
- An additional 60 days of safety stock

This does not mean that each batch must last exactly 210 days. It means that expected demand over this period is used to set the batch quantity. The safety stock protects against faster enrollment, manufacturing delays, and other unexpected demand. However, producing too much drug too early can increase expiry risk.

When a batch reaches the EU central depot, the system calculates how much stock the China regional depot needs. It then starts a transfer, subject to available inventory and shipment lead time.

The EU depot does not send all available stock to China. It first keeps enough to cover its own expected demand for the next 90 days. This protection setting is called **EU_PROTECT**. Section 4 examines how changes to this setting affect stock-outs and waste.

The model also checks China's inventory every day. If the regional depot falls below seven days of expected supply, the system starts a top-up shipment when EU stock is available. The stock still takes time to reach China. This rule provides a safety net between the larger transfers linked to manufacturing batches.

### 3.4 What the Simulation Produces

One simulation run represents only one possible version of the trial. It might include rapid enrollment at several sites, early dropout, or clusters of patient visits. A different run may produce a very different pattern.

For this reason, the model runs 100 independent replications. Each replication uses new random draws for site enrollment rates, visit timing, and patient dropout. This produces a range of possible outcomes rather than one apparently precise forecast. It therefore gives study teams a clearer view of real-world uncertainty.

The main outputs include:

- Stock-out rate at patient visits
- Full-chain waste rate
- Total kits dispensed
- Kits expired at the EU central depot
- Kits expired at the regional depot
- Kits expired at clinical sites
- Kits damaged during shipment

The model applies an assumed 1% damage rate to kits in each shipment. Damaged kits are removed from usable inventory and included in full-chain waste.

For the baseline trial of 250 patients, 23 sites, and two treatment arms, the results across the 100 replications were summarized as follows:

| Measure | Baseline result | Interpretation |
|---|---:|---|
| Stock-out rate | 0.68% | Well below the 5% target |
| Full-chain waste rate | 43.5% | Within the expected 30–50% planning range |

These results show that the baseline policy protects most patient visits while keeping waste within the expected range. They do not prove that the policy is optimal. The next step is to test which planning settings drive these outcomes and whether a better balance is possible.

---

## 4. Sensitivity Analysis and Parameter Optimization

### 4.1 What Sensitivity Analysis Means Here

**Sensitivity analysis** shows how strongly simulation results change when a planning setting changes. The analysis changes one setting at a time and keeps the others fixed. It uses 100 repeated simulation runs for each tested setting. Across all settings, this produces hundreds of trial scenarios with different patterns of enrollment, visits, dropout, and delivery timing.

This process is similar to adjusting one control on a refrigerator. If a small adjustment causes a large temperature change, that control matters. If little happens, the setting is less useful for improving performance.

The analysis used the following trial design:

- 250 patients
- 23 clinical sites
- 13 sites in the EU and 10 in China
- Two treatment arms in a double-blind trial, meaning that patients and most study staff do not know which treatment each patient receives
- An operating period of approximately 27 months

Under the baseline settings, the overall stock-out rate was 0.68% and full-chain waste was 43.5%. The analysis tested whether selected changes could reduce waste without pushing stock-outs above the 5% limit.

Four parameters had the greatest practical importance.

### 4.2 The Four Parameters That Matter Most

#### Site Reorder Target: THRESH Top

**THRESH top** is the inventory level that a site aims to reach when it places a resupply order. For example, if the target is 105 kits, the resupply calculation attempts to bring the site's usable and incoming inventory back toward 105 kits.

The baseline target was 105 kits. Reducing the EU site target to 70 kits lowered full-chain waste from 43.5% to about 40%. The overall stock-out rate increased from 0.68% to about 1.4%. This increase was less than one percentage point, and the result remained well below the 5% limit.

This was the single most powerful lever for reducing waste without creating an unacceptable stock-out risk. A lower target sends fewer kits to EU sites before they are needed. Less drug remains at slow-enrolling or non-enrolling sites. More stock stays at the depot, where it can support several sites.

The result also shows an important trade-off. The lowest possible stock-out rate is not always the best operational outcome. Holding more inventory can remove a small amount of stock-out risk while causing much more expiry.

**Recommendation:** Reduce the EU site target from 105 kits to 70 kits. Test this change together with the other recommended settings before implementation.

#### Minimum Shelf Life at Site Receipt: MIN_SHELF

**MIN_SHELF** is the minimum shelf life that a kit must have remaining when it arrives at a site. The default is 30 days.

At first, a stricter rule appears attractive. If sites accept only fresher drug, fewer kits should expire at sites. The simulation showed why this reasoning is incomplete.

When the rule becomes stricter, near-expiry kits remain at the China depot instead of moving to sites. Site expiry may fall, but depot expiry rises. Total waste across the supply chain barely changes.

The stricter rule therefore moves waste rather than reducing it. It is like refusing older food during a shop delivery. The shop may discard less food, but the same food may then be discarded at the warehouse.

MIN_SHELF still has an important role. It prevents sites from receiving drug that has too little usable life to support patient visits. It is a quality control setting, not a main waste-reduction tool.

**Recommendation:** Keep the 30-day default.

#### EU Inventory Protection: EU_PROTECT

**EU_PROTECT** controls how many days of expected EU demand the central depot reserves before transferring stock to China.

At the 90-day default, the stock-out rate at China patient visits was only 0.08%. When the reserve was reduced to 30 days, China's stock-out rate rose to 3.0%. This was about a 39-fold increase, while full-chain waste barely changed.

The result shows that stock held at the EU depot is not automatically excess stock. Some of it protects the regional supply chain. Transfers to China face long and uncertain transport and customs lead times. Once China runs short, the study team cannot correct the problem immediately.

A very low reserve can also create competition between regions. EU demand may consume inventory that would otherwise support China. By the time the shortage becomes visible, the shipment delay limits the available response.

**Recommendation:** Never reduce EU_PROTECT below 60 days. Keep 90 days as the safe operating point.

#### Manufacturing Batch Frequency

The analysis also changed the manufacturing schedule while keeping the total amount produced fixed. This separated the effect of delivery timing from the effect of total supply volume.

| Manufacturing option | Stock-out result | Waste result | Main issue |
|---|---:|---:|---|
| 4 large batches | 0.08% | 56% | Drug arrives early and waits too long |
| 8 batches, 60 days apart | 0.68% | 43.5% | Best balance among the tested options |
| 15 small batches | 3.8% | No meaningful overall benefit | Small deliveries provide too little protection between arrivals |

Four large batches provided strong protection against stock-outs. However, much of the drug arrived before it was needed. It then remained at depots for longer and expired. Full-chain waste rose to 56%.

Fifteen smaller batches placed less inventory into the network with each delivery. These smaller quantities provided less protection against demand peaks or a delayed delivery. Stock-outs increased to 3.8%.

The eight-batch schedule provided the best balance among the schedules tested. This does not prove that no other schedule could perform better. It shows that eight batches, 60 days apart, performed better than the tested alternatives.

**Recommendation:** Keep the eight-batch schedule with 60 days between batches.

### 4.3 Why the Right Waste Metric Matters

The analysis compared two waste measures:

- **Site-only waste, or V1:** Counts expiry at clinical sites only.
- **Full-chain waste, or V2:** Counts expiry at clinical sites, regional depots, and the EU central depot. It also includes other recorded losses, such as shipment damage.

V1 can give the wrong impression. For example, a stricter shelf-life acceptance rule reduces the amount of near-expiry drug sent to sites. Site-only waste then appears to improve. However, the rejected stock remains at the depot and expires there. Full-chain waste shows that the total loss has barely changed.

This distinction matters because the study still pays for drug that expires at a depot. Moving expired drug from one reporting category to another does not improve supply performance.

**Full-chain waste should therefore be the primary waste measure.** Site-only waste remains useful for identifying local problems, but it should not drive network-wide decisions by itself.

### 4.4 Recommended Operating Configuration

| Parameter | Default | Recommended | Expected outcome |
|---|---:|---:|---|
| THRESH top at EU sites | 105 kits | 70 kits | Full-chain waste falls from 43.5% to about 40%; overall stock-outs rise from 0.68% to about 1.4% |
| MIN_SHELF | 30 days | 30 days | No change needed |
| EU_PROTECT | 90 days | 90 days | Maintains strong protection for China |
| Manufacturing batch schedule | 8 batches, 60 days apart | 8 batches, 60 days apart | Maintains the best balance among the tested schedules |

The main practical change is the lower EU site target. The other default settings already provide a sound balance between patient protection and waste.

Changing one parameter at a time shows which individual settings have the strongest effects. It does not capture every possible interaction between settings. Before implementation, the study team should run the full recommended configuration in a combined simulation. This final test should confirm that the stock-out and waste results remain acceptable when all settings operate together.

### 4.5 Connection to the Academic Literature

These findings are consistent with Anisimov's 2010 work on clinical trial supply planning. That work showed that **overage**—drug produced above expected patient use—rises steeply when planners try to push stock-out risk close to zero. The simulation shows the same pattern. Very high inventory removes a small amount of stock-out risk but causes much more expiry.

The findings also support **center-stratified randomization**, where treatment assignments are balanced within each clinical site. Under comparable assumptions, this approach requires less overage than balancing treatment assignments only across the trial as a whole. It reduces the chance that one site will need far more stock for one treatment arm than planned.

Finally, both the published planning methods and the simulation show that more depots and more treatment arms increase the required overage when service targets and other assumptions remain the same. Each additional location or treatment arm divides inventory into smaller pools. A kit held for one treatment arm at one location cannot always meet demand for another arm or location. Careful inventory placement therefore becomes more important as the supply network becomes more complex.

---

## 5. AI-Assisted Implementation: The SKILL Approach

### 5.1 The Challenge of Building a Simulation from Scratch

A realistic investigational medicinal product supply simulation is not a simple spreadsheet. It must represent patients, visits, treatment assignments, kit types, expiry dates, shipments, depots, and site orders. It must also apply these rules in the correct order each day.

A faithful model often requires 500 to 1,000 lines of computer code. Writing that code manually can take several weeks. Testing unusual situations can take even longer.

The code itself is only part of the challenge. The required operational knowledge is often scattered across many sources:

- The clinical trial protocol
- The supply specification
- Randomization and blinding documents
- Shipping plans
- Depot instructions
- Email decisions
- Meeting notes
- Informal team practices

For example, the protocol may define the visit schedule. A supply document may describe the 13-day Do Not Dispense window. An email may confirm that sites review inventory weekly. Another document may explain how much EU inventory must be protected before stock moves to China.

A programmer must find these details, understand them, and translate them into consistent rules. Small misunderstandings can change the results. A model may run without an error message even when it does not reflect the real supply chain.

This creates a serious risk. A simulation can look professional and produce detailed tables while still being wrong. The main challenge is therefore not writing code quickly. It is converting operational knowledge into code without losing important rules.

### 5.2 What the SKILL Approach Is

The SKILL approach uses a structured set of instructions for an AI coding assistant called Amazon Kiro. These instructions capture supply chain knowledge as a reusable workflow.

A SKILL does more than tell the AI what output to create. It tells the AI how to complete the work. The instructions define the questions to ask, the checks to perform, the coding rules to follow, and the results to report.

A weak request might say:

> “Write a clinical trial supply simulation.”

That request leaves too much room for silent assumptions. The AI may choose an enrollment method, shipment rule, or waste definition without confirming whether it matches the study.

The SKILL instead directs the AI to follow a controlled sequence:

1. Read the full study and supply documents.
2. Identify missing or unclear information.
3. Present all major assumptions to the analyst.
4. Confirm unusual but important dispensing scenarios.
5. Generate the simulation only after approval.
6. Review the output for errors and unusual patterns.
7. Produce a standard report.
8. Record confirmed decisions and lessons for future sessions.

The result is more consistent and easier to review. The AI behaves less like a tool that produces code on demand. It behaves more like a junior analyst who has read the operations manual and follows a checklist.

This approach does not make the AI an independent decision-maker. The analyst remains responsible for confirming assumptions, reviewing results, and approving recommendations.

### 5.3 The Workflow in Practice

The SKILL workflow has six phases. The numbering includes two review stages before coding. These stages were added after practical experience showed that early confirmation prevents major errors.

| Phase | Main activity | Why it matters |
|---|---|---|
| 0 | Read before writing | Prevents coding from an incomplete understanding |
| 0.5 | Confirm every assumption | Stops the AI from making hidden choices |
| 0.7 | Verify unusual dispensing scenarios | Clarifies uncommon but important patient situations |
| 1 | Generate code | Applies confirmed rules consistently |
| 2 | Run and interpret | Checks whether outputs are credible and useful |
| 3 | Produce a structured report | Turns technical output into operational guidance |

#### Phase 0 — Read Before Writing

The AI first reads the full protocol and supply specification. It does not write any code during this phase.

It identifies the type of analysis required. For example, the study team may need a baseline simulation, a sensitivity analysis, or a comparison of several supply policies.

The AI also checks for a persistent context file from earlier sessions. In this implementation, the file is called supply_chain_context.md. It acts like a shared project notebook. It records confirmed decisions, known limitations, benchmark results, and lessons learned.

This step reduces repeated discussion. It also helps prevent a rule agreed in one session from being forgotten in the next. However, the team must review the saved information after any protocol amendment or supply-plan change.

#### Phase 0.5 — Confirm Every Assumption

Before coding, the AI presents a table of the major modeling decisions it plans to use. The analyst must approve or correct each item.

A confirmation table may include decisions such as:

| Topic | Proposed treatment in the model |
|---|---|
| Enrollment | Use different recruitment rates for low-, medium-, and high-enrolling sites |
| Screening | Apply screening failure before a patient enters the trial |
| Dropout | Model a steady chance of discontinuation over the treatment period |
| Dispensing | Use First Expired, First Out |
| Do Not Dispense rule | Block kits that will expire within 13 days |
| Site ordering | Review inventory once each week |
| Regional supply | Protect 90 days of EU demand before transferring stock to China |
| Waste | Count expiry and damage across the full supply chain |

The AI waits for explicit approval. It does not treat missing information as permission to choose a convenient default.

This stage creates a clear review record. It also gives supply and clinical operations teams a practical way to inspect the model before technical work begins.

#### Phase 0.7 — Verify Unusual Dispensing Scenarios

Some of the most damaging errors occur in unusual patient situations, sometimes called edge cases. The SKILL therefore includes a dedicated dispensing checklist with more than ten scenarios.

The checklist asks questions such as:

- What happens when a patient misses a visit?
- Is the missed dose skipped, delayed, or dispensed later?
- What happens if a patient arrives early?
- What happens if a patient arrives after a kit enters the Do Not Dispense window?
- What happens when stock runs out during a visit that requires several kits?
- Can the site dispense only part of the required quantity?
- What happens when the correct treatment arm is unavailable but another arm is in stock?
- What happens after permanent treatment discontinuation?
- Are future visits removed when a patient drops out?
- Can damaged or quarantined stock count toward the reorder target?
- Does incoming stock count when the site calculates its order?
- How are replacement visits or unscheduled visits handled?

Each scenario must be confirmed before coding starts. This prevents a general rule from being applied incorrectly to an exceptional case.

#### Phase 1 — Generate Code

Only after the analyst confirms the decisions does the AI generate the simulation code. In this project, it produces R code. R is a programming language commonly used for data analysis and simulation.

The SKILL includes mandatory coding rules. These include:

- Dispense kits using First Expired, First Out.
- Apply the Do Not Dispense window before checking availability.
- Review site inventory weekly.
- Ship only kits that already exist in depot inventory.
- Reduce depot inventory when a shipment leaves.
- Keep treatment arms and kit types separate.
- Track expiry at every location.
- Validate total enrollment before calculating performance measures.
- Use full-chain waste as the primary waste measure.
- Use repeated simulation runs to show uncertainty.

These rules turn past lessons into standard safeguards. The team does not need to remember and explain them again for every new analysis.

#### Phase 2 — Run and Interpret

The analyst runs the code in the approved company environment and shares the appropriate output with the AI. This separation allows the organization to maintain control over its data and computer systems.

The AI then explains the results in plain English. It compares the main measures with agreed benchmarks and looks for warning signs.

For example, it may flag:

- Enrollment far above or below the trial target
- Depot inventory that never decreases
- More kits dispensed than were produced
- A sudden increase in stock-outs after a small setting change
- Waste reported only at sites
- Large differences between simulation runs
- Results that conflict with a known baseline

The AI can suggest possible causes, but the analyst decides whether the explanation is credible.

#### Phase 3 — Produce a Structured Report

The final phase converts simulation output into a standard operational report. The report includes:

- A summary of confirmed assumptions
- A table of key performance measures
- Comparisons with agreed limits
- Important warnings or model limitations
- Recommended actions in priority order
- Questions that still require human decisions

This structure allows study managers and supply leads to review the findings without reading code or detailed technical output.

### 5.4 What AI Handles Well—and Where Humans Must Stay Involved

AI assistance provides the greatest value in work that is detailed, repetitive, and rule-based.

| AI handles well | Human judgment remains essential |
|---|---|
| Producing initial working R code from a 13-page supply specification in minutes | Deciding what stock-out risk is clinically acceptable |
| Testing dozens of setting combinations without fatigue or transcription errors | Interpreting ambiguous protocol language |
| Applying the same reporting format across analyses | Confirming whether assumptions reflect actual study operations |
| Checking outputs for logical inconsistencies | Assessing patient safety and regulatory impact |
| Recording decisions and lessons in the persistent context file | Reviewing and approving any change before implementation |

The persistent context file is especially useful for continuity. It can record that the team approved a 13-day Do Not Dispense window, selected full-chain waste as the primary measure, and rejected a previous interpretation of missed visits. This creates a practical form of institutional memory.

However, initial working code is not the same as a validated simulation. The code still requires testing, review, and refinement. Saved context is also not the same as expert judgment. A previous decision may no longer apply after a protocol amendment or supply-plan change. The team must review the file rather than accept it automatically.

No AI can decide the clinically acceptable stock-out rate by itself. The answer depends on the disease, available treatment alternatives, patient vulnerability, and regulatory expectations. The same stock-out rate may be manageable in one trial and unacceptable in another.

Human review is mandatory whenever a recommendation could affect patient treatment or safety.

### 5.5 Hard Lessons from Building the Simulation

The development process revealed three lessons that are useful for any team adopting AI-assisted simulation.

#### Validate Enrollment Before Trusting Any Result

An early model enrolled three to four times more patients than planned. The outputs still looked plausible. Inventory moved, visits occurred, and stock-outs were calculated. However, every result was meaningless because the simulated trial did not match the trial design.

The SKILL now requires an enrollment check before any performance result is interpreted. The model must compare simulated enrollment with the study target and explain any important difference.

#### Confirm That Every Shipment Pulls from Real Stock

An early version created new drug records when it shipped kits to sites. It did not remove those kits from depot inventory. This created “phantom drug.” Sites received supply, but depot stock never fell.

The SKILL now requires every shipped kit to exist at the sending location. The model must remove the kit from that location when shipment begins. It must also complete an inventory balance check. Total production must equal the kits dispensed, expired, damaged, in transit, or still in stock.

#### Use Full-Chain Waste

Early reports showed an encouragingly low waste rate. The measure counted only expiry at sites. It excluded expiry at the EU and regional depots.

The SKILL now uses full-chain waste as the primary reported waste measure. This prevents the model from presenting a transfer of waste between locations as an improvement. Location-level waste remains useful for showing where losses occur, but it should not replace the full-chain measure.

These errors were found through repeated human and AI review. They show why AI-generated code cannot be trusted only because it runs successfully. Teams must test it against known benchmarks, check basic inventory totals, and challenge results that appear unusually good. The SKILL makes those checks repeatable, but human review remains the final safeguard.

---

## 6. Discussion

Supply chain optimization is a strategic capability, not a back-office logistics task. A well-designed supply plan protects patients, controls costs, and helps the trial finish on time. A poor plan can cause missed patient visits, trial delays, and avoidable drug expiry. Waste also increases the drug supply cost for each patient enrolled.

Supply performance can also affect the remaining patent exclusivity period. This is the limited time in which the sponsor can sell the medicine without generic competition. If supply problems delay trial completion or regulatory submission, they may reduce this valuable commercial window.

The simulation shows the size of these trade-offs. The baseline policy produced a 0.68% stock-out rate but wasted 43.5% of supply across the full chain. Reducing the EU site inventory target from 105 to 70 kits lowered waste to about 40%. Stock-outs rose to about 1.4% but remained well below the 5% limit.

By contrast, reducing the EU reserve for China from 90 to 30 days increased China's stock-out rate from 0.08% to 3.0%, with little waste benefit. The manufacturing analysis showed another trade-off. Four large batches reduced stock-outs but increased waste to 56%. Fifteen smaller batches increased stock-outs to 3.8% without a meaningful overall waste benefit. The eight-batch schedule provided the best balance among the tested options.

These findings show why teams must consider patient protection, waste, and cost together. The lowest possible stock-out rate is not always the best result if it requires large amounts of drug that will expire. Likewise, a lower inventory target is not an improvement if it creates unacceptable treatment interruptions.

### 6.1 Using Analytic Methods and Simulation Together

Simulation and analytic methods are complementary. They answer different questions at different stages of a study.

- **Anisimov's formula-based planning methods support early study design.** They allow teams to compare broad options quickly. Examples include different numbers of sites, depots, treatment arms, and target service levels.
- **Simulation adds operational detail.** It can represent different enrollment rates across sites, non-enrolling sites, patient dropout, shipment lead times, weekly inventory reviews, and rules that respond to current stock levels.
- **Simulation can track individual kits.** This allows it to apply shelf-life rules and dispense the kit with the earliest expiry date first.
- **Simulation can support trial execution.** Teams can update the model with current enrollment, inventory, and delivery information. They can then test a revised ordering target or transfer rule before changing the live supply plan.

A practical approach is to use formula-based methods for fast comparisons during study design. Teams can then use simulation to test how the preferred plan performs under realistic operating conditions. During trial execution, they can rerun the simulation when enrollment, inventory, or delivery performance differs from plan.

### 6.2 Limitations

This approach has important limitations:

- **The model reflects one trial design.** It was calibrated for a 250-patient study with 23 sites, two treatment arms, and the operating assumptions described earlier. Every new study needs its own inputs for enrollment, dropout, treatment, shelf life, manufacturing, and delivery.
- **The SKILL approach requires suitable tools and people.** The team needs access to an AI coding assistant. It also needs an analyst who will review the model, challenge its logic, identify errors, and improve it through repeated testing. AI does not remove the need for human oversight.
- **Results depend on the input assumptions.** If enrollment estimates are too low, the model may recommend too little supply. If shelf life or delivery timing is unrealistic, the model may misstate waste or stock-out risk. Teams should therefore compare assumptions with actual study data and update them when conditions change.
- **The tested options do not cover every possible supply policy.** For example, the eight-batch schedule performed best among the schedules tested. This does not prove that it is the best schedule under every trial design or operating condition.

These limitations do not make the results unusable. They show why simulation should support operational judgment rather than replace it.

### 6.3 Broader Use in Clinical Operations

The SKILL workflow is not limited to drug supply chains. Teams can use the same structured human-AI collaboration for other complex clinical operations problems, including:

- Forecasting patient recruitment across countries and sites
- Testing adaptive trial designs that change in response to accumulating trial results
- Planning randomization based on biomarkers, which are measurable biological features used to classify patients
- Comparing site activation plans and enrollment recovery options
- Testing the effect of visit delays, dropout, or protocol changes

In each case, people define the operational problem, provide realistic assumptions, and challenge the results. AI helps build, test, and refine the simulation. This division of work combines operational experience with faster model development while keeping accountability with the study team.

---

## 7. Conclusion

Clinical trial supply teams must balance three competing goals: prevent stock-outs, control cost, and avoid waste. Improving one goal can weaken another. Simulation makes these trade-offs visible before teams change a live supply plan. In this study, lowering the EU site reorder target from 105 to 70 kits reduced full-chain waste from 43.5% to about 40%. The overall stock-out rate increased from 0.68% to about 1.4%, but remained well below the 5% limit. The analysis also showed that **EU_PROTECT** is the most critical setting for maintaining supply continuity in China. This setting reserves a defined number of days of expected EU demand before stock transfers to China. Reducing it from 90 to 30 days increased China’s stock-out rate from 0.08% to 3.0%, with almost no waste benefit.

The SKILL approach reduced the time from reviewing the protocol and supply documents to producing a working simulation from weeks to days. Human review checkpoints helped ensure that the model reflected the trial design before coding began. They also helped uncover serious early errors. These included enrolling three to four times too many patients, creating “phantom drug” that reached sites without leaving depot inventory, and using a waste measure that excluded depot losses. The SKILL workflow now includes guardrails to detect these problems. Each future simulation can therefore start with stronger controls and reach a useful result faster. The resulting model still requires human testing, review, and approval.

Supply teams should treat simulation-based planning as a standard operational tool, not a research exercise. Rigorous modeling allows teams to test decisions before patients and sites feel their effects. Structured AI assistance makes that modeling faster and more repeatable, while people retain control over assumptions, validation, and final decisions. This combination is ready for operational use today.
---

## References

1. Anisimov VV. Drug supply modelling in clinical trials (statistical methodology). *Pharmaceutical Outsourcing*. May/Jun 2010:17–20.

2. Lefew M, Ninh A, Anisimov V. End-to-end drug supply management in multicenter trials. *Methodology and Computing in Applied Probability*. 2021;23:695–709. https://doi.org/10.1007/s11009-020-09776-z

3. Anisimov VV, Fedorov VV. Modelling, prediction and adaptive adjustment of recruitment in multicentre trials. *Statistics in Medicine*. 2007;26(27):4958–4975.

4. Anisimov VV, Fedorov VV, Heiberger R, Saha S, Kothapalli M. Drug Supply Modeling Software: User Manual. GSK DDS Technical Report 2010-01. GlaxoSmithKline Pharmaceuticals; 2010.

5. Peterson M, Byrom B, Dowlman N, McEntegart D. Optimizing clinical trial supply requirements: simulation of computer-controlled supply chain management. *Clinical Trials*. 2004;1(4):399–412.
