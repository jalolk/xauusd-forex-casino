//+------------------------------------------------------------------+
//|                                                   GoldBarrier.mq5 |
//|                    Fixed-percentage barrier EA, built for XAUUSD  |
//|                                                                   |
//|  THE ONLY QUESTION THIS EA ASKS:                                  |
//|    P(price hits +TP% before it hits -SL%) > breakeven ?           |
//|                                                                   |
//|  With TP=0.51 / SL=0.49:                                          |
//|    Coin-flip baseline  = SL/(TP+SL)       = 49.00%                |
//|    Breakeven @ 35c gold spread            = 50.06%                |
//|    Edge required                          = +1.06 pp              |
//|                                                                   |
//|  OnTester() returns (win rate - coin-flip baseline) in pp, so     |
//|  the optimiser scores you against RANDOM, not against profit.     |
//|  A positive number is the only result that means anything.        |
//|                                                                   |
//|  NOT FINANCIAL ADVICE. Built for backtesting.                     |
//+------------------------------------------------------------------+
#property copyright "Built for backtesting. Not financial advice."
#property version   "1.00"
#property description "XAUUSD fixed-% barrier EA - TP 0.51% / SL 0.49%"
#property description "Coin-flip baseline 49.0%. Breakeven ~50.1%. Beat it or bin it."

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| Enums                                                             |
//+------------------------------------------------------------------+
enum ENUM_ENTRY_MODE
  {
   ENTRY_PULLBACK,      // Pullback: dip below EMA then reclaim it
   ENTRY_BREAKOUT,      // Breakout: take out N-bar high/low
   ENTRY_RSI_RECOVER,   // RSI: recover up through level
   ENTRY_NAIVE          // NAIVE control: last candle direction only
  };

enum ENUM_SIZING
  {
   SIZE_FIXED,          // Fixed lots
   SIZE_RISK_PERCENT    // Risk % of balance per trade
  };

//+------------------------------------------------------------------+
//| Inputs                                                            |
//+------------------------------------------------------------------+
input group           "=== Barrier (the whole point) ==="
input double          InpTPPercent        = 0.51;      // Take Profit (% of entry price)
input double          InpSLPercent        = 0.49;      // Stop Loss (% of entry price)

input group           "=== Entry Trigger ==="
input ENUM_ENTRY_MODE InpEntryMode        = ENTRY_PULLBACK;   // Entry mode (use NAIVE as control)
input ENUM_TIMEFRAMES InpEntryTF          = PERIOD_M15;       // Entry timeframe
input int             InpPullbackEMA      = 20;        // Pullback: EMA period
input int             InpDonchianBars     = 20;        // Breakout: lookback bars
input int             InpRSIPeriod        = 14;        // RSI: period
input double          InpRSIBuyLevel      = 45.0;      // RSI: long recovery level
input double          InpRSISellLevel     = 55.0;      // RSI: short recovery level

input group           "=== Regime Filter (higher timeframe) ==="
input bool            InpUseRegime        = true;      // Only trade with the HTF trend
input ENUM_TIMEFRAMES InpRegimeTF         = PERIOD_H1; // Regime timeframe
input int             InpRegimeFastEMA    = 50;        // Regime fast EMA
input int             InpRegimeSlowEMA    = 200;       // Regime slow EMA

input group           "=== Volatility Filter (barrier-aware - READ THIS) ==="
input bool            InpUseATRFilter     = true;      // Filter on barrier-to-ATR ratio
input int             InpATRPeriod        = 14;        // ATR period (entry TF)
input double          InpMinATRToTarget   = 3.0;       // Min bars-to-target (below = coin flip)
input double          InpMaxATRToTarget   = 20.0;      // Max bars-to-target (above = too slow)

input group           "=== Trend Strength ==="
input bool            InpUseADX           = true;      // Require minimum ADX
input int             InpADXPeriod        = 14;        // ADX period
input double          InpADXMin           = 20.0;      // ADX minimum

