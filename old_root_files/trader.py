import MetaTrader5 as mt5
from config import Config

class MT5Trader:
    def __init__(self):
        self.mt5 = mt5

    def open_position(self, symbol, action, sl_price=None, tp_price=None):
        """포지션 진입 (동적 랏 사이즈 적용)"""
        if self.mt5 is None:
            print(f"[{symbol}] 라이브 거래 불가: MT5 미연결")
            return None
            
        # 잔고 기반 동적 랏 사이즈 계산 (계좌 잔고의 1% 리스크)
        account_info = self.mt5.account_info()
        lot = Config.LOT
        
        if account_info and sl_price:
            balance = account_info.balance
            risk_amount = balance * (Config.RISK_PERCENT / 100)
            
            # 현재가와 손절가 차이 계산
            tick = self.mt5.symbol_info_tick(symbol)
            current_price = tick.ask if action == "BUY" else tick.bid
            price_diff = abs(current_price - sl_price)
            
            if price_diff > 0:
                symbol_info = self.mt5.symbol_info(symbol)
                if symbol_info:
                    # 리스크 금액에 맞춘 랏 사이즈 계산
                    # JPY 페어 여부에 따라 scale 조정
                    is_jpy = "JPY" in symbol
                    scale = 100 if is_jpy else 10000
                    pip_value = 10
                    
                    lot = risk_amount / (price_diff * scale * pip_value)
                    lot = round(lot, 2)
                    lot = max(0.01, min(lot, 100.0)) # 최대 100.0 랏으로 상향

        order_type = self.mt5.ORDER_TYPE_BUY if action == "BUY" else self.mt5.ORDER_TYPE_SELL
        price = self.mt5.symbol_info_tick(symbol).ask if action == "BUY" else self.mt5.symbol_info_tick(symbol).bid
        
        request = {
            "action": self.mt5.TRADE_ACTION_DEAL,
            "symbol": symbol,
            "volume": float(lot),
            "type": order_type,
            "price": price,
            "sl": float(sl_price) if sl_price else 0.0,
            "tp": float(tp_price) if tp_price else 0.0,
            "magic": Config.MAGIC_NUMBER,
            "comment": "FX Bot Enhanced",
            "type_time": self.mt5.ORDER_TIME_GTC,
            "type_filling": self.mt5.ORDER_FILLING_IOC,
        }
        
        result = self.mt5.order_send(request)
        if result.retcode != self.mt5.TRADE_RETCODE_DONE:
            print(f"[{symbol}] 주문 실패: {result.comment}")
        return result

    def update_trailing_stops(self, df_dict):
        """현재 열린 포지션들의 트레일링 스탑 업데이트 (ATR 기반)"""
        if self.mt5 is None: return
        
        positions = self.mt5.positions_get(magic=Config.MAGIC_NUMBER)
        if not positions: return
        
        for pos in positions:
            symbol = pos.symbol
            if symbol not in df_dict: continue
            
            df = df_dict[symbol]
            if df.empty: continue
            
            from strategy import prepare_indicators
            # 라이브 거래 시 세션 필터는 strategy.py에 포함되어 있음
            df = prepare_indicators(df)
            last_row = df.iloc[-1]
            atr = last_row['atr']
            
            tick = self.mt5.symbol_info_tick(symbol)
            if not tick: continue
            
            if pos.type == self.mt5.POSITION_TYPE_BUY:
                # 매수 포지션: 고점 갱신 시 SL 상향
                # 현재가(bid) 기준으로 trailing stop 계산
                new_sl = tick.bid - (atr * Config.TRAILING_STOP_ATR)
                if new_sl > pos.sl:
                    self._modify_sl(pos.ticket, new_sl)
                    print(f"[{symbol}] 매수 트레일링 스탑 상향: {pos.sl} -> {new_sl}")
                    
            elif pos.type == self.mt5.POSITION_TYPE_SELL:
                # 매도 포지션: 저점 갱신 시 SL 하향
                new_sl = tick.ask + (atr * Config.TRAILING_STOP_ATR)
                if pos.sl == 0 or new_sl < pos.sl:
                    self._modify_sl(pos.ticket, new_sl)
                    print(f"[{symbol}] 매도 트레일링 스탑 하향: {pos.sl} -> {new_sl}")

    def _modify_sl(self, ticket, sl):
        request = {
            "action": self.mt5.TRADE_ACTION_SLTP,
            "position": ticket,
            "sl": float(sl)
        }
        self.mt5.order_send(request)
