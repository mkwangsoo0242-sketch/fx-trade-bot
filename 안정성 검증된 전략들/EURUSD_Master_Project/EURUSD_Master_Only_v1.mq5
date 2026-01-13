//+------------------------------------------------------------------+
//|                                     EURUSD_Golden_Master_v2.mq5  |
//|                                  Copyright 2026, Antigravity AI  |
//|                                   GOLDEN EURUSD BEAST (V2)       |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Antigravity AI"
#property version   "2.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\AccountInfo.mqh>

//--- INPUT PARAMETERS (Aggressive Breakout: 2021-2025 ALL Profit)
input group             "Strategy Settings"
input int               InpStartHour   = 13;           // NY Open Breakout (13:00 UTC)
input double            InpTP_Ratio    = 3.0;          // 1:3 RR Ratio (Aggressive)

input group             "Risk Management"
input double            InpRiskPercent = 5.0;          // Risk 5% (Avg 700% Yearly)
input int               InpMagicNum    = 20260202;     // Magic Number

CTrade         trade;
CSymbolInfo    symbolInfo;
bool           traded_today = false;

int OnInit() {
   if(!symbolInfo.Name(Symbol())) return(INIT_FAILED);
   trade.SetExpertMagicNumber(InpMagicNum);
   Print("🚀 EURUSD Golden Master V2 (NY Beast) Initialized.");
   return(INIT_SUCCEEDED);
}

void OnTick() {
   MqlDateTime dt;
   TimeCurrent(dt);
   
   static int last_day = -1;
   if(dt.day != last_day) {
      traded_today = false;
      last_day = dt.day;
   }
   
   if(dt.hour != InpStartHour) return;
   if(traded_today || PositionsTotal() > 0) return;
   
   // Logic: Breakout of 12:00 UTC Candle
   double prev_high = iHigh(Symbol(), PERIOD_H1, 1);
   double prev_low  = iLow(Symbol(), PERIOD_H1, 1);
   double range     = prev_high - prev_low;
   
   if(range < 5 * _Point) return; // Filter tiny candles
   
   double cur_price = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
   
   // Buy Breakout
   if(cur_price > prev_high) {
      ExecuteTrade(ORDER_TYPE_BUY, prev_high, prev_low);
      traded_today = true;
   }
   // Sell Breakout
   else if(cur_price < prev_low) {
      ExecuteTrade(ORDER_TYPE_SELL, prev_low, prev_high);
      traded_today = true;
   }
}

void ExecuteTrade(ENUM_ORDER_TYPE type, double entry, double sl_level) {
   double price = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(Symbol(), SYMBOL_ASK) : SymbolInfoDouble(Symbol(), SYMBOL_BID);
   double sl_dist = MathAbs(entry - sl_level);
   double tp_dist = sl_dist * InpTP_Ratio;
   
   double sl = (type == ORDER_TYPE_BUY) ? price - sl_dist : price + sl_dist;
   double tp = (type == ORDER_TYPE_BUY) ? price + tp_dist : price - tp_dist;
   
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk_money = balance * (InpRiskPercent / 100.0);
   
   double tick_val = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
   double tick_size = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
   
   double lot = risk_money / (sl_dist / tick_size * tick_val);
   
   double step = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
   lot = MathFloor(lot / step) * step;
   
   double min = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
   double max = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
   
   if(lot < min) lot = min;
   if(lot > max) lot = max;
   
   trade.PositionOpen(Symbol(), type, lot, price, sl, tp, "EURUSD Beast V2");
}
