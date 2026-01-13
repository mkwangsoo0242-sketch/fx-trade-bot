import os
from dotenv import load_dotenv

load_dotenv()

class Config:
    LOGIN = int(os.getenv("MT5_LOGIN", 0))
    PASSWORD = os.getenv("MT5_PASSWORD", "")
    SERVER = os.getenv("MT5_SERVER", "")
    
    # 거래 설정 (v9.6 Optimized)
    SYMBOL = "EURUSD"
    SYMBOLS = ["EURUSD", "GBPUSD", "USDJPY", "USDCHF", "AUDUSD", "NZDUSD", "USDCAD"] 
    TIMEFRAME = "M5"  
    LOT = 0.01  
    MAGIC_NUMBER = 777888
    
    # 리스크 관리
    RISK_PERCENT = 2.0  
    SL_ATR_MULT = 1.5    
    TP_ATR_MULT = 2.0   
    
    # 지표 설정
    EMA_FAST = 12
    EMA_SLOW = 26
    EMA_TREND = 100
    RSI_PERIOD = 14
    ATR_PERIOD = 14
    ADX_PERIOD = 14
    ADX_MIN = 25         
    
    RSI_BUY_ZONE = 30   
    RSI_SELL_ZONE = 70  
    REJECTION_BUFFER_POINTS = 5.0
    EMA_GAP_POINTS = 10.0
    MAX_SPREAD = 20
    MAX_SLIPPAGE = 50
    
    # 트레일링 스탑
    USE_TRAILING = True
    TRAILING_STOP_POINTS = 80
    TRAILING_STEP_POINTS = 20
    
    # 본절 보호
    USE_BREAK_EVEN = True
    BREAK_EVEN_TRIGGER_ATR = 2.0
    
    # Time Filter
    START_HOUR = 9
    END_HOUR = 20
    
    # 전략 스위치
    USE_TREND_FILTER = True   
    USE_REJECTION = True      
