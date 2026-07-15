# Why the naive mode exists

`InpEntryMode = ENTRY_NAIVE` is green candle -> long, red candle -> short. No filters,
no regime, no ATR band, nothing. It is deliberately stupid.

It is the most important setting in this EA.

## The problem it solves

You add a filter. The backtest improves. You conclude the filter works.

You have no idea whether the filter works. You changed one thing and the number
moved, and numbers move on their own - that's what noise is. Without a control,
"it improved" is a sentence about your feelings.

## How to use it

1. Run `ENTRY_NAIVE` with every filter off. Record `OnTester`.
2. Run your filtered config. Record `OnTester`.
3. **The difference between those two numbers is your only result.**

Not the equity curve. Not the profit factor. The delta.

## What it looked like here

| Config | Trades | Win % | Baseline | Edge |
|---|---|---|---|---|
| naive M30 | 2,064 | 54.36% | 52.63% | +1.73pp (on fake ticks) |

The naive control - the deliberately stupid one, with no filters at all - printed
profit factor 1.08 and +210%.

If your clever filtered strategy can't beat *that*, your filters are decoration.

That's the whole point of a control group, and it's why every EA that doesn't ship
one is asking you to take its word for something.
