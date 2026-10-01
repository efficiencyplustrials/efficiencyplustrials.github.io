# Simulation-Based Optimization of Clinical Trial Drug Supply Chains: A Practical Framework with AI-Assisted Implementation

---

## 1. Introduction

Clinical trial supply teams must deliver the right drug to the right patient at the right time. They must also balance three competing goals:

- Minimize unused and expired drug
- Control shipping and handling costs
- Avoid stock-outs that could disrupt patient treatment

No single supply setting performs best on all three goals. Sending large quantities early can reduce shortage risk, but it may increase expiry. Sending smaller quantities more often can reduce waste, but it raises freight and packaging costs. Holding less stock at sites may improve efficiency, but it leaves less protection when enrollment rises unexpectedly or a shipment is delayed.

This balancing act is becoming harder. Trials increasingly operate across many countries, depots, and clinical sites. Some use multiple dosing or treatment arms. Others use adaptive designs, which allow planned changes in response to accumulating study information. Many biologic drugs also require cold chain, meaning temperature-controlled storage and transport. These conditions increase both supply complexity and delivery cost.

Patient enrollment adds further uncertainty. Some sites recruit quickly. Others recruit slowly or enroll no patients. The exact treatment assignment may not be known until a patient enters the trial. Patients may also miss visits or leave treatment early. As a result, teams cannot predict demand precisely.

Sponsors also face growing scrutiny over the environmental impact of discarded drug. Every unused kit that expires represents lost investment. It also represents wasted manufacturing materials, packaging, storage capacity, transport energy, and disposal effort.

Despite these challenges, many supply plans still rely on fixed overages and rules of thumb. Teams may produce a set percentage above expected demand or hold the same quantity at every site. These approaches are simple, but they can hide important differences among sites, treatment arms, and regions.

This paper presents a more practical, evidence-based approach. First, it describes a simulation framework that creates many realistic versions of a trial. The framework quantifies the trade-off between waste and stock-out risk for a detailed trial design. It also shows how shipment frequency and shipment size affect logistics cost. Second, the paper presents the SKILL approach. This structured, AI-assisted workflow helps clinical operations teams translate study rules into a working simulation without requiring a dedicated programmer to write every line manually. An analyst must still confirm assumptions, test the model, interpret the results, and approve recommendations.

Section 2 describes the supply chain structure and challenges; Section 3 presents the simulation framework; Section 4 reports sensitivity analysis findings; Section 5 describes the AI-assisted implementation approach; Sections 6 and 7 discuss implications and conclusions.

---

## 2. Clinical Trial Supply Chain: Structure and Challenges

A clinical trial supply chain moves drug through several controlled steps. A typical global network follows this path:

**Manufacturer → EU central depot → regional depots → clinical sites → patients**

The flow is generally one-way. Drug shipped to a regional depot or site usually cannot return to central inventory for reuse. Each transfer also requires documentation, temperature control where needed, and inventory tracking.

Regional depots place drug closer to patients. For example, a study may supply Chinese sites through a depot in China rather than shipping every order from Europe. This matters because customs clearance can take weeks or even months. A local depot shortens the final delivery route and reduces the risk that a site runs out while a shipment waits at the border.

### Manufacturing before demand is known

Manufacturers produce clinical drug in runs, also called batches. A batch is designed to produce a set quantity. The manufacturer cannot easily make only the exact number of kits needed the following week.

Manufacturing arrangements also change during development. In Phase 1 and Phase 2, the Product Development team may produce small batches in-house. These smaller runs may offer more flexibility. As the program approaches Phase 3, production often moves to a large commercial manufacturer. That manufacturer may later supply the approved product to pharmacies.

This shift brings greater capacity and readiness for commercial supply. However, it can also mean larger minimum batch sizes, longer planning cycles, and less flexibility to change quantities at short notice.

In both settings, production starts before actual patient demand is known. If enrollment is slower than expected, some drug may expire before use. This creates an inherent risk of waste.

### Three inventory tiers

After manufacturing, teams manage supply across three inventory tiers.

| Inventory tier | Main role | Typical planning concern |
|---|---|---|
| EU central depot | Holds the main study inventory and supplies regional depots | Holding enough stock to support the network without creating excessive aging inventory |
| Regional depot | Holds inventory near a country or group of countries | Protecting sites against customs and international transport delays |
| Clinical site | Holds kits for direct dispensing to patients | Keeping usable stock available for the correct treatment arm and visit |

Initial stock and ongoing resupply require different decisions. At study start, the sponsor sends a defined quantity to each depot. When a clinical site first opens, it receives a starting stock.

Choosing the starting quantity is an important planning decision. Too little stock can cause an early stock-out before the first resupply arrives. Too much stock can expire if the site recruits slowly. A site expected to enroll quickly may justify more starting stock than a small site with uncertain recruitment.

