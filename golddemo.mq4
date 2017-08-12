//+------------------------------------------------------------------+
//|                                                         test.mq4 |
//|                        Copyright 2016, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2016, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

#include <golddemo.mqh>

extern double StopLoss   =300.0;     // SL for an opened order
extern double TakeProfit =0.0;      // ТР for an opened order
extern int    Period_EMA_5=5;      // Period of EMA chart 5 bar
extern int    Period_EMA_10=10;      // Period of EMA chart 10 bar
extern double Rastvor    =0.5;    // Distance between MAs 
extern double Lots       = 1;     // Strictly set amount of lots
extern double Prots      =0.1;    // Percent of free margin 
bool Work=true;                    // EA will work.
string Symb;                       // Security name
int g_timeframe[] = {PERIOD_D1, PERIOD_M5, PERIOD_M15, PERIOD_M30, PERIOD_H1, PERIOD_H4};
CStatus* g_pstatus[STATUS_OBJARR_SIZE] = {NULL};
static int g_Ticket = 0;
static int g_LastTicket = 0;
static double g_Lot = 0.0;                             // Amount of lots in a selected order   
static double g_Lts = 0.0;                             // Amount of lots in an opened order
static double g_Price = 0.0;                           // Price of a selected order   
static double g_SL = 0.0;                             // SL of a selected order   
static double g_TP = 0.0;                              // TP за a selected order 
static int g_Tip = 0;
static datetime g_time = {0};
static int g_date = 0;
static int g_ordertotal = 0;
static int g_bbthreshold = 20;
static double g_profit = 0.0;
static bool g_h1ema50h4adx = false;
static double g_currentupperh1 = 0;
static double g_currentlowerh1 = 0;
static bool g_widesl = false;

string LineStatusToString(int status)
{
   switch(status)
   {
      case LINERELATION_CROSSUP:
         return "LINERELATION_CROSSUP";      
      case LINERELATION_CROSSDOWN:
         return "LINERELATION_CROSSDOWN"; 
      case LINERELATION_UPCLOSE:
         return "LINERELATION_UPCLOSE";
      case LINERELATION_DOWNCLOSE:
         return "LINERELATION_DOWNCLOSE";
      case LINERELATION_UPOPEN:    
         return "LINERELATION_UPOPEN";
      case LINERELATION_DOWNOPEN:
         return "LINERELATION_DOWNOPEN";
      case LINERELATION_TMP_CROSSUP:
         return "LINERELATION_TMP_CROSSUP";
      case LINERELATION_TMP_CROSSDOWN:
         return "LINERELATION_TMP_CROSSDOWN";
      case LINERELATION_REVER_UP:
         return "LINERELATION_REVER_UP";
      case LINERELATION_REVER_DOWN:
         return "LINERELATION_REVER_DOWN";
      case LINERELATION_UNKNOWN:      
      default:
         return "LINERELATION_UNKNOWN";
   }
   return "LINERELATION_UNKNOWN";
}

string TimeFrameToString(int time_frame)
{
   switch(time_frame)
   {
      case PERIOD_H4:
         return "H4";
      case PERIOD_H1:
         return "H1";
      case PERIOD_M30:
         return "M30";
      case PERIOD_M15:
         return "M15";
      case PERIOD_M5:
         return "M5";         
      case PERIOD_D1:
         return "D1";
      case PERIOD_W1:
         return "W1";
      case PERIOD_MN1:
         return "MN1";
      default:
         return "Unknown";
   }
   return "Unknown";
}

void OutputDebug(string str)
{
   Print(str);
}

//Chart line relationship status, like cross, about to close, keep opening. variable name with 1 is fast line, with 2 is slow line.
int CStatus::GetLineRelation(double c1, double c2, double l1, double l2, double ll1, double ll2, int time_frame)
{
   double c = c1 - c2;
   double l = l1 - l2;
   double ll = ll1- ll2;
   double threshold_up = 0.0;
   double threshold_down = 0.0;
   double base_dist_up = Rastvor * Point;
   double base_dist_down = -1 * Rastvor * Point;
   
   switch(time_frame)
   {
      case PERIOD_H4:
      case PERIOD_H1:
      case PERIOD_M30:
      case PERIOD_M15:
      case PERIOD_M5:         
      case PERIOD_D1:
      default:
         break;
   }
   
   if (ll <= 0 && l >= 0 && c > base_dist_up)
      return LINERELATION_CROSSUP;
   
   if (ll >= 0 && l <= 0 && c < base_dist_down)
      return LINERELATION_CROSSDOWN;
   
   if (ll > 0 && l > 0 && c > 0) 
   {
      if (c1 - l1 < threshold_up)                     //when two lines crossed up, use the gradient of current value and last value to see whether the curve is closing
         return LINERELATION_UPCLOSE;
      else
         return LINERELATION_UPOPEN;
   }
   
   if (ll < 0 && l < 0 && c < 0)
   {
      if (c1 - l1 > threshold_down)                   //when two lines crossed down, use the gradient of current value and last value to see whether the curve is closing
         return LINERELATION_DOWNCLOSE;
      else
         return LINERELATION_DOWNOPEN;
   }
   
   if (ll < 0 && l <= 0 && c > 0) 
      return LINERELATION_TMP_CROSSUP;
      
   if (ll > 0 && l >= 0 && c < 0) 
      return LINERELATION_TMP_CROSSDOWN;
      
   if (ll > 0 && l <= 0 && c > 0)
      return LINERELATION_REVER_UP;
      
   if (ll < 0 && l >= 0 && c < 0)
      return LINERELATION_REVER_DOWN;   
   
   return LINERELATION_UNKNOWN;    
}

bool CStatus::AssignValueSM(int& smatrix[][], int indicator, int status)
{
   int a = 0;
   int b = 0;
   
   switch(m_timeframe)
   {
      case PERIOD_H4:
         a = ARRAYINDEX_H4;
         break;
      case PERIOD_H1:
         a = ARRAYINDEX_H1;
         break;
      case PERIOD_M30:
         a = ARRAYINDEX_M30;
         break;      
      case PERIOD_M15:
         a = ARRAYINDEX_M15;
         break;      
      case PERIOD_M5: 
         a = ARRAYINDEX_M5;
         break;              
      case PERIOD_D1:
         a = ARRAYINDEX_D1;
         break;   
      case PERIOD_W1:
         a = ARRAYINDEX_W1;
         break;  
      case PERIOD_MN1:
         a = ARRAYINDEX_Mth;
         break;  
      default:
         return false;
   }
   
   b = indicator;
   
   smatrix[a][b] = status;
   return true;
}

int CStatus::CheckMACDH(int& smatrix[][], double& gradient_sec, double& gradient_old, double& gradient_cur)
{
   int ret = 0;
   int status = 0;
   int err = ERR_NO_ERROR;
   
   double current_fast = iCustom(m_symb, m_timeframe, "MACD_Histogram", "", 7, 14, 9, "", false, false, false, 0, 0);
   if ((err = GetLastError()) != ERR_NO_ERROR)
   {
      return err;
   }
   
   double current_slow = iCustom(m_symb, m_timeframe, "MACD_Histogram", "", 7, 14, 9, "", false, false, false, 1, 0);
   if ((err = GetLastError()) != ERR_NO_ERROR)
   {
      return err;
   }
   
   double last_fast = iCustom(m_symb, m_timeframe, "MACD_Histogram", "", 7, 14, 9, "", false, false, false, 0, 1);
   if ((err = GetLastError()) != ERR_NO_ERROR)
   {
      return err;
   }
   
   double last_slow = iCustom(m_symb, m_timeframe, "MACD_Histogram", "", 7, 14, 9, "", false, false, false, 1, 1);
   if ((err = GetLastError()) != ERR_NO_ERROR)
   {
      return err;
   }
   
   double llast_fast = iCustom(m_symb, m_timeframe, "MACD_Histogram", "", 7, 14, 9, "", false, false, false, 0, 2);
   if ((err = GetLastError()) != ERR_NO_ERROR)
   {
      return err;
   }
   
   double llast_slow = iCustom(m_symb, m_timeframe, "MACD_Histogram", "", 7, 14, 9, "", false, false, false, 1, 2);
   if ((err = GetLastError()) != ERR_NO_ERROR)
   {
      return err;
   }
   
   double lfourth_fast = iCustom(m_symb, m_timeframe, "MACD_Histogram", "", 7, 14, 9, "", false, false, false, 0, 3);
   if ((err = GetLastError()) != ERR_NO_ERROR)
   {
      return err;
   }
   
   double lfourth_slow = iCustom(m_symb, m_timeframe, "MACD_Histogram", "", 7, 14, 9, "", false, false, false, 1, 3);
   if ((err = GetLastError()) != ERR_NO_ERROR)
   {
      return err;
   }
   
   ret = GetLineRelation(current_fast, current_slow, last_fast, last_slow, llast_fast, llast_slow, m_timeframe); 
   gradient_old = last_fast - llast_fast; 
   gradient_cur = current_fast - last_fast;
   gradient_sec = lfourth_fast - llast_fast;
   OutputDebug(StringConcatenate("MACD_Histogram ", TimeFrameToString(m_timeframe), ": LineRelation ", LineStatusToString(ret),
         "; current_fast ", current_fast, "; current_slow ", current_slow, "; last_fast ", last_fast, "; last_slow ", last_slow,
         "; llast_fast ", llast_fast, "; llast_slow ", llast_slow, "; lfourth_fast ", lfourth_fast, "; lfourth_slow ", lfourth_slow,
         "; gradient_old ", gradient_old, "; gradient_cur ", gradient_cur, "; gradient_sec ", gradient_sec));
   
   switch(ret)
   {
      case LINERELATION_CROSSUP:
          status = STATUS_CROSS_UP;  
          break;       
      case LINERELATION_CROSSDOWN:
         status = STATUS_CROSS_DOWN;
         break;
      case LINERELATION_UPCLOSE:
         if (m_timeframe == PERIOD_M5)
            status = STATUS_UNKNOWN;
         else
            status = STATUS_CLOSE_DOWN;
         break;
      case LINERELATION_DOWNCLOSE:
         if (m_timeframe == PERIOD_M5)
            status = STATUS_UNKNOWN;
         else
            status = STATUS_CLOSE_UP;
         break;
      case LINERELATION_UPOPEN:    
         status = STATUS_KEEP_UP;  
         break;
      case LINERELATION_DOWNOPEN:
         status = STATUS_KEEP_DOWN;
         break;
      case LINERELATION_TMP_CROSSDOWN:
         status = STATUS_TMP_CROSSDOWN;
         break;
      case LINERELATION_TMP_CROSSUP:
         status = STATUS_TMP_CROSSUP;
         break;
      case LINERELATION_REVER_UP:
         status = STATUS_REVER_UP;
         break;
      case LINERELATION_REVER_DOWN:
         status = STATUS_REVER_DOWN;
         break;  
      case LINERELATION_UNKNOWN:
      default:
         status = STATUS_BAD;
         break;
   }
   
   if (AssignValueSM(smatrix, ARRAYINDEX_MACDH, status))
      err = ERR_NO_ERROR;
   else
      err = ERROR_VALUEASSIGN;
   
   return err;
}

