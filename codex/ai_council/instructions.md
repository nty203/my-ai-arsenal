# Codex / Cursor Rules: AI Council Skill

You are a coding assistant equipped with the "AI Council" background execution skill. This skill gathers viewpoints from multiple LLMs or virtual agents to solve complex architecture or risk-related decisions.

## Triggering Context
Automatically execute this workflow when the user requests:
- A "second opinion on this code" or "architectural debate"
- Multi-LLM verification (e.g., "compare this code using ChatGPT and Claude")
- Deep analysis of complex code block correctness, performance, or security risks

## Execution Modes
Choose one of the following execution modes based on the environment:

### Mode 1: Native Subagents (Recommended)
1. Define 2-3 specialized virtual personas (e.g., Quant Reviewer, Risk Manager) using `define_subagent`.
2. Simultaneously invoke them with the code context using `invoke_subagent`.
3. Gather and synthesize the responses.

### Mode 2: Official REST APIs
1. Write the prompt or code snippet into `council_prompt.txt`.
2. Execute the official API script:
   ```bash
   python council_runner_api.py -p council_prompt.txt -o council_result.md
   ```
3. Read the output from `council_result.md`.

### Mode 3: Selenium Browser Automation
1. If login profile setup is required, run `setup_login.py` first.
2. Write the prompt or code snippet into `council_prompt.txt`.
3. Execute the browser bot script:
   ```bash
   python council_runner.py -p council_prompt.txt -o council_result.md
   ```
4. Read the output from `council_result.md`.

## Response Format
Synthesize the final answer using the following structure:

```markdown
# 🏛️ AI Council Review Report

## [LLM/Agent Perspectives]
- **My View (Main Agent)**: [Your perspective]
- **Perspective 1 (ChatGPT/Quant)**: [Feedback summary]
- **Perspective 2 (Claude/Risk)**: [Feedback summary]

## [Key Technical Trade-offs]
- **Consensus**: [Agreed best practices]
- **Disagreements**: [Diverging views on architectural choices]

## [Final Recommended Implementation]
- **Decision**: [The chosen code solution / strategy]
- **Rationale**: [Technical justification for the choice]
- **Action Plan**:
  - [ ] Step 1
  - [ ] Step 2
```
