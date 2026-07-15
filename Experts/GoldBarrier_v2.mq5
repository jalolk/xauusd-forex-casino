//+------------------------------------------------------------------+
//|                                                GoldBarrier_v2.mq5 |
//|                                                                   |
//|  v2 changes -- all four aimed at ONE thing: stopping you from     |
//|  believing a result that hasn't earned it.                        |
//|                                                                   |
//|   1. TICK DENSITY DETECTOR                                        |
//|      Counts real ticks per bar. Under ~50/bar the tester is       |
//|      GUESSING the intrabar path -- which for a barrier race IS    |
//|      the entire experiment. OnTester() refuses to give a verdict. |
//|                                                                   |
//|   2. STATISTICAL VERDICT                                          |
//|      OnTester() now reports z-score, p-value, trades-required,    |
//|      and a plain-English ruling. No more eyeballing PF.           |
//|                                                                   |
//|   3. BUY-AND-HOLD BENCHMARK                                       |
//|      Beating zero is easy. The bar is beating the asset you're    |
//|      trading. OnTester() computes it and says if you lost.        |
//|                                                                   |
//|   4. TIME STOP + SWAP ACCOUNTING                                  |
//|      v1 held 19.7h on average = swap on nearly every trade.       |
//|      Swap alone can eat a 1.4pp edge. Now capped and measured.    |
//|                                                                   |
//|  WHAT THIS CODE CANNOT FIX:                                       |
//|      - Getting real tick data (Tester setting + broker history)   |
//|      - Your sample size (needs more symbols / more years)         |
//|      - The 3 months a demo forward-test takes                     |
//|                                                                   |
//|  NOT FINANCIAL ADVICE.                                            |
//+------------------------------------------------------------------+
#property copyright "Built for backtesting. Not financial advice."
#property version   "2.00"
#property description "Fixed-% barrier EA with tick-model detection and a statistical verdict"

#include <Trade\Trade.mqh>

enum ENUM_ENTRY_MODE
  {
   ENTRY_PULLBACK,      // Pullback: dip below EMA then reclaim
   ENTRY_BREAKOUT,      // Breakout: take out N-bar high/low
   ENTRY_RSI_RECOVER,   // RSI: recover through level
   ENTRY_NAIVE          // NAIVE control: last candle direction
  };

enum ENUM_SIZING
  {
   SIZE_FIXED,          // Fixed lots
   SIZE_RISK_PERCENT    // Risk % of balance
  };

//+------------------------------------------------------------------+
input group           "=== Barrier ==="
input double          InpTPPercent        = 0.90;      // Take Profit (% of entry)
input double          InpSLPercent        = 1.00;      // Stop Loss (% of entry)

input group           "=== Entry Trigger ==="
input ENUM_ENTRY_MODE InpEntryMode        = ENTRY_NAIVE;
input ENUM_TIMEFRAMES InpEntryTF          = PERIOD_M30;
input int             InpPullbackEMA      = 20;
input int             InpDonchianBars     = 20;
input int             InpRSIPeriod        = 14;
input double          InpRSIBuyLevel      = 45.0;
input double          InpRSISellLevel     = 55.0;

input group           "=== Regime Filter ==="
input bool            InpUseRegime        = false;
input ENUM_TIMEFRAMES InpRegimeTF         = PERIOD_H1;
input int             InpRegimeFastEMA    = 50;
input int             InpRegimeSlowEMA    = 200;

input group           "=== Volatility Filter ==="
input bool            InpUseATRFilter     = false;
input int             InpATRPeriod        = 14;
input double          InpMinATRToTarget   = 3.0;
input double          InpMaxATRToTarget   = 20.0;

input group           "=== Trend Strength ==="
input bool            InpUseADX           = false;
input int             InpADXPeriod        = 14;
input double          InpADXMin           = 20.0;