int CStatus::CheckSpike(int& smatrix[][])
{
   int ret = 0;
   int status = 0;
   int err = ERR_NO_ERROR;
   
   double last_open = iOpen(m_symb, m_timeframe, SHIFT_LAST_ONE);
   if ((err = GetLastError()) != ERR_NO_ERROR)
   {
      return err;
   }
   
   double last_close = iClose(m_symb, m_timeframe, SHIFT_LAST_ONE);   
   if ((err = GetLastError()) != ERR_NO_ERROR)
   {
      return err;
   }
   
   double llast_open = iOpen(m_symb, m_timeframe, SHIFT_LAST_TWO);
   if ((err = GetLastError()) != ERR_NO_ERROR)
   {
      return err;
   }
   
   double llast_close = iClose(m_symb, m_timeframe, SHIFT_LAST_TWO);   
   if ((err = GetLastError()) != ERR_NO_ERROR)
   {
      return err;
   } 
   
   if ((((llast_close - llast_open < 0) && (SPIKE_MULTIPLY_OPP * (llast_close - llast_open) > (last_open - last_close)))
      || ((llast_close - llast_open > 0) && (SPIKE_MULTIPLY_OPP * (llast_close - llast_open) < (last_open - last_close)))
      || ((llast_close - llast_open < 0) && (SPIKE_MULTIPLY_SAME * (llast_close - llast_open) > (last_close - last_open)))
      || ((llast_close - llast_open > 0) && (SPIKE_MULTIPLY_SAME * (llast_close - llast_open) < (last_close - last_open))))      
      && (last_open - last_close > SPIKE_THRESHOLD_POS || last_open - last_close < SPIKE_THRESHOLD_NEG)
      )
      status = STATUS_SPIKE_REVERSE;
   else
      status = STATUS_SPIKE_NO;

   OutputDebug(StringConcatenate("EMA ", TimeFrameToString(m_timeframe), ": last_open ", last_open, ", last_close ", last_close, ", status ", status));  

   if (AssignValueSM(smatrix, ARRAYINDEX_SPIKE_REVERSE, status))
      err = ERR_NO_ERROR;
   else
      err = ERROR_VALUEASSIGN;
   
   return err;         
}

int CStatus::CheckEMA(int& smatrix[][])
{
   int ret = 0;
   int status = 0;
   int err = ERR_NO_ERROR;
   
   double current_5 = iMA(m_symb, m_timeframe, Period_EMA_5, 0, MODE_EMA, PRICE_CLOSE, 0);
   if ((err = GetLastError()) != ERR_NO_ERROR)
   {
      return err;
   }
   
	double current_10 = iMA(m_symb, m_timeframe, Period_EMA_10, 0, MODE_EMA, PRICE_CLOSE, 0);
	if ((err = GetLastError()) != ERR_NO_ERROR)
   {
      return err;
   }
   
	double last_5 = iMA(m_symb, m_timeframe, Period_EMA_5, 0, MODE_EMA, PRICE_CLOSE, 1);
	if ((err = GetLastError()) != ERR_NO_ERROR)
   {
      return err;
   }
   
	double last_10 = iMA(m_symb, m_timeframe, Period_EMA_10, 0, MODE_EMA, PRICE_CLOSE, 1);
	if ((err = GetLastError()) != ERR_NO_ERROR)
   {
      return err;
   }
   
	double llast_5 = iMA(m_symb, m_timeframe, Period_EMA_5, 0, MODE_EMA, PRICE_CLOSE, 2);
	if ((err = GetLastError()) != ERR_NO_ERROR)
   {
      return err;
   }
   
	double llast_10 = iMA(m_symb, m_timeframe, Period_EMA_10, 0, MODE_EMA, PRICE_CLOSE, 2);
	if ((err = GetLastError()) != ERR_NO_ERROR)
   {
      return err;
   }   
	
	ret = GetLineRelation(current_5, current_10, last_5, last_10, llast_5, llast_10, m_timeframe); 
   OutputDebug(StringConcatenate("EMA ", TimeFrameToString(m_timeframe), ": LineRelation ", LineStatusToString(ret),
      "; current_5 ", current_5, "; current_10 ", current_10, "; last_5 ", last_5, "; last_10 ", last_10,
      "; llast_5 ", llast_5, "; llast_10 ", llast_10));
   switch(ret)
   {
      case LINERELATION_CROSSUP:
         status = STATUS_CROSS_UP; 
         break;        
      case LINERELATION_CROSSDOWN:
         status = STATUS_CROSS_DOWN;
         break;
      case LINERELATION_UPCLOSE:
         if (m_timeframe == PERIOD_M5)
            status = STATUS_UNKNOWN;
         else
            status = STATUS_CLOSE_UP;
         break;
      case LINERELATION_DOWNCLOSE:
         if (m_timeframe == PERIOD_M5)
            status = STATUS_UNKNOWN;
         else
            status = STATUS_CLOSE_DOWN;
         break;
      case LINERELATION_UPOPEN:    
         status = STATUS_KEEP_UP; 
         break; 
      case LINERELATION_DOWNOPEN:
         status = STATUS_KEEP_DOWN;
         break;
      case LINERELATION_TMP_CROSSDOWN:
         status = STATUS_TMP_CROSSDOWN;
         break;
      case LINERELATION_TMP_CROSSUP:
         status = STATUS_TMP_CROSSUP;
         break;
      case LINERELATION_UNKNOWN:
      default:
         status = STATUS_BAD;
         break;
   }
   
   if (AssignValueSM(smatrix, ARRAYINDEX_EMA, status))
      err = ERR_NO_ERROR;
   else
      err = ERROR_VALUEASSIGN;
   
   return err;
}

int CStatus::CheckEMA50(int& smatrix[][])
{
   int ret = 0;
   int status = STATUS_SUPPRESS_NO;
   int err = ERR_NO_ERROR;
   double gap = 0;
   double currentcandleopenprice = iOpen(m_symb, m_timeframe, SHIFT_CURRENT);
   double lastcandleopenprice = iOpen(m_symb, m_timeframe, SHIFT_LAST_ONE);
   double lastcandlecloseprice = iClose(m_symb, m_timeframe, SHIFT_LAST_ONE);
   double llastcandleopenprice = iOpen(m_symb, m_timeframe, SHIFT_LAST_TWO);
   double llastcandlecloseprice = iClose(m_symb, m_timeframe, SHIFT_LAST_TWO);
   double ltcandleopenprice = iOpen(Symb, m_timeframe, SHIFT_LAST_THRID);
   double ltastcandlecloseprice = iClose(m_symb, m_timeframe, SHIFT_LAST_THRID);   
      
   double current_50 = iMA(m_symb, m_timeframe, 50, 0, MODE_EMA, PRICE_CLOSE, 0);
   if ((err = GetLastError()) != ERR_NO_ERROR)
   {
      return err;
   }
   
   double last_50 = iMA(m_symb, m_timeframe, 50, 0, MODE_EMA, PRICE_CLOSE, 1);
   if ((err = GetLastError()) != ERR_NO_ERROR)
   {
      return err;
   }   

   double llast_50 = iMA(m_symb, m_timeframe, 50, 0, MODE_EMA, PRICE_CLOSE, 2);
   if ((err = GetLastError()) != ERR_NO_ERROR)
   {
      return err;
   }

   double ltast_50 = iMA(m_symb, m_timeframe, 50, 0, MODE_EMA, PRICE_CLOSE, 3);
   if ((err = GetLastError()) != ERR_NO_ERROR)
   {
      return err;
   }
   
   switch(m_timeframe)
   {
      case PERIOD_D1:
         gap = D1EMA50GAP;
         break;
      case PERIOD_H4:
         gap = H4EMA50GAP;
         break;
      case PERIOD_H1:
         gap = H1EMA50GAP;
         break;
      case PERIOD_M30:
         gap = M30EMA50GAP;
         break;
      case PERIOD_M15:
         gap = M15EMA50GAP;
         break;
      case PERIOD_M5:
         gap = M5EMA50GAP;
         break;
      default:
         gap = 0;
         break;
   }
         
   if (currentcandleopenprice >= current_50 && currentcandleopenprice <= current_50 + gap)
   {
      status = STATUS_EMA50_SUPPRESS_SELL;
   }
   
   if (currentcandleopenprice <= current_50 && currentcandleopenprice >= current_50 - gap)
   {
      status = STATUS_EMA50_SUPPRESS_BUY;
   }
   
   if (llastcandleopenprice >= llast_50 && llastcandlecloseprice <= llast_50
      && lastcandleopenprice <= last_50 && lastcandlecloseprice < last_50 && currentcandleopenprice < current_50)
      status = STATUS_EMA50_SUPPRESS_BUY;
      
   if (llastcandleopenprice <= llast_50 && llastcandlecloseprice >= llast_50
      && lastcandleopenprice >= last_50 && lastcandlecloseprice > last_50 && currentcandleopenprice > current_50)
      status = STATUS_EMA50_SUPPRESS_SELL;
      
   if (lastcandleopenprice >= last_50 && lastcandlecloseprice <= last_50
      && currentcandleopenprice <= current_50)
   {
      if (llastcandleopenprice <= llast_50)
         status = STATUS_EMA50_SUPPRESS_BOTH;
      else
         status = STATUS_EMA50_SUPPRESS_BUY;
   }
      
   if (lastcandleopenprice <= last_50 && lastcandlecloseprice >= last_50
      && currentcandleopenprice >= current_50)
   {
      if (llastcandleopenprice >= llast_50)
         status = STATUS_EMA50_SUPPRESS_BOTH;
      else
         status = STATUS_EMA50_SUPPRESS_SELL;
   }

   OutputDebug(StringConcatenate("CheckEMA50: ", TimeFrameToString(m_timeframe), " currentcandleopenprice: ", currentcandleopenprice, ", lastcandleopenprice: ", lastcandleopenprice, ", lastcandlecloseprice: ", lastcandlecloseprice,
      ", llastcandleopenprice: ", llastcandleopenprice, ", llastcandlecloseprice: ", llastcandlecloseprice, ", ltcandleopenprice: ", ltcandleopenprice, ", ltastcandlecloseprice: ", ltastcandlecloseprice,
      ", current_50: ", current_50, ", last_50: ", last_50, ", status: ", status, ", llast_50: ", llast_50, ", ltast_50: ", ltast_50));
      
   if (AssignValueSM(smatrix, ARRAYINDEX_EMA50, status))
      err = ERR_NO_ERROR;
   else
      err = ERROR_VALUEASSIGN;   
   
   return 0;
}

