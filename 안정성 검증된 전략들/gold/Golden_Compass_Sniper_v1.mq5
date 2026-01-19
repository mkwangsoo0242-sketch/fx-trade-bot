//+------------------------------------------------------------------+
//|                                      Golden_Compass_Sniper_v1.mq5|
//|                                  Copyright 2026, FX Bot Strategy |
//|                                   GOLDEN COMPASS SNIPER (V1)     |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, FX Bot Strategy"
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
      if(PositionSelectByTicket(t) && PositionGetInteger(POSITION_MAGIC) == Inp_MagicNum) {
         if(pCount > 0) pos_json += ",";
         pos_json += "{\"ticket\":"+IntegerToString(t)+",\"symbol\":\""+_Symbol+"\",\"time\":\""+TimeToString(PositionGetInteger(POSITION_TIME))+"\",\"type\":\""+(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?"buy":"sell")+"\",\"vol\":"+DoubleToString(PositionGetDouble(POSITION_VOLUME),2)+",\"open\":"+DoubleToString(PositionGetDouble(POSITION_PRICE_OPEN),5)+",\"sl\":"+DoubleToString(PositionGetDouble(POSITION_SL),5)+",\"tp\":"+DoubleToString(PositionGetDouble(POSITION_TP),5)+",\"cur\":"+DoubleToString(PositionGetDouble(POSITION_PRICE_CURRENT),5)+",\"pnl\":"+DoubleToString(PositionGetDouble(POSITION_PROFIT),2)+"}";
         pCount++;
      }
   }
   string json = "{\"strategy\":\"Gold Compass Sniper\",\"balance\":"+DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE),2)+",\"equity\":"+DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY),2)+",\"margin\":"+DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN),2)+",\"free_margin\":"+DoubleToString(AccountInfoDouble(ACCOUNT_FREEMARGIN),2)+",\"margin_level\":"+DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN_LEVEL),2)+",\"positions\":["+pos_json+"]}";
   char data[], result[]; string hd="Content-Type: application/json\r\n", rh;
   StringToCharArray(json, data, 0, WHOLE_ARRAY, CP_UTF8);
   WebRequest("POST", "http://172.21.22.224:5555", hd, 50, data, result, rh);
}

//--- INPUT PARAMETERS
input group             "--- RISK MANAGEMENT ---"
input double   Inp_RiskPercent    = 2.0;       // Risk per trade (% of Balance)
input double   Inp_FixedLot       = 0.0;       // Fixed Lot (If > 0, Risk% is ignored)
input int      Inp_MagicNum       = 888888;    // Magic Number

input group             "--- STRATEGY SETTINGS ---"
input int      Inp_StartHour      = 10;        // Start Hour (Server Time, 10 = London Open)
input int      Inp_EndHour        = 20;        // End Hour (Server Time)
input int      Inp_RSI_Period     = 14;        // RSI Period (Daily Trend)
input double   Inp_TP_ATR_Mult    = 3.0;       // Take Profit (ATR Multiplier)
input double   Inp_SL_ATR_Mult    = 1.5;       // Stop Loss (ATR Multiplier)

input group             "--- SYSTEM ---"
input bool     Inp_ShowStatus     = true;      // Show On-Screen Status
input bool     Inp_TestMode       = false;     // Test Mode (Ignore Time)

//--- GLOBAL VARIABLES
CTrade         m_trade;
CSymbolInfo    m_symbol;
CPositionInfo  m_position;
CAccountInfo   m_account;

int            h_rsi;      // RSI Handle
int            h_atr;      // ATR Handle
bool           m_isTradedToday = false;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
    // Symbol Validation
    if(!m_symbol.Name(Symbol())) return(INIT_FAILED);
    
    string sym = Symbol();
    StringToUpper(sym);
    if(StringFind(sym, "XAU") < 0 && StringFind(sym, "GOLD") < 0) {
        Alert("WARNING: This EA is optimized for GOLD (XAUUSD). Current: ", Symbol());
    }

    // Indicators Initialization
    h_rsi = iRSI(Symbol(), PERIOD_D1, Inp_RSI_Period, PRICE_CLOSE);
    h_atr = iATR(Symbol(), PERIOD_H1, 14);
    
    if(h_rsi == INVALID_HANDLE || h_atr == INVALID_HANDLE) {
        Print("Failed to initialize indicators");
        return(INIT_FAILED);
    }
    
    m_trade.SetExpertMagicNumber(Inp_MagicNum);
    EventSetTimer(1);
    Print("Golden Compass Sniper V2 Initialized.");
    return(INIT_SUCCEEDED);
}
void OnTimer() { SendStatus(); }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    IndicatorRelease(h_rsi);
    IndicatorRelease(h_atr);
    Comment(""); // Clear screen
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick() {
    SendStatus();
    MqlDateTime dt;
    TimeCurrent(dt);
    
    // Reset daily trade flag
    static int lastDay = -1;
    if(dt.day != lastDay) {
        m_isTradedToday = false;
        lastDay = dt.day;
    }
    
    // Display Status
    if(Inp_ShowStatus) DisplayStatus(dt);
    
    // Check if we can trade
    if(m_isTradedToday || GetActivePositions() > 0) return;
    
    // Time Filter
    bool isTime = (dt.hour >= Inp_StartHour && dt.hour <= Inp_EndHour);
    if(!isTime && !Inp_TestMode) return;
    
    // Strategy Logic
    CheckForEntry();
}