input group           "=== Session (SERVER time - check your broker offset) ==="
input bool            InpUseSession       = true;      // Restrict to session hours
input int             InpSessionStartHour = 8;         // Session start hour
input int             InpSessionEndHour   = 20;        // Session end hour

input group           "=== Risk ==="
input ENUM_SIZING     InpSizingMode       = SIZE_RISK_PERCENT;  // Sizing mode
input double          InpFixedLots        = 0.01;      // Fixed lots (if SIZE_FIXED)
input double          InpRiskPercent      = 0.5;       // Risk % of balance (if SIZE_RISK_PERCENT)

input group           "=== Guards ==="
input double          InpMaxSpreadPct     = 0.020;     // Max spread as % of price (0=off)
input int             InpMaxOpenPositions = 1;         // Max concurrent positions
input int             InpCooldownBars     = 3;         // Bars to wait after a trade
input double          InpMaxDailyLossPct  = 0;         // Daily loss limit % (0=off)

input group           "=== Misc ==="
input ulong           InpMagic            = 880051;    // Magic number
input int             InpSlippagePoints   = 30;        // Slippage (points)
input bool            InpVerbose          = false;     // Log rejected signals

//+------------------------------------------------------------------+
//| Globals                                                           |
//+------------------------------------------------------------------+
CTrade   trade;
int      hRegimeFast = INVALID_HANDLE;
int      hRegimeSlow = INVALID_HANDLE;
int      hEntryEMA   = INVALID_HANDLE;
int      hATR        = INVALID_HANDLE;
int      hADX        = INVALID_HANDLE;
int      hRSI        = INVALID_HANDLE;

datetime g_lastBarTime      = 0;
datetime g_lastTradeBarTime = 0;
datetime g_currentDay       = 0;
double   g_dayStartBalance  = 0.0;

//+------------------------------------------------------------------+
//| Init                                                              |
//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpTPPercent <= 0.0 || InpSLPercent <= 0.0)
     {
      Print("FATAL: TP% and SL% must both be > 0");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpRegimeFastEMA >= InpRegimeSlowEMA)
     {
      Print("FATAL: regime fast EMA must be < slow EMA");
      return INIT_PARAMETERS_INCORRECT;
     }

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippagePoints);
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.LogLevel(LOG_LEVEL_ERRORS);

   hRegimeFast = iMA(_Symbol, InpRegimeTF, InpRegimeFastEMA, 0, MODE_EMA, PRICE_CLOSE);
   hRegimeSlow = iMA(_Symbol, InpRegimeTF, InpRegimeSlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   hEntryEMA   = iMA(_Symbol, InpEntryTF,  InpPullbackEMA,   0, MODE_EMA, PRICE_CLOSE);
   hATR        = iATR(_Symbol, InpEntryTF, InpATRPeriod);
   hADX        = iADX(_Symbol, InpEntryTF, InpADXPeriod);
   hRSI        = iRSI(_Symbol, InpEntryTF, InpRSIPeriod, PRICE_CLOSE);

   if(hRegimeFast == INVALID_HANDLE || hRegimeSlow == INVALID_HANDLE ||
      hEntryEMA   == INVALID_HANDLE || hATR        == INVALID_HANDLE ||
      hADX        == INVALID_HANDLE || hRSI        == INVALID_HANDLE)
     {
      Print("FATAL: indicator handle creation failed, err=", GetLastError());
      return INIT_FAILED;
     }

   g_dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);

   // Sanity readout - gold digits vary by broker (2 vs 3), this catches it.
   double price  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   long   digits = SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double point  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   long   spr    = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   double baseline = 100.0 * InpSLPercent / (InpTPPercent + InpSLPercent);

   PrintFormat("--- GoldBarrier init on %s ---", _Symbol);
   PrintFormat("  digits=%d  point=%.5f  price=%.2f  spread=%d pts (%.4f%% of price)",
               digits, point, price, spr, (spr * point) / price * 100.0);
   PrintFormat("  TP=%.2f%% (%.2f currency)   SL=%.2f%% (%.2f currency)",
               InpTPPercent, price * InpTPPercent / 100.0,
               InpSLPercent, price * InpSLPercent / 100.0);
   PrintFormat("  Coin-flip baseline win rate = %.2f%%  <-- YOU MUST BEAT THIS", baseline);
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   IndicatorRelease(hRegimeFast);
   IndicatorRelease(hRegimeSlow);
   IndicatorRelease(hEntryEMA);
   IndicatorRelease(hATR);
   IndicatorRelease(hADX);
   IndicatorRelease(hRSI);
  }