int CStatus::CheckPFE(int& smatrix[][])
{
   int err = ERR_NO_ERROR;
   int status = 0; 
   double threshold_up = 0;
   double threshold_down = 0;
   
   double pfe_current = iCustom(m_symb,m_timeframe, "PFE", 7, true, 5, 0, 0);
   if ((err = GetLastError()) != ERR_NO_ERROR)
   {
      OutputDebug(StringConcatenate("PFE ", TimeFrameToString(m_timeframe), ": Current PFE error: ", err));
      return err;
   }

   double pfe_last = iCustom(m_symb,m_timeframe, "PFE", 7, true, 5, 0, 1);
   if ((err = GetLastError()) != ERR_NO_ERROR)
   {
      OutputDebug(StringConcatenate("PFE ", TimeFrameToString(m_timeframe), ": Last PFE error: ", err));
      return err;
   }

   double pfe_llast = iCustom(m_symb,m_timeframe, "PFE", 7, true, 5, 0, 2);
   if ((err = GetLastError()) != ERR_NO_ERROR)
   {
      OutputDebug(StringConcatenate("PFE ", TimeFrameToString(m_timeframe), ": LLast PFE error: ", err));
      return err;
   }

   double pfe_flast = iCustom(m_symb,m_timeframe, "PFE", 7, true, 5, 0, 3);
   if ((err = GetLastError()) != ERR_NO_ERROR)
   {
      OutputDebug(StringConcatenate("PFE ", TimeFrameToString(m_timeframe), ": FLast PFE error: ", err));
      return err;
   }
   
   if (m_timeframe == PERIOD_H4)
   {
      threshold_up = 0.4;
      threshold_down = -0.4;
   }
   else if (m_timeframe == PERIOD_H1)
   {
      threshold_up = 0.6;
      threshold_down = -0.6;   
   }
   else if (m_timeframe == PERIOD_M30)
   {
      threshold_up = 0.6;
      threshold_down = -0.6;    
   }
   else
   {
      threshold_up = 0;
      threshold_down = 0;
   }

   if (pfe_llast >= pfe_last && pfe_last >= pfe_current && pfe_current < 0)
   {
      if (pfe_last > 0)
        status = STATUS_PFE_SUPPRESS_BUY; 
   }
   else if (pfe_llast >= pfe_last && pfe_last >= pfe_current && pfe_current >= 0)
   {
      if (pfe_current < threshold_up)   
         status = STATUS_PFE_POS_NOTRADEZONE;
      if (pfe_current >= threshold_up && m_timeframe == PERIOD_H4)
         status = 0;
   }
   else if (pfe_llast < pfe_last && pfe_last > pfe_current && pfe_llast >= 0 && pfe_current >= 0)
   {
      if (pfe_current < threshold_up || pfe_llast < threshold_up)
         status = STATUS_PFE_POS_NOTRADEZONE;  
   }
   else if (pfe_llast > pfe_last && pfe_last < pfe_current && pfe_last >= 0)
   {
      if (pfe_llast < threshold_up && pfe_current < threshold_up && m_timeframe == PERIOD_H4)
         status = STATUS_PFE_POS_NOTRADEZONE;
   }
   
   if (pfe_llast <= pfe_last && pfe_last <= pfe_current && pfe_current > 0)
   {
      if (pfe_last < 0)
        status = STATUS_PFE_SUPPRESS_SELL; 
   }   
   else if (pfe_llast <= pfe_last && pfe_last <= pfe_current && pfe_current <= 0)
   {
      if (pfe_current > threshold_down)   
         status = STATUS_PFE_NEG_NOTRADEZONE;
      if (pfe_current <= threshold_down && m_timeframe == PERIOD_H4)
         status = 0;
   }
   else if (pfe_llast > pfe_last && pfe_last < pfe_current && pfe_llast <= 0 && pfe_current <= 0)
   {
      if (pfe_current > threshold_down || pfe_llast > threshold_down)
         status = STATUS_PFE_NEG_NOTRADEZONE;  
   }
   else if (pfe_llast < pfe_last && pfe_last > pfe_current && pfe_last <= 0)
   {
      if (pfe_llast > threshold_down && pfe_current > threshold_down && m_timeframe == PERIOD_H4)
         status = STATUS_PFE_NEG_NOTRADEZONE;
   }
            
   OutputDebug(StringConcatenate("PFE ", TimeFrameToString(m_timeframe), ": Current PFE ", pfe_current, " Last PFE ", pfe_last, " LLast PFE ", pfe_llast, " FLast PFE ", pfe_flast, " status ", status));

   if (AssignValueSM(smatrix, ARRAYINDEX_PFE, status))
      err = ERR_NO_ERROR;
   else
      err = ERROR_VALUEASSIGN;   
      
   return 0;   
}

int CStatus::CheckADX(int& smatrix[][])
{
   int err = ERR_NO_ERROR;
   int status = 0;
   int time_range = 0;
   int adx_threshold = 25;
   int adx_threshold_h = 25;
   
   double adx_pdi = iADX(m_symb, m_timeframe, m_period, m_apprice, MODE_PLUSDI, SHIFT_CURRENT);
   if ((err = GetLastError()) != ERR_NO_ERROR)
   {
      return err;
   }
   
   double adx_ndi = iADX(m_symb, m_timeframe, m_period, m_apprice, MODE_MINUSDI, SHIFT_CURRENT);
   if ((err = GetLastError()) != ERR_NO_ERROR)
   {
      return err;
   }
   
   double adx_sth = iADX(m_symb, m_timeframe, m_period, m_apprice, MODE_MAIN, SHIFT_CURRENT); 
   if ((err = GetLastError()) != ERR_NO_ERROR)
   {
      return err;
   }  
   
   double adx_sth_last = iADX(m_symb, m_timeframe, m_period, m_apprice, MODE_MAIN, SHIFT_LAST_ONE); 
   if ((err = GetLastError()) != ERR_NO_ERROR)
   {
      return err;
   } 
   
   if (m_timeframe == PERIOD_H4)
   {
      adx_threshold_h = 20;
      if (adx_sth < H1EMA50H4ADX_THRESHOD)
         g_h1ema50h4adx = true;
      else
         g_h1ema50h4adx = false;
   }
   else
      adx_threshold_h = 25;
   
   if (adx_sth_last > adx_sth && adx_sth > adx_threshold_h)
   {
      status = STATUS_CROSS_DOWN;
      OutputDebug(StringConcatenate("ADX ", TimeFrameToString(m_timeframe), ": Down. ", " Current strength ", adx_sth, " Last strength ", adx_sth_last, " +DI ", adx_pdi, " -DI ", adx_ndi));
   }
   else if (adx_sth >= adx_sth_last && (adx_sth > adx_threshold_h || adx_pdi > adx_threshold_h || adx_ndi > adx_threshold_h))
   {
      status = STATUS_CROSS_UP;
      OutputDebug(StringConcatenate("ADX ", TimeFrameToString(m_timeframe), ": Up. ", " Current strength ", adx_sth, " Last strength ", adx_sth_last, " +DI ", adx_pdi, " -DI ", adx_ndi));
   }
   else
   {
      status = STATUS_UNKNOWN;
      OutputDebug(StringConcatenate("ADX ", TimeFrameToString(m_timeframe), ": STATUS_UNKNOWN. ", " Current strength ", adx_sth, " Last strength ", adx_sth_last, " +DI ", adx_pdi, " -DI ", adx_ndi));
   }
   
   if (adx_sth_last > adx_sth && adx_ndi < adx_threshold_h && adx_pdi < adx_threshold_h)
   {
      if ((adx_sth_last - adx_sth < 0.2 && adx_sth_last > 50 && adx_sth > 50) || (m_timeframe == PERIOD_H4 && adx_sth_last > 40 && adx_sth > 40))
      {
         status = STATUS_CROSS_UP;
         OutputDebug(StringConcatenate("ADX ", TimeFrameToString(m_timeframe), ": Strength both larger than 50, no obvious difference. ", " Current strength ", adx_sth, " Last strength ", adx_sth_last, " +DI ", adx_pdi, " -DI ", adx_ndi));
      }
      else
      {
         status = STATUS_BAD;
         OutputDebug(StringConcatenate("ADX ", TimeFrameToString(m_timeframe), ": STATUS_BAD. ", " Current strength ", adx_sth, " Last strength ", adx_sth_last, " +DI ", adx_pdi, " -DI ", adx_ndi));         
      }
   }

   if (AssignValueSM(smatrix, ARRAYINDEX_ADX, status))
      err = ERR_NO_ERROR;
   else
      err = ERROR_VALUEASSIGN;   

   return err;
}

