import argparse
import logging
import time
import undetected_chromedriver as uc

logging.basicConfig(level=logging.INFO, format='%(message)s')
logger = logging.getLogger(__name__)

def main():
    parser = argparse.ArgumentParser(description="AI Council 초기 셋업: 챗봇 로그인을 위한 세션 생성기")
    parser.add_argument("--profile-dir", "-d", default="./chrome_profile", help="저장할 크롬 프로필 디렉토리 경로 (기본값: ./chrome_profile)")
    parser.add_argument("--chrome-version", "-v", type=int, default=None, help="현재 설치된 크롬의 주요 버전 번호 (예: 125, 126, 130 등). 생략 시 자동 감지")
    args = parser.parse_args()

    logger.info("="*50)
    logger.info("🚀 AI Council 초기 로그인 셋업을 시작합니다.")
    logger.info("이 작업은 최초 1회만 수행하면 되며, 로그인된 쿠키 정보를 안전하게 저장합니다.")
    logger.info("="*50)
    
    options = uc.ChromeOptions()
    options.add_argument("--disable-dev-shm-usage")
    # 화면을 보여줘야 사람이 로그인할 수 있으므로 headless 모드는 사용하지 않음

    try:
        logger.info(f"초기화 중... (저장 경로: {args.profile_dir})")
        if args.chrome_version:
            driver = uc.Chrome(options=options, user_data_dir=args.profile_dir, version_main=args.chrome_version)
        else:
            driver = uc.Chrome(options=options, user_data_dir=args.profile_dir)
            
        driver.set_page_load_timeout(60)
        
        logger.info("\n✅ 1/2. ChatGPT 로그인을 진행합니다...")
        driver.get("https://chatgpt.com")
        input("👉 브라우저 창에서 ChatGPT 로그인을 완료한 후, 터미널 창에서 [ENTER] 키를 누르세요...")

        logger.info("\n✅ 2/2. Claude 로그인을 진행합니다...")
        driver.get("https://claude.ai/new")
        input("👉 브라우저 창에서 Claude 로그인을 완료한 후, 터미널 창에서 [ENTER] 키를 누르세요...")

        logger.info("\n🎉 모든 셋업이 완료되었습니다! 안전하게 브라우저를 종료합니다.")
        driver.quit()
        logger.info(f"\n💡 이제부터는 'python ai_council/council_runner.py' 명령어를 통해 봇이 백그라운드에서 자동 구동됩니다!")

    except Exception as e:
        logger.error(f"오류가 발생했습니다: {e}")

if __name__ == "__main__":
    main()
