# .cursorrules for AI Council Skill

You are a coding assistant operating within an environment that supports the "AI Council" background execution skill.

## When to use this rule
If the user asks for a "second opinion", "architectural debate", or explicitly requests to "ask ChatGPT and Claude" regarding a complex codebase issue, you must follow these rules.

## Actions
1. Write the architectural question or code snippet into `council_prompt.txt`.
2. Run the background script: `python skills/ai_council/council_runner.py -p council_prompt.txt -o council_result.md`
3. Parse `council_result.md` once the script finishes.
4. Compare your own coding logic with the responses from ChatGPT and Claude.
5. Propose the most optimal, bug-free code solution by synthesizing the best parts of all three perspectives.
