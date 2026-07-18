@echo off
cd /d "%~dp0"
echo Starting Council Run > council_log.txt
python run_council_gui.py >> council_log.txt 2>&1
echo Done >> council_log.txt