After initiation, sites usually follow automatic resupply rules. When usable stock falls below a set minimum, the site requests more drug from the depot. The word “usable” is important. A kit may be physically present but unavailable for dispensing.

Sites follow **First Expired, First Out (FEFO)**. This means staff dispense the kit with the earliest expiry date first. They also apply a **Do Not Dispense (DND)** period. In the example used in this paper, a kit that will expire within 13 days cannot be given to a patient. It remains physically on the shelf, but it no longer protects the site from a stock-out.

Most trials manage these activities through **Interactive Response Technology (IRT)**. IRT is the electronic system used to manage patient randomization and drug supply. When a patient is randomized, IRT assigns the patient to a treatment arm and identifies the kit to dispense. It also tracks site inventory and can trigger automatic resupply requests.

The rules configured in IRT must closely match the rules used in the supply simulation. These include minimum stock levels, kit assignment logic, and resupply thresholds. If the simulation assumes one rule while IRT uses another, the simulation results will not reflect actual trial operations.

### Why supply is difficult to plan

Several uncertainties act at the same time:

- Sites enroll faster or slower than forecast.
- Randomization determines the required treatment arm only when the patient enters the trial.
- Manufacturing, transport, customs, and final delivery can take longer than planned.
- Every kit has a limited shelf life.

Together, these conditions create a **shelf-life-constrained supply chain**. In plain terms, inventory loses its usefulness over time. Unlike many commercial supply chains, ordering more drug earlier does not always improve performance. Extra stock may expire before patients arrive.

Some causes of waste are largely fixed and outside the study team's control. These include the number of countries and depots, customs requirements, and the drug's shelf life. Label language requirements can also force separate kit production for different regions.

Other choices are adjustable. Teams can change the initial quantities sent to depots and sites. They can also change the stock thresholds that trigger ongoing resupply. Separating fixed factors from adjustable factors helps teams focus optimization work where it can make a practical difference.

### Waste, cost, and patient service

Clinical supply teams use more than one waste definition. A common operational measure compares the number of kits shipped with the number used:

**Waste percentage = kits shipped but not used, divided by kits used, expressed as a percentage.**

For example, if a study ships 140 kits and uses 100, this measure reports 40% waste. A planning range of 30% to 50% is common for clinical trials. The appropriate range varies by study design, shelf life, and the waste definition used. This level is not automatically a sign of failure. Some extra inventory is necessary to protect patients against uncertain enrollment and treatment assignment.

This paper also uses a broader full-chain waste measure. It includes drug that expires or is damaged at the central depot, regional depots, and sites. It reports that loss as a percentage of total drug produced. Because the two measures use different denominators, teams should always state which definition they are reporting.

Waste must also be balanced against logistics cost. Smaller, more frequent shipments can reduce expiry, but they increase freight, packaging, and handling costs. If the smallest shipping carton holds four kits, sending one kit at a time requires four shipments instead of one shipment containing all four kits. When fixed packaging and freight costs apply to every shipment, the total shipping cost can approach four times the cost of the consolidated shipment. Actual costs depend on carrier rates, routes, and handling requirements.

Cold-chain requirements make this trade-off more severe. Cold chain means temperature-controlled transport and storage. Some biologic drugs require ultra-cold conditions, making each shipment extremely expensive. A team may reasonably accept somewhat higher drug waste in exchange for fewer, better-consolidated shipments.

Stock-outs carry serious consequences. Patients may miss visits or receive treatment late. Sites may need extra monitoring and coordination. Recruitment timelines may extend. For a successful product, supply delays can also consume part of the remaining patent exclusivity period and shorten the commercial window after approval.

Expiry also has an environmental cost. Every discarded kit represents materials and energy used in manufacturing, packaging, storage, and transport. Disposal then adds to pharmaceutical waste streams. As trials become larger and more global, sponsors increasingly consider this environmental footprint alongside financial cost.

### Measures used in this paper

| Key performance indicator | Practical definition | Planning guide |
|---|---|---|
| **Stock-out rate** | Percentage of patient visits where no usable drug was available for the patient's assigned treatment | Target below 5% |
| **Full-chain waste rate** | Drug that expired or was damaged at the central depot, regional depots, or sites, as a percentage of total drug produced | A 30%–50% planning range is common, but results depend on study design and the waste definition used |
| **Logistics cost** | Cost driven mainly by shipment frequency, shipment size, and cold-chain requirements | Lower cost must be balanced against waste and stock-out risk |

These measures capture the central planning challenge: protect patients while limiting waste and controlling delivery cost. The simulation approach described later builds on the clinical trial supply modeling foundation presented by Anisimov (2010) and Lefew, Ninh, and Anisimov (2021).

---

## 3. Stochastic Simulation Framework

A supply forecast often shows one expected enrollment curve and one expected demand total. Real trials rarely follow that exact path. Some sites open late. Some recruit quickly. Others enroll no patients. Patients may also leave treatment early.

