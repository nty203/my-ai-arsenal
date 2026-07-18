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

        # 1. Check if 'Continue as account' / '내 계정으로 계속' popup (including Google One-Tap iframe) is present
        try:
            # Check main document first
            continue_btns = self.driver.find_elements(By.XPATH,
                "//button[contains(., '계정으로') or contains(., 'Continue as')] | //div[contains(., '계정으로 계속')]")
            if continue_btns and continue_btns[0].is_displayed():
                logger.info("Found 'Continue as account' button in main doc. Clicking automatically...")
                self.driver.execute_script("arguments[0].click();", continue_btns[0])
                time.sleep(4)

            # Check inside Google One-Tap iframe
            iframes = self.driver.find_elements(By.CSS_SELECTOR, "iframe[src*='accounts.google.com'], iframe[title*='Google']")
            for iframe in iframes:
                try:
                    self.driver.switch_to.frame(iframe)
                    g_btns = self.driver.find_elements(By.XPATH, "//div[contains(text(), '계정으로') or contains(text(), 'Continue as')] | //span[contains(text(), '계정으로') or contains(text(), 'Continue as')] | //button")
                    if g_btns:
                        logger.info("Found 'Continue as account' inside Google One-Tap iframe! Clicking...")
                        self.driver.execute_script("arguments[0].click();", g_btns[0])
                        self.driver.switch_to.default_content()
                        time.sleep(4)
                        break
                    self.driver.switch_to.default_content()
                except Exception:
                    self.driver.switch_to.default_content()
        except Exception as e:
            logger.warning(f"Error checking continue button: {e}")

        # 2. Check if logged in vs Guest mode
        try:
            login_btns = [e for e in self.driver.find_elements(By.CSS_SELECTOR, "[data-testid='login-button'], button[data-testid='welcome-login-button']") if e.is_displayed()]
            login_links = [e for e in self.driver.find_elements(By.XPATH, "//button[contains(., 'Log in') or contains(., '로그인')] | //a[contains(., 'Log in') or contains(., '로그인')]") if e.is_displayed()]

            if login_btns or login_links:
                logger.info("ChatGPT in guest mode. Waiting for login or 'Continue as account' popup...")
                start_w = time.time()
                while time.time() - start_w < 600:
                    # Check for 'Continue as account' popup
                    try:
                        c_btns = self.driver.find_elements(By.XPATH, "//button[contains(., '계정으로') or contains(., 'Continue as')]")
                        if c_btns and c_btns[0].is_displayed():
                            logger.info("Clicking 'Continue as account' popup during wait...")
                            self.driver.execute_script("arguments[0].click();", c_btns[0])
                            time.sleep(4)
                    except Exception:
                        pass

                    # Check if logged in (profile button / user avatar present)
                    profile = self.driver.find_elements(By.CSS_SELECTOR, "[data-testid='profile-button'], button[aria-label*='User profile'], button[aria-label*='프로필'], div.avatar")
                    if profile and any(p.is_displayed() for p in profile):
                        logger.info("ChatGPT login verified.")
                        break

                    # Check if login buttons gone
                    l_btns = [e for e in self.driver.find_elements(By.CSS_SELECTOR, "[data-testid='login-button']") if e.is_displayed()]
                    if not l_btns:
                        break

                    time.sleep(2)
        except Exception as e:
            logger.warning(f"Error checking login state: {e}")

        self.wait.until(EC.presence_of_element_located((By.CSS_SELECTOR,
            "div#prompt-textarea, textarea#prompt-textarea, div[contenteditable='true']")))
        logger.info("ChatGPT input box ready.")

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
                    "div[data-message-author-role='assistant'], div.markdown, article div.prose, div.agent-turn")
                if not responses:
                    # Fallback to article elements or body if specific selectors fail
                    responses = self.driver.find_elements(By.CSS_SELECTOR, "article")

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

                if stable_count > 6 and last_text_len > 0:
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
