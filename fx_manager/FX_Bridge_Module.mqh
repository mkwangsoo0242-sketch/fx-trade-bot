//+------------------------------------------------------------------+
//|                                              FX_Bridge_Module.mqh|
//|                                  Copyright 2026, Antigravity AI  |
//|                                  Real-time UDP Socket Version    |
//+------------------------------------------------------------------+
#property strict

#import "ws2_32.dll"
int socket(int af, int type, int protocol);
int sendto(int s, uchar &buf[], int len, int flags, uchar &addr[], int addrlen);
int closesocket(int s);
int wsastartup(int wVersionRequested, uchar &lpWSAData[]);
#import

#define AF_INET 2
#define SOCK_DGRAM 2
#define IPPROTO_UDP 17

int m_socket = -1;
uchar m_sockaddr[16]; // byte array for sockaddr_in structure

//+------------------------------------------------------------------+
//| 초기화: 소켓 연결 설정                                           |
//+------------------------------------------------------------------+
bool InitRealtimeBridge(string host, int port)
{
   uchar wsaData[400];
   if(wsastartup(0x202, wsaData) != 0) {
      Print("[!] WSAStartup Fail");
      return false;
   }

   m_socket = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
   if(m_socket == -1) {
      Print("[!] Socket Creation Fail");
      return false;
   }

   ArrayFill(m_sockaddr, 0, 16, 0);
   // Family: AF_INET (2)
   m_sockaddr[0] = 2; 
   m_sockaddr[1] = 0;
   
   // Port: Big-endian conversion
   m_sockaddr[2] = (uchar)(port >> 8);
   m_sockaddr[3] = (uchar)(port & 0xFF);
   
   // Addr: 127.0.0.1
   m_sockaddr[4] = 127;
   m_sockaddr[5] = 0;
   m_sockaddr[6] = 0;
   m_sockaddr[7] = 1;

   Print("[*] FX Realtime Bridge Initialized (127.0.0.1:", port, ")");
   return true;
}

//+------------------------------------------------------------------+
//| 메인 루프: 실시간 데이터 전송                                    |
//+------------------------------------------------------------------+
void SendRealtimeStatus(long magic, string strategyName)
{
   if(m_socket == -1) 
   {
      if(!InitRealtimeBridge("127.0.0.1", 5555)) return;
   }

   string json = "{";
   json += "\"account\":\"" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + "\",";
   json += "\"balance\":" + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2) + ",";
   json += "\"equity\":" + DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2) + ",";
   json += "\"pnl\":" + DoubleToString(AccountInfoDouble(ACCOUNT_PROFIT), 2) + ",";
   json += "\"positions\":[";
   
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
   int res = sendto(m_socket, buf, ArraySize(buf)-1, 0, m_sockaddr, 16);
   
   if(res == -1) {
      Print("[!] Send Fail - Check Python Manager");
      m_socket = -1; // Retry init next time
   }
}

void CloseBridge() { if(m_socket != -1) closesocket(m_socket); }