input group           "=== Session ==="
input bool            InpUseSession       = false;
input int             InpSessionStartHour = 8;
input int             InpSessionEndHour   = 20;

input group           "=== Risk ==="
input ENUM_SIZING     InpSizingMode       = SIZE_FIXED;
input double          InpFixedLots        = 0.01;
input double          InpRiskPercent      = 0.5;

input group           "=== Guards ==="
input double          InpMaxSpreadPct     = 0.030;     // Max spread % of price (0=off)
input int             InpMaxOpenPositions = 1;
input int             InpCooldownBars     = 0;
input double          InpMaxDailyLossPct  = 0;         // 0=off

input group           "=== v2: Time Stop (kills swap drag) ==="
input int             InpMaxBarsInTrade   = 0;         // Force-close after N bars (0=off)

input group           "=== v2: Honesty Checks ==="
input bool            InpTickDensityCheck = true;      // Detect fake tick models
input double          InpMinTicksPerBar   = 50.0;      // Below this = OHLC modelling
input bool            InpAbortOnFakeTicks = false;     // true = refuse to run at all

input group           "=== Misc ==="
input ulong           InpMagic            = 880200;
input int             InpSlippagePoints   = 30;
input bool            InpVerbose          = false;

//+------------------------------------------------------------------+
CTrade   trade;
int      hRegimeFast=INVALID_HANDLE, hRegimeSlow=INVALID_HANDLE;
int      hEntryEMA=INVALID_HANDLE, hATR=INVALID_HANDLE;
int      hADX=INVALID_HANDLE, hRSI=INVALID_HANDLE;

datetime g_lastBarTime=0, g_lastTradeBarTime=0, g_currentDay=0;
double   g_dayStartBalance=0.0;

//--- v2: tick density + benchmark tracking
long     g_tickCount=0, g_barCount=0;
double   g_firstPrice=0.0, g_lastPrice=0.0;
datetime g_firstTime=0;
double   g_openLots=0.0;      // lot size used, for the B&H comparison

//+------------------------------------------------------------------+
//| Standard normal CDF (Abramowitz & Stegun 26.2.17)                |
//+------------------------------------------------------------------+
double NormalCDF(double z)
  {
   double t = 1.0 / (1.0 + 0.2316419 * MathAbs(z));
   double d = 0.3989422804014327 * MathExp(-z * z / 2.0);
   double p = d * t * (0.319381530 + t * (-0.356563782 + t * (1.781477937
              + t * (-1.821255978 + t * 1.330274429))));
   return (z > 0.0) ? 1.0 - p : p;
  }

//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpTPPercent <= 0.0 || InpSLPercent <= 0.0)
     { Print("FATAL: TP% and SL% must be > 0"); return INIT_PARAMETERS_INCORRECT; }
   if(InpRegimeFastEMA >= InpRegimeSlowEMA)
     { Print("FATAL: regime fast EMA must be < slow EMA"); return INIT_PARAMETERS_INCORRECT; }

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

   if(hRegimeFast==INVALID_HANDLE || hRegimeSlow==INVALID_HANDLE ||
      hEntryEMA==INVALID_HANDLE   || hATR==INVALID_HANDLE ||
      hADX==INVALID_HANDLE        || hRSI==INVALID_HANDLE)
     { Print("FATAL: handle creation failed, err=", GetLastError()); return INIT_FAILED; }

   g_dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   g_tickCount = 0;
   g_barCount  = 0;

   double baseline = 100.0 * InpSLPercent / (InpTPPercent + InpSLPercent);
   PrintFormat("--- GoldBarrier v2 on %s | TP %.2f%% / SL %.2f%% ---", _Symbol, InpTPPercent, InpSLPercent);
   PrintFormat("    Coin-flip baseline win rate = %.2f%%  <-- the number to beat", baseline);
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   IndicatorRelease(hRegimeFast); IndicatorRelease(hRegimeSlow);
   IndicatorRelease(hEntryEMA);   IndicatorRelease(hATR);
   IndicatorRelease(hADX);        IndicatorRelease(hRSI);
  }

