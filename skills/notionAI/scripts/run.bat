@echo off
set NODE_EXTRA_CA_CERTS=E:\AK\support\support\Dobi_Slackbot\neople-ca.pem
set PLAYWRIGHT_BROWSERS_PATH=%USERPROFILE%\AppData\Local\ms-playwright
cd /d %~dp0
npx tsx %*
