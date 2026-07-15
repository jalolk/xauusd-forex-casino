# tools/

Python scripts that produced every number in the root README.
Nothing here is illustrative. Run them and check the maths yourself.

| script | what it proves |
|---|---|
| `coinflip_baseline.py`   | A coin flip wins `SL/(TP+SL)` of the time. Monte Carlo confirms the closed form. |
| `prove_no_edge.py`       | EV = exactly 0 for **every** TP/SL combination. Then the casino house-edge table, then why volume makes it worse. |
| `significance.py`        | How often a no-edge strategy prints your profit factor by pure luck, at each trade count. |
| `barrier_throughput.py`  | Why your timeframe doesn't control trade count — the barrier does. |
| `parse_report.py`        | Pull the key stats (incl. ticks/bar) out of an MT5 `ReportTester-*.html`. |

```bash
pip install numpy
python3 tools/prove_no_edge.py
```

## The ticks-per-bar check

The single fastest way to know if your backtest is fiction:

```bash
python3 tools/parse_report.py   # prints >>> TICKS PER BAR
```

- **< 10/bar** → OHLC modelling. The tester guessed the intrabar path. Your barrier result is fiction.
- **~50-200/bar** → M1 OHLC. Better. Still guessing.
- **1000+/bar** → real ticks. Now we can talk.
