//+------------------------------------------------------------------+
//|                                    FX_Bot_Scalper_Python_v9.6.mq5|
//|                              Python Strategy Converted to MQL5     |
//|                                   FINAL OPTIMIZED VERSION           |
//+------------------------------------------------------------------+
#property copyright "2026, Trae AI Bot"
#property link      "https://www.mql5.com"
#property version   "9.6"
#property description "EURUSD M1 Professional Scalper - Optimized"
#property strict

#include <Trade/Trade.mqh>

//--- 호환성 정의
#ifndef SYMBOL_FILLING_MODE
#define SYMBOL_FILLING_MODE 5
#endif

//--- 입력 파라미터
input double InpLot = 0.01;             // 기본 랏 크기
input double InpRiskPercent = 2.0;      // 회당 리스크 (안정성 회복)
input double InpSLATRMult = 1.5;        // 손절 폭 (ATR 1.5배 - M5 최적화)
input double InpTPATRMult = 2.0;        // 익절 폭 (ATR 2.0배 - M5 최적화)
input int InpEmaFast = 12;              
input int InpEmaSlow = 26;              
input int InpEmaTrend = 100;            
input int InpRsiPeriod = 14;            
input int InpRsiBuyZone = 30;           // 매수 RSI (30 이하 - M5 진입 기회)
input int InpRsiSellZone = 70;          // 매도 RSI (70 이상 - M5 진입 기회)
input int InpAtrPeriod = 14;            
input int InpAdxPeriod = 14;            
input int InpAdxMin = 25;               // 최소 ADX 강도 (25 - M5 추세 강도)
input int InpMaxSpread = 20;            // 최대 허용 스프레드 (2.0 pips)
input int InpMaxSlippage = 50;          // 최대 허용 슬리피지 (5.0 pips)
input bool InpUseTrailing = true;       // 트레일링 스탑 사용
input double InpTrailingStop = 80;      // 트레일링 스탑 거리 (8 pips)
input double InpTrailingStep = 20;      // 트레일링 스탑 단계 (2 pips)
input bool InpUseBreakEven = true;      // 본절 보호 사용
input double InpBreakEvenTrigger = 1.5; // 본절 발동 ATR 배수
input bool InpUseRejection = true;      
input double InpRejectionBuffer = 5.0;  // 리젝션 버퍼 (5.0 Points - M5 대응)
input double InpEmaGapPoints = 10.0;    // EMA 간 최소 간격 (1.0 pips - M5 정렬)
input int InpStartHour = 9;             // 거래 시작 시간 (서버 시간 09:00 - 런던 개장)
input int InpEndHour = 20;              // 거래 종료 시간 (서버 시간 20:00 - 뉴욕 중반)
input long InpMagicNumber = 777888;     
input bool InpUseTrendFilter = true;    // 장기 추세 필터
input bool InpForceEntryTest = false;    

//--- 글로벌 변수
CTrade Trade;
int hEMAFast, hEMASlow, hEMATrend, hRSI, hATR, hADX;
datetime last_trade_time = 0;

int OnInit()
{
   Print("EA 초기화 - v9.6 OPTIMIZED (Latency Aware)");
   Trade.SetExpertMagicNumber(InpMagicNumber);
   Trade.SetDeviationInPoints(InpMaxSlippage); // 슬리피지 허용 설정 추가
   
   long filling = 0;
   if(SymbolInfoInteger(_Symbol, (ENUM_SYMBOL_INFO_INTEGER)SYMBOL_FILLING_MODE, filling)) {
      if((filling & 1) != 0) Trade.SetTypeFilling(ORDER_FILLING_FOK);
      else if((filling & 2) != 0) Trade.SetTypeFilling(ORDER_FILLING_IOC);
      else Trade.SetTypeFilling(ORDER_FILLING_RETURN);
   }
   else Trade.SetTypeFilling(ORDER_FILLING_FOK);
   
   hEMAFast = iMA(_Symbol, PERIOD_M5, InpEmaFast, 0, MODE_EMA, PRICE_CLOSE);
   hEMASlow = iMA(_Symbol, PERIOD_M5, InpEmaSlow, 0, MODE_EMA, PRICE_CLOSE);
   hEMATrend = iMA(_Symbol, PERIOD_M5, InpEmaTrend, 0, MODE_EMA, PRICE_CLOSE);
   hRSI = iRSI(_Symbol, PERIOD_M5, InpRsiPeriod, PRICE_CLOSE);
   hATR = iATR(_Symbol, PERIOD_M5, InpAtrPeriod);
   hADX = iADX(_Symbol, PERIOD_M5, InpAdxPeriod);
   
   if(_Period != PERIOD_M5) {
      Print("WARNING: This EA is optimized for M5 timeframe. Current timeframe is not M5.");
   }
   
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   IndicatorRelease(hEMAFast); IndicatorRelease(hEMASlow); IndicatorRelease(hEMATrend);
   IndicatorRelease(hRSI); IndicatorRelease(hATR); IndicatorRelease(hADX);
}

