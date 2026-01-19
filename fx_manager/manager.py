import os
import json
import time
from datetime import datetime

# MT5의 Common/Files 폴더 또는 Wine의 가상 드라이브 내 MQL5/Files 폴더 경로를 설정해야 합니다.
# 현재는 테스트를 위해 로직만 구현합니다.
MONITOR_PATH = "/home/ser1/새 폴더/fx거래 봇/fx_manager/fx_status.json"

def get_fx_status():
    if not os.path.exists(MONITOR_PATH):
        return {"status": "offline", "message": "MT5 연동 대기 중..."}
    
    try:
        with open(MONITOR_PATH, 'r') as f:
            data = json.load(f)
            return data
    except Exception as e:
        return {"status": "error", "message": str(e)}

def display_dashboard():
    while True:
        os.system('clear')
        status = get_fx_status()
        
        print("="*50)
        print(f" FX 전용 개별 관리 시스템 (v1.0) - {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        print("="*50)
        
        if status.get("status") == "offline":
            print(f"\n [!] {status['message']}")
        else:
            print(f"\n [계좌 정보]")
            print(f" - 계좌번호: {status.get('account', 'N/A')}")
            print(f" - 잔고(Balance): ${status.get('balance', 0):,.2f}")
            print(f" - 평가금(Equity): ${status.get('equity', 0):,.2f}")
            print(f" - 현재손익(PnL): ${status.get('pnl', 0):,.2f}")
            
            print(f"\n [활성 전략 및 포지션]")
            positions = status.get("positions", [])
            if not positions:
                print(" - 현재 열린 포지션이 없습니다.")
            else:
                for pos in positions:
                    print(f" - [{pos['symbol']}] {pos['type']} | 랏: {pos['volume']} | 손익: ${pos['pnl']:.2f}")
        
        print("\n" + "="*50)
        print(" [Q] 종료 | [R] 강제 리프레시")
        time.sleep(2)

if __name__ == "__main__":
    # 초기 테스트용 가짜 데이터 생성
    test_data = {
        "status": "online",
        "account": "75455436",
        "balance": 1282.96,
        "equity": 1275.46,
        "pnl": -7.50,
        "positions": [
            {"symbol": "AUDUSD", "type": "BUY", "volume": 0.09, "pnl": -5.75}
        ]
    }
    with open(MONITOR_PATH, 'w') as f:
        json.dump(test_data, f)
        
    try:
        display_dashboard()
    except KeyboardInterrupt:
        print("\n관리 시스템 종료.")