//+------------------------------------------------------------------+
//| Helpers                                                           |
//+------------------------------------------------------------------+
bool GetBuf(int handle, int buffer, int count, double &out[])
  {
   ArraySetAsSeries(out, true);
   return (CopyBuffer(handle, buffer, 0, count, out) >= count);
  }

void Reject(string why)
  {
   if(InpVerbose) Print("reject: ", why);
  }

//+------------------------------------------------------------------+
//| Filters                                                           |
//+------------------------------------------------------------------+
bool RegimeAllows(bool isLong)
  {
   if(!InpUseRegime) return true;
   double f[], s[];
   if(!GetBuf(hRegimeFast, 0, 3, f)) return false;
   if(!GetBuf(hRegimeSlow, 0, 3, s)) return false;
   return isLong ? (f[1] > s[1]) : (f[1] < s[1]);
  }

//--- The important one. Barrier distance measured in ATRs.
//--- Too few ATRs  -> single bar can hit either side -> pure coin flip, you just pay spread.
//--- Too many ATRs -> hours of exposure to mean reversion before you resolve.
bool VolatilityOK(double price)
  {
   if(!InpUseATRFilter) return true;
   double a[];
   if(!GetBuf(hATR, 0, 3, a)) return false;
   if(a[1] <= 0.0) return false;
   double tpDist = price * InpTPPercent / 100.0;
   double ratio  = tpDist / a[1];
   if(ratio < InpMinATRToTarget) { Reject(StringFormat("ATR ratio %.1f too low (chop)", ratio));  return false; }
   if(ratio > InpMaxATRToTarget) { Reject(StringFormat("ATR ratio %.1f too high (slow)", ratio)); return false; }
   return true;
  }

bool TrendStrengthOK()
  {
   if(!InpUseADX) return true;
   double a[];
   if(!GetBuf(hADX, 0, 3, a)) return false;   // buffer 0 = main ADX line
   if(a[1] < InpADXMin) { Reject(StringFormat("ADX %.1f < %.1f", a[1], InpADXMin)); return false; }
   return true;
  }

bool SessionOK()
  {
   if(!InpUseSession) return true;
   MqlDateTime t;
   TimeToStruct(TimeCurrent(), t);
   if(InpSessionStartHour <= InpSessionEndHour)
      return (t.hour >= InpSessionStartHour && t.hour < InpSessionEndHour);
   return (t.hour >= InpSessionStartHour || t.hour < InpSessionEndHour);  // wraps midnight
  }

bool SpreadOK()
  {
   if(InpMaxSpreadPct <= 0.0) return true;
   double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(price <= 0.0) return false;
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   long   spr   = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   double sprPct = (spr * point) / price * 100.0;
   if(sprPct > InpMaxSpreadPct) { Reject(StringFormat("spread %.4f%% too wide", sprPct)); return false; }
   return true;
  }

bool CooldownOK()
  {
   if(InpCooldownBars <= 0 || g_lastTradeBarTime == 0) return true;
   int shift = iBarShift(_Symbol, InpEntryTF, g_lastTradeBarTime, false);
   return (shift >= InpCooldownBars);
  }

