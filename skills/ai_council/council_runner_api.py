import os
import sys
import json
import argparse
import logging
import requests

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

def call_openai_api(prompt_text):
    api_key = os.environ.get("OPENAI_API_KEY")
    if not api_key:
        return "**Error:** OPENAI_API_KEY environment variable not found."
    
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {api_key}"
    }
    data = {
        "model": "gpt-4o",
        "messages": [{"role": "user", "content": prompt_text}],
        "temperature": 0.7
    }
    try:
        response = requests.post("https://api.openai.com/v1/chat/completions", headers=headers, json=data, timeout=60)
        response.raise_for_status()
        return response.json()['choices'][0]['message']['content']
    except Exception as e:
        logger.error(f"OpenAI API error: {e}")
        return f"**Error:** Failed to call OpenAI API: {e}"

def call_anthropic_api(prompt_text):
    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        return "**Error:** ANTHROPIC_API_KEY environment variable not found."
    
    headers = {
        "x-api-key": api_key,
        "anthropic-version": "2023-06-01",
        "content-type": "application/json"
    }
    data = {
        "model": "claude-3-5-sonnet-20240620",
        "max_tokens": 4096,
        "messages": [{"role": "user", "content": prompt_text}],
        "temperature": 0.7
    }
    try:
        response = requests.post("https://api.anthropic.com/v1/messages", headers=headers, json=data, timeout=60)
        response.raise_for_status()
        return response.json()['content'][0]['text']
    except Exception as e:
        logger.error(f"Anthropic API error: {e}")
        return f"**Error:** Failed to call Anthropic API: {e}"

def main():
    parser = argparse.ArgumentParser(description="Run cross-LLM validation using Official REST APIs.")
    parser.add_argument("--prompt-file", "-p", required=True, help="Path to the text file containing the prompt/analysis.")
    parser.add_argument("--output", "-o", required=True, help="Path to save the combined results.")
    args = parser.parse_args()
    
    if not os.path.exists(args.prompt_file):
        logger.error(f"Prompt file not found: {args.prompt_file}")
        sys.exit(1)
        
    with open(args.prompt_file, 'r', encoding='utf-8') as f:
        prompt_text = f.read()

    results = []
    
    logger.info("=== Starting ChatGPT (OpenAI API) Validation ===")
    gpt_response = call_openai_api(prompt_text)
    results.append(f"## 🤖 ChatGPT Response\n\n{gpt_response}\n\n")
    
    logger.info("=== Starting Claude (Anthropic API) Validation ===")
    claude_response = call_anthropic_api(prompt_text)
    results.append(f"## 🧠 Claude Response\n\n{claude_response}\n\n")
        
    with open(args.output, 'w', encoding='utf-8') as f:
        f.write("# Cross-LLM API Validation Results\n\n")
        for res in results:
            f.write(res)
            
    logger.info(f"=== Cross validation complete. Results saved to {args.output} ===")

if __name__ == "__main__":
    main()
