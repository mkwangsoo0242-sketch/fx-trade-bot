import pandas as pd
import numpy as np
from strategy import get_ohlcv as get_data, prepare_indicators, eurusd_enhanced_strategy
from config import Config

def run_integrated_backtest(initial_balance=10000, csv_file=None):
    print("="*50)
    print(f"   통합 멀티 페어 병렬 백테스트 시작 (잔고: ${initial_balance})")
    print("="*50)
    
    # 1. 모든 페어 데이터 수집 및 지표 계산
    df_dict = {}
    
    if csv_file:
        print(f"CSV 파일 {csv_file}에서 데이터를 로드합니다...")
        try:
            df = pd.read_csv(csv_file)
            # MT5 내보내기 형식에 맞춰 컬럼명 표준화
            df.columns = [c.lower().replace("<", "").replace(">", "") for c in df.columns]
            if 'time' not in df.columns and 'datetime' in df.columns:
                df = df.rename(columns={'datetime': 'time'})
            elif 'date' in df.columns and 'time' in df.columns:
                df['time'] = pd.to_datetime(df['date'] + ' ' + df['time'])
            
            df['time'] = pd.to_datetime(df['time'])
            df = prepare_indicators(df)
            df = df.dropna().reset_index(drop=True)
            # 파일 이름이나 컬럼에서 심볼 추출 (없으면 기본값)
            symbol = "EURUSD" 
            df_dict[symbol] = df
        except Exception as e:
            print(f"CSV 로드 에러: {e}")
            return
    else:
        for symbol in Config.SYMBOLS:
            print(f"[{symbol}] 데이터 로딩 중...")
            df = get_data(symbol, Config.TIMEFRAME, 10000)
            if df is not None and not df.empty:
                df = prepare_indicators(df)
                df = df.dropna().reset_index(drop=True)
                df_dict[symbol] = df
            
    if not df_dict:
        print("데이터를 불러올 수 없습니다.")
        return
        
    # 2. 모든 데이터의 공통 시간 범위 찾기
    all_times = sorted(list(set().union(*[df['time'].tolist() for df in df_dict.values()])))
    
    balance = initial_balance
    positions = {} # {symbol: {"type": 1/-1, "entry_price": p, "sl": s, "tp": t, "lot": l}}
    trades = []
    pip_value = 10
    
    print(f"총 {len(all_times)}개 타임스텝 진행...")
    
    for current_time in all_times:
        if balance <= 0:
            print("!!! 파산 !!!")
            balance = 0
            break
            
        for symbol, df in df_dict.items():
            # 현재 시간에 해당하는 데이터 행 찾기
            row_idx = df.index[df['time'] == current_time]
            if len(row_idx) == 0: continue
            
            idx = row_idx[0]
            if idx < 1: continue
            
            last_row = df.loc[idx]
            prev_row = df.loc[idx-1]
            
            is_jpy = "JPY" in symbol
            scale = 100 if is_jpy else 10000
            
            # --- 1. 포지션 관리 ---
            if symbol in positions:
                pos = positions[symbol]
                
                if pos['type'] == 1: # 매수 포지션
                    # 청산 조건 체크
                    if last_row['low'] <= pos['sl']:
                        profit = (pos['sl'] - pos['entry_price']) * scale * pip_value * pos['lot']
                        balance += profit
                        trades.append({"symbol": symbol, "profit": profit, "time": current_time})
                        del positions[symbol]
                        continue
                    elif last_row['high'] >= pos['tp']:
                        profit = (pos['tp'] - pos['entry_price']) * scale * pip_value * pos['lot']
                        balance += profit
                        trades.append({"symbol": symbol, "profit": profit, "time": current_time})
                        del positions[symbol]
                        continue
                elif pos['type'] == -1: # 매도 포지션
                    # 청산 조건 체크
                    if last_row['high'] >= pos['sl']:
                        profit = (pos['entry_price'] - pos['sl']) * scale * pip_value * pos['lot']
                        balance += profit
                        trades.append({"symbol": symbol, "profit": profit, "time": current_time})
                        del positions[symbol]
                        continue
                    elif last_row['low'] <= pos['tp']:
                        profit = (pos['entry_price'] - pos['tp']) * scale * pip_value * pos['lot']
                        balance += profit
                        trades.append({"symbol": symbol, "profit": profit, "time": current_time})
                        del positions[symbol]
                        continue
            
            # --- 2. 진입 로직 ---
            if symbol not in positions and balance > 0:
                # 데이터프레임의 현재까지의 데이터만 전달 (Look-ahead bias 방지)
                current_df = df.iloc[:idx+1]
                signal = eurusd_enhanced_strategy(current_df, already_prepared=True, symbol=symbol)
                
                if signal == "HOLD":
                    continue
                
                atr = last_row['atr']
                if atr == 0: continue
                
                sl_dist = atr * Config.SL_ATR_MULT
                tp_dist = atr * Config.TP_ATR_MULT
                
                if signal == "BUY":
                    risk_amount = balance * (Config.RISK_PERCENT / 100)
                    lot_size = risk_amount / (sl_dist * scale * pip_value)
                    lot_size = min(500.0, max(0.01, round(lot_size, 2)))
                    
                    positions[symbol] = {
                        "type": 1,
                        "entry_price": last_row['close'],
                        "sl": last_row['close'] - sl_dist,
                        "tp": last_row['close'] + tp_dist,
                        "lot": lot_size
                    }
                    
                elif signal == "SELL":
                    risk_amount = balance * (Config.RISK_PERCENT / 100)
                    lot_size = risk_amount / (sl_dist * scale * pip_value)
                    lot_size = min(500.0, max(0.01, round(lot_size, 2)))
                    
                    positions[symbol] = {
                        "type": -1,
                        "entry_price": last_row['close'],
                        "sl": last_row['close'] + sl_dist,
                        "tp": last_row['close'] - tp_dist,
                        "lot": lot_size
                    }

    # 결과 출력
    print("\n" + "="*50)
    print("      통합 병렬 백테스트 결과      ")
    print("="*50)
    print(f"최종 잔고: ${balance:.2f}")
    print(f"수익률: {((balance - initial_balance) / initial_balance * 100):.2f}%")
    print(f"총 거래 횟수: {len(trades)}회")
    
    if trades:
        win_trades = [t for t in trades if t['profit'] > 0]
        win_rate = len(win_trades) / len(trades) * 100
        print(f"승률: {win_rate:.2f}%")
        
        # 페어별 성과
        symbol_stats = {}
        for t in trades:
            sym = t['symbol']
            if sym not in symbol_stats:
                symbol_stats[sym] = {"profit": 0, "count": 0, "wins": 0}
            symbol_stats[sym]["profit"] += t['profit']
            symbol_stats[sym]["count"] += 1
            if t['profit'] > 0:
                symbol_stats[sym]["wins"] += 1
        
        print("\n[페어별 성과]")
        for sym, stats in sorted(symbol_stats.items(), key=lambda x: x[1]['profit'], reverse=True):
            win_rate = (stats['wins'] / stats['count'] * 100) if stats['count'] > 0 else 0
            print(f"- {sym}: ${stats['profit']:.2f} (거래 {stats['count']}회, 승률 {win_rate:.2f}%)")
    
    print("="*50)

if __name__ == "__main__":
    run_integrated_backtest()