int CStatus::CheckBollinger(int& smatrix[][])
{
   int err = ERR_NO_ERROR;
   int status = 0;
   double bbd[4] = {0.0};
   double upper[4] = {0.0};
   double lower[4] = {0.0};
   double upper_sum = 0.0;
   double lower_sum = 0.0;
   int period = PERIOD_M5;
   double bbthresholdm30 = BBBAND_THRESHOD_M30;
   double bbthresholdh1 = BBBAND_THRESHOD_H1;
   
   if (g_widesl)
      bbthresholdh1 = 6.5;
   
   if (m_timeframe == PERIOD_M30 || m_timeframe == PERIOD_H1)
   {
      for (int i = 3; i >= 0; i--)
      {
         if (g_widesl)
            upper[i] = iBands(m_symb, m_timeframe, 35, m_bb_deviation, 0, PRICE_CLOSE, MODE_UPPER, i);
         else
            upper[i] = iBands(m_symb, m_timeframe, m_bbperiod, m_bb_deviation, 0, PRICE_CLOSE, MODE_UPPER, i);
         if ((err = GetLastError()) != ERR_NO_ERROR)
         {
            return err;
         }
         
         if (g_widesl)
            lower[i] = iBands(m_symb, m_timeframe, 35, m_bb_deviation, 0, PRICE_CLOSE, MODE_LOWER, i);
         else
            lower[i] = iBands(m_symb, m_timeframe, m_bbperiod, m_bb_deviation, 0, PRICE_CLOSE, MODE_LOWER, i);
         if ((err = GetLastError()) != ERR_NO_ERROR)
         {
            return err;
         }
         
         bbd[i] = upper[i] - lower[i];
      } 
      
      if (m_timeframe == PERIOD_M30)
      {
         if (bbd[1] < bbthresholdm30 || bbd[2] < bbthresholdm30 || bbd[3] < bbthresholdm30)
         {
            if ((upper[1] < iClose(m_symb, period, 1) || upper[1] < iOpen(m_symb, period, 0))
               || (upper[2] < iClose(m_symb, period, 1) || upper[2] < iOpen(m_symb, period, 0))
               || (upper[3] < iClose(m_symb, period, 1) || upper[3] < iOpen(m_symb, period, 0)))
            {
               status = STATUS_CROSS_UP;
            }
            
            if ((lower[1] > iClose(m_symb, period, 1) || lower[1] > iOpen(m_symb, period, 0))
               || (lower[2] > iClose(m_symb, period, 1) || lower[2] > iOpen(m_symb, period, 0))
               || (lower[3] > iClose(m_symb, period, 1) || lower[3] > iOpen(m_symb, period, 0)))
            {
               status = STATUS_CROSS_DOWN;
            }
         }
      }
      
      if (m_timeframe == PERIOD_H1)
      {
         if (bbd[1] < bbthresholdh1 && bbd[2] < bbthresholdh1 && bbd[3] < bbthresholdh1)
         {
            if ((upper[1] < iClose(m_symb, period, 1) || upper[1] < iOpen(m_symb, period, 0))
               || (upper[2] < iClose(m_symb, period, 1) || upper[2] < iOpen(m_symb, period, 0))
               || (upper[3] < iClose(m_symb, period, 1) || upper[3] < iOpen(m_symb, period, 0)))
            {
               status = STATUS_TMP_CROSSUP;
            }
            
            if ((lower[1] > iClose(m_symb, period, 1) || lower[1] > iOpen(m_symb, period, 0))
               || (lower[2] > iClose(m_symb, period, 1) || lower[2] > iOpen(m_symb, period, 0))
               || (lower[3] > iClose(m_symb, period, 1) || lower[3] > iOpen(m_symb, period, 0)))
            {
               status = STATUS_TMP_CROSSDOWN;
            }         
         }

         if (bbd[1] >= bbthresholdh1)
         {
            status = STATUS_BAD;
         }
         
      }

      OutputDebug(StringConcatenate("Bollinger ", TimeFrameToString(m_timeframe), ": bbd[3] ", bbd[3], ", bbd[2] ", bbd[2], ", bbd[1] ", bbd[1], ", bbd[0] ", bbd[0],
         ", upper avg ", upper_sum / 3, ", lower avg ", lower_sum / 3, ", status ", status));
      
      if (AssignValueSM(smatrix, ARRAYINDEX_BBBAND, status))
         err = ERR_NO_ERROR;
      else
         err = ERROR_VALUEASSIGN;
   }
   
   return err;
}