void OnTick()
{
   // 0. 트레일링 스탑 및 본절가 보호 적용
   if(InpUseTrailing) ApplyTrailingStop();
   if(InpUseBreakEven) ApplyBreakEven();

   // 1. 시간 필터
   MqlDateTime dt;
   TimeCurrent(dt);
   if(dt.hour < InpStartHour || dt.hour >= InpEndHour) return;

   // 2. 스프레드 체크
   long spread = 0;
   if(SymbolInfoInteger(_Symbol, (ENUM_SYMBOL_INFO_INTEGER)SYMBOL_SPREAD, spread)) {
      if(spread > InpMaxSpread) {
         static datetime last_spread_log = 0;
         if(TimeCurrent() - last_spread_log > 600) {
            PrintFormat("Spread too high: %d > %d", spread, InpMaxSpread);
            last_spread_log = TimeCurrent();
         }
         return;
      }
   }

   // 2. 가격 데이터 복사
   MqlRates rates[]; ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, _Period, 0, 2, rates) != 2) {
      Print("Error: Failed to copy rates");
      return;
   }
   datetime current_bar_time = rates[0].time;
   
   // 3. 포지션 체크
   bool has_position = false;
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && PositionSelectByTicket(ticket)) {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber) {
            has_position = true; break;
         }
      }
   }

   // 4. 진입 로직
   if(!has_position && last_trade_time != current_bar_time)
   {
       double ema_f = GetVal(hEMAFast), ema_s = GetVal(hEMASlow), ema_t = GetVal(hEMATrend);
       double rsi = GetVal(hRSI), atr = GetVal(hATR), adx = GetVal(hADX);
       double adx_prev = GetValPrev(hADX, 1);
       double ema_t_prev = GetValPrev(hEMATrend, 1);
       
       // 지표 값 유효성 검사
       if(ema_f <= 0 || rsi <= 0 || atr <= 0 || adx <= 0) {
           static datetime last_data_err = 0;
           if(TimeCurrent() - last_data_err > 300) {
               PrintFormat("Indicator Data Not Ready: EMA_F:%.5f, RSI:%.2f, ATR:%.5f, ADX:%.2f", ema_f, rsi, atr, adx);
               last_data_err = TimeCurrent();
           }
           return;
       }

       MqlRates prev_rates[]; ArraySetAsSeries(prev_rates, true);
       if(CopyRates(_Symbol, _Period, 1, 1, prev_rates) != 1) return;
       double prev_close = prev_rates[0].close;
       double prev_low = prev_rates[0].low;
       double prev_high = prev_rates[0].high;

       // 조건 판별
       // 200 EMA 기울기 확인 (상승/하락 추세 강화)
       bool trend_up = !InpUseTrendFilter || (prev_close > ema_t && ema_t > ema_t_prev);
       bool trend_dn = !InpUseTrendFilter || (prev_close < ema_t && ema_t < ema_t_prev);
       
       // EMA 간격 필터: 추세가 확실할 때만 진입
       bool ema_gap_up = (ema_f - ema_s) > (InpEmaGapPoints * _Point);
       bool ema_gap_dn = (ema_s - ema_f) > (InpEmaGapPoints * _Point);
       
       // EMA 정배열/역배열 필터 (200 EMA 위에서 20/50 정배열 확인)
       bool ema_aligned_up = ema_f > ema_s && ema_gap_up;
       bool ema_aligned_dn = ema_f < ema_s && ema_gap_dn;
       
       bool rsi_ok_up = rsi < InpRsiBuyZone;
       bool rsi_ok_dn = rsi > InpRsiSellZone;
       
       // ADX 필터: 최소 강도 + 상승 중인지 확인
       bool adx_ok = adx > InpAdxMin && adx > adx_prev;

       double buffer = InpRejectionBuffer * _Point;
       // 리젝션: 저가가 EMA 20 근처까지 내려왔었는지 확인 (풀백 확인)
       // 그리고 종가는 EMA 20 위에 머물러 있어야 함 (추세 유지 확인)
       bool touch_up = (prev_low <= (ema_f + buffer)) && (prev_close > ema_f);
       bool touch_dn = (prev_high >= (ema_f - buffer)) && (prev_close < ema_f);
       
       // 반전 확인: 이전 캔들이 양봉(매수) 또는 음봉(매도)으로 마감 (몸통이 있는 캔들)
       bool candle_confirm_up = prev_rates[0].close > prev_rates[0].open;
       bool candle_confirm_dn = prev_rates[0].close < prev_rates[0].open;

       bool buy_cond = trend_up && ema_aligned_up && rsi_ok_up && adx_ok && touch_up && candle_confirm_up;
       bool sell_cond = trend_dn && ema_aligned_dn && rsi_ok_dn && adx_ok && touch_dn && candle_confirm_dn;

       // 진단용 화면 표시
       string diagnostic = StringFormat(
           "DIAGNOSTIC (M1):\n"
           "- Trend: %s\n"
           "- EMA Align: %s (Gap: %.1f)\n"
           "- RSI: %.1f (OK: %s)\n"
           "- ADX: %.1f (Min: %d)\n"
           "- Pullback: %s\n"
           "- Candle: %s",
           (trend_up || trend_dn ? "OK" : "WAIT"),
           (ema_aligned_up || ema_aligned_dn ? "OK" : "WAIT"), (ema_f - ema_s)/_Point,
           rsi, (rsi_ok_up || rsi_ok_dn ? "OK" : "WAIT"),
           adx, InpAdxMin,
           (touch_up || touch_dn ? "OK" : "WAIT"),
           (candle_confirm_up || candle_confirm_dn ? "OK" : "WAIT")
       );
       Comment(diagnostic);

       if(InpForceEntryTest) {
           buy_cond = true;
           Print("DEBUG: Force Entry Test is ON - Triggering Buy");
       }

       // 상태 요약 로깅 (전문가 탭 확인용)
       static datetime last_status_log = 0;
       if(TimeCurrent() - last_status_log > 300) {
           string msg = StringFormat("Status: RSI:%.1f, ADX:%.1f, EMA_F:%.5f, EMA_T:%.5f", rsi, adx, ema_f, ema_t);
           Print(msg);
           Comment(msg + "\nWaiting for Entry Conditions...");
           last_status_log = TimeCurrent();
       }

       if(buy_cond || sell_cond) {
           double sl_dist = atr * InpSLATRMult;
           long stops_level_long = 0;
           double stops_level = 0;
           if(SymbolInfoInteger(_Symbol, (ENUM_SYMBOL_INFO_INTEGER)SYMBOL_TRADE_STOPS_LEVEL, stops_level_long)) {
               stops_level = stops_level_long * _Point;
           }
           if(sl_dist < stops_level) sl_dist = stops_level + 10*_Point;

           double lot = CalculateLot(sl_dist);
           PrintFormat("Entry Triggered: RSI:%.1f, ADX:%.1f, Gap:%.1f. Lot:%.2f", rsi, adx, (ema_f-ema_s)/_Point, lot);

           if(buy_cond) {
               double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
               double sl = NormalizeDouble(ask - sl_dist, _Digits);
               double tp = NormalizeDouble(ask + (atr * InpTPATRMult), _Digits);
               if(Trade.Buy(lot, _Symbol, ask, sl, tp)) {
                   if(Trade.ResultRetcode() == TRADE_RETCODE_DONE || Trade.ResultRetcode() == TRADE_RETCODE_PLACED) {
                       last_trade_time = current_bar_time;
                       PrintFormat("BUY SUCCESS: Ticket:%I64u", Trade.ResultOrder());
                   } else {
                       PrintFormat("BUY FAILED: %s", Trade.ResultRetcodeDescription());
                   }
               }
           }
           else if(sell_cond) {
               double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
               double sl = NormalizeDouble(bid + sl_dist, _Digits);
               double tp = NormalizeDouble(bid - (atr * InpTPATRMult), _Digits);
               if(Trade.Sell(lot, _Symbol, bid, sl, tp)) {
                   if(Trade.ResultRetcode() == TRADE_RETCODE_DONE || Trade.ResultRetcode() == TRADE_RETCODE_PLACED) {
                       last_trade_time = current_bar_time;
                       PrintFormat("SELL SUCCESS: Ticket:%I64u", Trade.ResultOrder());
                   } else {
                       PrintFormat("SELL FAILED: %s", Trade.ResultRetcodeDescription());
                   }
               }
           }
       }
   }
}

