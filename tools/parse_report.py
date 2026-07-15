import re, html, sys

def grab(path):
    raw = open(path, encoding='utf-8', errors='replace').read()
    txt = re.sub(r'<t[dh][^>]*>', '|', raw)
    txt = re.sub(r'<[^>]+>', ' ', txt)
    txt = html.unescape(txt)
    lines = [re.sub(r'\s+',' ',l).strip() for l in txt.split('\n')]
    lines = [l for l in lines if l and l != '|']
    flat = ' '.join(lines)
    out = {}
    keys = ["Period:", "History Quality:", "Bars:", "Ticks:", "Total Net Profit:",
            "Gross Profit:", "Gross Loss:", "Profit Factor:", "Expected Payoff:",
            "Sharpe Ratio:", "Total Trades:", "Short Trades (won %):",
            "Long Trades (won %):", "Profit Trades (% of total):",
            "Loss Trades (% of total):", "Balance Drawdown Maximal:",
            "Equity Drawdown Maximal:", "Balance Drawdown Relative:",
            "Equity Drawdown Relative:", "OnTester result:",
            "Average position holding time:", "Average profit trade:",
            "Average loss trade:", "Initial Deposit:"]
    for k in keys:
        m = re.search(re.escape('|'+k)+r'\s*\|\s*([^|]+?)\s*\|', flat)
        if m: out[k] = m.group(1).strip()
    inputs = {}
    for m in re.finditer(r'\|\s*(Inp\w+)=([^\s|]+)', flat):
        inputs[m.group(1)] = m.group(2)
    return out, inputs

for label, path in [("REPLICATE", "r_replicate_set.html"), ("TIMESTOP", "r_timestop.html")]:
    o, i = grab(path)
    print("="*66)
    print(f"  {label}")
    print("="*66)
    for k in ["Period:", "Bars:", "Ticks:", "History Quality:", "Total Trades:",
              "Profit Trades (% of total):", "Long Trades (won %):", "Short Trades (won %):",
              "Profit Factor:", "Total Net Profit:", "OnTester result:",
              "Equity Drawdown Maximal:", "Equity Drawdown Relative:", "Sharpe Ratio:",
              "Average position holding time:"]:
        if k in o: print(f"  {k:<32} {o[k]}")
    tp = i.get('InpTPPercent'); sl = i.get('InpSLPercent')
    print(f"  {'TP/SL:':<32} {tp} / {sl}")
    print(f"  {'InpMaxBarsInTrade:':<32} {i.get('InpMaxBarsInTrade')}")
    print(f"  {'InpEntryMode:':<32} {i.get('InpEntryMode')}")
    try:
        b = float(o["Bars:"].replace(" ","")); t = float(o["Ticks:"].replace(" ",""))
        print(f"  {'>>> TICKS PER BAR:':<32} {t/b:.2f}")
    except Exception as e:
        pass
    print()