int CStatus::CheckMACD2C(int& smatrix[][])
{
   int err = ERR_NO_ERROR;
   int status = 0;
   int status_g = 0;
   
	double macd2c_wave_cur = iCustom(m_symb,m_timeframe, "MACD_2Colour", 12, 26, 9, MODE_MACD2C_WAVE, SHIFT_CURRENT);
   if ((err = GetLastError()) != ERR_NO_ERROR)
   {
      return err;
   }  
   
	double macd2c_pos_cur = iCustom(m_symb,m_timeframe, "MACD_2Colour", 12, 26, 9, MODE_MACD2C_POSITIVE, SHIFT_CURRENT);
   if ((err = GetLastError()) != ERR_NO_ERROR)
   {
      return err;
   }  
   
	double macd2c_neg_cur = iCustom(m_symb,m_timeframe, "MACD_2Colour", 12, 26, 9, MODE_MACD2C_NEGATIVE, SHIFT_CURRENT);
   if ((err = GetLastError()) != ERR_NO_ERROR)
   {
      return err;
   } 

   double macd2c_wave_last = iCustom(m_symb,m_timeframe, "MACD_2Colour", 12, 26, 9, MODE_MACD2C_WAVE, SHIFT_LAST_ONE);
   if ((err = GetLastError()) != ERR_NO_ERROR)
   {
      return err;
   } 
   
	double macd2c_pos_last = iCustom(m_symb,m_timeframe, "MACD_2Colour", 12, 26, 9, MODE_MACD2C_POSITIVE, SHIFT_LAST_ONE);
   if ((err = GetLastError()) != ERR_NO_ERROR)
   {
      return err;
   }  
   
	double macd2c_neg_last = iCustom(m_symb,m_timeframe, "MACD_2Colour", 12, 26, 9, MODE_MACD2C_NEGATIVE, SHIFT_LAST_ONE);
   if ((err = GetLastError()) != ERR_NO_ERROR)
   {
      return err;
   }  
   
   double macd2c_wave_llast = iCustom(m_symb,m_timeframe, "MACD_2Colour", 12, 26, 9, MODE_MACD2C_WAVE, SHIFT_LAST_TWO);
   if ((err = GetLastError()) != ERR_NO_ERROR)
   {
      return err;
   } 
      
   double macd2c_pos_llast = iCustom(m_symb,m_timeframe, "MACD_2Colour", 12, 26, 9, MODE_MACD2C_POSITIVE, SHIFT_LAST_TWO);
   if ((err = GetLastError()) != ERR_NO_ERROR)
   {
      return err;
   }  
   
	double macd2c_neg_llast = iCustom(m_symb,m_timeframe, "MACD_2Colour", 12, 26, 9, MODE_MACD2C_NEGATIVE, SHIFT_LAST_TWO);
   if ((err = GetLastError()) != ERR_NO_ERROR)
   {
      return err;
   } 
   
   double macd2c_pos_lthird = iCustom(m_symb,m_timeframe, "MACD_2Colour", 12, 26, 9, MODE_MACD2C_POSITIVE, SHIFT_LAST_THRID);
   if ((err = GetLastError()) != ERR_NO_ERROR)
   {
      return err;
   }  
   
	double macd2c_neg_lthird = iCustom(m_symb,m_timeframe, "MACD_2Colour", 12, 26, 9, MODE_MACD2C_NEGATIVE, SHIFT_LAST_THRID);
   if ((err = GetLastError()) != ERR_NO_ERROR)
   {
      return err;
   }
   
   if (status == 0)
   {

	 if (macd2c_pos_last > 0 && macd2c_neg_last == 0 && macd2c_pos_last < macd2c_wave_last)
	 {
	    if (macd2c_pos_llast >= macd2c_wave_llast)
	       status = STATUS_MACD2C_BELOW_YL_CLOSE;
	    else
	       status = STATUS_MACD2C_BELOW_YL;
	 }
	 if (macd2c_pos_last == 0 && macd2c_neg_last < 0 && macd2c_neg_last < macd2c_wave_last
	    && macd2c_neg_llast >= macd2c_wave_llast)
	    status = STATUS_MACD2C_BELOW_YL_CLOSE;
         
	 if (macd2c_pos_last == 0 && macd2c_neg_last < 0 && macd2c_neg_last > macd2c_wave_last)
	 {
	    if (macd2c_neg_llast <= macd2c_wave_llast)
	       status = STATUS_MACD2C_ABOVE_YL_CLOSE;
	    else
	       status = STATUS_MACD2C_ABOVE_YL;
	 }
         
	 if (macd2c_pos_last > 0 && macd2c_neg_last == 0 && macd2c_pos_last > macd2c_wave_last
	    && macd2c_neg_llast <= macd2c_wave_llast)
	    status = STATUS_MACD2C_ABOVE_YL_CLOSE;
         
	 if (macd2c_pos_last > 0 && macd2c_neg_last == 0 && macd2c_pos_last > macd2c_wave_last
	    && macd2c_pos_cur > 0 && macd2c_neg_cur == 0 && macd2c_pos_cur > macd2c_wave_cur)
	 {
	    status = STATUS_MACD2C_ABOVE_YL;
	 }
         
	 if (macd2c_pos_last == 0 && macd2c_neg_last < 0 && macd2c_neg_last < macd2c_wave_last
	    && macd2c_pos_cur == 0 && macd2c_neg_cur < 0 && macd2c_neg_cur < macd2c_wave_cur)
	 {
	    status = STATUS_MACD2C_BELOW_YL;
	 }    

   }
   
   if (macd2c_pos_cur >= 0 && macd2c_pos_last == 0 && macd2c_pos_llast == 0 && macd2c_pos_lthird == 0)
   {
      if ((macd2c_neg_llast - macd2c_neg_lthird >= 0) && (macd2c_neg_last - macd2c_neg_llast > 0))
         status_g = GRADIENT_RED_UP;
      else if ((macd2c_neg_llast - macd2c_neg_lthird < 0) && (macd2c_neg_last - macd2c_neg_llast <= 0))
         status_g = GRADIENT_RED_DOWN;
      else if ((macd2c_neg_llast - macd2c_neg_lthird >= 0) && (macd2c_neg_last - macd2c_neg_llast < 0))
         status_g = GRADIENT_RED_REVERT_DOWN;
      else if ((macd2c_neg_llast - macd2c_neg_lthird < 0) && (macd2c_neg_last - macd2c_neg_llast > 0))
         status_g = GRADIENT_RED_REVERT_UP;
      else if ((macd2c_neg_llast - macd2c_neg_lthird > 0) && (macd2c_neg_last - macd2c_neg_llast == 0))
         status_g = GRADIENT_RED_UP;
      else if ((macd2c_neg_llast - macd2c_neg_lthird == 0) && (macd2c_neg_last - macd2c_neg_llast == 0))
         status_g = GRADIENT_ZERO;
      else
         status_g = GRADIENT_UNKOWN;
   }
   else if (macd2c_pos_cur > 0 && macd2c_pos_last > 0 && macd2c_pos_llast == 0 && macd2c_pos_lthird == 0)
   {
      if ((macd2c_neg_llast - macd2c_neg_lthird >= 0) && (macd2c_pos_last - macd2c_neg_llast > 0))
         status_g = GRADIENT_CROSS_UP;
      else if ((macd2c_neg_llast - macd2c_neg_lthird < 0) && (macd2c_pos_last - macd2c_neg_llast > 0))
         status_g = GRADIENT_RED_REVERT_UP;
      else
         status_g = GRADIENT_UNKOWN;
   }
   else if (macd2c_pos_cur > 0 && macd2c_pos_last > 0 && macd2c_pos_llast > 0 && macd2c_pos_lthird == 0)
   {
      if ((macd2c_pos_llast - macd2c_neg_lthird > 0) && (macd2c_pos_last - macd2c_pos_llast >= 0))
         status_g = GRADIENT_CROSS_UP;
      else if ((macd2c_pos_llast - macd2c_neg_lthird > 0) && (macd2c_pos_last - macd2c_pos_llast < 0))
         status_g = GRADIENT_GREEN_REVERT_DOWN;
      else
         status_g = GRADIENT_UNKOWN;
   }
   else if (macd2c_pos_cur >= 0 && macd2c_pos_last > 0 && macd2c_pos_llast > 0 && macd2c_pos_lthird > 0)
   {
      if ((macd2c_pos_llast - macd2c_pos_lthird >= 0) && (macd2c_pos_last - macd2c_pos_llast > 0))
         status_g = GRADIENT_GREEN_UP;
      else if ((macd2c_pos_llast - macd2c_pos_lthird < 0) && (macd2c_pos_last - macd2c_pos_llast <= 0))
         status_g = GRADIENT_GREEN_DOWN;
      else if ((macd2c_pos_llast - macd2c_pos_lthird >= 0) && (macd2c_pos_last - macd2c_pos_llast < 0))
         status_g = GRADIENT_GREEN_REVERT_DOWN;
      else if ((macd2c_pos_llast - macd2c_pos_lthird < 0) && (macd2c_pos_last - macd2c_pos_llast > 0))
         status_g = GRADIENT_GREEN_REVERT_UP;
      else if ((macd2c_pos_llast - macd2c_pos_lthird > 0) && (macd2c_pos_last - macd2c_pos_llast == 0))
         status_g = GRADIENT_GREEN_UP;
      else if ((macd2c_pos_llast - macd2c_pos_lthird == 0) && (macd2c_pos_last - macd2c_pos_llast == 0))
         status_g = GRADIENT_ZERO;
      else
         status_g = GRADIENT_UNKOWN;   
   }
   else if (macd2c_pos_cur == 0 && macd2c_pos_last == 0 && macd2c_pos_llast > 0 && macd2c_pos_lthird > 0)
   {
      if ((macd2c_pos_llast - macd2c_pos_lthird > 0) && (macd2c_neg_last - macd2c_pos_llast < 0))
         status_g = GRADIENT_GREEN_REVERT_DOWN;
      else if ((macd2c_pos_llast - macd2c_pos_lthird <= 0) && (macd2c_neg_last - macd2c_pos_llast < 0))
         status_g = GRADIENT_CROSS_DOWN;
      else
         status_g = GRADIENT_UNKOWN;
   }
   else if (macd2c_pos_cur == 0 && macd2c_pos_last == 0 && macd2c_pos_llast == 0 && macd2c_pos_lthird > 0)
   {
      if ((macd2c_neg_llast - macd2c_pos_lthird < 0) && (macd2c_neg_last - macd2c_neg_llast <= 0))
         status_g = GRADIENT_CROSS_DOWN;
      else if ((macd2c_neg_llast - macd2c_pos_lthird < 0) && (macd2c_neg_last - macd2c_neg_llast > 0))
         status_g = GRADIENT_GREEN_REVERT_UP;
      else
         status_g = GRADIENT_UNKOWN;
   }
   else if (macd2c_pos_last == 0 && macd2c_pos_llast > 0 && macd2c_pos_lthird == 0)
   {
      status_g = GRADIENT_GREEN_REVERT_DOWN;
   }
   else if (macd2c_pos_last > 0 && macd2c_pos_llast == 0 && macd2c_pos_lthird > 0)
   {
      status_g = GRADIENT_GREEN_REVERT_UP;
   }
   else
      status_g = GRADIENT_UNKOWN;
   
   
   OutputDebug(StringConcatenate("MACD_2C ", TimeFrameToString(m_timeframe), ": Status ", status,
         "; macd2c_wave_cur ", macd2c_wave_cur, "; macd2c_pos_cur ", macd2c_pos_cur, "; macd2c_neg_cur ", macd2c_neg_cur, "; macd2c_wave_last ", macd2c_wave_last,
         "; macd2c_pos_last ", macd2c_pos_last, "; macd2c_neg_last ", macd2c_neg_last, "; macd2c_wave_llast ", macd2c_wave_llast, "; macd2c_pos_llast ", 
         macd2c_pos_llast, "; macd2c_neg_llast ", macd2c_neg_llast, "; macd2c_pos_lthird ", macd2c_pos_lthird, "; macd2c_neg_lthird ", macd2c_neg_lthird));
   OutputDebug(StringConcatenate("MACD_2C_G ", TimeFrameToString(m_timeframe), ": Status_g ", status_g));
            
   if (AssignValueSM(smatrix, ARRAYINDEX_MACD2C, status))
      err = ERR_NO_ERROR;
   else
      err = ERROR_VALUEASSIGN;   
   
   if (err == ERROR_VALUEASSIGN)
      return err;
      
   if (AssignValueSM(smatrix, ARRAYINDEX_MACD2C_G, status_g))
      err = ERR_NO_ERROR;
   else
      err = ERROR_VALUEASSIGN;  
      
   return err;
}

int CStatus::CheckASRC(int& smatrix[][])
{
   int err = ERR_NO_ERROR;
   int status = STATUS_ASRC_NONE;
   string strTL1 = "";
   string strTL2 = "";
   string strMIDL = "";
   string str = "";
   
   switch(m_timeframe)
   {
      case PERIOD_D1:
         strTL1 = "TL1_D1";
         strTL2 = "TL2_D1";
         strMIDL = "MIDL_D1";
         break;
      case PERIOD_H4:
         strTL1 = "TL1_H4";
         strTL2 = "TL2_H4";
         strMIDL = "MIDL_H4";
         break;
      case PERIOD_H1:
         strTL1 = "TL1_H1";
         strTL2 = "TL2_H1";
         strMIDL = "MIDL_H1";
         break;
      case PERIOD_M30:
         strTL1 = "TL1_M30";
         strTL2 = "TL2_M30";
         strMIDL = "MIDL_M30";
         break;
      case PERIOD_M15:
         strTL1 = "TL1_M15";
         strTL2 = "TL2_M15";
         strMIDL = "MIDL_M15";
         break;
      case PERIOD_M5:
         strTL1 = "TL1_M5";
         strTL2 = "TL2_M5";
         strMIDL = "MIDL_M5";
         break;
      default:
         strTL1 = "";
         strTL2 = "";
         strMIDL = "";
         break;
   }
   
   double current_TL1 = ObjectGetValueByShift(strTL1, SHIFT_CURRENT);
   if ((err = GetLastError()) != ERR_NO_ERROR)
   {
      return err;
   }
   double current_TL2 = ObjectGetValueByShift(strTL2, SHIFT_CURRENT);
   if ((err = GetLastError()) != ERR_NO_ERROR)
   {
      return err;
   }
   double current_MIDL = ObjectGetValueByShift(strMIDL, SHIFT_CURRENT);
   if ((err = GetLastError()) != ERR_NO_ERROR)
   {
      return err;
   }
   
   if (m_timeframe == PERIOD_D1 || m_timeframe == PERIOD_H4)
   {
      if ((Bid >= current_TL1 - ASRCD1GAP && Bid <= current_TL1) || (Ask >= current_TL1 - ASRCD1GAP && Ask <= current_TL1))
      {
         status = STATUS_ASRC_TOP;
      }      
      else if ((Bid <= current_TL2 + ASRCD1GAP && Bid >= current_TL2) || (Ask <= current_TL2 + ASRCD1GAP && Ask >= current_TL2))
      {
         status = STATUS_ASRC_BOTTOM;
      }
      else
         status = STATUS_ASRC_NONE;      
   }
   else
   {
      if ((Bid >= current_TL2 - ASRCD1GAP && Bid <= current_TL2) || (Ask >= current_TL2 - ASRCD1GAP && Ask <= current_TL2))
      {
         status = STATUS_ASRC_TOP;
      }      
      else if ((Bid <= current_TL1 + ASRCD1GAP && Bid >= current_TL1) || (Ask <= current_TL1 + ASRCD1GAP && Ask >= current_TL1))
      {
         status = STATUS_ASRC_BOTTOM;
      }
      else
         status = STATUS_ASRC_NONE;
   }
   
   OutputDebug(StringConcatenate("ASRC ", TimeFrameToString(m_timeframe), ": Status ", status,
         ",", strTL1, ", current_TL1:", current_TL1, ",", strTL2, ", current_TL2:", current_TL2, ",", strMIDL, ", current_MIDL:", current_MIDL)); 
         
   if (AssignValueSM(smatrix, ARRAYINDEX_ASRC, status))
      err = ERR_NO_ERROR;
   else
      err = ERROR_VALUEASSIGN;   
      
   return err;  
}

