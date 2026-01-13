from connection import connect_mt5
from strategy import eurusd_enhanced_strategy, prepare_indicators
from trader import MT5Trader
from config import Config
import time

def main():
    mt5 = connect_mt5()
    if not mt5:
        print("MT5 연결 실패. 설정을 확인해주세요.")
        return
        
    trader = MT5Trader()
    
    print(f"FX 봇 가동 시작... (감시 대상: {Config.SYMBOLS})")
    
    while True:
        try:
            # 모든 통화쌍의 최신 데이터 수집
            from connection import get_data
            df_dict = {}
            for symbol in Config.SYMBOLS:
                df = get_data(symbol, Config.TIMEFRAME, 500)
                if df is not None and not df.empty:
                    df_dict[symbol] = df
            
            # 1. 트레일링 스탑 업데이트
            trader.update_trailing_stops(df_dict)
            
            # 2. 각 통화쌍별 전략 체크
            for symbol, df in df_dict.items():
                # 지표 계산 및 전략 실행
                df = prepare_indicators(df)
                signal = eurusd_enhanced_strategy(df, already_prepared=True)
                    
                # 현재 포지션 확인
                if mt5:
                    positions = mt5.positions_get(symbol=symbol, magic=Config.MAGIC_NUMBER)
                    
                    if not positions:
                        last_row = df.iloc[-1]
                        atr = last_row['atr']
                        
                        if signal == "BUY":
                            sl = last_row['close'] - (atr * Config.SL_ATR_MULT)
                            tp = last_row['close'] + (atr * Config.TP_ATR_MULT)
                            # M1 스캘핑에서는 즉시 진입이 중요하므로 로깅 후 진입
                            print(f"[{symbol}] M1 매수 시그널 발생! Price={last_row['close']}, ATR={atr:.5f}")
                            trader.open_position(symbol, "BUY", sl, tp)
                            
                        elif signal == "SELL":
                            sl = last_row['close'] + (atr * Config.SL_ATR_MULT)
                            tp = last_row['close'] - (atr * Config.TP_ATR_MULT)
                            print(f"[{symbol}] M1 매도 시그널 발생! Price={last_row['close']}, ATR={atr:.5f}")
                            trader.open_position(symbol, "SELL", sl, tp)
            
            # 10초 대기 (M1 차트 대응)
            time.sleep(10)
            
        except Exception as e:
            print(f"에러 발생: {e}")
            time.sleep(10)

if __name__ == "__main__":
    main()
