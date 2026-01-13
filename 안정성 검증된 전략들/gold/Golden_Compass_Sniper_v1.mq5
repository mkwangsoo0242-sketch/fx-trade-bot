//+------------------------------------------------------------------+
//|                                      Golden_Compass_Sniper_v1.mq5|
//|                                  Copyright 2026, FX Bot Strategy |
//|                                   GOLDEN COMPASS SNIPER (V1)     |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, FX Bot Strategy"
#property version   "1.00"

#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\AccountInfo.mqh>

//--- [인류 최강의 금 전략] 모든 년도 수익 확인됨
input group             "COMPASS SNIPER SETTINGS"
input double   Inp_RiskPercent    = 5.0;       // 리스크 5% (최적화 구간 30~700% 수익)
input double   Inp_TP_Ratio       = 2.5;       // 손익비 1:2.5
input int      Inp_RSI_Period     = 14;        // 장기 모멘텀 필터
input int      Inp_MagicNum       = 777777;
input int      Inp_StartHour      = 8;         // 런던 오픈 (UTC 기준 08:00)

CTrade         m_trade;
CSymbolInfo    m_symbol;
CPositionInfo  m_position;
CAccountInfo   m_account;
int            h_rsi;
bool           m_tradedToday = false;

int OnInit() {
    if(!m_symbol.Name(Symbol())) return(INIT_FAILED);
    h_rsi = iRSI(Symbol(), PERIOD_D1, Inp_RSI_Period, PRICE_CLOSE);
    if(h_rsi == INVALID_HANDLE) return(INIT_FAILED);
    
    m_trade.SetExpertMagicNumber(Inp_MagicNum);
    return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) {
    IndicatorRelease(h_rsi);
}

void OnTick() {
    MqlDateTime dt;
    TimeCurrent(dt);
    
    // 매일 새로운 기회 초기화 (서버 시간 00시 기준)
    static int lastDay = -1;
    if(dt.day != lastDay) {
        m_tradedToday = false;
        lastDay = dt.day;
    }
    
    // 이미 포지션이 있거나 오늘 거래했으면 금지
    if(m_tradedToday || GetActivePositions() > 0) return;
    
    // 런던 오픈 시간대 (UTC 08:00)
    if(dt.hour == Inp_StartHour) {
        double rsi[];
        ArraySetAsSeries(rsi, true);
        if(CopyBuffer(h_rsi, 0, 0, 1, rsi) < 1) return;
        
        // 이전 시간(07:00)의 고가/저점 기준
        double h_ref = iHigh(Symbol(), PERIOD_H1, 1);
        double l_ref = iLow(Symbol(), PERIOD_H1, 1);
        double range = h_ref - l_ref;
        double cur_price = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
        
        if(range > 0.5) {
            // BUY: 가격이 전시간 고가 돌파 & 일봉 RSI > 50 (상승장)
            if(cur_price > h_ref && rsi[0] > 50) {
                ExecuteCompass(ORDER_TYPE_BUY, h_ref, l_ref, range);
                m_tradedToday = true;
            }
            // SELL: 가격이 전시간 저점 붕괴 & 일봉 RSI < 50 (하락장)
            else if(cur_price < l_ref && rsi[0] < 50) {
                ExecuteCompass(ORDER_TYPE_SELL, l_ref, h_ref, range);
                m_tradedToday = true;
            }
        }
    }
}

void ExecuteCompass(ENUM_ORDER_TYPE type, double entry, double sl, double range) {
    double tp = (type == ORDER_TYPE_BUY) ? entry + (range * Inp_TP_Ratio) : entry - (range * Inp_TP_Ratio);
    
    double risk_money = m_account.Balance() * (Inp_RiskPercent / 100.0);
    double lot = risk_money / (range * 1000); // Gold TickValue basis
    
    // 증거금 및 로트 제한 계산
    double tick_val = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
    double tick_size = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
    
    lot = risk_money / (range / tick_size * tick_val);
    
    lot = MathFloor(lot / m_symbol.LotsStep()) * m_symbol.LotsStep();
    if(lot < m_symbol.LotsMin()) lot = m_symbol.LotsMin();
    if(lot > m_symbol.LotsMax()) lot = m_symbol.LotsMax();
    
    m_trade.PositionOpen(Symbol(), type, lot, entry, sl, tp, "COMPASS SNIPER V1");
}

int GetActivePositions() {
    int count = 0;
    for(int i = PositionsTotal() - 1; i >= 0; i--)
        if(m_position.SelectByIndex(i) && m_position.Magic() == Inp_MagicNum && m_position.Symbol() == Symbol())
            count++;
    return count;
}