A **stochastic simulation** reflects this uncertainty by allowing events to vary from one simulation run to another. In plain terms, it creates many realistic versions of how the trial could unfold. The model then shows how the supply chain performs across those different versions.

The example in this paper represents a trial with:

- 250 patients
- 23 clinical sites
- Two treatment arms
- A 52-week treatment period
- An overall simulation horizon of about 850 days

The longer horizon allows the model to capture enrollment, treatment, final patient visits, and drug expiry after recruitment slows or stops.

### 3.1 Modeling patient enrollment

Sites do not all recruit at the same pace. Treating every site as an “average site” would hide an important source of supply risk.

The simulation therefore assigns each active site to one of three recruitment tiers:

| Recruitment tier | Average enrollment pace | Practical example |
|---|---:|---|
| Low | 1 patient per month | A small site with a limited patient pool |
| Medium | 2 patients per month | A typical established research site |
| High | 4 patients per month | A large specialist center with strong recruitment |

These rates describe successful enrollment after screening. The model draws each site's rate from a realistic mix of the three tiers. It also assumes that 15% of sites never enroll a patient. These zero-enrolling sites still matter. They may receive initial stock that remains unused and eventually expires.

The model separates screening from enrollment. Screening is the process used to determine whether a potential patient meets the trial requirements. In this example, 35% of screened patients fail screening. They do not enter the trial and do not create treatment demand.

For example, a site may screen 20 people but enroll only about 13. A supply plan based on all 20 would overstate demand. The simulation accounts for this screening loss while maintaining the assigned pace of successful enrollment.

Patient dropout creates another important source of variation. The simulation assumes that 20% of enrolled patients leave treatment before completing the 52-week period. It determines when each dropout occurs and stops future dispensing for that patient.

Dropout must be modeled directly. If the model assumes that every patient completes every visit, it overestimates total drug demand. In this trial, omitting dropout can increase the demand estimate by about 10% to 15%. That difference could lead to unnecessary manufacturing and higher expiry.

### 3.2 How the simulation runs day by day

The simulation advances one day at a time for about 850 days. This approach works like a detailed operational calendar. Each day, the model checks what could happen and updates inventory throughout the network.

Events occur in a defined sequence:

1. **New patients may enroll.**  
   Each site may screen and enroll patients based on its assigned recruitment pace.

2. **Existing patients may attend visits.**  
   Active patients return according to the trial visit schedule. Visit timing can vary within the rules of the protocol.

3. **Sites dispense drug.**  
   The model identifies the patient's treatment arm and required kit type. It then selects the usable kit with the earliest expiry date.

4. **Sites review inventory when scheduled.**  
   A site checks whether its usable stock is below the required level. If so, it places a resupply order.

5. **Depots process pending orders.**  
   Regional depots prepare and ship available stock to sites. International transfers may also move from the EU depot to China.

6. **Scheduled manufacturing batches may arrive.**  
   On planned arrival days, newly released kits enter inventory at the EU central depot.

7. **Expired drug is removed and recorded.**  
   The model logs where the expiry occurred. This allows teams to distinguish waste at the central depot, regional depot, and site levels.

The model tracks every kit separately. Each kit has:

- A kit type: 5 ml, 2.5 ml, or 7.5 ml
- A treatment arm: A or B
- An expiry date
- A current location and shipment status

Individual tracking matters because kits are not interchangeable in every situation. A site may have many kits in total but still lack the correct type or treatment arm for a patient.

The model follows First Expired, First Out. It dispenses the eligible kit with the earliest expiry date first. It also applies the 13-day Do Not Dispense period. A kit within that period remains in physical inventory but cannot be given to a patient. It therefore does not count as usable stock when the site reviews its inventory.

Sites review stock once each week rather than triggering orders every day. When a site orders, it requests enough drug to reach its target inventory level. The calculation includes usable stock already at the site and stock already in transit.

This weekly review reduces over-ordering. Daily triggers can create several overlapping orders before the first shipment arrives. It is similar to repeatedly ordering groceries online without checking what is already on the delivery truck.

### 3.3 Manufacturing and replenishment policy

Manufacturing follows a fixed schedule. The model includes eight batches, with one batch arriving every 60 days starting on Day 0.

Each batch is sized to cover approximately 210 days of expected demand. This planning quantity includes:

- A 150-day planned coverage window
- An additional 60 days of safety stock

Safety stock is extra inventory held to protect the trial against higher demand or delayed supply. However, this protection has a limit. Too much early production increases the chance that kits will expire before use.

When a manufacturing batch reaches the EU central depot, the model automatically calculates how much stock the China depot needs. It then prepares a transfer, subject to one important protection rule.

The EU depot must keep enough inventory to cover its own expected demand for the next 90 days before sending stock to China. This setting is called **EU_PROTECT**. Section 4 examines how changing this parameter affects patient service and waste.

The model also performs a daily safety check on the China depot. If China falls below seven days of expected supply, the system sends a top-up shipment when suitable EU stock is available. This rule provides a safety net between the larger transfers linked to manufacturing batch arrivals.

