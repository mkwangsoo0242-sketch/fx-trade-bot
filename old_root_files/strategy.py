import pandas as pd
import numpy as np
try:
    import MetaTrader5 as mt5
    MT5_AVAILABLE = True
except ImportError:
    MT5_AVAILABLE = False
    
import yfinance as yf
from config import Config

def get_ohlcv(symbol, timeframe, n=100):
    # MT5를 사용할 수 있는 경우 (Windows)
    if MT5_AVAILABLE:
        tf_map = {
            "M1": mt5.TIMEFRAME_M1,
            "M5": mt5.TIMEFRAME_M5,
            "M15": mt5.TIMEFRAME_M15,
            "H1": mt5.TIMEFRAME_H1,
            "D1": mt5.TIMEFRAME_D1,
        }
        rates = mt5.copy_rates_from_pos(symbol, tf_map.get(timeframe, mt5.TIMEFRAME_M15), 0, n)
        if rates is not None:
            df = pd.DataFrame(rates)
            df['time'] = pd.to_datetime(df['time'], unit='s')
            return df

    # MT5를 사용할 수 없거나 데이터 수집 실패 시 Yahoo Finance 사용 (Linux/Backtest용)
    print(f"Yahoo Finance에서 {symbol} 데이터를 가져옵니다...")
    yf_symbol = f"{symbol[:3]}{symbol[3:]}=X" # EURUSD -> EURUSD=X
    
    interval_map = {
        "M1": "1m", "M5": "5m", "M15": "15m", "H1": "1h", "D1": "1d"
    }
    
    # Yahoo Finance 제약사항: 1분 데이터는 7일, 5/15분 데이터는 60일까지 가능
    if timeframe == "M1":
        download_period = "7d"
    elif timeframe in ["M5", "M15"]:
        download_period = "60d"
    else:
        download_period = "1y"
    
    data = yf.download(yf_symbol, period=download_period, interval=interval_map.get(timeframe, "15m"))
    if data.empty:
        return pd.DataFrame()
        
    df = data.reset_index()
    
    # MultiIndex 컬럼 처리 (yfinance 최신 버전 대응)
    if isinstance(df.columns, pd.MultiIndex):
        df.columns = [c[0] if isinstance(c, tuple) and c[0] else c for c in df.columns]
    
    df.columns = [str(c).lower() for c in df.columns]
    if 'datetime' in df.columns:
        df = df.rename(columns={'datetime': 'time'})
    elif 'date' in df.columns:
        df = df.rename(columns={'date': 'time'})
        
    return df.tail(n)

def calculate_rsi(df, period=14):
    delta = df['close'].diff()
    gain = (delta.where(delta > 0, 0)).rolling(window=period).mean()
    loss = (-delta.where(delta < 0, 0)).rolling(window=period).mean()
    
    rs = gain / loss
    rsi = 100 - (100 / (1 + rs))
    return rsi

def calculate_atr(df, period=14):
    high_low = df['high'] - df['low']
    high_close = (df['high'] - df['close'].shift()).abs()
    low_close = (df['low'] - df['close'].shift()).abs()
    ranges = pd.concat([high_low, high_close, low_close], axis=1)
    true_range = ranges.max(axis=1)
    return true_range.rolling(window=period).mean()

def calculate_adx(df, period=14):
    df = df.copy()
    df['tr'] = calculate_atr(df, 1)
    df['up_move'] = df['high'].diff()
    df['down_move'] = df['low'].shift() - df['low']
    
    df['plus_dm'] = np.where((df['up_move'] > df['down_move']) & (df['up_move'] > 0), df['up_move'], 0)
    df['minus_dm'] = np.where((df['down_move'] > df['up_move']) & (df['down_move'] > 0), df['down_move'], 0)
    
    df['plus_di'] = 100 * (df['plus_dm'].rolling(window=period).mean() / df['tr'].rolling(window=period).mean())
    df['minus_di'] = 100 * (df['minus_dm'].rolling(window=period).mean() / df['tr'].rolling(window=period).mean())
    
    df['dx'] = 100 * (abs(df['plus_di'] - df['minus_di']) / (df['plus_di'] + df['minus_di']))
    df['adx'] = df['dx'].rolling(window=period).mean()
    return df['adx']

