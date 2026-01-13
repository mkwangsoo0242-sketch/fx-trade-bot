import subprocess
import sys

def install(package):
    subprocess.check_call([sys.executable, "-m", "pip", "install", package])

if __name__ == "__main__":
    try:
        install("yfinance")
        install("pandas")
        install("numpy")
        install("python-dotenv")
        print("Installation successful!")
    except Exception as e:
        print(f"Error: {e}")