Together, these rules balance two needs. China requires enough local stock to manage long international lead times. At the same time, the EU depot must not transfer so much that European sites face shortages.

### 3.4 What the simulation produces

One simulation run represents only one possible trial outcome. It might include unusually fast recruitment, fewer dropouts, or several delayed visits. A different run may produce the opposite pattern.

The framework therefore runs 100 independent replications. A replication is one complete simulated version of the trial. Each replication uses different random draws for:

- Site enrollment rates
- Patient arrival patterns
- Visit timing
- Patient dropout events

The result is a range of possible outcomes rather than one fixed forecast. This helps teams see whether a supply policy performs reliably under uncertainty, not only under average conditions.

The main outputs include:

| Output | What it shows |
|---|---|
| Visit-level stock-out rate | Percentage of patient visits where the correct usable drug was unavailable |
| Full-chain waste rate | Percentage of produced drug that expired or was damaged anywhere in the network |
| Kits dispensed | Total kits provided to patients |
| Kits expired by location | Expiry at the EU depot, China depot, or clinical sites |
| Kits damaged in transit | Shipped kits lost under the assumed 1% damage rate for each shipment |

For the baseline trial design, the average stock-out rate across the 100 replications was **0.68%**. The average full-chain waste rate was **43.5%**.

Both results fall within the planning ranges used in this paper. The stock-out rate is well below the 5% target and indicates strong patient protection. The waste rate is within the 30% to 50% planning range. It reflects the extra inventory needed to support 23 sites, two treatment arms, multiple kit types, and uncertain enrollment.

These baseline results provide the starting point for the sensitivity analysis and optimization in Section 4.

---

## 4. Sensitivity Analysis and Parameter Optimization

### 4.1 What sensitivity analysis means here

A simulation shows how one supply policy may perform. A **sensitivity analysis** tests how much the results change when the team adjusts that policy.

The process is straightforward:

1. Start with the baseline supply settings.
2. Change one setting at a time.
3. Run the simulation repeatedly under the new setting.
4. Compare stock-outs and waste with the baseline.
5. Identify changes that improve performance without creating unacceptable risk.

Each setting is tested across many simulated versions of the trial. In total, this requires hundreds of simulation runs. Changing one setting at a time helps the team identify which setting caused the difference and how large that difference was.

The trial in this example includes:

- 250 patients
- 23 sites, including 13 in the EU and 10 in China
- Two treatment arms
- A double-blind design, where patients and blinded study staff do not know the assigned treatment
- About 27 months of study operations within an overall simulation horizon of about 850 days

Under the baseline settings, the average visit-level stock-out rate was **0.68%**. Full-chain waste was **43.5%**. The analysis then tested whether different operating settings could reduce waste while keeping the stock-out rate below the 5% target.

Four parameters had the greatest practical effect.

### 4.2 The four parameters that matter most

#### Site reorder target

The first parameter is **THRESH top**, or the site reorder target. It defines how much stock a site aims to hold after resupply.

The default target was 105 kits. This gave sites a large inventory cushion, but some kits remained unused at slower-recruiting sites. Lowering the target to 70 kits reduced full-chain waste from 43.5% to about 40%. The stock-out rate increased from 0.68% to about 1.4%, but it remained well below the 5% limit.

This was the strongest waste-reduction opportunity identified in the analysis. It reduced the amount of drug held at the point where inventory is least flexible. Once drug reaches a site, it usually cannot be moved elsewhere for use.

The change is similar to stocking less product on each store shelf while keeping replacement stock available nearby. The shelf holds less excess inventory, but customers still receive the product because resupply remains active.

**Recommendation:** Reduce the EU site reorder target from 105 kits to 70 kits. Monitor actual enrollment and delivery performance after implementation.

#### Minimum shelf life at site receipt

The second parameter is **MIN_SHELF**, or the minimum remaining shelf life that a site will accept when a shipment arrives.

At first, a stricter rule appears helpful. If sites accept only newer kits, fewer kits should expire at sites. However, the simulation showed that this change does not reduce waste across the full supply chain.

When sites reject kits with shorter remaining shelf life, those kits stay at the regional depot. In China, this near-expiry inventory then accumulates and expires at the depot instead. Site expiry falls, but depot expiry rises. Total waste barely changes.

This is like moving food that is close to expiry from a kitchen shelf back into a warehouse. The kitchen looks better, but the food still expires.

The shelf-life rule remains important for quality and patient protection. A kit must have enough remaining shelf life to support shipment, dispensing, and protocol requirements. However, tightening the rule should not be presented as a waste-reduction action.

**Recommendation:** Keep the 30-day minimum. Treat it as a quality control setting, not a waste-reduction lever.

#### EU inventory protection

The third parameter is **EU_PROTECT**. It defines how many days of expected EU demand the central depot must reserve before transferring stock to China.

