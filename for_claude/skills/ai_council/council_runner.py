import argparse
import os
import sys
import logging

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
from cross_llm_validator import ChatGPTBot, ClaudeBot

logging.basicConfig(level=logging.INFO, format='%(message)s')
logger = logging.getLogger(__name__)

def main():
    parser = argparse.ArgumentParser(description="Run cross-LLM validation using Selenium bots.")
    parser.add_argument("--prompt-file", "-p", required=True, help="Path to the text file containing the prompt/analysis.")
    parser.add_argument("--output", "-o", required=True, help="Path to save the combined results.")
    parser.add_argument("--user-data-dir", "-u", default="./chrome_profile", help="Chrome User Data Directory for persistent login.")
    parser.add_argument("--headless", action="store_true", help="Run browser in headless mode (not recommended due to bot detection).")
    
    args = parser.parse_args()
    
    if not os.path.exists(args.prompt_file):
        logger.error(f"Prompt file not found: {args.prompt_file}")
        sys.exit(1)
        
    with open(args.prompt_file, 'r', encoding='utf-8') as f:
        prompt_text = f.read()

    results = []
    
    # 1. ChatGPT
    logger.info("=== Starting ChatGPT Validation ===")
    try:
        gpt_bot = ChatGPTBot(user_data_dir=args.user_data_dir, headless=args.headless)
        gpt_bot.start_new_chat()
        gpt_bot.send_message(prompt_text)
        gpt_response = gpt_bot.get_latest_response()
        results.append(f"## 🤖 ChatGPT Response\n\n{gpt_response}\n\n")
        gpt_bot.close()
    except Exception as e:
        logger.error(f"ChatGPT validation failed: {e}")
        results.append(f"## 🤖 ChatGPT Response\n\n**Error:** {e}\n\n")
        try:
            gpt_bot.close()
        except:
            pass
        
    # 2. Claude
    logger.info("=== Starting Claude Validation ===")
    try:
        claude_bot = ClaudeBot(user_data_dir=args.user_data_dir, headless=args.headless)
        claude_bot.start_new_chat()
        claude_bot.send_message(prompt_text)
        claude_response = claude_bot.get_latest_response()
        results.append(f"## 🧠 Claude Response\n\n{claude_response}\n\n")
        claude_bot.close()
    except Exception as e:
        logger.error(f"Claude validation failed: {e}")
        results.append(f"## 🧠 Claude Response\n\n**Error:** {e}\n\n")
        try:
            claude_bot.close()
        except:
            pass
        
    # Write output
    with open(args.output, 'w', encoding='utf-8') as f:
        f.write(f"# Cross-LLM Validation Results\n\n")
        for res in results:
            f.write(res)
            
    logger.info(f"=== Cross validation complete. Results saved to {args.output} ===")

if __name__ == "__main__":
    main()