bool DailyLossOK()
  {
   if(InpMaxDailyLossPct <= 0.0) return true;
   MqlDateTime t;
   TimeToStruct(TimeCurrent(), t);
   t.hour = 0; t.min = 0; t.sec = 0;
   datetime today = StructToTime(t);
   if(today != g_currentDay)
     {
      g_currentDay      = today;
      g_dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
     }
   if(g_dayStartBalance <= 0.0) return true;
   double eq    = AccountInfoDouble(ACCOUNT_EQUITY);
   double ddPct = (g_dayStartBalance - eq) / g_dayStartBalance * 100.0;
   return (ddPct < InpMaxDailyLossPct);
  }

int CountPositions()
  {
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == (long)InpMagic)
         n++;
     }
   return n;
  }

//+------------------------------------------------------------------+
//| Entry triggers                                                    |
//+------------------------------------------------------------------+
bool TriggerLong()
  {
   double c1 = iClose(_Symbol, InpEntryTF, 1);
   double c2 = iClose(_Symbol, InpEntryTF, 2);

   if(InpEntryMode == ENTRY_PULLBACK)
     {
      double e[];
      if(!GetBuf(hEntryEMA, 0, 4, e)) return false;
      return (c2 < e[2] && c1 > e[1]);          // dipped below, reclaimed
     }
   if(InpEntryMode == ENTRY_BREAKOUT)
     {
      int idx = iHighest(_Symbol, InpEntryTF, MODE_HIGH, InpDonchianBars, 2);
      if(idx < 0) return false;
      return (c1 > iHigh(_Symbol, InpEntryTF, idx));
     }
   if(InpEntryMode == ENTRY_RSI_RECOVER)
     {
      double r[];
      if(!GetBuf(hRSI, 0, 4, r)) return false;
      return (r[2] < InpRSIBuyLevel && r[1] >= InpRSIBuyLevel);
     }
   if(InpEntryMode == ENTRY_NAIVE)
      return (c1 > iOpen(_Symbol, InpEntryTF, 1));   // your original spec, as a control

   return false;
  }

bool TriggerShort()
  {
   double c1 = iClose(_Symbol, InpEntryTF, 1);
   double c2 = iClose(_Symbol, InpEntryTF, 2);

   if(InpEntryMode == ENTRY_PULLBACK)
     {
      double e[];
      if(!GetBuf(hEntryEMA, 0, 4, e)) return false;
      return (c2 > e[2] && c1 < e[1]);
     }
   if(InpEntryMode == ENTRY_BREAKOUT)
     {
      int idx = iLowest(_Symbol, InpEntryTF, MODE_LOW, InpDonchianBars, 2);
      if(idx < 0) return false;
      return (c1 < iLow(_Symbol, InpEntryTF, idx));
     }
   if(InpEntryMode == ENTRY_RSI_RECOVER)
     {
      double r[];
      if(!GetBuf(hRSI, 0, 4, r)) return false;
      return (r[2] > InpRSISellLevel && r[1] <= InpRSISellLevel);
     }
   if(InpEntryMode == ENTRY_NAIVE)
      return (c1 < iOpen(_Symbol, InpEntryTF, 1));

   return false;
  }

//+------------------------------------------------------------------+
//| Sizing                                                            |
//+------------------------------------------------------------------+
double NormalizeLots(double lots)
  {
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(lotStep <= 0.0) lotStep = 0.01;

   lots = MathFloor(lots / lotStep) * lotStep;
   if(lots < minLot) lots = minLot;
   if(lots > maxLot) lots = maxLot;

   int lotDigits = (int)MathMax(0, MathCeil(-MathLog10(lotStep)));
   return NormalizeDouble(lots, lotDigits);
  }

double CalcLots(double entry, double sl)
  {
   if(InpSizingMode == SIZE_FIXED)
      return NormalizeLots(InpFixedLots);

   double riskMoney = AccountInfoDouble(ACCOUNT_BALANCE) * InpRiskPercent / 100.0;
   double slDist    = MathAbs(entry - sl);
   if(slDist <= 0.0) return 0.0;

   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickValue <= 0.0 || tickSize <= 0.0) return 0.0;

   double lossPerLot = (slDist / tickSize) * tickValue;
   if(lossPerLot <= 0.0) return 0.0;

   return NormalizeLots(riskMoney / lossPerLot);
  }