double GetVal(int handle) {
    double b[]; ArraySetAsSeries(b, true);
    if(CopyBuffer(handle, 0, 0, 1, b) == 1) return b[0];
    return 0;
}

double GetValPrev(int handle, int shift) {
    double b[]; ArraySetAsSeries(b, true);
    if(CopyBuffer(handle, 0, shift, 1, b) == 1) return b[0];
    return 0;
}

double CalculateLot(double sl_points) {
    double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    if(min_lot <= 0) min_lot = 0.01;
    double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    if(max_lot <= 0) max_lot = 10.0;

    double lot = min_lot;
    if(sl_points > 0) {
        double balance = AccountInfoDouble(ACCOUNT_BALANCE);
        double risk_money = balance * (InpRiskPercent / 100.0);
        double tick_val = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
        if(tick_val > 0) {
            double points_val = sl_points / _Point;
            lot = NormalizeDouble(risk_money / (points_val * tick_val), 2);
        }
    }
    
    double free_margin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
    double margin_req = 0;
    if(OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, lot, SymbolInfoDouble(_Symbol, SYMBOL_ASK), margin_req)) {
        if(margin_req > free_margin * 0.5) {
            lot = NormalizeDouble(lot * (free_margin * 0.5 / margin_req), 2);
        }
    }

    if(lot < min_lot) lot = min_lot;
    if(lot > max_lot) lot = max_lot;
    return lot;
}