At the default setting of 90 days, the China stock-out rate was only 0.08%. When the reserve fell to 30 days, the China stock-out rate rose to 3.0%. Based on the underlying simulation results before rounding, this was approximately a 39-fold increase. Full-chain waste barely changed.

This result may appear surprising because a lower EU reserve allows more stock to move to China earlier. However, doing so can leave too little suitable stock at the EU depot for later transfers. The network then has less ability to respond when demand or shipment timing differs from the forecast.

The 30-day setting remained below the overall 5% planning limit, but it created a large and unnecessary increase in risk. It also provided less protection against delays not fully captured by the model.

**Recommendation:** Never set EU protection below 60 days. Keep the 90-day default as the safe operating point.

#### Manufacturing batch frequency

The fourth parameter is manufacturing frequency. This analysis held total production volume fixed and changed how that volume was divided across batches.

Four large batches produced the lowest observed stock-out rate, at about 0.08%. However, full-chain waste increased to 56%. Large quantities arrived early and remained at the depot for long periods. Many kits expired before patients needed them.

At the other extreme, 15 small batches increased the stock-out rate to 3.8%. Each batch provided a smaller supply cushion. A period of fast enrollment or higher demand could use the available stock before the next manufacturing arrival.

Eight batches arriving at 60-day intervals provided the best balance. They avoided the heavy expiry associated with four large batches while maintaining a stronger supply cushion than 15 small batches.

**Recommendation:** Keep the schedule of eight batches at 60-day intervals.

### 4.3 Why the right waste metric matters

The analysis compared two waste measures:

- **Site-only waste, or V1:** Counts drug that expires at clinical sites only.
- **Full-chain waste, or V2:** Counts drug that expires or is damaged at the EU central depot, regional depots, and clinical sites. It reports this loss as a percentage of total drug produced.

V1 can give a misleading result. For example, a stricter shelf-life acceptance rule reduces the number of kits that expire at sites. Under V1, this looks like an improvement.

V2 shows what actually happened. The rejected kits remained at the depot and expired there. The location of the waste changed, but the total loss barely changed.

A site-only measure may encourage teams to solve a local problem by moving it elsewhere. It can also hide expiry caused by early manufacturing or excess regional inventory.

**Full-chain waste should therefore be the primary waste measure.** Site-level waste remains useful for identifying where losses occur, but teams should not use it alone to select a supply policy.

### 4.4 Recommended operating configuration

| Parameter | Default | Recommended | Expected outcome |
|---|---:|---:|---|
| THRESH top, EU site target | 105 kits | 70 kits | Full-chain waste falls from 43.5% to about 40%; stock-outs rise from 0.68% to about 1.4% |
| MIN_SHELF | 30 days | 30 days | No change needed |
| EU_PROTECT | 90 days | 90 days | No change needed |
| Manufacturing batch schedule | 8 batches at 60-day intervals | 8 batches at 60-day intervals | No change needed |

Only the EU site target requires adjustment. The other baseline settings already provide a sound balance between patient service and waste.

### 4.5 Connection to the academic literature

The findings are consistent with Anisimov (2010). That work showed that excess supply rises steeply when planners try to drive stock-out risk close to zero. The simulation confirms the same practical lesson. The four-batch schedule achieved very low stock-outs, but waste rose to 56%.

The literature also shows that **center-stratified randomization** can require less excess inventory than unstratified randomization. Center-stratified randomization keeps treatment assignments more balanced within each site. Unstratified randomization balances assignments mainly across the trial as a whole. Both the published formulas and the simulation indicate that better local balance reduces the extra stock needed at individual sites.

Finally, both approaches show that adding depots or treatment arms increases the required overage when other trial conditions remain similar. Each additional location and treatment arm divides inventory into smaller pools. A kit in the wrong location or treatment-arm pool cannot meet an immediate patient need. Careful parameter optimization therefore becomes more valuable as trial networks become more complex.

---

## 5. AI-Assisted Implementation: The SKILL Approach

### 5.1 The challenge of building a simulation from scratch

A faithful clinical trial drug supply simulation is not a simple spreadsheet. It must represent patients, visits, kits, expiry dates, shipments, depots, and resupply decisions. Depending on the study, a working model may require 500 to 1,000 lines of computer code.

Writing that code manually can take several weeks. Testing unusual situations can take even longer. For example:

- A patient misses a scheduled visit.
- A kit expires while it is in transit.
- A site has drug on the shelf, but none is usable because of the Do Not Dispense period.
- A patient discontinues treatment between visits.
- The correct treatment-arm kit is unavailable even though the site has other kits.
- Two resupply orders overlap because the first shipment has not yet arrived.

The larger challenge is not the coding itself. It is translating study rules into precise instructions.

The required information is rarely in one place. Enrollment assumptions may be in the protocol. Kit details may be in the supply specification. Shipment rules may be in an Interactive Response Technology document. An important clarification about customs may exist only in an approved email or meeting record.

