import pandas as pd

try:
    import MetaTrader5 as mt5
    MT5_AVAILABLE = True
except ImportError:
    MT5_AVAILABLE = False

from config import Config

def initialize_mt5():
    if not MT5_AVAILABLE:
        print("MetaTrader5 라이브러리를 사용할 수 없는 환경(Linux 등)입니다.")
        return False
        
    if not mt5.initialize(login=Config.LOGIN, password=Config.PASSWORD, server=Config.SERVER):
        print("MetaTrader5 초기화 실패, 에러 코드 =", mt5.last_error())
        return False
    
    print(f"MT5 연결 성공! 계좌: {Config.LOGIN}")
    return True

def connect_mt5():
    if initialize_mt5():
        return mt5
    return None

def get_data(symbol, timeframe, n=500):
    """MT5 또는 Yahoo Finance에서 데이터를 가져옴"""
    from strategy import get_ohlcv
    return get_ohlcv(symbol, timeframe, n)

def shutdown_mt5():
    if MT5_AVAILABLE:
        mt5.shutdown()
