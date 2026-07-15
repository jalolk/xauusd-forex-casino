#!/usr/bin/env python3
"""
What win rate does a COIN FLIP get with TP=0.51% / SL=0.49%?
Simulate a driftless random walk, first barrier touched wins.
This is the number your 'price going up' filter has to beat.
"""
import numpy as np

rng = np.random.default_rng(42)

TP_PCT = 0.51
SL_PCT = 0.49
N_TRADES = 200_000
VOL_PER_STEP = 0.0002   # 0.02% per tick-step, arbitrary; result is scale-invariant
MAX_STEPS = 2_000_000

def simulate(drift_per_step=0.0):
    """Vectorised barrier race. Returns fraction of trades hitting TP first."""
    up = np.log(1 + TP_PCT / 100)
    dn = np.log(1 - SL_PCT / 100)
    pos = np.zeros(N_TRADES)
    alive = np.ones(N_TRADES, dtype=bool)
    won = np.zeros(N_TRADES, dtype=bool)
    steps = 0
    while alive.any() and steps < 60000:
        n = alive.sum()
        pos[alive] += rng.normal(drift_per_step, VOL_PER_STEP, n)
        hit_tp = alive & (pos >= up)
        hit_sl = alive & (pos <= dn)
        won |= hit_tp
        alive &= ~(hit_tp | hit_sl)
        steps += 1
    return won.sum() / N_TRADES


p_random = simulate(0.0)
theory = SL_PCT / (TP_PCT + SL_PCT)

print("=" * 62)
print(f"  TP = {TP_PCT}%   SL = {SL_PCT}%")
print("=" * 62)
print(f"  Theoretical coin-flip win rate  SL/(TP+SL) : {theory*100:.3f}%")
print(f"  Monte Carlo ({N_TRADES:,} trades)          : {p_random*100:.3f}%")
print()

# Breakeven: EV = p*(TP - c) + (1-p)*(-SL - c) = 0  ->  p = (SL + c)/(TP + SL)
print("  Breakeven win rate needed, by round-trip cost:")
print(f"  {'cost':>18} | {'as % of price':>14} | {'breakeven p':>12} | {'edge needed':>12}")
print("  " + "-" * 62)
for label, cost_pct in [
    ("0 (frictionless)", 0.0),
    ("1.5 pip EURUSD", 0.0139),
    ("3 pip EURUSD", 0.0278),
    ("5 pip / retail", 0.0463),
    ("BTC 0.05% taker", 0.05),
    ("XAUUSD ~35c", 0.0106),
]:
    be = (SL_PCT + cost_pct) / (TP_PCT + SL_PCT)
    print(f"  {label:>18} | {cost_pct:>13.4f}% | {be*100:>11.3f}% | {(be-theory)*100:>+11.3f}pp")

print()
print("  Expected value per trade at coin-flip accuracy (49.0%):")
for label, cost_pct in [("1.5 pip EURUSD", 0.0139), ("3 pip EURUSD", 0.0278), ("BTC 0.05%", 0.05)]:
    ev = theory * (TP_PCT - cost_pct) + (1 - theory) * (-SL_PCT - cost_pct)
    print(f"  {label:>18} : {ev:+.5f}% per trade  ->  {ev*1000:+.2f}% after 1,000 trades")
print("=" * 62)