Important rules can therefore become scattered across many sources. These rules include:

- First Expired, First Out dispensing
- The 13-day Do Not Dispense window
- The weekly site inventory review
- EU inventory protection before transfers to China
- Treatment-arm and kit-type requirements
- Blinding controls that limit access to treatment assignments

A programmer may know how to build a simulation but not know which operational details matter. A supply expert may understand the process but not know how to express every rule in computer code. This gap creates a high risk of hidden assumptions and incorrect results.

AI coding assistants can shorten the development process. However, a broad request such as “write a clinical supply simulation” is not enough. The AI may fill information gaps with assumptions that sound reasonable but do not match the study.

The **SKILL approach** addresses this problem by controlling how the AI works.

### 5.2 What the SKILL approach is

A **skill** is a structured set of instructions given to an AI coding assistant. In this example, the assistant is Amazon Kiro. The skill captures clinical supply knowledge and turns it into a reusable workflow.

The analyst does not simply ask the AI to generate a simulation. Instead, the SKILL instructs the AI to:

1. Read the study documents and approved clarifications.
2. Identify missing or unclear information.
3. Present its proposed assumptions.
4. Confirm difficult dispensing scenarios.
5. Generate the simulation only after approval.
6. Review the results for possible errors.
7. Record confirmed decisions and lessons for future work.

The AI follows the same steps each time. This makes the process more consistent and easier to review.

A useful analogy is the difference between giving a new employee a single task and giving that employee an operations manual. Without the manual, the employee may complete the task quickly but miss important controls. With the manual, the employee knows what to check, when to ask questions, and how to document the work.

Under the SKILL approach, the AI acts less like a code generator and more like a junior analyst who has read the operations manual. The human analyst still owns the assumptions, reviews the model, interprets the outputs, and approves the final recommendations.

### 5.3 The workflow in practice

The SKILL uses six phases. The phase numbers include intermediate checkpoints because the team added these controls during development.

| Phase | Main activity | Why it matters |
|---|---|---|
| 0 | Read before writing | Prevents the AI from coding from an incomplete summary |
| 0.5 | Confirm every assumption | Makes hidden decisions visible |
| 0.7 | Verify dispensing edge cases | Checks unusual but important patient scenarios |
| 1 | Generate the simulation | Builds the model using confirmed rules |
| 2 | Run and interpret | Checks results and identifies possible anomalies |
| 3 | Produce a structured report | Converts technical output into operational findings |

#### Phase 0 — Read before writing

The AI first reads the full trial protocol, supply specification, IRT rules, and relevant approved clarifications. It does this before writing any code.

It identifies the type of analysis required. For example, the request may involve a baseline simulation, a sensitivity analysis, or a comparison of resupply policies.

The AI also checks for a persistent context file. This is a saved record of decisions from earlier work sessions. In this implementation, the file is named `supply_chain_context.md`. It may contain confirmed definitions, agreed assumptions, previous errors, and lessons learned.

This step reduces the risk that the team will revisit the same question or apply different rules in different sessions. The team should store and manage this file in an approved environment, using the same access and document controls applied to other study materials.

#### Phase 0.5 — Confirm every assumption

Next, the AI produces a table of the major decisions required to build the model. It does not proceed until the analyst approves or corrects each item.

For example, the table may state:

- How patient dropout will be spread across the treatment period
- Whether missed visits are skipped or rescheduled
- How stock already in transit affects a resupply order
- When a kit becomes unusable under the Do Not Dispense rule
- Whether shipment damage occurs before or after receipt
- How the model protects EU inventory before transferring stock to China

Nothing is assumed silently. If a protocol statement is unclear, the AI highlights it as an open question.

This checkpoint may feel slower than immediate code generation. In practice, it saves time. Correcting an assumption in a review table takes minutes. Finding the same error after hundreds of simulation runs may take days.

#### Phase 0.7 — Verify dispensing edge cases

The AI then reviews a dedicated checklist of more than 10 dispensing scenarios. These are situations that are easy to overlook but can materially change the results.

The checklist includes questions such as:

- What happens when a patient misses a visit?
- What happens when the required kit is unavailable?
- Can a visit be partly completed if it requires several kits and stock runs out?
- What happens to future visits after a patient discontinues?
- Does a kit inside the Do Not Dispense window count as usable stock?
- Which kit is selected when several suitable kits are available?
- Can stock intended for one treatment arm be used for another?
- How are kits handled if they expire on the day of a visit?
- Does an order include inventory already in transit?
- What happens when the depot cannot fill the complete order?

The analyst must confirm every scenario before coding begins. This creates a clear operational record and supports later testing.

#### Phase 1 — Generate the simulation

Only after approval does the AI create the simulation. In this case, it produces R code. R is a programming language commonly used for data analysis and simulation.

The SKILL contains non-negotiable rules. These include:

- Use First Expired, First Out dispensing.
- Apply the Do Not Dispense window when counting usable stock.
- Review site inventory weekly.
- Pull shipped kits from existing depot inventory.
- Track treatment arms internally while protecting blinding in operational outputs and user access.
- Validate total enrollment before calculating performance measures.
- Record expiry and damage at every inventory level.

These controls make the generated model more consistent across studies and analysts. They do not remove the need for testing and human review.

#### Phase 2 — Run and interpret

The analyst runs the simulation in the approved computing environment and provides the output for review. The AI then explains the findings in plain English.

It checks whether:

- Enrollment matches the trial target.
- Dispensing volumes are reasonable.
- Depot inventory decreases when shipments occur.
- Waste is recorded at all locations.
- Stock-out and waste rates fall within agreed planning ranges.
- Any result appears too high, too low, or internally inconsistent.

The AI can also help prepare and review sensitivity analyses across many parameter combinations. This reduces repetitive manual work and the risk of copying the wrong settings. However, the analyst must still confirm that each tested combination is valid and that the results make operational sense.

#### Phase 3 — Produce a structured report

The final phase converts the output into a format that the supply team can use. The report includes:

- A summary of the confirmed assumptions
- A table of key performance indicators
- Comparisons with the baseline
- Anomalies or limitations
- Prioritized recommendations
- Decisions that require human approval

This step helps prevent technical output from being shared without operational interpretation.

### 5.4 What AI handles well—and where humans must stay involved

AI provides the most value in repetitive, structured work.

| AI strengths | Human responsibilities |
|---|---|
| Produces an initial code draft from a 13-page supply specification in minutes | Decides whether the completed model reflects the actual study |
| Applies confirmed rules across many parameter combinations | Sets acceptable patient-service and safety limits |
| Reduces fatigue and manual transcription errors | Interprets unclear protocol language |
| Reviews outputs for possible logical inconsistencies | Judges whether recommendations are operationally feasible |
| Records confirmed decisions across sessions | Reviews and approves any change affecting patient safety |

The persistent context file also helps retain institutional knowledge. It records why a decision was made, not only what the decision was. This can support handovers between analysts and reduce repeated errors.

However, an initial code draft is not the same as a validated simulation. AI can introduce errors even when its output appears reasonable. Teams must test the model before trusting its results.

Human judgment remains essential. An acceptable stock-out rate depends on the disease, patient population, treatment alternatives, and regulatory setting. AI cannot decide what level of patient risk is acceptable.

The same rule applies to ambiguous study language. A person who knows the study must determine the intended meaning. Any supply strategy that could affect patient safety requires formal human review and sign-off before implementation.

### 5.5 Hard lessons from building the simulation

Three early errors show why AI-generated simulations require strong validation.

| Practical lesson | What happened | Control added to the SKILL |
|---|---|---|
| Validate enrollment first | An early model enrolled three to four times too many patients. The results looked plausible but were meaningless. | The model must compare simulated enrollment with the study target before any result is interpreted. |
| Confirm that shipments reduce depot stock | An early model created new kit records when shipping to sites. Depot inventory did not decrease. This produced “phantom drug” that had never been manufactured. | Every shipment must pull identified kits from existing depot inventory. |
| Use full-chain waste | An early report counted only site expiry. It missed expiry at central and regional depots, making waste appear artificially low. | Full-chain waste is the required primary measure. Expiry by location may be shown as a supporting breakdown. |

These problems were found through repeated human and AI review. The AI helped identify inconsistencies, but human analysts challenged results that did not make operational sense.

The main lesson is simple: fast code generation is not the same as a trustworthy simulation. Teams should test AI-generated models against known patient totals, inventory movements, and benchmark scenarios before using them for supply decisions.

The SKILL approach makes those checks part of the standard workflow. It combines AI speed with human control, documented assumptions, and repeatable validation.

---

## 6. Discussion

Clinical trial supply optimization is a strategic capability. It is not simply a back-office logistics task. Supply decisions affect patient continuity, trial timelines, and development costs.

A shortage of the correct kit can disrupt a treatment visit. Repeated disruptions can slow trial delivery and reduce the time available to sell a medicine under patent protection. At the other extreme, excessive supply raises manufacturing, storage, shipping, and destruction costs. It also increases the supply cost for each patient treated.

The simulation shows why teams must balance these risks. The baseline policy achieved a low stock-out rate of 0.68%, but full-chain waste reached 43.5%. Reducing the EU site target from 105 to 70 kits lowered waste to about 40%. Stock-outs increased to about 1.4%, but remained below the 5% target.

By contrast, four large manufacturing batches reduced stock-outs to about 0.08% while increasing waste to 56%. The safest-looking policy was therefore not the best overall policy. It protected strongly against shortages but produced too much drug too early.

These findings have a broader business meaning. A well-designed supply plan supports reliable trial delivery while controlling the cost per patient. A poorly designed plan can delay treatment, slow the study, and leave large quantities of unused drug to expire.

### Simulation and formula-based methods serve different needs