//+------------------------------------------------------------------+
//| Entry Logic                                                      |
//+------------------------------------------------------------------+
void CheckForEntry() {
    double rsi[], atr[];
    ArraySetAsSeries(rsi, true);
    ArraySetAsSeries(atr, true);
    
    if(CopyBuffer(h_rsi, 0, 0, 1, rsi) < 1 || CopyBuffer(h_atr, 0, 0, 1, atr) < 1) return;
    
    // Price Reference (Previous H1 Candle)
    double h_ref = iHigh(Symbol(), PERIOD_H1, 1);
    double l_ref = iLow(Symbol(), PERIOD_H1, 1);
    double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
    double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
    
    // ATR based dynamic SL/TP
    double sl_dist = atr[0] * Inp_SL_ATR_Mult;
    double tp_dist = atr[0] * Inp_TP_ATR_Mult;
    
    // BUY: Price > Prev High & RSI(D1) > 50
    if(ask > h_ref && rsi[0] > 50) {
        double sl = ask - sl_dist;
        double tp = ask + tp_dist;
        ExecuteTrade(ORDER_TYPE_BUY, ask, sl, tp, "Breakout Buy");
    }
    // SELL: Price < Prev Low & RSI(D1) < 50
    else if(bid < l_ref && rsi[0] < 50) {
        double sl = bid + sl_dist;
        double tp = bid - tp_dist;
        ExecuteTrade(ORDER_TYPE_SELL, bid, sl, tp, "Breakout Sell");
    }
}

//+------------------------------------------------------------------+
//| Execute Trade with Money Management                              |
//+------------------------------------------------------------------+
void ExecuteTrade(ENUM_ORDER_TYPE type, double price, double sl, double tp, string comment) {
    double lot = Inp_FixedLot;
    
    if(lot <= 0) {
        double risk_money = m_account.Balance() * (Inp_RiskPercent / 100.0);
        double sl_points = MathAbs(price - sl) / m_symbol.TickSize();
        double tick_val = m_symbol.TickValue();
        
        if(sl_points > 0 && tick_val > 0) {
            lot = risk_money / (sl_points * tick_val);
        }
    }
    
    // Lot constraints
    lot = MathFloor(lot / m_symbol.LotsStep()) * m_symbol.LotsStep();
    if(lot < m_symbol.LotsMin()) lot = m_symbol.LotsMin();
    if(lot > m_symbol.LotsMax()) lot = m_symbol.LotsMax();
    
    if(m_trade.PositionOpen(Symbol(), type, lot, price, sl, tp, comment)) {
        Print("Trade Opened: ", comment, " Lot: ", lot);
        m_isTradedToday = true;
    } else {
        Print("Trade Failed: ", m_trade.ResultRetcodeDescription());
    }
}

//+------------------------------------------------------------------+
//| Get Count of Active Positions                                    |
//+------------------------------------------------------------------+
int GetActivePositions() {
    int count = 0;
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        if(m_position.SelectByIndex(i) && m_position.Magic() == Inp_MagicNum && m_position.Symbol() == Symbol())
            count++;
    }
    return count;
}

//+------------------------------------------------------------------+
//| Display Status on Chart                                          |
//+------------------------------------------------------------------+
void DisplayStatus(MqlDateTime &dt) {
    string out = "--- GOLDEN COMPASS SNIPER V2 ---\n";
    out += "Server Time: " + IntegerToString(dt.hour) + ":" + (dt.min < 10 ? "0" : "") + IntegerToString(dt.min) + "\n";
    out += "Trading Window: " + IntegerToString(Inp_StartHour) + ":00 - " + IntegerToString(Inp_EndHour) + ":00\n";
    out += "Account Balance: " + DoubleToString(m_account.Balance(), 2) + "\n";
    out += "Traded Today: " + (m_isTradedToday ? "YES" : "NO") + "\n";
    out += "Active Positions: " + IntegerToString(GetActivePositions()) + "\n";
    if(Inp_TestMode) out += "!!! TEST MODE ACTIVE !!!\n";
    
    Comment(out);
}