//+------------------------------------------------------------------+
bool GetBuf(int handle, int buffer, int count, double &out[])
  {
   ArraySetAsSeries(out, true);
   return (CopyBuffer(handle, buffer, 0, count, out) >= count);
  }

void Reject(string why) { if(InpVerbose) Print("reject: ", why); }

//+------------------------------------------------------------------+
bool RegimeAllows(bool isLong)
  {
   if(!InpUseRegime) return true;
   double f[], s[];
   if(!GetBuf(hRegimeFast,0,3,f)) return false;
   if(!GetBuf(hRegimeSlow,0,3,s)) return false;
   return isLong ? (f[1] > s[1]) : (f[1] < s[1]);
  }

bool VolatilityOK(double price)
  {
   if(!InpUseATRFilter) return true;
   double a[];
   if(!GetBuf(hATR,0,3,a)) return false;
   if(a[1] <= 0.0) return false;
   double ratio = (price * InpTPPercent / 100.0) / a[1];
   if(ratio < InpMinATRToTarget || ratio > InpMaxATRToTarget)
     { Reject(StringFormat("ATR ratio %.1f out of band", ratio)); return false; }
   return true;
  }

bool TrendStrengthOK()
  {
   if(!InpUseADX) return true;
   double a[];
   if(!GetBuf(hADX,0,3,a)) return false;
   if(a[1] < InpADXMin) { Reject("ADX too low"); return false; }
   return true;
  }

bool SessionOK()
  {
   if(!InpUseSession) return true;
   MqlDateTime t; TimeToStruct(TimeCurrent(), t);
   if(InpSessionStartHour <= InpSessionEndHour)
      return (t.hour >= InpSessionStartHour && t.hour < InpSessionEndHour);
   return (t.hour >= InpSessionStartHour || t.hour < InpSessionEndHour);
  }

bool SpreadOK()
  {
   if(InpMaxSpreadPct <= 0.0) return true;
   double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(price <= 0.0) return false;
   double sprPct = (SymbolInfoInteger(_Symbol,SYMBOL_SPREAD) *
                    SymbolInfoDouble(_Symbol,SYMBOL_POINT)) / price * 100.0;
   if(sprPct > InpMaxSpreadPct) { Reject("spread too wide"); return false; }
   return true;
  }

bool CooldownOK()
  {
   if(InpCooldownBars <= 0 || g_lastTradeBarTime == 0) return true;
   return (iBarShift(_Symbol, InpEntryTF, g_lastTradeBarTime, false) >= InpCooldownBars);
  }

bool DailyLossOK()
  {
   if(InpMaxDailyLossPct <= 0.0) return true;
   MqlDateTime t; TimeToStruct(TimeCurrent(), t);
   t.hour=0; t.min=0; t.sec=0;
   datetime today = StructToTime(t);
   if(today != g_currentDay)
     { g_currentDay = today; g_dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE); }
   if(g_dayStartBalance <= 0.0) return true;
   double dd = (g_dayStartBalance - AccountInfoDouble(ACCOUNT_EQUITY)) / g_dayStartBalance * 100.0;
   return (dd < InpMaxDailyLossPct);
  }

int CountPositions()
  {
   int n = 0;
   for(int i = PositionsTotal()-1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == (long)InpMagic) n++;
     }
   return n;
  }

//--- v2: time stop. v1 averaged 19h43m per trade = swap on almost every one.
void CheckTimeStop()
  {
   if(InpMaxBarsInTrade <= 0) return;
   long maxSec = (long)InpMaxBarsInTrade * PeriodSeconds(InpEntryTF);
   for(int i = PositionsTotal()-1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != (long)InpMagic) continue;
      datetime opened = (datetime)PositionGetInteger(POSITION_TIME);
      if((long)(TimeCurrent() - opened) >= maxSec)
        {
         trade.PositionClose(tk);
         Reject("time stop fired");
        }
     }
  }