def prepare_indicators(df):
    # Only keep indicators used in FX_Bot_Scalper.mq5 v9.6
    
    # EMA
    df['ema_fast'] = df['close'].ewm(span=Config.EMA_FAST, adjust=False).mean()
    df['ema_slow'] = df['close'].ewm(span=Config.EMA_SLOW, adjust=False).mean()
    df['ema_trend'] = df['close'].ewm(span=Config.EMA_TREND, adjust=False).mean()
    
    # RSI
    df['rsi'] = calculate_rsi(df, Config.RSI_PERIOD)
    
    # ATR
    df['atr'] = calculate_atr(df, Config.ATR_PERIOD)

    # ADX
    df['adx'] = calculate_adx(df, Config.ADX_PERIOD)
    
    return df

def eurusd_enhanced_strategy(df, already_prepared=False, symbol="EURUSD"):
    """EUR/USD Professional Strategy v9.6 (True Pullback Entry)"""
    if not already_prepared:
        df = prepare_indicators(df)
    # Need at least 2 bars for previous completed bar (index -2)
    if 'ema_trend' not in df.columns or len(df) < 2:
        return "HOLD"
    
    # Use data from the previous completed bar (Index 1 in MQL5, iloc[-2] in Python)
    prev_bar = df.iloc[-2]
    
    # 1. EMA Trend Filter (Long term)
    use_trend = getattr(Config, 'USE_TREND_FILTER', False)
    # Check EMA 200 slope in Python too
    prev_prev_bar = df.iloc[-3] if len(df) >= 3 else prev_bar
    trend_buy = not use_trend or (prev_bar['close'] > prev_bar['ema_trend'] and prev_bar['ema_trend'] > prev_prev_bar['ema_trend'])
    trend_sell = not use_trend or (prev_bar['close'] < prev_bar['ema_trend'] and prev_bar['ema_trend'] < prev_prev_bar['ema_trend'])

    # 2. EMA Cross (Short term) & Gap
    # Define point early to avoid NameError
    point = 0.00001 if "JPY" not in symbol else 0.001
    ema_gap = getattr(Config, 'EMA_GAP_POINTS', 25.0) * point
    ema_aligned_buy = (prev_bar['ema_fast'] - prev_bar['ema_slow']) > ema_gap
    ema_aligned_sell = (prev_bar['ema_slow'] - prev_bar['ema_fast']) > ema_gap
    
    # 3. RSI Momentum (Pullback)
    rsi_buy_condition = prev_bar['rsi'] < Config.RSI_BUY_ZONE
    rsi_sell_condition = prev_bar['rsi'] > Config.RSI_SELL_ZONE
    
    # 4. Strength Filter (ADX) + Slope
    adx_ok = prev_bar['adx'] > Config.ADX_MIN and prev_bar['adx'] > prev_prev_bar['adx']

    # 5. Price Rejection (Near EMA)
    # Convert points to decimal (0.00001 for 5-digit)
    use_rejection = getattr(Config, 'USE_REJECTION', False)
    buffer = Config.REJECTION_BUFFER_POINTS * point
    
    # Buy: Price touched EMA area and closed above it (Pullback condition)
    price_rejection_buy = not use_rejection or (prev_bar['low'] <= (prev_bar['ema_fast'] + buffer) and prev_bar['close'] > prev_bar['ema_fast'])
    # Sell: Price touched EMA area and closed below it (Pullback condition)
    price_rejection_sell = not use_rejection or (prev_bar['high'] >= (prev_bar['ema_fast'] - buffer) and prev_bar['close'] < prev_bar['ema_fast'])

    # 6. Candlestick Confirmation (Optional but improves win rate)
    # For Buy, previous bar should be bullish or at least not extremely bearish
    candle_ok_buy = prev_bar['close'] >= prev_bar['open']
    candle_ok_sell = prev_bar['close'] <= prev_bar['open']

    # Combine conditions
    if trend_buy and ema_aligned_buy and rsi_buy_condition and adx_ok and price_rejection_buy and candle_ok_buy:
        return "BUY"
    elif trend_sell and ema_aligned_sell and rsi_sell_condition and adx_ok and price_rejection_sell and candle_ok_sell:
        return "SELL"
    
    return "HOLD"
