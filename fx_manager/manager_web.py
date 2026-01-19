import json
import sys
import time
from flask import Flask, request, jsonify, render_template_string
import logging
from datetime import datetime

# Flask 로그 차단
log = logging.getLogger('werkzeug')
log.setLevel(logging.ERROR)

app = Flask(__name__)

# 데이터 저장소
bots_data = {} # strategy: {"positions": [], "last_seen": timestamp}
acc_info = {"bal": 0.0, "eq": 0.0, "mar": 0.0, "free": 0.0, "lev": 0.0}

HTML_TEMPLATE = """
<!DOCTYPE html>
<html lang="ko">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>FX BOT MASTER CONTROL</title>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;600;700&display=swap" rel="stylesheet">
    <style>
        :root {
            --bg: #05070a;
            --card: rgba(255, 255, 255, 0.03);
            --accent: #00d2ff;
            --up: #00ffa3;
            --down: #ff3e7e;
            --text: #e0e6ed;
            --border: rgba(255, 255, 255, 0.08);
        }
        * { margin:0; padding:0; box-sizing:border-box; font-family: 'Inter', sans-serif; }
        body { background: var(--bg); color: var(--text); padding: 20px; }
        .container { max-width: 1400px; margin: 0 auto; }
        
        header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 20px; }
        .logo { font-size: 22px; font-weight: 800; color: var(--accent); }
        
        /* 봇 생존 상태 바 */
        .bot-status-bar { display: flex; gap: 10px; margin-bottom: 30px; flex-wrap: wrap; }
        .bot-tag { background: var(--card); border: 1px solid var(--border); padding: 10px 15px; border-radius: 10px; font-size: 12px; display: flex; align-items: center; }
        .dot { width: 8px; height: 8px; border-radius: 50%; margin-right: 8px; }
        .dot.online { background: var(--up); box-shadow: 0 0 10px var(--up); }
        .dot.offline { background: var(--down); }

        .stats-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 20px; margin-bottom: 30px; }
        .stat-card { background: var(--card); border: 1px solid var(--border); padding: 20px; border-radius: 15px; }
        .stat-label { font-size: 11px; color: #8892b0; margin-bottom: 5px; }
        .stat-value { font-size: 22px; font-weight: 700; }

        .table-container { background: var(--card); border: 1px solid var(--border); border-radius: 20px; overflow: hidden; }
        th { padding: 15px 25px; font-size: 11px; color: #5c6c8c; text-align: left; border-bottom: 1px solid var(--border); text-transform: uppercase; }
        td { padding: 15px 25px; font-size: 13px; border-bottom: 1px solid var(--border); }
        .pnl-up { color: var(--up); font-weight: 700; }
        .pnl-down { color: var(--down); font-weight: 700; }
    </style>
</head>
<body>
    <div class="container" id="app"></div>

    <script>
        async function update() {
            try {
                const r = await fetch('/api/data');
                const d = await r.json();
                const app = document.getElementById('app');
                const now = Date.now() / 1000;
                
                let botHTML = '';
                let totalPnl = 0;
                let rows = '';
                
                // 봇 상태 생성
                for(let b in d.bots) {
                    const lastSeen = d.bots[b].last_seen;
                    const diff = Math.floor(now - lastSeen);
                    const isOnline = diff < 5;
                    const statusText = isOnline ? 'ONLINE (' + diff + 's)' : 'OFFLINE (' + diff + 's)';
                    botHTML += `
                        <div class="bot-tag">
                            <span class="dot ${isOnline ? 'online' : 'offline'}"></span>
                            <b>${b}</b>: ${statusText}
                        </div>
                    `;
                    
                    d.bots[b].positions.forEach(p => {
                        totalPnl += p.pnl;
                        const pnlC = p.pnl >= 0 ? 'pnl-up' : 'pnl-down';
                        rows += `
                            <tr>
                                <td style="color:var(--accent); font-weight:700">${p.symbol}</td>
                                <td>${p.type.toUpperCase()}</td>
                                <td>${p.vol}</td>
                                <td>${p.open.toFixed(5)}</td>
                                <td>${p.cur.toFixed(5)}</td>
                                <td class="${pnlC}">$${p.pnl.toFixed(2)}</td>
                                <td style="opacity:0.5">${b}</td>
                            </tr>
                        `;
                    });
                }

                app.innerHTML = `
                    <header>
                        <div class="logo">FX BOT REAL-TIME MONITOR</div>
                        <div style="font-size:12px; opacity:0.5">Last Full Sync: ${new Date().toLocaleTimeString()}</div>
                    </header>

                    <div class="bot-status-bar">${botHTML || '<div class="bot-tag">대기 중인 봇 없음...</div>'}</div>

                    <div class="stats-grid">
                        <div class="stat-card"><div class="stat-label">ACCOUNT BALANCE</div><div class="stat-value">$${d.acc.bal.toLocaleString()}</div></div>
                        <div class="stat-card"><div class="stat-label">EQUITY</div><div class="stat-value">$${d.acc.eq.toLocaleString()}</div></div>
                        <div class="stat-card"><div class="stat-label">MARGIN LEVEL</div><div class="stat-value" style="color:var(--accent)">${d.acc.lev.toFixed(1)}%</div></div>
                        <div class="stat-card"><div class="stat-label">LIVE PnL</div><div class="stat-value ${totalPnl>=0?'pnl-up':'pnl-down'}">$${totalPnl.toFixed(2)}</div></div>
                    </div>

                    <div class="table-container">
                        <table>
                            <thead><tr><th>Symbol</th><th>Type</th><th>Lots</th><th>Entry</th><th>Price</th><th>Profit</th><th>Bot</th></tr></thead>
                            <tbody>${rows || '<tr><td colspan="7" style="text-align:center; padding:50px; opacity:0.3">No Active Positions</td></tr>'}</tbody>
                        </table>
                    </div>
                `;
            } catch(e) {}
        }
        setInterval(update, 1000);
        update();
    </script>
</body>
</html>
"""

@app.route('/')
def index():
    return render_template_string(HTML_TEMPLATE)

@app.route('/api/data')
def data():
    return jsonify({"acc": acc_info, "bots": bots_data})

@app.route('/', methods=['POST'])
def update_post():
    global bots_data, acc_info
    try:
        raw = request.data.decode('utf-8').replace('\x00', '').strip()
        d = json.loads(raw)
        s = d.get('strategy', 'Unknown')
        
        acc_info = {
            "bal": float(d.get("balance", 0)),
            "eq": float(d.get("equity", 0)),
            "mar": float(d.get("margin", 0)),
            "free": float(d.get("free_margin", 0)),
            "lev": float(d.get("margin_level", 0))
        }
        
        bots_data[s] = {
            "positions": d.get('positions', []),
            "last_seen": time.time()
        }
    except: pass
    return "OK"

if __name__ == '__main__':
    print("[*] Bot Health Monitor Started: http://172.21.22.224:5555")
    app.run(host='0.0.0.0', port=5555, debug=False)
