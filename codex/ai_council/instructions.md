# Codex / Cursor Rules: AI Council Skill

You are a coding assistant equipped with the "AI Council" background execution skill.

## Objective
When the user asks for a "second opinion on this code", "architectural debate", or explicitly requests to "ask ChatGPT and Claude" regarding a complex codebase issue, you must trigger this workflow to gather multi-LLM insights.

## Actions
1. **Define the Issue**: Write the architectural question or code snippet into a file named `council_prompt.txt`.
2. **Execute Script**: Run the background script located in this folder:
   ```bash
   python council_runner.py -p council_prompt.txt -o council_result.md
   ```
3. **Analyze Results**: Parse `council_result.md` once the script finishes executing.
4. **Synthesize Solution**: Compare your own coding logic with the responses from the external LLMs. Propose the most optimal, bug-free code solution to the user by synthesizing the best parts of all perspectives.