//+------------------------------------------------------------------+
bool TriggerLong()
  {
   double c1 = iClose(_Symbol, InpEntryTF, 1);
   double c2 = iClose(_Symbol, InpEntryTF, 2);
   if(InpEntryMode == ENTRY_PULLBACK)
     { double e[]; if(!GetBuf(hEntryEMA,0,4,e)) return false; return (c2 < e[2] && c1 > e[1]); }
   if(InpEntryMode == ENTRY_BREAKOUT)
     { int i = iHighest(_Symbol,InpEntryTF,MODE_HIGH,InpDonchianBars,2);
       if(i < 0) return false; return (c1 > iHigh(_Symbol,InpEntryTF,i)); }
   if(InpEntryMode == ENTRY_RSI_RECOVER)
     { double r[]; if(!GetBuf(hRSI,0,4,r)) return false;
       return (r[2] < InpRSIBuyLevel && r[1] >= InpRSIBuyLevel); }
   if(InpEntryMode == ENTRY_NAIVE)
      return (c1 > iOpen(_Symbol, InpEntryTF, 1));
   return false;
  }

bool TriggerShort()
  {
   double c1 = iClose(_Symbol, InpEntryTF, 1);
   double c2 = iClose(_Symbol, InpEntryTF, 2);
   if(InpEntryMode == ENTRY_PULLBACK)
     { double e[]; if(!GetBuf(hEntryEMA,0,4,e)) return false; return (c2 > e[2] && c1 < e[1]); }
   if(InpEntryMode == ENTRY_BREAKOUT)
     { int i = iLowest(_Symbol,InpEntryTF,MODE_LOW,InpDonchianBars,2);
       if(i < 0) return false; return (c1 < iLow(_Symbol,InpEntryTF,i)); }
   if(InpEntryMode == ENTRY_RSI_RECOVER)
     { double r[]; if(!GetBuf(hRSI,0,4,r)) return false;
       return (r[2] > InpRSISellLevel && r[1] <= InpRSISellLevel); }
   if(InpEntryMode == ENTRY_NAIVE)
      return (c1 < iOpen(_Symbol, InpEntryTF, 1));
   return false;
  }

//+------------------------------------------------------------------+
double NormalizeLots(double lots)
  {
   double mn = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double mx = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double st = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(st <= 0.0) st = 0.01;
   lots = MathFloor(lots / st) * st;
   if(lots < mn) lots = mn;
   if(lots > mx) lots = mx;
   return NormalizeDouble(lots, (int)MathMax(0, MathCeil(-MathLog10(st))));
  }

double CalcLots(double entry, double sl)
  {
   if(InpSizingMode == SIZE_FIXED) return NormalizeLots(InpFixedLots);
   double riskMoney = AccountInfoDouble(ACCOUNT_BALANCE) * InpRiskPercent / 100.0;
   double slDist = MathAbs(entry - sl);
   if(slDist <= 0.0) return 0.0;
   double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tv <= 0.0 || ts <= 0.0) return 0.0;
   double lossPerLot = (slDist / ts) * tv;
   if(lossPerLot <= 0.0) return 0.0;
   return NormalizeLots(riskMoney / lossPerLot);
  }

