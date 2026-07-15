import numpy as np
# Expected time for a driftless walk to hit +a or -b:  E[T] = a*b / sigma^2
TP, SL = 0.51, 0.49
print("="*66)
print("  How many trades can this barrier PHYSICALLY produce? (1 pos at a time)")
print("="*66)
print(f"  {'gold annual vol':>16} | {'daily vol':>9} | {'avg trade':>10} | {'trades/day':>10} | {'per year':>9}")
print("  " + "-"*62)
for annual in [12, 15, 18, 22, 28]:
    daily = annual / np.sqrt(252)
    days = (TP * SL) / (daily**2)
    hrs = days * 23          # gold trades ~23h/day
    per_day = 1.0 / days
    print(f"  {annual:>15}% | {daily:>8.2f}% | {hrs:>8.1f}h | {per_day:>10.2f} | {per_day*252:>9.0f}")
print()
print("  Trades needed to prove a +2pp edge: ~3,714")
print("  " + "-"*62)
for yrs in [1, 2, 5, 10, 16]:
    n = 2.4 * 252 * yrs
    ok = "ENOUGH" if n >= 3714 else "underpowered"
    print(f"  {yrs:>2} years of history -> ~{int(n):>5,} trades   {ok}")
print("="*66)
