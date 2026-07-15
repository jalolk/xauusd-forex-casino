# Why your backtest is probably fiction

## The one number that matters

Open your MT5 report. Find `Bars` and `Ticks`. Divide.

```
Bars: 76,982   Ticks: 303,429   ->  3.94 ticks per bar
```

3.94 ticks per bar means MT5 checked the price **four times** inside each 30-minute
candle: open, high, low, close. It did not simulate the path between them.
It assumed one.

## Why that specifically destroys THIS strategy

This EA is a race. Price starts at X. Does it reach `X * 1.009` or `X * 0.99` first?

The answer depends **entirely** on the order in which prices occurred inside the bar.
That ordering is the experiment. It is the only thing being measured.

With OHLC modelling, MT5 doesn't know the ordering. It guesses, using a fixed
heuristic (roughly O->H->L->C on up bars, O->L->H->C on down bars). So when both
your barriers sit inside one bar's range, the tester decides your trade's outcome
by convention rather than by data.

For a trend-following EA that holds for weeks, that guess is a rounding error.
For a barrier race, **the guess is the result.**

## What to do

Strategy Tester -> Modelling -> **"Every tick based on real ticks"**

Then check the ratio again. Real ticks on gold gives you thousands per bar,
not four. If your broker has no real tick history for your date range:

- Get it from Dukascopy and import
- Or shorten the range to where real ticks exist

**Fewer trades on real data beats 4,404 trades on guessed data.** One of those
numbers means something.

## The detector

`GoldBarrier_v2.mq5` counts ticks per bar itself and returns `-1000` from
`OnTester()` if the density is below `InpMinTicksPerBar` (default 50).

This is deliberate. It means the optimiser can never rank a fake-tick run above
a real one, no matter how green the equity curve is. Set
`InpAbortOnFakeTicks=true` and it won't even run.

You cannot accidentally trust a bad tick model. That's a feature.