//H4 status 
void CStatusH4::CStatusH4(string s)
{
   m_timeframe = PERIOD_H4;
   m_symb = s;
   m_period = 7;
   m_apprice = PRICE_CLOSE;
   m_bb_deviation = 2;
   m_bbperiod = 14;
}

//H1 status
void CStatusH1::CStatusH1(string s)
{
   m_timeframe = PERIOD_H1;
   m_symb = s;
   m_period = 7;
   m_apprice = PRICE_CLOSE;
   m_bb_deviation = 2;
   m_bbperiod = 14;
}

//M30 status
void CStatusM30::CStatusM30(string s)
{
   m_timeframe = PERIOD_M30;
   m_symb = s;
   m_period = 7;
   m_apprice = PRICE_CLOSE;
   m_bb_deviation = 2;
   m_bbperiod = 14;
}

//M15 status
void CStatusM15::CStatusM15(string s)
{
   m_timeframe = PERIOD_M15;
   m_symb = s;
   m_period = 7;
   m_apprice = PRICE_CLOSE;
   m_bb_deviation = 2;
   m_bbperiod = 14;
}

//M5 status
void CStatusM5::CStatusM5(string s)
{
   m_timeframe = PERIOD_M5;
   m_symb = s;
   m_period = 7;
   m_apprice = PRICE_CLOSE;
   m_bb_deviation = 2;
   m_bbperiod = 14;
}

//M3 status
void CStatusD1::CStatusD1(string s)
{
   m_timeframe = PERIOD_D1;
   m_symb = s;
   m_period = 7;
   m_apprice = PRICE_CLOSE;
   m_bb_deviation = 2;
   m_bbperiod = 14;
}

void CStatusW1::CStatusW1(string s)
{
   m_timeframe = PERIOD_W1;
   m_symb = s;
   m_period = 7;
   m_apprice = PRICE_CLOSE;
   m_bb_deviation = 2;
   m_bbperiod = 14;
}

void CStatusMth::CStatusMth(string s)
{
   m_timeframe = PERIOD_MN1;
   m_symb = s;
   m_period = 7;
   m_apprice = PRICE_CLOSE;
   m_bb_deviation = 2;
   m_bbperiod = 14;
}

//Order value
int SetOrderValue(double& lots)
{
   double Min_Lot=0.0;                         // Minimal amount of lots   
   double Step=0.0;                            // Step of lot size change   
	double Free=0.0;                            // Current free margin   
	double One_Lot=0.0;                         // Price of one lot  
	int err = ERR_NO_ERROR;
	
	RefreshRates();                              // Refresh rates   
	Min_Lot = MarketInfo(Symb, MODE_MINLOT);        // Minimal number of lots    
	if ((err = GetLastError()) != ERR_NO_ERROR)
   {
      return err;
   }
   
	Free = AccountFreeMargin();                 // Free margin   
	if ((err = GetLastError()) != ERR_NO_ERROR)
   {
      return err;
   }
   
	One_Lot = MarketInfo(Symb, MODE_MARGINREQUIRED);// Price of 1 lot  
	if ((err = GetLastError()) != ERR_NO_ERROR)
   {
      return err;
   }
   
	Step = MarketInfo(Symb, MODE_LOTSTEP);       // Step is changed   
	if ((err = GetLastError()) != ERR_NO_ERROR)
   {
      return err;
   }
	
	if (Lots < 0)                                // If lots are set,     
		lots = Lots;                                // work with them   
	else                                         // % of free margin   
	{
		lots = MathFloor(Free*Prots/One_Lot/Step)*Step;// For opening   
		if ((err = GetLastError()) != ERR_NO_ERROR)
      {
         return err;
      }
   }
   
   lots = 0.1;
	if (lots * One_Lot > Free)                      // Lot larger than free margin   
	{      
		Print(" Not enough money for ", lots," lots");     
		return 1;                                   // Exit start()    
	}
	
	return 0;
}

int SelectOrder(string symb, int& count)
{
	int Total = 0;                                        // Amount of orders   
	int ordertotal = OrdersTotal();                                   
	
	for(int i = 0; i < ordertotal; i++)          // Loop through orders    
	{      
		if (OrderSelect(i, SELECT_BY_POS) == true) // If there is the next one        
		{                                       // Analyzing orders:         
			if (OrderSymbol() != symb)
				continue;      // Another security         
			
			Total++;                               // Counter of market orders 
		}  
	} 
	
	count = Total;
	if (Total > 1)  
	   return Total;

   return count;
}

int Decide(int& smatrix[][], string symb, int ordertotal, int& result, int ordertype)
{
   int err = ERR_NO_ERROR;   
   int i = 0;
   double gradient_cur = 0.0;
   double gradient_old = 0.0;
   double gradient_sec = 0.0;
   double profit = 0.0;
   bool bbenter = false;
   
   result = 0;
   
   for (i = STATUS_OBJARR_SIZE - 1; i >= 0; i--)
   {
      //no order opened
      err = g_pstatus[i].CheckBollinger(smatrix);
      if (err != ERR_NO_ERROR)
         return err;

      err = g_pstatus[i].CheckMACDH(smatrix, gradient_sec, gradient_old, gradient_cur);
      if (err != ERR_NO_ERROR)
         return err;
         
      err = g_pstatus[i].CheckEMA(smatrix);
      if (err != ERR_NO_ERROR)
         return err;  
         
      err = g_pstatus[i].CheckADX(smatrix);
      if (err != ERR_NO_ERROR)
         return err;             
         
/*      err = g_pstatus[i].CheckMACD2C(smatrix);
      if (err != ERR_NO_ERROR)
         return err; 
         
      err = g_pstatus[i].CheckSpike(smatrix);
      if (err != ERR_NO_ERROR)
         return err; 
      
      err = g_pstatus[i].CheckEMA50(smatrix);
      if (err != ERR_NO_ERROR)
         return err;   
      
      err = g_pstatus[i].CheckPFE(smatrix);
      if (err != ERR_NO_ERROR)
         return err;  
         
      g_pstatus[i].CheckASRC(smatrix);
*/      
   } 
   
   if (ordertotal == 0)
   {
      if ((smatrix[ARRAYINDEX_M30][ARRAYINDEX_BBBAND] == STATUS_CROSS_UP && smatrix[ARRAYINDEX_H1][ARRAYINDEX_BBBAND] != STATUS_BAD 
         && (smatrix[ARRAYINDEX_M30][ARRAYINDEX_EMA] == STATUS_CROSS_UP || smatrix[ARRAYINDEX_M30][ARRAYINDEX_EMA] == STATUS_TMP_CROSSUP
         || smatrix[ARRAYINDEX_M30][ARRAYINDEX_MACDH] == STATUS_CROSS_UP || smatrix[ARRAYINDEX_M30][ARRAYINDEX_MACDH] == STATUS_TMP_CROSSUP))
         || (smatrix[ARRAYINDEX_H1][ARRAYINDEX_BBBAND] == STATUS_TMP_CROSSUP 
         && (smatrix[ARRAYINDEX_H1][ARRAYINDEX_EMA] == STATUS_CROSS_UP || smatrix[ARRAYINDEX_H1][ARRAYINDEX_EMA] == STATUS_TMP_CROSSUP
         || smatrix[ARRAYINDEX_H1][ARRAYINDEX_MACDH] == STATUS_CROSS_UP || smatrix[ARRAYINDEX_H1][ARRAYINDEX_MACDH] == STATUS_TMP_CROSSUP)))
      {
         result = ORDER_OPEN_BUY;
         bbenter = true;
         OutputDebug(StringConcatenate("Order decision: ORDER_OPEN_BUY. Condition 21 cross BB upper."));
      }
      
      if ((smatrix[ARRAYINDEX_M30][ARRAYINDEX_BBBAND] == STATUS_CROSS_DOWN && smatrix[ARRAYINDEX_H1][ARRAYINDEX_BBBAND] != STATUS_BAD
         && (smatrix[ARRAYINDEX_M30][ARRAYINDEX_EMA] == STATUS_CROSS_DOWN || smatrix[ARRAYINDEX_M30][ARRAYINDEX_EMA] == STATUS_TMP_CROSSDOWN
         || smatrix[ARRAYINDEX_M30][ARRAYINDEX_MACDH] == STATUS_CROSS_DOWN || smatrix[ARRAYINDEX_M30][ARRAYINDEX_MACDH] == STATUS_TMP_CROSSDOWN))
         || (smatrix[ARRAYINDEX_H1][ARRAYINDEX_BBBAND] == STATUS_TMP_CROSSDOWN
         && (smatrix[ARRAYINDEX_H1][ARRAYINDEX_EMA] == STATUS_CROSS_DOWN || smatrix[ARRAYINDEX_H1][ARRAYINDEX_EMA] == STATUS_TMP_CROSSDOWN
         || smatrix[ARRAYINDEX_H1][ARRAYINDEX_MACDH] == STATUS_CROSS_DOWN || smatrix[ARRAYINDEX_H1][ARRAYINDEX_MACDH] == STATUS_TMP_CROSSDOWN)))
      {
         result = ORDER_OPEN_SELL;
         bbenter = true;
         OutputDebug(StringConcatenate("Order decision: ORDER_OPEN_SELL. Condition 22 cross BB lower."));
      }
                         
      if (result == ORDER_OPEN_BUY || result == ORDER_OPEN_SELL)
      {
         if (smatrix[ARRAYINDEX_H4][ARRAYINDEX_ADX] == STATUS_CROSS_UP || bbenter == true)
         {
            TakeProfit = 800;
         }     
      }        
   }
   else if(ordertotal == 1)
   {
      if (StopLoss != 0)
      {        
         if (ordertype == OP_BUY)
         {
            profit = Bid - g_Price;
            if (profit > g_profit)
               g_profit = profit;
            
            if (g_profit > 150*Point) 
            {           
               g_SL = g_Price + 10*Point; 
               result = ORDER_MODIFY;
            }
        
            if (g_profit > 500*Point)
            {
               g_SL = g_Price + 350*Point;  
               result = ORDER_MODIFY;
            } 
            
            if (g_profit > 600*Point)
            {
               g_SL = g_Price + 400*Point;  
               result = ORDER_MODIFY;
            } 
                       
            if (g_profit > 700*Point)
            {
               g_SL = g_Price + 500*Point;  
               result = ORDER_MODIFY;
            }
         }
         
         if (ordertype == OP_SELL)
         {
            profit = g_Price - Ask;
            if (profit > g_profit)
               g_profit = profit;
            
            if (g_profit > 150*Point)  
            {          
               g_SL = g_Price - 10*Point; 
               result = ORDER_MODIFY;
            }

            if (g_profit > 500*Point)
            {
               g_SL = g_Price - 350*Point;
               result = ORDER_MODIFY;
            }

            if (g_profit > 600*Point)
            {
               g_SL = g_Price - 400*Point;
               result = ORDER_MODIFY;
            }   

            if (g_profit > 700*Point)
            {
               g_SL = g_Price - 500*Point;
               result = ORDER_MODIFY;
            }                      
         }  
      }         
   }
   
   return err;
}

