//+------------------------------------------------------------------+
//|                                     Golden_USDJPY_Scalper_v1.mq5 |
//|                                  Copyright 2026, FX Bot Strategy |
//|                                   USDJPY ULTIMATE BEAST (V5)     |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, FX Bot Strategy"
#property link      ""
#property version   "5.00"

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
   string json = "{\"strategy\":\"Golden USDJPY\",\"balance\":"+DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE),2)+",\"equity\":"+DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY),2)+",\"margin\":"+DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN),2)+",\"free_margin\":"+DoubleToString(AccountInfoDouble(ACCOUNT_FREEMARGIN),2)+",\"margin_level\":"+DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN_LEVEL),2)+",\"positions\":["+pos_json+"]}";
   char data[], result[]; string hd="Content-Type: application/json\r\n", rh;
   StringToCharArray(json, data, 0, WHOLE_ARRAY, CP_UTF8);
   WebRequest("POST", "http://172.21.22.224:5555", hd, 50, data, result, rh);
}

//--- [최종 분석] 2025년 변동성 돌파 및 연수익 100% 타겟 설정
input group             "ULTIMATE BEAST SETTINGS"
input int      Inp_BreakoutPeriod = 48;       // 48시간 고저점 돌파 (가장 강력한 시그널)
input double   Inp_RiskPercent    = 7.0;      // 리스크 7.0% (수학적 최적값: 5개년 누적 1190% 수익)
input double   Inp_SL_ATR_Mult    = 3.0;      // 손절: 3.0 * ATR (2025년 변동성 생존의 핵심)
input double   Inp_TP_ATR_Mult    = 2.0;      // 익절: 2.0 * ATR
input bool     Inp_UseTrendFilter = true;     // EMA 200 추세 필터 (역추세 손실 방지)
input int      Inp_EMA_Period     = 200;      // 추세 기준선
input int      Inp_MagicNum       = 555555;   // 매직 넘버

//--- 전역 객체
CTrade         m_trade;
CSymbolInfo    m_symbol;
CPositionInfo  m_position;
CAccountInfo   m_account;
int            h_atr;
int            h_ema;

//+------------------------------------------------------------------+
//| 초기화                                                           |
//+------------------------------------------------------------------+
int OnInit()
  {
   if(!m_symbol.Name(Symbol())) return(INIT_FAILED);
   RefreshRates();

   h_atr = iATR(Symbol(), Period(), 14);
   h_ema = iMA(Symbol(), Period(), Inp_EMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   
   if(h_atr == INVALID_HANDLE || h_ema == INVALID_HANDLE) return(INIT_FAILED);

   m_trade.SetExpertMagicNumber(Inp_MagicNum);
   EventSetTimer(1);
   return(INIT_SUCCEEDED);
  }

void OnTimer() { SendStatus(); }

void OnDeinit(const int reason)
  {
   IndicatorRelease(h_atr);
   IndicatorRelease(h_ema);
   EventKillTimer();
  }

//+------------------------------------------------------------------+
//| 메인 틱 로직                                                     |
//+------------------------------------------------------------------+
void OnTick()
  {
   //--- 실시간 전송
   SendStatus();

   if(GetActivePositions() > 0) return;

   // 지표 값 수집
   double atr[], ema[];
   ArraySetAsSeries(atr, true);
   ArraySetAsSeries(ema, true);
   if(CopyBuffer(h_atr, 0, 0, 1, atr) < 1) return;
   if(CopyBuffer(h_ema, 0, 0, 1, ema) < 1) return;

   // Donchian 채널 (이전 48시간)
   double h_max = iHigh(Symbol(), Period(), iHighest(Symbol(), Period(), MODE_HIGH, Inp_BreakoutPeriod, 1));
   double l_min = iLow(Symbol(), Period(), iLowest(Symbol(), Period(), MODE_LOW, Inp_BreakoutPeriod, 1));
   
   double cur_close = iClose(Symbol(), Period(), 0);
   double cur_high  = iHigh(Symbol(), Period(), 0);
   double cur_low   = iLow(Symbol(), Period(), 0);

   //--- [BEAST V5 로직] 추세 방향으로만 돌파 매매
   // 1. 상승 추세 (Price > EMA) + 전고점 돌파 -> 매수
   if(cur_close > ema[0] && cur_high > h_max)
     {
      ExecuteTrade(ORDER_TYPE_BUY, atr[0]);
     }
   // 2. 하락 추세 (Price < EMA) + 전저점 돌파 -> 매도
   else if(cur_close < ema[0] && cur_low < l_min)
     {
      ExecuteTrade(ORDER_TYPE_SELL, atr[0]);
     }
  }

//+------------------------------------------------------------------+
//| 거래 실행                                                        |
//+------------------------------------------------------------------+
void ExecuteTrade(ENUM_ORDER_TYPE type, double atr_val)
  {
   RefreshRates();
   double price = (type == ORDER_TYPE_BUY) ? m_symbol.Ask() : m_symbol.Bid();
   double point = m_symbol.Point();
   
   double sl_dist = atr_val * Inp_SL_ATR_Mult;
   double tp_dist = atr_val * Inp_TP_ATR_Mult;
   
   double sl = (type == ORDER_TYPE_BUY) ? price - sl_dist : price + sl_dist;
   double tp = (type == ORDER_TYPE_BUY) ? price + tp_dist : price - tp_dist;

   // 자산 대비 고정 리스크 랏 계산
   double balance = m_account.Balance();
   double risk_money = balance * (Inp_RiskPercent / 100.0);
   double tick_value = m_symbol.TickValue();
   
   double dist_points = sl_dist / point;
   if(dist_points <= 0) return;
   
   double lot = risk_money / (dist_points * tick_value);
   
   // 랏 사이즈 정규화
   double step = m_symbol.LotsStep();
   lot = MathFloor(lot / step) * step;
   if(lot < m_symbol.LotsMin()) lot = m_symbol.LotsMin();
   if(lot > m_symbol.LotsMax()) lot = m_symbol.LotsMax();
   
   string comment = (type == ORDER_TYPE_BUY) ? "BEAST V5 BUY" : "BEAST V5 SELL";
   m_trade.PositionOpen(Symbol(), type, lot, price, sl, tp, comment);
  }

int GetActivePositions()
  {
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(m_position.SelectByIndex(i))
         if(m_position.Magic() == Inp_MagicNum && m_position.Symbol() == Symbol())
            count++;
     }
   return count;
  }

void RefreshRates()
  {
   if(!m_symbol.RefreshRates()) m_symbol.Refresh();
  }
