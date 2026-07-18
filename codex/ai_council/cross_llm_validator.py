import os
import time
import logging
from selenium import webdriver
from selenium.webdriver.chrome.service import Service
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.common.by import By
from selenium.webdriver.common.keys import Keys
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from webdriver_manager.chrome import ChromeDriverManager

logger = logging.getLogger(__name__)
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')


class BaseLLMBot:
    """
    Base class using standard selenium webdriver (NOT undetected_chromedriver).
    undetected_chromedriver patches the Chrome binary which invalidates Windows
    App-Bound Encryption cookies on every run, causing constant logouts.
    Standard selenium with anti-detection flags preserves cookies correctly.
    """
    def __init__(self, user_data_dir=None, headless=False):
        self.options = Options()

        # Anti-detection flags (same approach as gemini_selenium_bot.py)
        self.options.add_argument("--no-sandbox")
        self.options.add_argument("--disable-dev-shm-usage")
        self.options.add_argument("--disable-gpu")
        self.options.add_argument("--disable-blink-features=AutomationControlled")
        self.options.add_experimental_option("excludeSwitches", ["enable-automation"])
        self.options.add_experimental_option("useAutomationExtension", False)
        self.options.add_argument("--start-maximized")
        self.options.add_argument("--lang=ko-KR")

        if headless:
            self.options.add_argument("--headless=new")

        if user_data_dir:
            if not os.path.exists(user_data_dir):
                os.makedirs(user_data_dir)
                logger.info(f"Created new profile directory: {user_data_dir}")
            logger.info(f"Using User Data Dir: {user_data_dir}")
            self.options.add_argument(f"--user-data-dir={user_data_dir}")

        try:
            logger.info("Initializing Chrome Driver (standard selenium)...")
            service = Service(ChromeDriverManager().install())
            self.driver = webdriver.Chrome(service=service, options=self.options)
            # Remove navigator.webdriver flag via CDP
            self.driver.execute_cdp_cmd("Page.addScriptToEvaluateOnNewDocument", {
                "source": "Object.defineProperty(navigator, 'webdriver', {get: () => undefined})"
            })
            self.driver.set_page_load_timeout(60)
            logger.info("Chrome Driver initialized successfully.")
        except Exception as e:
            logger.error(f"Failed to initialize Chrome Driver: {e}")
            raise

        self.wait = WebDriverWait(self.driver, 30)

    def close(self):
        if self.driver:
            try:
                self.driver.quit()
            except Exception:
                pass


class ChatGPTBot(BaseLLMBot):
    def start_new_chat(self):
        logger.info("Navigating to ChatGPT...")
        self.driver.get("https://chatgpt.com/")
        time.sleep(4)

        # Check login state: if input box is already visible, we're logged in
        try:
            input_box = WebDriverWait(self.driver, 8).until(
                EC.presence_of_element_located((By.CSS_SELECTOR,
                    "div#prompt-textarea, textarea#prompt-textarea, div[contenteditable='true']"))
            )
            logger.info("ChatGPT already logged in (input area detected).")
            return
        except Exception:
            pass

        # Not logged in: wait for user to login manually
        logger.info("ChatGPT login required. Waiting up to 600 seconds for manual login...")
        wait_long = WebDriverWait(self.driver, 600)
        wait_long.until(EC.presence_of_element_located((By.CSS_SELECTOR,
            "div#prompt-textarea, textarea#prompt-textarea, div[contenteditable='true']")))
        logger.info("ChatGPT login successful.")
        time.sleep(3)

    def send_message(self, message):
        logger.info(f"Sending message to ChatGPT: {message[:50]}...")
        try:
            input_box = self.wait.until(EC.presence_of_element_located((By.CSS_SELECTOR,
                "div#prompt-textarea, textarea#prompt-textarea, div[contenteditable='true']")))
            self.driver.execute_script("arguments[0].focus(); arguments[0].click();", input_box)
            time.sleep(0.5)

            logger.info("Injecting text via JS ClipboardEvent...")
            js_paste = """
            const text = arguments[1];
            const dt = new DataTransfer();
            dt.setData('text/plain', text);
            const pasteEvent = new ClipboardEvent('paste', {
              clipboardData: dt,
              bubbles: true,
              cancelable: true
            });
            arguments[0].dispatchEvent(pasteEvent);
            """
            self.driver.execute_script(js_paste, input_box, message)
            time.sleep(1.5)

            try:
                send_button = WebDriverWait(self.driver, 10).until(
                    EC.element_to_be_clickable((By.CSS_SELECTOR, "button[data-testid='send-button']"))
                )
                if send_button.get_attribute("disabled"):
                    time.sleep(2)
                send_button.click()
            except Exception as e:
                logger.warning(f"Send button not found, using Enter: {e}")
                input_box.send_keys(Keys.ENTER)

            time.sleep(2)
        except Exception as e:
            logger.error(f"Failed to send message: {e}")
            raise

    def get_latest_response(self, timeout=300):
        logger.info("Waiting for response from ChatGPT...")
        start_time = time.time()
        last_text_len = 0
        stable_count = 0

        while time.time() - start_time < timeout:
            try:
                responses = self.driver.find_elements(By.CSS_SELECTOR,
                    "div[data-message-author-role='assistant']")
                if not responses:
                    time.sleep(1)
                    continue

                latest_response = responses[-1]
                current_text = latest_response.text

                if len(current_text) > last_text_len:
                    last_text_len = len(current_text)
                    stable_count = 0
                else:
                    stable_count += 1

                if stable_count > 10 and last_text_len > 0:
                    return current_text
                time.sleep(1)
            except Exception as e:
                logger.warning(f"Error reading response: {e}")
                time.sleep(1)

        raise TimeoutError("Timed out waiting for ChatGPT response.")