//On tick main process.
int start()  
{   
	int Total = 0;                           // Amount of orders in a window    
	int Tip = -1;                          // Type of selected order (B=0,S=1)   
	int Ticket = 0;                          // Order number   
	double Lot = 0.0;                             // Amount of lots in a selected order   
	double Lts = 0.0;                             // Amount of lots in an opened order
	double Price = 0.0;                           // Price of a selected order   
	double SL = 0.0;                             // SL of a selected order   
	double TP = 0.0;                              // TP за a selected order  
	datetime orderclosetime = 0;
	datetime currentcandleopentime = 0;	
	
	int ret = 0;

	bool Ans = false;                     // Server response after closing   
	int err = ERR_NO_ERROR;
	int lastresult = 0;
	int ordertotal = 0;
	int result = ORDER_NO;
	int status_matrix[STATUS_OBJARR_SIZE][INDICATOR_COUNT] = {0}; //record all the status of the trade windows and indicators	
	double closeprice = 0.0;
	double closedorderSL = 0.0;
	double closedorderTP = 0.0;
	double openprice = 0.0;
   int ordertype = 0;
	string subject = "Test EA order operation notification";
	
	//--------------------------------------------------------------- 3 --   // Preliminary processing   
	if(Bars < Period_EMA_10)                       // Not enough bars     
	{      
		Print("Not enough bars in the window. EA doesn't work.");      
		return 0;                                   // Exit start()     
	}   
   
	if(Work == false)                              // Critical error     
	{      
		Print("Critical error. EA doesn't work.");      
		return 0;                                   // Exit start()     
	}
	
	ret = SelectOrder(Symb, ordertotal);
	OutputDebug(StringConcatenate("SelectOrder return: ", ret, ", ordertotal", ordertotal));
	if (ret == -1)
	   return 0;
	else if (ret > 1)
      return ERROR_MULTORDER;
   else if (ret == 1)
   {
      g_Ticket = OrderTicket();
      Lot = OrderLots();
      Tip = OrderType();
   }

	//--------------------------------------------------------------- 5 --   // Trading criteria    
   CStatusH4 sh4(Symb);
   CStatusH1 sh1(Symb);
   CStatusM30 sm30(Symb);
   CStatusM15 sm15(Symb);
   CStatusM5 sm5(Symb);
   CStatusD1 sd1(Symb);

   g_pstatus[ARRAYINDEX_H4] = &sh4;
   g_pstatus[ARRAYINDEX_H1] = &sh1;
   g_pstatus[ARRAYINDEX_M30] = &sm30;
   g_pstatus[ARRAYINDEX_M15] = &sm15;
   g_pstatus[ARRAYINDEX_M5] = &sm5;
   g_pstatus[ARRAYINDEX_D1] = &sd1; 

   err = Decide(status_matrix, Symb, ordertotal, result, Tip);
   if (err != ERR_NO_ERROR)
   {
      Print("Critical error ", err, ". EA doesn't work.");
      return err;
   }

	//--------------------------------------------------------------- 6 --   // Closing orders   
	while(true)                                  // Loop of closing orders     
	{  
		if (result == ORDER_CLOSE && Tip == OP_BUY)//g_ticketopenedbuy == true)                // Order Buy is opened..        
		{                                       // and there is criterion to close         
			Print("Attempt to close Buy ", g_Ticket, ". Waiting for response..");         
			RefreshRates();                        // Refresh rates      
			   
			Ans = OrderClose(g_Ticket, Lot, Bid, 2);      // Closing Buy 
			if (Ans == true)                         // Success :) 
			{
			   g_time = TimeCurrent(); 
			   string tmpstr = StringConcatenate("Closed order Buy at ", g_time, ", price ", Bid, ", lots ", g_Lts);            
				Print (tmpstr); //Ticket); 
				SendMail(subject, tmpstr);  
				g_profit = 0;
				g_LastTicket = g_Ticket;	
 
				break;                              // Exit closing loop           
			}   

			if (Fun_Error(GetLastError())==1)      // Processing errors            
				continue;                           // Retrying         
			return 0;                                // Exit start()        
		}       
			
		if (result == ORDER_CLOSE && Tip == OP_SELL)                // Order Sell is opened..        
		{                                       // and there is criterion to close         
			Print("Attempt to close Sell ", g_Ticket, ". Waiting for response..");        
			RefreshRates();                        // Refresh rates  
			      
			Ans = OrderClose(g_Ticket, Lot, Ask, 2);      // Closing Sell 
			if (Ans == true)                         // Success :)  
			{ 
			   g_time = TimeCurrent();  
			   string tmpstr = StringConcatenate("Closed order Sell at ", g_time, ", price ", Ask, ", lots ", g_Lts); 
			   Print(tmpstr); 
			   SendMail(subject, tmpstr);
			   g_profit = 0;
			   g_LastTicket = g_Ticket;	
			   
				break;                              // Exit closing loop           
			}
			
			if (Fun_Error(GetLastError())==1)      // Processing errors           
				continue;                           // Retrying        
			return 0;                                // Exit start()       
		}   
		break;                                    // Exit while    
	}

	//--------------------------------------------------------------- 7 --   // Order value   
   if (SetOrderValue(Lts) != 0)
      return 0;

	//--------------------------------------------------------------- 8 --   // Opening orders   
	while(true)                                  // Orders opening loop    
	{
		if (ordertotal == 0 && result == ORDER_OPEN_BUY)              // No new orders +      
		{                                       // criterion for opening Buy 
         //check whether last closed order is closed as stop loss.
			if (OrderSelect(OrdersHistoryTotal() - 1, SELECT_BY_POS, MODE_HISTORY) == true)
			{
			   closeprice = OrderClosePrice(); 
			   openprice = OrderOpenPrice();
			   closedorderSL = OrderStopLoss(); 
			   closedorderTP = OrderTakeProfit();
			   orderclosetime = OrderCloseTime();
			   ordertype = OrderType();
			   g_profit = 0;
			   
			   if ((closeprice - closedorderSL < CLOSEGAP_POS) && (closeprice - closedorderSL > CLOSEGAP_NEG) 
			      && (((closeprice > openprice) && ordertype == OP_SELL) || ((closeprice < openprice) && ordertype == OP_BUY)))
			      lastresult = ORDER_CLOSE_SL;
			   else if (closeprice - closedorderTP < CLOSEGAP_POS && closeprice - closedorderTP > CLOSEGAP_NEG)
			      lastresult = ORDER_CLOSE_TP;
            OutputDebug(StringConcatenate("Last closed order ticket is: ", OrderTicket(), 
			      ", close price is: ", closeprice, ", closed order stop loss is: ", closedorderSL, ", openprice is: ", openprice, ", lastresult is: ", lastresult, ", order close time is: ",
			      orderclosetime, ", closed order take profit is: ", closedorderTP));
			}
			else
			{
			   OutputDebug(StringConcatenate("OrderSelect Error message is:", GetLastError()));
			}				
			
         //Order closed in the same M30 candle, not good, suppress coming orders until this candle closes.
   	   if (lastresult == ORDER_CLOSE_SL && g_widesl == false && g_date == TimeDay(orderclosetime))
   	   {  
            g_widesl = true;
            OutputDebug(StringConcatenate("Order closed with stop loss, change BB condition to 28 candles."));
            return 0;
   	   }
   	   
   	   OutputDebug(StringConcatenate("g_widesl is:", g_widesl));

			RefreshRates();                        // Refresh rates       
			SL = Ask - New_Stop(StopLoss)*Point;     // Calculating SL of opened
         TP = Ask + TakeProfit*Point;   // Calculating TP of opened       
			Print("Attempt to open Buy. Waiting for response.. TP ", TP, " Point ", Point);       
			Ticket = OrderSend(Symb, OP_BUY, Lts, Ask, 2, SL, TP, NULL);//Opening Buy

			if (Ticket > 0)                        // Success :) 
			{
			   if (OrderSelect(Ticket, SELECT_BY_TICKET))
			      g_Price = OrderOpenPrice();
			   else
			      g_Price = Ask;
            g_TP = TP;
            g_SL = SL;
            g_Lts = Lts;
            g_Tip = OP_BUY;
            g_time = TimeCurrent();
            
   			string tmpstr = StringConcatenate("Opened order Buy at ", g_time, ", price ", g_Price, ", stop lost ", g_SL, ", lots ", g_Lts);
   			Print(tmpstr);
   			SendMail(subject, tmpstr);
            g_widesl = false;
				return 0;                             // Exit start()
			}
			if (Fun_Error(GetLastError())==1)      // Processing errors
				continue;                           // Retrying
			return 0;                                // Exit start()
		}   

		if (ordertotal == 0 && result == ORDER_OPEN_SELL)              // No opened orders +
		{
         //check whether last closed order is closed as stop loss.
			if (OrderSelect(OrdersHistoryTotal() - 1, SELECT_BY_POS, MODE_HISTORY) == true)
			{
			   closeprice = OrderClosePrice(); 
			   openprice = OrderOpenPrice();
			   closedorderSL = OrderStopLoss(); 
			   closedorderTP = OrderTakeProfit();
			   orderclosetime = OrderCloseTime();
			   ordertype = OrderType();
			   g_profit = 0;
			   
			   if ((closeprice - closedorderSL < CLOSEGAP_POS) && (closeprice - closedorderSL > CLOSEGAP_NEG) 
			      && (((closeprice > openprice) && ordertype == OP_SELL) || ((closeprice < openprice) && ordertype == OP_BUY)))
			      lastresult = ORDER_CLOSE_SL;
			   else if (closeprice - closedorderTP < CLOSEGAP_POS && closeprice - closedorderTP > CLOSEGAP_NEG)
			      lastresult = ORDER_CLOSE_TP;
            OutputDebug(StringConcatenate("Last closed order ticket is: ", OrderTicket(), 
			      ", close price is: ", closeprice, ", closed order stop loss is: ", closedorderSL, ", openprice is: ", openprice, ", lastresult is: ", lastresult, ", order close time is: ",
			      orderclosetime, ", closed order take profit is: ", closedorderTP));
			}
			else
			{
			   OutputDebug(StringConcatenate("OrderSelect Error message is:", GetLastError()));
			}					
			
         //Order closed in the same M30 candle, not good, suppress coming orders until this candle closes.
   	   if (lastresult == ORDER_CLOSE_SL && g_widesl == false && g_date == TimeDay(orderclosetime))
   	   {
            g_widesl = true;
            OutputDebug(StringConcatenate("Order closed with stop loss, change BB condition to 28 candles."));
            return 0;   	      
   	   }
   	   
   	   OutputDebug(StringConcatenate("g_widesl is:", g_widesl));
   	   
      	// criterion for opening Sell
			RefreshRates();                        // Refresh rates
			SL = Bid + New_Stop(StopLoss)*Point;     // Calculating SL of opened
			TP = Bid - TakeProfit*Point;   // Calculating TP of opened
			Print("Attempt to open Sell. Waiting for response.. TP ", TP, " Point ", Point);
			Ticket = OrderSend(Symb, OP_SELL, Lts, Bid, 2, SL, TP, NULL);//Opening Sell

			if (Ticket > 0)                        // Success :)
			{
			   if (OrderSelect(Ticket, SELECT_BY_TICKET))
			      g_Price = OrderOpenPrice();
			   else
			      g_Price = Bid;
            g_TP = TP;
            g_SL = SL;            
            g_Lts = Lts;
            g_Tip = OP_SELL;
            g_time = TimeCurrent();
            
   			string tmpstr = StringConcatenate("Opened order Sell at ", g_time, ", price ", g_Price, ", stop lost ", g_SL, ", lots ", g_Lts);
   		   Print(tmpstr);
   		   SendMail(subject, tmpstr);
   			g_widesl = false;
				return 0;                             // Exit start()
			}
			if (Fun_Error(GetLastError())==1)      // Processing errors
				continue;                           // Retrying
			return 0;                                // Exit start()
		}      
		break;                                    // Exit while     
	}//--------------------------------------------------------------- 9 --   
	
	//--------------------------------------------------------------- 6 --   // Closing orders   
	while(true)                                  // Loop of closing orders     
	{  
	   if (ordertotal == 1 && result == ORDER_MODIFY)
	   {
	      if (OrderSelect(g_Ticket, SELECT_BY_TICKET) && OrderModify(OrderTicket(),OrderOpenPrice(), g_SL, OrderTakeProfit(), 0))
	      {
	         Print(StringConcatenate("Order modified with new stop loss: ", g_SL));
	      }
	   }
      if (Fun_Error(GetLastError())==1)      // Processing errors           
			continue;                           // Retrying        
		break;                                    // Exit while    
	}
	
	return 0;                                      // Exit start()  
}