//+------------------------------------------------------------------+
//| Execution                                                         |
//+------------------------------------------------------------------+
void TryOpen(bool isLong)
  {
   int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double point  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   long   stops  = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double entry, sl, tp;

   if(isLong)
     {
      entry = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      tp    = NormalizeDouble(entry * (1.0 + InpTPPercent / 100.0), digits);
      sl    = NormalizeDouble(entry * (1.0 - InpSLPercent / 100.0), digits);
     }
   else
     {
      entry = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      tp    = NormalizeDouble(entry * (1.0 - InpTPPercent / 100.0), digits);
      sl    = NormalizeDouble(entry * (1.0 + InpSLPercent / 100.0), digits);
     }
   if(entry <= 0.0) return;

   double minDist = stops * point;
   if(MathAbs(entry - sl) < minDist || MathAbs(entry - tp) < minDist)
     {
      Print("Rejected: TP/SL inside broker stops level (", stops, " points)");
      return;
     }

   double lots = CalcLots(entry, sl);
   if(lots <= 0.0) { Print("Rejected: lot calc returned 0"); return; }

   bool ok = isLong ? trade.Buy(lots, _Symbol, 0.0, sl, tp, "GB-L")
                    : trade.Sell(lots, _Symbol, 0.0, sl, tp, "GB-S");

   if(ok)
      g_lastTradeBarTime = iTime(_Symbol, InpEntryTF, 0);
   else
      PrintFormat("Order failed: %d %s", trade.ResultRetcode(), trade.ResultRetcodeDescription());
  }

//+------------------------------------------------------------------+
//| Tick                                                              |
//+------------------------------------------------------------------+
void OnTick()
  {
   datetime bt = iTime(_Symbol, InpEntryTF, 0);
   if(bt == g_lastBarTime) return;      // one decision per closed bar
   g_lastBarTime = bt;

   if(!DailyLossOK())                          return;
   if(CountPositions() >= InpMaxOpenPositions) return;
   if(!CooldownOK())                           return;
   if(!SessionOK())                            return;
   if(!SpreadOK())                             return;

   double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(!VolatilityOK(price))   return;
   if(!TrendStrengthOK())     return;

   if(RegimeAllows(true)  && TriggerLong())  { TryOpen(true);  return; }
   if(RegimeAllows(false) && TriggerShort()) { TryOpen(false); return; }
  }

//+------------------------------------------------------------------+
//| Custom optimisation criterion                                     |
//|   Returns (actual win rate - coin-flip baseline) in pp.           |
//|   Optimising on THIS instead of net profit is the whole trick:    |
//|   it scores the filters against randomness, not against luck.     |
//+------------------------------------------------------------------+
double OnTester()
  {
   if(!HistorySelect(0, TimeCurrent())) return -100.0;

   int wins = 0, losses = 0;
   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
     {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) != (long)InpMagic) continue;
      if(HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;
      double p = HistoryDealGetDouble(ticket, DEAL_PROFIT)
               + HistoryDealGetDouble(ticket, DEAL_SWAP)
               + HistoryDealGetDouble(ticket, DEAL_COMMISSION);
      if(p > 0.0)      wins++;
      else if(p < 0.0) losses++;
     }

   int n = wins + losses;
   if(n < 30) return -100.0;   // too few trades to distinguish edge from noise

   double winRate  = 100.0 * wins / n;
   double baseline = 100.0 * InpSLPercent / (InpTPPercent + InpSLPercent);
   PrintFormat("=== Trades: %d | Win rate: %.2f%% | Coin-flip: %.2f%% | Edge: %+.2f pp ===",
               n, winRate, baseline, winRate - baseline);
   return winRate - baseline;
  }
//+------------------------------------------------------------------+