void ApplyTrailingStop() {
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        if(PositionSelectByTicket(PositionGetTicket(i))) {
            if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber) {
                ENUM_POSITION_TYPE pos_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
                double current_sl = PositionGetDouble(POSITION_SL);
                double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
                
                if(pos_type == POSITION_TYPE_BUY) {
                    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
                    if(bid - open_price > InpTrailingStop * _Point) {
                        double new_sl = NormalizeDouble(bid - InpTrailingStop * _Point, _Digits);
                        if(new_sl > current_sl + InpTrailingStep * _Point) {
                            Trade.PositionModify(PositionGetTicket(i), new_sl, PositionGetDouble(POSITION_TP));
                        }
                    }
                }
                else if(pos_type == POSITION_TYPE_SELL) {
                    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
                    if(open_price - ask > InpTrailingStop * _Point) {
                        double new_sl = NormalizeDouble(ask + InpTrailingStop * _Point, _Digits);
                        if(new_sl < current_sl - InpTrailingStep * _Point || current_sl == 0) {
                            Trade.PositionModify(PositionGetTicket(i), new_sl, PositionGetDouble(POSITION_TP));
                        }
                    }
                }
            }
        }
    }
}

void ApplyBreakEven() {
    double atr = GetVal(hATR);
    if(atr <= 0) return;

    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        if(PositionSelectByTicket(PositionGetTicket(i))) {
            if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber) {
                ENUM_POSITION_TYPE pos_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
                double current_sl = PositionGetDouble(POSITION_SL);
                double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
                double tp = PositionGetDouble(POSITION_TP);
                
                if(pos_type == POSITION_TYPE_BUY) {
                    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
                    if(bid - open_price > InpBreakEvenTrigger * atr) {
                        double be_price = open_price + 10 * _Point; // 진입가 + 1핍
                        if(current_sl < be_price) {
                            Trade.PositionModify(PositionGetTicket(i), be_price, tp);
                        }
                    }
                }
                else if(pos_type == POSITION_TYPE_SELL) {
                    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
                    if(open_price - ask > InpBreakEvenTrigger * atr) {
                        double be_price = open_price - 10 * _Point; // 진입가 - 1핍
                        if(current_sl > be_price || current_sl == 0) {
                            Trade.PositionModify(PositionGetTicket(i), be_price, tp);
                        }
                    }
                }
            }
        }
    }
}