//-------------------------------------------------------------- 10 --

int Fun_Error(int Error)                        // Function of processing errors  
{   
	switch(Error)     
	{                                          // Not crucial errors                  
		case  4: 
			Print("Trade server is busy. Trying once again..");
			Sleep(3000);                           // Simple solution 
			return(1);                             // Exit the function      
		case 135:
			Print("Price changed. Trying once again..");         
			RefreshRates();                        // Refresh rates       
			return(1);                             // Exit the function      
		case 136:
			Print("No prices. Waiting for a new tick..");         
			while(RefreshRates()==false)           // Till a new tick            
			Sleep(1);                           // Pause in the loop         
		return(1);                             // Exit the function      
			case 137:
			Print("Broker is busy. Trying once again..");         
			Sleep(3000);                           // Simple solution         
		return(1);                             // Exit the function      
			case 146:
			Print("Trading subsystem is busy. Trying once again..");         
			Sleep(500);                            // Simple solution         
		return(1);                             // Exit the function         // Critical errors      
			case  2: 
			Print("Common error.");         
			return(0);                             // Exit the function      
		case  5: 
			Print("Old terminal version.");         
			Work=false;                            // Terminate operation         
			return(0);                             // Exit the function      
		case 64: 
			Print("Account blocked.");         
			Work=false;                            // Terminate operation
			return(0);                             // Exit the function      
		case 133:
			Print("Trading forbidden.");         
			return(0);                             // Exit the function 
		case 134:
			Print("Not enough money to execute operation.");    
			return(0);                             // Exit the function     
		default: 
//			Print("Error occurred: ",Error);  // Other variants    
			return(0);                             // Exit the function    
	}  
}

//-------------------------------------------------------------- 11 --
double New_Stop(double Parametr)                      // Checking stop levels  
{   
	double Min_Dist = MarketInfo(Symb, MODE_STOPLEVEL);// Minimal distance 
	if (Parametr < Min_Dist)                     // If less than allowed   
	{      
		Parametr=Min_Dist;                        // Sett allowed    
		Print("Increased distance of stop level.");     
	}  
	return(Parametr);                            // Returning value  
}

int GetTimeRange(int& time_range)
{
   datetime dt = {0};
   int err = ERR_NO_ERROR;
   int hour = 0;
   int min = 0;
   int workday = 0;
   
   dt = TimeCurrent();
   hour = TimeHour(dt);
   min = TimeMinute(dt);
   workday = TimeDayOfWeek(dt);

   if (hour >= 0 && hour < 3 && workday == 1)
   {
      time_range = TIMERANGE_NO;
   }
   else
      time_range = TIMERANGE_TRADE;

   return err;
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
//--- create timer
   int err = 0;
   Symb = Symbol();
   EventSetTimer(60);
   if (Symb != "XAUUSD")
   {
      ChartSetSymbolPeriod(0, "XAUUSD", PERIOD_D1);       
      err = GetLastError();
      if (err != ERR_NO_ERROR)
      {
         Print("Failed to init chart to XAUUSD.");
         return(INIT_FAILED);
      }
   }
      
   return(INIT_SUCCEEDED);
}
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
//--- destroy timer
   EventKillTimer();
}
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
//---
   int time_range = 0;
   int day = TimeDay(TimeCurrent());
   GetTimeRange(time_range);
   
   if (time_range == TIMERANGE_NO)
   {
      return; 
   }
   
   if (g_date != day)
   {
      g_date = day; 
      g_widesl = false;
      OutputDebug(StringConcatenate("A new day, reset g_widesl."));
   }
      
   start();
   
}
//+------------------------------------------------------------------+
//| Timer function                                                   |
//+------------------------------------------------------------------+
void OnTimer()
  {
//---
   
  }
//+------------------------------------------------------------------+
//| Tester function                                                  |
//+------------------------------------------------------------------+
double OnTester()
  {
//---
   double ret=0.0;
//---

//---
   return(ret);
  }
//+------------------------------------------------------------------+
//| ChartEvent function                                              |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
  {
//---
   
  }
//+------------------------------------------------------------------+