void TryOpen(bool isLong)
  {
   int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double point  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   long   stops  = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double entry, sl, tp;

   if(isLong)
     {
      entry = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      tp = NormalizeDouble(entry * (1.0 + InpTPPercent/100.0), digits);
      sl = NormalizeDouble(entry * (1.0 - InpSLPercent/100.0), digits);
     }
   else
     {
      entry = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      tp = NormalizeDouble(entry * (1.0 - InpTPPercent/100.0), digits);
      sl = NormalizeDouble(entry * (1.0 + InpSLPercent/100.0), digits);
     }
   if(entry <= 0.0) return;

   double minDist = stops * point;
   if(MathAbs(entry-sl) < minDist || MathAbs(entry-tp) < minDist)
     { Print("Rejected: inside stops level"); return; }

   double lots = CalcLots(entry, sl);
   if(lots <= 0.0) return;
   g_openLots = lots;

   bool ok = isLong ? trade.Buy(lots,_Symbol,0.0,sl,tp,"GB-L")
                    : trade.Sell(lots,_Symbol,0.0,sl,tp,"GB-S");
   if(ok) g_lastTradeBarTime = iTime(_Symbol, InpEntryTF, 0);
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   //--- v2: tick density tracking. Runs on EVERY tick, before the bar gate.
   g_tickCount++;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(bid > 0.0)
     {
      g_lastPrice = bid;
      if(g_firstPrice <= 0.0) { g_firstPrice = bid; g_firstTime = TimeCurrent(); }
     }

   CheckTimeStop();

   datetime bt = iTime(_Symbol, InpEntryTF, 0);
   if(bt == g_lastBarTime) return;
   g_lastBarTime = bt;
   g_barCount++;

   if(!DailyLossOK())                          return;
   if(CountPositions() >= InpMaxOpenPositions) return;
   if(!CooldownOK())                           return;
   if(!SessionOK())                            return;
   if(!SpreadOK())                             return;

   double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(!VolatilityOK(price)) return;
   if(!TrendStrengthOK())   return;

   if(RegimeAllows(true)  && TriggerLong())  { TryOpen(true);  return; }
   if(RegimeAllows(false) && TriggerShort()) { TryOpen(false); return; }
  }

