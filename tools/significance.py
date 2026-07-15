#!/usr/bin/env python3
"""
Is PF 1.04 an edge, or is it luck?

Null hypothesis: the EA has NO edge. Gold random-walks. You enter at Ask,
so in bid-space your barriers are asymmetric by the spread:
    up   barrier = 0.51% + spread%
    down barrier = 0.49% - spread%
Realised P&L is still exactly +0.51% / -0.49% per trade.

Question: how often does a NO-EDGE strategy print PF >= 1.04 by chance?
"""
import numpy as np

rng = np.random.default_rng(7)

TP, SL = 0.51, 0.49
SPREAD = 0.0106          # XAUUSD ~35c at 3300 = 0.0106% of price

# --- Under the null, win prob = down_barrier / (up_barrier + down_barrier)
up_b = TP + SPREAD
dn_b = SL - SPREAD
p_null = dn_b / (up_b + dn_b)

def pf_from_p(p):
    return (p * TP) / ((1 - p) * SL)

def p_from_pf(pf):
    # p*TP / ((1-p)*SL) = pf   ->   p = pf*SL / (TP + pf*SL)
    return (pf * SL) / (TP + pf * SL)

p_breakeven = p_from_pf(1.0)
p_observed  = p_from_pf(1.04)

print("=" * 70)
print(f"  TP={TP}%  SL={SL}%  spread={SPREAD}%")
print("=" * 70)
print(f"  Effective barriers in bid-space : +{up_b:.4f}% / -{dn_b:.4f}%")
print()
print(f"  NO-EDGE win rate (the null)     : {p_null*100:.2f}%   -> PF {pf_from_p(p_null):.3f}")
print(f"  Breakeven win rate (PF = 1.00)  : {p_breakeven*100:.2f}%")
print(f"  YOUR result   (PF = 1.04)       : {p_observed*100:.2f}%")
print(f"  Apparent edge over no-edge      : {(p_observed - p_null)*100:+.2f} pp")
print()

# --- How often does pure luck produce PF >= 1.04?
print("  P(a NO-EDGE strategy prints PF >= 1.04 by pure luck):")
print(f"  {'trades':>8} | {'P(PF>=1.04)':>12} | {'verdict':<34}")
print("  " + "-" * 62)

N_SIMS = 200_000
for n in [100, 200, 300, 500, 1000, 2000, 5000, 10000]:
    wins = rng.binomial(n, p_null, N_SIMS)
    gross_p = wins * TP
    gross_l = (n - wins) * SL
    with np.errstate(divide="ignore", invalid="ignore"):
        pf = np.where(gross_l > 0, gross_p / gross_l, np.inf)
    prob = (pf >= 1.04).mean()
    if   prob > 0.30: v = "pure noise, means nothing"
    elif prob > 0.15: v = "still probably luck"
    elif prob > 0.05: v = "interesting, not proof"
    elif prob > 0.01: v = "worth taking seriously"
    else:             v = "likely a real edge"
    print(f"  {n:>8} | {prob*100:>11.1f}% | {v:<34}")

print()
# --- Sample size needed to prove the edge is real
print("  Trades needed to call this edge REAL (one-sided, 95% conf, 80% power):")
delta = p_observed - p_null
n_req = ((1.645 + 0.842) * np.sqrt(0.25) / delta) ** 2
print(f"    effect size = {delta*100:.2f} pp  ->  n ~ {int(n_req):,} trades")
print("=" * 70)
