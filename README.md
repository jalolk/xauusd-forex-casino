# 🎰 You Are Not The Casino

**An MT5 Expert Advisor that spams gold trades and then mathematically proves to you that it shouldn't have.**

![Edge](https://img.shields.io/badge/edge-%2B1.40pp-yellow)
![Significance](https://img.shields.io/badge/p--value-0.10-red)
![Verdict](https://img.shields.io/badge/verdict-NOT%20SIGNIFICANT-red)
![Buy and Hold](https://img.shields.io/badge/vs%20buy--and--hold-LOST-critical)
![OnTester](https://img.shields.io/badge/OnTester-−1000-black)
![License](https://img.shields.io/badge/license-MIT-blue)

---

## What is this

Most forex EAs on GitHub are trying to sell you a dream.

This one is trying to take it away from you, using arithmetic, as a kindness.

`GoldBarrier` is a fully functional MT5 Expert Advisor. It opens tiny positions on XAUUSD with a fixed-percentage take profit and stop loss, thousands of times, exactly like you always suspected a "casino algorithm" should work. It backtests green. It has a profit factor above 1. It made +210% in six years.

It is also, on current evidence, **an expensive random number generator**, and it will tell you so itself, in your own terminal, every single run.

That's the entire project.

---

## The pitch (what every other repo would say here)

> 🚀🚀 **XAUUSD SCALPER — 54% WIN RATE — PROFIT FACTOR 1.08 — +210% IN 6 YEARS** 🚀🚀
> 2,064 trades. Fully automated. Set and forget. DM for VPS setup. 💰

Every number in that box is true. Here's the report to prove it:

| Metric | Value |
|---|---|
| Total Net Profit | **+2,101.69** on a 1,000 deposit |
| Profit Factor | **1.08** |
| Win rate | **54.36%** |
| Total Trades | **2,064** |
| Period | 2020.01.01 – 2026.07.15 |
| Sharpe Ratio | 0.42 |

And here is what the EA printed underneath it:

```
================================================================
  GoldBarrier v2 -- VERDICT
================================================================
  Tick density : 3.9 ticks/bar  (303429 ticks / 76982 bars)

  *** STOP. THE TICK MODEL IS FAKE. ***

  ---------------- RULING ----------------
  INVALID - fake tick model. Re-run on real ticks.
  WARNING: buying and holding the asset beat this EA.
================================================================

OnTester result: -1000
```

The EA refused to score its own winning backtest.

---

## Why it did that

### 1. You cannot choose your way to an edge

The strategy is a race: does price move up `TP%` before it moves down `SL%`? Surely there's a magic ratio?

There is not. Here is the expected value of **every** TP/SL combination, on a driftless walk:

```
      TP%     SL% |   ratio |  win rate |     EV/trade
     0.51    0.49 |    1.04 |    49.00% | +0.000000000%
     0.60    0.40 |    1.50 |    40.00% | +0.000000000%
     0.90    0.10 |    9.00 |    10.00% | +0.000000000%
     0.10    0.90 |    0.11 |    90.00% | +0.000000000%
     5.00    0.50 |   10.00 |     9.09% | +0.000000000%
```

**Exactly zero. All of them.** Not approximately — exactly. It's the [optional stopping theorem](https://en.wikipedia.org/wiki/Optional_stopping_theorem), and it is not negotiable.

Want a 90% win rate? Set TP 0.10 / SL 0.90. You'll get it. You'll also make exactly nothing, because your 10% of losses are 9× the size. The market does not care where you drew your lines.

Then you add the spread, and every single row goes negative.

### 2. The casino analogy is backwards

A casino wins because it **wrote the rules**: 37 slots, pays 36:1. Structural. It never predicts anything.

You don't write the rules. You enter at Ask and exit at Bid. Guess who wrote *that* rule.

```
  game                           |  house edge | who has it
  Blackjack (basic strategy)     |       0.50% | the casino, over the player
  Baccarat (banker)              |       1.06% | the casino, over the player
  Craps (pass line)              |       1.41% | the casino, over the player
  YOUR 0.51/0.49 gold trade      |       2.16% | >>> THE BROKER, over you <<<
  Roulette (single zero)         |       2.70% | the casino, over the player
  Slots (typical)                |       8.00% | the casino, over the player
```

**You are not the house. You are at a roulette table with a slightly nicer wheel.** The spread is the green zero. The broker never has to be right about anything.

### 3. "But I'll make it up on volume"

The casino spams volume because its edge is **already positive**. The Law of Large Numbers is its employee. Point that same law at a negative edge and it executes you with equal reliability:

```
    trades |  P(profit) @ -2.16% edge |  P(profit) @ +2% edge
        10 |                   56.56% |                64.85%
       100 |                   44.72% |                68.86%
     1,000 |                   24.30% |                88.75%
    10,000 |                    1.64% |               100.00%
   100,000 |                    0.00% |               100.00%
```

Volume is a magnifying glass, not an engine. It doesn't create an edge — it reveals the one you already have. **Spam a negative edge and you don't become the casino. You become its favourite customer.**

### 4. The entire strategy is 29 coin flips

```
  Coin flip would have won :  1090 of 2071
  You actually won         :  1119 of 2071
  Difference               :    29 trades   <-- this is the whole edge

  Random noise in the win COUNT has SD = +/- 23 trades
  You are 1.28 standard deviations above chance.

  Trades needed for significance : ~7,889   (you have 2,071)
```

Six years. 2,064 trades. A 38% equity drawdown. **Twenty-nine lucky coin flips** separate +210% from nothing.

At ~1.26 trades/day you'd need **~25 years** of gold history to prove that edge. It does not exist at your broker, and the 2001 gold market has nothing to do with this one. **At this barrier width, on this one symbol, the edge is unprovable in principle.**

### 5. It lost to doing absolutely nothing

The EA traded 0.01 lots = **one ounce of gold**. Gold went 1505 → 4117 over the test window.

| | Profit on 1,000 | Max drawdown | Trades | Sharpe |
|---|---|---|---|---|
| **This EA** | +2,101 | **38.08%** | 2,064 | 0.42 |
| **Buy 1oz gold. Go outside.** | **+2,612** | ~22% | 1 | — |

Six years of automation, 2,064 executions, and a 38% drawdown — to underperform *a man who bought one ounce of gold and forgot about it.*

---

## The features nobody wants

Standard EAs hide this stuff. This one leads with it.

### 🔍 Tick-model lie detector

Counts real ticks per bar. Under ~50/bar means the tester never simulated the intrabar path — it **guessed** it from an assumed O→H→L→C ordering. For a strategy that is *nothing but* a race between two price levels, the path **is** the experiment.

Get caught, and `OnTester()` returns **−1000**, so the optimiser can never rank a fantasy above a real result. Set `InpAbortOnFakeTicks=true` and it won't even finish.

### ⚖️ An `OnTester()` that scores you against randomness

Not against profit. **Optimise on profit and you will find gorgeous parameters on pure noise, every time, guaranteed.** This one returns *win rate minus the coin-flip baseline*, plus z-score, p-value, required sample size, and a plain-English ruling:

```
  INVALID          - fake tick model. Re-run on real ticks.
  NO EDGE          - at or below a coin flip.
  NOT SIGNIFICANT  - indistinguishable from luck.
  MARGINAL         - interesting, not proof.
  UNDERPOWERED     - p looks good, you need ~N trades.
  SIGNIFICANT      - survives the null. Now forward-test on demo.
```

### 📉 Buy-and-hold benchmark

Beating zero is easy. Beating the asset you're trading is the actual bar. The EA computes it and prints `WARNING: buying and holding the asset beat this EA.` when you lose to a sleeping man.

### 🎮 A control group

`InpEntryMode = ENTRY_NAIVE` — green candle → long, red candle → short. No filters. It exists so you can measure whether your clever filters beat *stupid*. **Run it first. Always.** A result without a control is a vibe.

---

## Results table

Every run here is on OHLC modelling (3.94 ticks/bar), which is exactly why every `OnTester` reads −1000. These numbers are **decorative**.

| Config | Trades | Win % | PF | Net | Sharpe | Avg hold | OnTester |
|---|---|---|---|---|---|---|---|
| M30 naive (v1) | 2,071 | 54.03% | 1.07 | +1,880 | 0.34 | 19:43 | 1.426 |
| M30 replicate (v2) | 2,064 | 54.36% | 1.08 | +2,101 | 0.42 | 19:45 | **−1000** |
| M30 + time stop (v2) | 4,404 | 49.82% | 1.05 | +1,460 | 0.27 | 09:14 | **−1000** |

Fun detail: the time stop **doubled** the trade count and dropped the win rate *below* the coin-flip baseline (49.82% vs 52.63%), while Sharpe fell from 0.42 to 0.27. An "improvement" that improved nothing.

---

## Install

```bash
git clone https://github.com/YOURNAME/you-are-not-the-casino.git
```

1. Copy `Experts/GoldBarrier_v2.mq5` → `MQL5/Experts/`
2. Copy `Presets/*.set` → `MQL5/Presets/`
3. Compile in MetaEditor (F7). No external indicators needed.
4. Strategy Tester → **Modelling: "Every tick based on real ticks"**
5. Watch it return −1000 anyway because your broker doesn't have real ticks back to 2020
6. Achieve enlightenment

---

## FAQ

**Q: Can I run this on a real account?**
Its own `OnTester()` returns −1000. It is telling you no. Listen to it.

**Q: What if I optimise the parameters?**
You'll find a beautiful set. On noise. That's why `OnTester()` scores you against random instead of against profit — to make curve-fitting *harder*, not easier. You're welcome, and I'm sorry.

**Q: The backtest is green though.**
So is the OHLC path assumption that produced it.

**Q: What TP/SL makes me the casino?**
None. Read section 1 again. I'll wait.

**Q: Is there any way to actually be the casino?**
Two. **Market making** — quote both sides, collect the spread, which needs colocation and inventory models and is banned by your broker anyway. Or **card counting** — find real information, accept you're a player with an edge rather than the house. There is no third option and the third option is what you were hoping for.

**Q: So is any of this profitable?**
Maybe +1.40pp. On fake ticks. With p=0.10. On one symbol. Losing to buy-and-hold. You tell me.

**Q: Why does this exist?**
Because "my backtest is green" and "I found an edge" are different sentences, and roughly nobody's repo knows that.

---

## Actually doing this properly

If you want the real answer instead of a nice feeling:

1. **Real ticks.** Dukascopy, or a broker with genuine tick history. Non-negotiable. Fewer trades on real data beats 4,404 on guessed data.
2. **Pool 20 symbols.** 20 × 2,000 = 40,000 trades, clearing the 7,889 threshold five times over. An edge on gold alone is a story about gold. An edge across twenty uncorrelated instruments is a finding.
3. **Benchmark buy-and-hold**, not zero.
4. **Demo forward-test, 3+ months.** Live spread, live slippage, live swap, zero risk.
5. *Then* talk about money you can afford to set on fire.

Most people never find an edge. That's not pessimism — it's why the edge is worth something when you do.

---

## License

MIT. Do whatever you want. It's not going to help.

## Disclaimer

**Not financial advice.** This software is an educational demonstration that trading a fixed-percentage barrier without an edge has negative expectancy, and it demonstrates this by having negative expectancy. Trading involves substantial risk of loss. You are responsible for your own decisions.

The author's honest position: **do not run this with real money.** It's a teaching instrument. The lesson is free. The tuition, if you ignore it, is not.

---

<div align="center">

*"The house always wins. You're just confused about which one you are."*

</div>
