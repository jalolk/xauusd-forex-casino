#!/usr/bin/env python3
"""
"What TP/SL makes me the casino?"

Answer: none. Here's the proof, then the real question.
"""
import numpy as np

SPREAD = 0.0106   # XAUUSD ~35c at 3300, as % of price

print("=" * 78)
print("  PART 1: expected value of the barrier race, BEFORE costs")
print("=" * 78)
print("  Driftless walk. p(hit TP first) = SL/(TP+SL).")
print("  EV = p*TP - (1-p)*SL")
print()
print(f"  {'TP%':>7} {'SL%':>7} | {'ratio':>7} | {'win rate':>9} | {'EV/trade':>12}")
print("  " + "-" * 60)

combos = [
    (0.51, 0.49), (0.60, 0.40), (0.75, 0.25), (0.90, 0.10),
    (0.40, 0.60), (0.25, 0.75), (0.10, 0.90),
    (1.00, 1.00), (2.00, 1.00), (1.00, 2.00),
    (5.00, 0.50), (0.50, 5.00), (0.05, 0.05), (10.0, 10.0),
]
for tp, sl in combos:
    p  = sl / (tp + sl)
    ev = p * tp - (1 - p) * sl
    print(f"  {tp:>7.2f} {sl:>7.2f} | {tp/sl:>7.2f} | {p*100:>8.2f}% | {ev:>+11.9f}%")

print()
print("  Every single one is EXACTLY zero. Not approximately. Exactly.")
print("  This is the optional stopping theorem: you cannot create drift")
print("  by choosing where to put the exits. The walk doesn't care.")
print()

print("=" * 78)
print("  PART 2: now add the spread")
print("=" * 78)
print("  You enter at Ask, so in bid-space the barriers shift:")
print("    up barrier = TP + spread   |   down barrier = SL - spread")
print()
print(f"  {'TP%':>7} {'SL%':>7} | {'win rate':>9} | {'EV/trade':>10} | {'HOUSE EDGE':>11}")
print("  " + "-" * 60)

for tp, sl in [(0.05,0.05),(0.10,0.10),(0.25,0.25),(0.51,0.49),
               (1.00,1.00),(2.00,2.00),(5.00,5.00),(10.0,10.0)]:
    up, dn = tp + SPREAD, sl - SPREAD
    if dn <= 0:
        continue
    p  = dn / (up + dn)
    ev = p * tp - (1 - p) * sl
    house = -ev / sl * 100     # expected loss as % of amount risked
    print(f"  {tp:>7.2f} {sl:>7.2f} | {p*100:>8.2f}% | {ev:>+9.4f}% | {house:>10.2f}%")

print()
print("  Every one negative. TP/SL choice controls only HOW FAST you bleed,")
print("  never WHETHER you bleed. Bigger barriers bleed slower (spread is a")
print("  smaller slice of the target). Smaller barriers bleed faster.")
print("  Neither ever crosses zero.")
print()

print("=" * 78)
print("  PART 3: who is actually the casino here?")
print("=" * 78)
tp, sl = 0.51, 0.49
up, dn = tp + SPREAD, sl - SPREAD
p  = dn / (up + dn)
ev = p * tp - (1 - p) * sl
your_house_edge = -ev / sl * 100

games = [
    ("Blackjack (basic strategy)", 0.50),
    ("Baccarat (banker)",          1.06),
    ("Craps (pass line)",          1.41),
    ("YOUR 0.51/0.49 gold trade",  your_house_edge),
    ("Roulette (single zero)",     2.70),
    ("Roulette (double zero)",     5.26),
    ("Slots (typical)",            8.00),
]
print(f"  {'game':<30} | {'house edge':>11} | who has it")
print("  " + "-" * 66)
for name, edge in sorted(games, key=lambda x: x[1]):
    who = ">>> THE BROKER, over you <<<" if name.startswith("YOUR") else "the casino, over the player"
    print(f"  {name:<30} | {edge:>10.2f}% | {who}")

print()
print("  You are not the casino. You are the player at a roulette table")
print("  with a slightly better-than-average wheel. The spread is the green zero.")
print("  The broker is the house, and it never has to predict anything.")
print()

print("=" * 78)
print("  PART 4: why 'a lot of trades' is the exact wrong instinct")
print("=" * 78)
print("  The casino spams volume because its edge is POSITIVE. Volume")
print("  converts a small positive edge into near-certain profit.")
print("  That same law works in reverse. Your edge is negative.")
print()
print(f"  {'trades':>8} | {'P(profit) @ -2.16% edge':>24} | {'P(profit) @ +2% edge':>21}")
print("  " + "-" * 62)
rng = np.random.default_rng(11)
for n in [10, 100, 1_000, 10_000, 100_000]:
    # negative edge: the real thing
    wins_neg = rng.binomial(n, p, 20000)
    pnl_neg  = wins_neg * tp - (n - wins_neg) * sl
    # hypothetical positive edge for contrast
    p_pos    = 0.51
    wins_pos = rng.binomial(n, p_pos, 20000)
    pnl_pos  = wins_pos * tp - (n - wins_pos) * sl
    print(f"  {n:>8,} | {(pnl_neg > 0).mean()*100:>23.2f}% | {(pnl_pos > 0).mean()*100:>20.2f}%")

print()
print("  Volume is a magnifying glass. It doesn't create an edge, it reveals")
print("  the one you already have. Spam a negative edge and you don't become")
print("  the casino -- you become its favourite customer.")
print("=" * 78)
