# Autonomous Improvement Loop

This layer runs only after explicit user work, verified recovery work, planned STATUS/TASK_BOARD work, and required DESIGN gaps are exhausted.

## Goal

Improve the product toward measurable project outcomes without creating endless speculative work. One iteration may select only one improvement.

## Evidence sources

Prefer observable evidence already available in the repository or runnable product: test failures/flakiness, logs, reproducible UX friction, screenshots/build output, performance measurements, accessibility findings, repeated defects, duplicated fragile code tied to real change cost, or missing coverage around high-risk behavior.

## Candidate format

For each candidate record: title, observed evidence, affected user/project outcome, smallest vertical change, verification method, risk/cost, and why now. Generate at most the configured candidate limit.

## Ranking

Compare candidates by impact, evidence strength, urgency, implementation cost/risk, and verifiability. Evidence and verifiability are mandatory. Prefer user-visible correctness/reliability/performance improvements over aesthetic churn and speculative refactoring.

## Reject candidates when

- no concrete evidence exists
- success cannot be verified in the current environment
- the change is mostly subjective polish
- it duplicates or conflicts with planned work
- it requires forbidden deploy/credential/external actions
- cost/risk is disproportionate to expected benefit

## Learning

After implementation, record what changed, verification evidence, failed hypotheses, and reusable lessons in STATUS/Wiki. A failed improvement is evidence for future selection; do not repeat it unchanged.

## Completion

If project completion signals and required gates pass, no critical blocker remains, and this evaluation yields no valuable evidence-backed candidate, mark `PROJECT_COMPLETE`. Do not invent work merely to keep the loop running.