//+------------------------------------------------------------------+
//| v2 OnTester: the verdict machine                                  |
//+------------------------------------------------------------------+
double OnTester()
  {
   double ticksPerBar = (g_barCount > 0) ? (double)g_tickCount / (double)g_barCount : 0.0;

   Print("");
   Print("================================================================");
   Print("  GoldBarrier v2 -- VERDICT");
   Print("================================================================");

   //--- CHECK 1: is the tick model real?
   bool fakeTicks = (ticksPerBar < InpMinTicksPerBar);
   PrintFormat("  Tick density : %.1f ticks/bar  (%d ticks / %d bars)",
               ticksPerBar, (int)g_tickCount, (int)g_barCount);
   if(fakeTicks && InpTickDensityCheck)
     {
      Print("  ");
      Print("  *** STOP. THE TICK MODEL IS FAKE. ***");
      Print("  Under 50 ticks/bar means the tester did NOT simulate the");
      Print("  intrabar path -- it guessed it from an assumed O->H->L->C.");
      Print("  This strategy is a RACE between two price levels. The path");
      Print("  IS the experiment. Every number below is meaningless.");
      Print("  ");
      Print("  Fix: Strategy Tester -> Modelling -> 'Every tick based on");
      Print("  real ticks'. If your broker lacks real ticks for this range,");
      Print("  get them (Dukascopy) or shorten the range to where they exist.");
      Print("================================================================");
      if(InpAbortOnFakeTicks) return -1000.0;
     }

   //--- gather trade outcomes
   if(!HistorySelect(0, TimeCurrent())) return -1000.0;
   int wins=0, losses=0;
   double grossWin=0.0, grossLoss=0.0, totalSwap=0.0, totalComm=0.0;
   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
     {
      ulong tk = HistoryDealGetTicket(i);
      if(tk == 0) continue;
      if(HistoryDealGetInteger(tk, DEAL_MAGIC) != (long)InpMagic) continue;
      if(HistoryDealGetInteger(tk, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;
      double pr = HistoryDealGetDouble(tk, DEAL_PROFIT);
      double sw = HistoryDealGetDouble(tk, DEAL_SWAP);
      double cm = HistoryDealGetDouble(tk, DEAL_COMMISSION);
      totalSwap += sw; totalComm += cm;
      double net = pr + sw + cm;
      if(net > 0.0)      { wins++;   grossWin  += net; }
      else if(net < 0.0) { losses++; grossLoss += -net; }
     }
   int n = wins + losses;
   if(n < 30) { Print("  Fewer than 30 trades. Nothing to say."); return -1000.0; }

   //--- CHECK 2: statistics
   double winRate  = 100.0 * wins / n;
   double baseline = 100.0 * InpSLPercent / (InpTPPercent + InpSLPercent);
   double edgePP   = winRate - baseline;
   double se       = MathSqrt(0.25 / n) * 100.0;
   double z        = edgePP / se;
   double pval     = 1.0 - NormalCDF(z);
   double nReq     = (edgePP != 0.0)
                     ? MathPow((1.645 + 0.842) * 0.5 / (edgePP/100.0), 2.0) : 0.0;

   Print("  ");
   PrintFormat("  Trades            : %d  (%d W / %d L)", n, wins, losses);
   PrintFormat("  Win rate          : %.2f%%", winRate);
   PrintFormat("  Coin-flip baseline: %.2f%%", baseline);
   PrintFormat("  EDGE              : %+.2f pp", edgePP);
   PrintFormat("  Extra wins vs coin: %+d trades   (noise SD = +/- %.0f trades)",
               wins - (int)MathRound(n * baseline/100.0),
               MathSqrt(n * (baseline/100.0) * (1.0-baseline/100.0)));
   PrintFormat("  z-score           : %+.2f", z);
   PrintFormat("  p-value (1-sided) : %.4f", pval);
   PrintFormat("  Trades needed     : ~%d  (you have %d)", (int)nReq, n);

   //--- CHECK 3: buy-and-hold benchmark
   double netProfit = grossWin - grossLoss;
   double bh = 0.0;
   if(g_firstPrice > 0.0 && g_lastPrice > 0.0 && g_openLots > 0.0)
     {
      double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      if(tv > 0.0 && ts > 0.0)
         bh = ((g_lastPrice - g_firstPrice) / ts) * tv * g_openLots;
     }
   Print("  ");
   PrintFormat("  Net profit (EA)   : %.2f", netProfit);
   PrintFormat("  Buy & hold same   : %.2f   (%.2f -> %.2f, %.2f lots)",
               bh, g_firstPrice, g_lastPrice, g_openLots);
   if(bh > 0.0)
      PrintFormat("  EA vs buy & hold  : %+.1f%%   <-- THIS is the real benchmark",
                  (netProfit/bh - 1.0) * 100.0);
   PrintFormat("  Swap paid         : %.2f  (%.1f%% of gross profit)",
               totalSwap, (grossWin>0.0 ? -totalSwap/grossWin*100.0 : 0.0));
   PrintFormat("  Commission paid   : %.2f", totalComm);

   //--- ruling
   Print("  ");
   Print("  ---------------- RULING ----------------");
   if(fakeTicks && InpTickDensityCheck)
      Print("  INVALID - fake tick model. Re-run on real ticks.");
   else if(edgePP <= 0.0)
      Print("  NO EDGE - at or below a coin flip.");
   else if(pval > 0.10)
      Print("  NOT SIGNIFICANT - indistinguishable from luck.");
   else if(pval > 0.05)
      Print("  MARGINAL - interesting, not proof. Need more trades.");
   else if(n < (int)nReq)
      PrintFormat("  UNDERPOWERED - p looks good but you need ~%d trades.", (int)nReq);
   else
      Print("  SIGNIFICANT - survives the null. Now forward-test on demo.");

   if(bh > 0.0 && netProfit < bh)
      Print("  WARNING: buying and holding the asset beat this EA.");
   Print("================================================================");

   if(fakeTicks && InpTickDensityCheck) return -1000.0;
   return edgePP;
  }
//+------------------------------------------------------------------+
