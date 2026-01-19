//+------------------------------------------------------------------+
//|                                              FX_Bridge_Module.mqh|
//|                                  Copyright 2026, Antigravity AI  |
//|                                  Real-time UDP Socket Version    |
//+------------------------------------------------------------------+
#property strict

//--- 윈도우 소켓 API 선언 (MT5-Python 다이렉트 통신)
#import "ws2_32.dll"
int socket(int af, int type, int protocol);
int sendto(int s, uchar &buf[], int len, int flags, int addr[], int addrlen);
int closesocket(int s);
int wsastartup(int wVersionRequested, uchar &lpWSAData[]);
#import

#define AF_INET 2
#define SOCK_DGRAM 2
#define IPPROTO_UDP 17

int m_socket = -1;
int m_addr[4]; // IP/Port 저장

//+------------------------------------------------------------------+
//| 초기화: 소켓 연결 설정                                           |
//+------------------------------------------------------------------+
bool InitRealtimeBridge(string host, int port)
{
   uchar data[400];
   if(wsastartup(0x202, data) != 0) return false;

   m_socket = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
   if(m_socket == -1) return false;

   // 주소 설정 (127.0.0.1:5555)
   m_addr[0] = 0x02; // sin_family
   m_addr[1] = (port << 8 & 0xFF00) | (port >> 8 & 0x00FF); // sin_port (big-endian)
   m_addr[2] = 0x0100007F; // 127.0.0.1 (sin_addr)
   m_addr[3] = 0;

   return true;
}

//+------------------------------------------------------------------+
//| 메인 루프: 실시간 데이터 전송 (0ms 지연)                         |
//+------------------------------------------------------------------+
void SendRealtimeStatus(long magic, string strategyName)
{
   if(m_socket == -1) 
   {
      InitRealtimeBridge("127.0.0.1", 5555);
      if(m_socket == -1) return;
   }

   string json = "{";
   json += "\"account\": \"" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + "\",";
   json += "\"balance\": " + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2) + ",";
   json += "\"equity\": " + DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2) + ",";
   json += "\"pnl\": " + DoubleToString(AccountInfoDouble(ACCOUNT_PROFIT), 2) + ",";
   json += "\"positions\": [";
   
   int posCount = 0;
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      if(PositionSelectByTicket(PositionGetTicket(i)))
      {
         if(posCount > 0) json += ",";
         json += "{\"symbol\":\"" + PositionGetString(POSITION_SYMBOL) + "\",";
         json += "\"type\":\"" + (PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?"BUY":"SELL") + "\",";
         json += "\"volume\":" + DoubleToString(PositionGetDouble(POSITION_VOLUME), 2) + ",";
         json += "\"pnl\":" + DoubleToString(PositionGetDouble(POSITION_PROFIT), 2) + "}";
         posCount++;
      }
   }
   json += "]}";

   uchar buf[];
   StringToCharArray(json, buf);
   sendto(m_socket, buf, ArraySize(buf)-1, 0, m_addr, 16);
}

void CloseBridge() { if(m_socket != -1) closesocket(m_socket); }
