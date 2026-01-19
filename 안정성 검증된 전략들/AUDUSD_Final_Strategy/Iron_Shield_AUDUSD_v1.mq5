//+------------------------------------------------------------------+
//|                                     Iron_Shield_AUDUSD_v1.mq5    |
//|                                  Copyright 2026, Antigravity AI  |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Antigravity AI"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

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
   string json = "{\"strategy\":\"Iron Shield AUDUSD\",\"balance\":"+DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE),2)+",\"equity\":"+DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY),2)+",\"margin\":"+DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN),2)+",\"free_margin\":"+DoubleToString(AccountInfoDouble(ACCOUNT_FREEMARGIN),2)+",\"margin_level\":"+DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN_LEVEL),2)+",\"positions\":["+pos_json+"]}";
   char data[], result[]; string hd="Content-Type: application/json\r\n", rh;
   StringToCharArray(json, data, 0, WHOLE_ARRAY, CP_UTF8);
   WebRequest("POST", "http://172.21.22.224:5555", hd, 50, data, result, rh);
}

//--- INPUT PARAMETERS
input group             "Strategy Settings"
input int               InpEMAPeriod   = 200;          // EMA Period
input int               InpRSIPeriod   = 14;           // RSI Period
input int               InpRSILower    = 30;           // RSI Lower Level (Buy)
input int               InpRSIUpper    = 70;           // RSI Upper Level (Sell)

input group             "Risk Management"
input double            InpRiskPercent = 5.0;          // Risk per Trade (%)
input int               InpTP_Pips     = 30;           // Take Profit (Pips)
input int               InpSL_Pips     = 60;           // Stop Loss (Pips)
input double            InpMaxLot      = 50.0;         // Maximum Lot Size
input int               InpMagicNum    = 20260106;     // Magic Number

//--- GLOBAL VARIABLES
int      handleEMA;
int      handleRSI;
CTrade   trade;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Init handles
   handleEMA = iMA(_Symbol, _Period, InpEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   handleRSI = iRSI(_Symbol, _Period, InpRSIPeriod, PRICE_CLOSE);
   
   if(handleEMA == INVALID_HANDLE || handleRSI == INVALID_HANDLE)
   {
      Print("Error creating handles");
      return(INIT_FAILED);
   }
   
   trade.SetExpertMagicNumber(InpMagicNum);
   EventSetTimer(1);
   return(INIT_SUCCEEDED);
}
void OnTimer() { SendStatus(); }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(handleEMA);
   IndicatorRelease(handleRSI);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   SendStatus(); 
   if(PositionExists()) return;

   //--- Get indicator values
   double ema[];
   double rsi[];
   ArraySetAsSeries(ema, true);
   ArraySetAsSeries(rsi, true);
   
   if(CopyBuffer(handleEMA, 0, 0, 2, ema) < 2) return;
   if(CopyBuffer(handleRSI, 0, 0, 2, rsi) < 2) return;
   
   double close = iClose(_Symbol, _Period, 0);
   double p_ema = ema[0];
   double p_rsi = rsi[0];
   
   //--- Entry Logic
   bool buy_cond  = (close < p_ema && p_rsi < InpRSILower);
   bool sell_cond = (close > p_ema && p_rsi > InpRSIUpper);
   
   if(buy_cond)
   {
      ExecuteOrder(ORDER_TYPE_BUY);
   }
   else if(sell_cond)
   {
      ExecuteOrder(ORDER_TYPE_SELL);
   }
}

//+------------------------------------------------------------------+
//| Check if position exists                                         |
//+------------------------------------------------------------------+
bool PositionExists()
{
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetInteger(POSITION_MAGIC) == InpMagicNum && PositionGetString(POSITION_SYMBOL) == _Symbol)
            return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Execute Order with Risk Management                               |
//+------------------------------------------------------------------+
void ExecuteOrder(ENUM_ORDER_TYPE type)
{
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   double sl_dist = InpSL_Pips * 10.0 * point; // Assuming 5-digit broker (10 points = 1 pip)
   double tp_dist = InpTP_Pips * 10.0 * point;
   
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = balance * (InpRiskPercent / 100.0);
   
   // Calculate Lot Size based on Risk and Stop Loss
   // Formula: Lot = Risk / (SL_in_Points * TickValuePerPoint)
   // For AUDUSD, TickValue is usually per 1 lot.
   double lot = riskAmount / (InpSL_Pips * 10.0 * (tickValue / (tickSize/point)));
   
   // Round to step
   lot = MathFloor(lot / lotStep) * lotStep;
   if(lot < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN)) lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(lot > InpMaxLot) lot = InpMaxLot;
   
   double price = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl = (type == ORDER_TYPE_BUY) ? price - sl_dist : price + sl_dist;
   double tp = (type == ORDER_TYPE_BUY) ? price + tp_dist : price - tp_dist;
   
   if(type == ORDER_TYPE_BUY)
      trade.Buy(lot, _Symbol, price, sl, tp, "Iron Shield Buy");
   else
      trade.Sell(lot, _Symbol, price, sl, tp, "Iron Shield Sell");
}