class ClaudeBot(BaseLLMBot):
    def start_new_chat(self):
        logger.info("Navigating to Claude...")
        self.driver.get("https://claude.ai/new")
        time.sleep(4)

        # Check if already logged in
        try:
            WebDriverWait(self.driver, 8).until(
                EC.presence_of_element_located((By.CSS_SELECTOR, "div[contenteditable='true']"))
            )
            logger.info("Claude already logged in (input area detected).")
            return
        except Exception:
            pass

        # Not logged in: wait for user to login manually
        logger.info("Claude login required. Waiting up to 600 seconds for manual login...")
        wait_long = WebDriverWait(self.driver, 600)
        try:
            wait_long.until(EC.element_to_be_clickable((By.CSS_SELECTOR, "div[contenteditable='true']")))
            logger.info("Claude login successful.")
        except Exception as e:
            self.driver.save_screenshot("claude_error.png")
            logger.error("Timed out waiting for Claude login. Screenshot saved.")
            raise e

    def send_message(self, message):
        logger.info(f"Sending message to Claude: {message[:50]}...")
        try:
            input_box = self.wait.until(EC.presence_of_element_located(
                (By.CSS_SELECTOR, "div[contenteditable='true']")))
            self.driver.execute_script("arguments[0].focus(); arguments[0].click();", input_box)
            time.sleep(0.5)

            logger.info("Injecting text via JS ClipboardEvent...")
            js_paste = """
            const text = arguments[1];
            const dt = new DataTransfer();
            dt.setData('text/plain', text);
            const pasteEvent = new ClipboardEvent('paste', {
              clipboardData: dt,
              bubbles: true,
              cancelable: true
            });
            arguments[0].dispatchEvent(pasteEvent);
            """
            self.driver.execute_script(js_paste, input_box, message)
            time.sleep(1.5)

            input_box.send_keys(Keys.ENTER)
            logger.info("Pressed Enter to send message.")
            time.sleep(2)
        except Exception as e:
            logger.error(f"Failed to send message: {e}")
            self.driver.save_screenshot("claude_send_error.png")
            raise

    def get_latest_response(self, timeout=300):
        logger.info("Waiting for response from Claude...")
        start_time = time.time()
        last_text_len = 0
        stable_count = 0

        while time.time() - start_time < timeout:
            try:
                body_text = self.driver.find_element(By.TAG_NAME, "body").text

                if len(body_text) > last_text_len:
                    last_text_len = len(body_text)
                    stable_count = 0
                else:
                    stable_count += 1

                if stable_count > 10 and last_text_len > 0:
                    # Try to extract just the assistant response
                    responses = self.driver.find_elements(By.CSS_SELECTOR,
                        "div.font-claude-message, [data-testid='chat-message-content']")
                    if responses:
                        return responses[-1].text
                    return body_text
                time.sleep(1)
            except Exception as e:
                logger.warning(f"Error reading response: {e}")
                time.sleep(1)

        self.driver.save_screenshot("claude_timeout_error.png")
        html = self.driver.page_source
        with open("claude_timeout_body.html", "w", encoding="utf-8") as f:
            f.write(html)
        raise TimeoutError("Timed out waiting for Claude response. Screenshot saved.")
