import socket
import json
import os
from datetime import datetime

# 모든 IP에서 데이터를 받도록 설정 (0.0.0.0)
HOST = '0.0.0.0'
PORT = 5555

def run_debug_manager():
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind((HOST, PORT))
    
    os.system('clear')
    print("="*60)
    print(f" 🔍 FX DEBUG MONITORING MODE (Port: {PORT})")
    print(f" 현재 MT5로부터 데이터를 기다리는 중입니다...")
    print("="*60)

    while True:
        try:
            # 데이터 수신
            data, addr = sock.recvfrom(65535)
            raw_msg = data.decode('utf-8')
            
            # 데이터가 들어오면 즉시 시간과 함께 출력
            now = datetime.now().strftime('%H:%M:%S.%f')[:-3]
            print(f"[{now}] 📥 데이터 수신 성공! (From: {addr})")
            
            status = json.loads(raw_msg)
            
            # 화면 갱신
            os.system('clear')
            print("="*60)
            print(f" 🔥 FX REAL-TIME LIVE - {now}")
            print(f" [수신지: {addr[0]}:{addr[1]}]")
            print("="*60)
            
            print(f"\n 💰 Balance: ${status.get('balance', 0):,.2f}")
            print(f" 📊 Equity:  ${status.get('equity', 0):,.2f}")
            print(f" 📈 PnL:     ${status.get('pnl', 0):,.2f}")
            
            positions = status.get("positions", [])
            print(f"\n [포지션: {len(positions)}개]")
            for pos in positions:
                print(f" - {pos['symbol']} {pos['type']} | Vol: {pos['volume']} | PnL: ${pos['pnl']:.2f}")

        except Exception as e:
            print(f"\n [!] 에러 발생: {e}")

if __name__ == "__main__":
    run_debug_manager()