Simulation and formula-based methods are complementary. Teams should not treat them as competing approaches.

Anisimov’s formulas provide fast comparisons during study design. They can help teams assess how the number of sites, treatment arms, or depots affects the amount of supply required. This is useful when the trial is still being planned and detailed operating data are limited.

Simulation provides more operational detail. For example, the model in this paper can represent:

- Different recruitment rates across sites, including the 15% of sites assumed to enroll no patients
- First Expired, First Out dispensing, which uses the eligible kit with the earliest expiry date first
- Weekly inventory reviews rather than daily ordering
- Reorder thresholds that can be tested or adjusted as enrollment develops
- Shipment lead times and damage
- Patient dropout and differences in visit timing
- Expiry at central depots, regional depots, and clinical sites

Formula-based methods provide a quick map. Simulation provides a detailed route plan. A practical approach is to use formulas for early study design choices and simulation for detailed planning, policy testing, and updates during trial execution.

### Important limitations

Teams should apply the findings with appropriate caution:

- **The model represents one trial design.** The findings should not be transferred directly to another study. Each new trial needs its own assumptions for enrollment, dropout, visits, shipping, shelf life, treatment assignment, and manufacturing.
- **The SKILL approach requires suitable resources.** Teams need access to an AI coding assistant. They also need an analyst who is willing to test, review, and improve the model through repeated cycles. AI can support implementation, but it does not remove the need for human review.
- **Results depend on input quality.** If enrollment estimates are too high or too low, the supply plan may also be wrong. The same applies to assumptions about dropout, delivery times, damage, and shelf life. Teams should compare assumptions with actual study data and update the model as the trial progresses.

These limitations do not reduce the value of simulation. They define how teams should use it. Simulation is a decision aid, not a fixed prediction of exactly what will happen.

### Broader use across clinical operations

The SKILL workflow is not limited to drug supply. Clinical operations teams can use the same structured collaboration between people and AI for other complex simulation tasks, including:

- **Patient recruitment modeling:** Testing how site openings, recruitment rates, and screen failures may affect enrollment timelines
- **Adaptive trial scenario testing:** Exploring trial designs that allow planned changes based on accumulating study information
- **Biomarker-driven randomization:** Testing treatment assignment rules that depend on a patient’s biological characteristics

The common principle is simple. Clinical and operational experts define the problem and the decision rules. AI helps build and refine the implementation. People validate the model, challenge its assumptions, and remain responsible for all decisions.

---

## 7. Conclusion

Clinical trial supply teams must balance three competing goals: avoid waste, control cost, and prevent stock-outs that could disrupt patient treatment. Simulation makes these trade-offs visible and manageable. In the trial examined here, lowering the EU site reorder target from 105 to 70 kits reduced full-chain waste from 43.5% to about 40%. The visit-level stock-out rate rose from 0.68% to about 1.4%, but remained well below the 5% planning threshold. The analysis also showed that EU_PROTECT—the inventory reserved at the EU depot before transfers to China—is the most critical setting for continuity of supply in China. Reducing it too far created a large and unnecessary increase in stock-out risk.

The SKILL approach made detailed simulation more practical. It reduced the time needed to move from protocol and supply documents to a working simulation from weeks to days. Human review remained central at every stage. Analysts confirmed assumptions, checked difficult dispensing scenarios, tested the model, and approved recommendations. Early failures also became permanent safeguards. The SKILL now checks for excessive enrollment, confirms that shipments reduce depot inventory, and requires full-chain waste reporting. These controls prevent over-enrollment, “phantom drug,” and misleading site-only waste measures from quietly distorting results.

Supply teams should treat simulation-based planning as a standard operating tool, not a research exercise. Teams can use it to test policies before implementation, update plans as actual trial data arrive, and explain decisions with clear evidence. Rigorous modeling, combined with structured AI assistance and human oversight, is ready for operational use today.
---

## References

1. Anisimov VV. Drug supply modelling in clinical trials (statistical methodology). *Pharmaceutical Outsourcing*. May/Jun 2010:17–20.

2. Lefew M, Ninh A, Anisimov V. End-to-end drug supply management in multicenter trials. *Methodology and Computing in Applied Probability*. 2021;23:695–709. https://doi.org/10.1007/s11009-020-09776-z

3. Anisimov VV, Fedorov VV. Modelling, prediction and adaptive adjustment of recruitment in multicentre trials. *Statistics in Medicine*. 2007;26(27):4958–4975.

4. Anisimov VV, Fedorov VV, Heiberger R, Saha S, Kothapalli M. Drug Supply Modeling Software: User Manual. GSK DDS Technical Report 2010-01. GlaxoSmithKline Pharmaceuticals; 2010.

5. Peterson M, Byrom B, Dowlman N, McEntegart D. Optimizing clinical trial supply requirements: simulation of computer-controlled supply chain management. *Clinical Trials*. 2004;1(4):399–412.
