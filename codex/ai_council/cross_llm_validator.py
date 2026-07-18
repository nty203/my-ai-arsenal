import os
import time
import logging
import undetected_chromedriver as uc
from selenium.webdriver.common.by import By
from selenium.webdriver.common.keys import Keys
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
import pyperclip

logger = logging.getLogger(__name__)
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

class BaseLLMBot:
    def __init__(self, user_data_dir=None, headless=False):
        self.options = uc.ChromeOptions()
        
        self.options.add_argument("--disable-dev-shm-usage")
        if headless:
            self.options.add_argument("--headless")
            
        try:
            logger.info("Initializing Undetected Chrome Driver...")
            self.driver = uc.Chrome(
                options=self.options,
                user_data_dir=user_data_dir,
                version_main=150
            )
            self.driver.set_page_load_timeout(60)
            logger.info("Chrome Driver initialized successfully.")
        except Exception as e:
            logger.error(f"Failed to initialize Chrome Driver: {e}")
            raise

        self.wait = WebDriverWait(self.driver, 30)

    def close(self):
        if self.driver:
            self.driver.quit()

class ChatGPTBot(BaseLLMBot):
    def start_new_chat(self):
        logger.info("Navigating to ChatGPT...")
        self.driver.get("https://chatgpt.com/")
        
        # Check if login button is present
        try:
            time.sleep(3) # Wait a bit for the page and UI to load
            login_buttons = self.driver.find_elements(By.CSS_SELECTOR, "[data-testid='login-button']")
            login_links = [e for e in self.driver.find_elements(By.TAG_NAME, "a") if "login" in (e.get_attribute("href") or "").lower()]
            if login_buttons or login_links:
                logger.info("ChatGPT login required. Waiting up to 600 seconds for manual login on the browser window...")
                wait_long = WebDriverWait(self.driver, 600)
                # Wait until both buttons and links disappear (meaning user logged in)
                if login_buttons:
                    wait_long.until_not(EC.presence_of_element_located((By.CSS_SELECTOR, "[data-testid='login-button']")))
                if login_links:
                    def no_login_links(driver):
                        return not any("login" in (e.get_attribute("href") or "").lower() for e in driver.find_elements(By.TAG_NAME, "a"))
                    wait_long.until(no_login_links)
                
                logger.info("ChatGPT login successful (login elements disappeared).")
                time.sleep(3) # Wait for reload after login
        except Exception as e:
            logger.warning(f"Error while checking login state: {e}")

        logger.info("Waiting for ChatGPT input box... If you are still not logged in, please log in now.")
        wait_long = WebDriverWait(self.driver, 600)
        try:
            wait_long.until(EC.element_to_be_clickable((By.CSS_SELECTOR, "div[contenteditable='true'], textarea#prompt-textarea")))
            logger.info("ChatGPT loaded successfully.")
        except Exception as e:
            logger.error("Timed out waiting for ChatGPT login.")
            raise e

    def send_message(self, message):
        logger.info(f"Sending message to ChatGPT: {message[:50]}...")
        try:
            input_box = self.wait.until(EC.presence_of_element_located((By.CSS_SELECTOR, "div[contenteditable='true'], textarea#prompt-textarea")))
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
                logger.error(f"Could not find or click Send button: {e}")
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
                responses = self.driver.find_elements(By.CSS_SELECTOR, "div[data-message-author-role='assistant']")
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
        
        logger.info("Waiting for Claude input box... If you are not logged in, please log in now on the browser window.")
        wait_long = WebDriverWait(self.driver, 600)
        try:
            wait_long.until(EC.element_to_be_clickable((By.CSS_SELECTOR, "div[contenteditable='true']")))
            logger.info("Claude loaded successfully.")
        except Exception as e:
            self.driver.save_screenshot("claude_error.png")
            logger.error("Timed out waiting for Claude login. Screenshot saved.")
            raise e

    def send_message(self, message):
        logger.info(f"Sending message to Claude: {message[:50]}...")
        try:
            # Try to get current message count to track response
            try:
                # Claude's message blocks often have grid or flex classes, let's just count all paragraphs inside prose
                existing_msgs = self.driver.find_elements(By.CSS_SELECTOR, ".ProseMirror p, div[data-test-render-count]")
                self.last_msg_count = len(existing_msgs)
            except:
                self.last_msg_count = 0

            # Find the new tiptap editor
            input_box = self.wait.until(EC.presence_of_element_located((By.CSS_SELECTOR, "div[contenteditable='true']")))
            
            # Click it (using JS to bypass any overlapping overlays)
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
            
            # Send using ENTER key since button selectors change frequently
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
                # Look for Claude's response blocks
                responses = self.driver.find_elements(By.CSS_SELECTOR, "div.font-claude-message, div.font-user-message + div, .ProseMirror:not([contenteditable='true'])")
                
                if not responses:
                    time.sleep(2)
                    continue
                
                latest_response = responses[-1]
                current_text = latest_response.text
                
                if len(current_text) > last_text_len:
                    last_text_len = len(current_text)
                    stable_count = 0
                else:
                    stable_count += 1
                
                # If stable for 10 seconds and has text, we consider it done
                if stable_count > 10 and last_text_len > 0:
                    return current_text
                time.sleep(1)
            except Exception as e:
                logger.warning(f"Error reading response: {e}")
                time.sleep(1)

        self.driver.save_screenshot("claude_timeout_error.png")
        html = self.driver.page_source
        with open("claude_timeout_body.html", "w", encoding="utf-8") as f:
            f.write(html)
        raise TimeoutError("Timed out waiting for Claude response. Screenshot saved.")
