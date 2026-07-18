import os
import sys
import shutil
import subprocess
import traceback

def ignore_files(dir, files):
    return [f for f in files if f.startswith('Singleton') or f.endswith('.lock') or f == 'Local State']

def main():
    try:
        user_data_dir = os.path.abspath('./chrome_profile')
        user_data_dir_copy = os.path.abspath('./chrome_profile_copy')

        print(f"Original Profile: {user_data_dir}")
        print(f"Copy Profile: {user_data_dir_copy}")

        # Clean existing copy
        if os.path.exists(user_data_dir_copy):
            try:
                shutil.rmtree(user_data_dir_copy)
            except Exception as e:
                print(f"Failed to clean existing copy: {e}")

        # Copy safe profile without locks
        print("Copying safe profile...")
        shutil.copytree(user_data_dir, user_data_dir_copy, ignore=ignore_files)

        # Build command to run the main council script
        cmd = [
            sys.executable,
            "council_runner.py",
            "-p", "council_prompt.txt",
            "-o", "council_result.md",
            "-u", user_data_dir_copy
        ]

        print("Executing council_runner.py in GUI mode...")
        result = subprocess.run(cmd, capture_output=True, text=True, encoding='utf-8')
        print(result.stdout)
        if result.stderr:
            print(result.stderr)
            
        print("SUCCESS")
    except Exception as e:
        traceback.print_exc()

if __name__ == '__main__':
    main()
