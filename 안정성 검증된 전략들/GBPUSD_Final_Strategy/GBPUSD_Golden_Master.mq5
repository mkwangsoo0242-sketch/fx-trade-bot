//+------------------------------------------------------------------+
//|                                   GBPUSD_Golden_Master.mq5       |
//|                                  Copyright 2026, Antigravity AI  |
//|                                     Updated: London Trend Beast  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Antigravity AI"
#property version   "2.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\AccountInfo.mqh>

void SendStatus() {
   string pos_json = ""; int pCount = 0;
   for(int i=0; i<PositionsTotal(); i++) {
      ulong t = PositionGetTicket(i);
      if(PositionSelectByTicket(t) && PositionGetInteger(POSITION_MAGIC) == InpMagicNum) {
         if(pCount > 0) pos_json += ",";
         pos_json += "{\"ticket\":"+IntegerToString(t)+",\"symbol\":\""+_Symbol+"\",\"time\":\""+TimeToString(PositionGetInteger(POSITION_TIME))+"\",\"type\":\""+(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?"buy":"sell")+"\",\"vol\":"+DoubleToString(PositionGetDouble(POSITION_VOLUME),2)+",\"open\":"+DoubleToString(PositionGetDouble(POSITION_PRICE_OPEN),5)+",\"sl\":"+DoubleToString(PositionGetDouble(POSITION_SL),5)+",\"tp\":"+DoubleToString(PositionGetDouble(POSITION_TP),5)+",\"cur\":"+DoubleToString(PositionGetDouble(POSITION_PRICE_CURRENT),5)+",\"pnl\":"+DoubleToString(PositionGetDouble(POSITION_PROFIT),2)+"}";
         pCount++;
      }
   }
   string json = "{\"strategy\":\"GBPUSD Golden Master\",\"balance\":"+DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE),2)+",\"equity\":"+DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY),2)+",\"margin\":"+DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN),2)+",\"free_margin\":"+DoubleToString(AccountInfoDouble(ACCOUNT_FREEMARGIN),2)+",\"margin_level\":"+DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN_LEVEL),2)+",\"positions\":["+pos_json+"]}";
   char data[], result[]; string hd="Content-Type: application/json\r\n", rh;
   StringToCharArray(json, data, 0, WHOLE_ARRAY, CP_UTF8);
   WebRequest("POST", "http://172.21.22.224:5555", hd, 50, data, result, rh);
}

//--- INPUT PARAMETERS
input group             "Risk Management"
input double            InpRiskPercent = 5.0;       // Risk per Trade (%) - Optimal for consistency
input int               InpMagicNum    = 888002;    // Magic Number

input group             "Strategy Settings"
input int               InpStartHour   = 8;         // London Open Hour (UTC)
input double            InpTPRatio     = 2.0;       // TP = SL * 2.0
input int               InpEMAPeriod   = 200;       // Trend Filter Period

//--- GLOBAL VARIABLES
CTrade         trade;
CSymbolInfo    symbolInfo;
CAccountInfo   accountInfo;
int            handleEMA;
bool           traded_today = false;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   if(!symbolInfo.Name(Symbol())) return(INIT_FAILED);
   
   handleEMA = iMA(Symbol(), Period(), InpEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   if(handleEMA == INVALID_HANDLE) return(INIT_FAILED);
   
   trade.SetExpertMagicNumber(InpMagicNum);
   EventSetTimer(1);
   Print("🚀 GBP/USD Golden Master V2 (London Trend) Initialized.");
   return(INIT_SUCCEEDED);
}
void OnTimer() { SendStatus(); }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(handleEMA);
}

//+------------------------------------------------------------------+
//| OnTick function                                                  |
//+------------------------------------------------------------------+
void OnTick()
{
   SendStatus();
   MqlDateTime dt;
   TimeCurrent(dt);
   
   // Reset daily flag at midnight
   static int last_day = -1;
   if(dt.day != last_day) {
      traded_today = false;
      last_day = dt.day;
   }
   
   // Check Hour
   if(dt.hour != InpStartHour) return;
   if(traded_today) return;
   if(PositionsTotal() > 0) return; // Manage one trade at a time for safety
   
   // Get Data
   double ema[];
   ArraySetAsSeries(ema, true);
   if(CopyBuffer(handleEMA, 0, 0, 2, ema) < 2) return;
   
   // Previous Hour High/Low (07:00 Candle)
   double h1_high = iHigh(Symbol(), PERIOD_H1, 1);
   double h1_low  = iLow(Symbol(), PERIOD_H1, 1);
   double close_1 = iClose(Symbol(), PERIOD_H1, 1); // Previous candle close for trend check
   
   double range = h1_high - h1_low;
   if(range < 10 * _Point) return; // Filter tiny volatility
   
   double cur_price = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
   
   // Strategy Logic:
   // 1. Trend Filter: Previous Close > EMA -> UP, < EMA -> DOWN
   // 2. Breakout: Current Price > Prev High -> BUY
   
   bool trend_up   = (close_1 > ema[1]);
   bool trend_down = (close_1 < ema[1]);
   
   // BUY Logic
   if(trend_up && cur_price > h1_high) {
      ExecuteTrade(ORDER_TYPE_BUY, h1_high, h1_low);
      traded_today = true;
   }
   // SELL Logic
   else if(trend_down && cur_price < h1_low) {
      ExecuteTrade(ORDER_TYPE_SELL, h1_low, h1_high);
      traded_today = true;
   }
}

//+------------------------------------------------------------------+
//| Trade Execution                                                  |
//+------------------------------------------------------------------+
void ExecuteTrade(ENUM_ORDER_TYPE type, double entry, double sl_level) {
   double price = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(Symbol(), SYMBOL_ASK) : SymbolInfoDouble(Symbol(), SYMBOL_BID);
   
   double sl_dist = MathAbs(entry - sl_level);
   double tp_dist = sl_dist * InpTPRatio;
   
   double sl = (type == ORDER_TYPE_BUY) ? price - sl_dist : price + sl_dist;
   double tp = (type == ORDER_TYPE_BUY) ? price + tp_dist : price - tp_dist;
   
   // Risk Calc
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk_money = balance * (InpRiskPercent / 100.0);
   
   double tick_val = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
   double tick_size = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
   
   // Lot = Risk / (SL_Dist * TickVal / TickSize)
   double lot = risk_money / (sl_dist / tick_size * tick_val);
   
   // Normalize Lot
   double step = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
   lot = MathFloor(lot / step) * step;
   
   double min_lot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
   double max_lot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
   
   if(lot < min_lot) lot = min_lot;
   if(lot > max_lot) lot = max_lot; 
   
   trade.PositionOpen(Symbol(), type, lot, price, sl, tp, "GBPUSD Master V2");
}
