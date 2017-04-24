//+------------------------------------------------------------------+
//|                                                         test.mq4 |
//|                        Copyright 2016, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2016, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

#include <gold.mqh>

extern double StopLoss   =300.0;     // SL for an opened order
extern double TakeProfit =0.0;      // ТР for an opened order
extern int    Period_EMA_5=5;      // Period of EMA chart 5 bar
extern int    Period_EMA_10=10;      // Period of EMA chart 10 bar
extern double Rastvor    =0.5;    // Distance between MAs 
extern double Lots       = 1;     // Strictly set amount of lots
extern double Prots      =0.1;    // Percent of free margin 
bool Work=true;                    // EA will work.
string Symb;                       // Security name
int g_timeframe[] = {PERIOD_M3, PERIOD_M5, PERIOD_M15, PERIOD_M30, PERIOD_H1, PERIOD_H4};
CStatus* g_pstatus[STATUS_OBJARR_SIZE] = {NULL};
static bool g_ticketopenedbuy = false;
static bool g_ticketopenedsell = false;
static double g_Lot = 0.0;                             // Amount of lots in a selected order   
static double g_Lts = 0.0;                             // Amount of lots in an opened order
static double g_Price = 0.0;                           // Price of a selected order   
static double g_SL = 0.0;                             // SL of a selected order   
static double g_TP = 0.0;                              // TP за a selected order 
static double g_M30lopen = 0.0;                          //record last M30 candle open price
static double g_M30lclose = 0.0;                         //record last M30 candle close price
static double g_M30lhigh = 0.0;                          //record last M30 candle high price
static double g_M30llow = 0.0;                           //record last M30 candle low price
static bool g_bM30Suppression = false;                   //flag to suppress continue entering when close in the same M30 candle
static int g_Tip = 0;
static datetime g_time = {0};
static int g_ordertotal = 0;
static int g_bbthreshold = 20;
static int g_CCIbuy = false;
static int g_CCIsell = false;
static double g_profit = 0.0;
static int iHandle = INVALID_HANDLE;

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
      case PERIOD_M3:
         return "M3";
      default:
         return "Unknown";
   }
   return "Unknown";
}

void OutputDebug(string str)
{
//   Print(str);
   int iErrorCode = ERR_NO_ERROR;
   str = str + TimeToStr(TimeCurrent(), TIME_DATE|TIME_SECONDS);
   if (FileWrite(iHandle, str) == 0)
   {
      iErrorCode = GetLastError();
      Print("Error: File txt write error.", iErrorCode);
   }
   return;
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
      case PERIOD_M3:
      default:
//         threshold_up = GRADIENT_THRESHOLD_UP;
//         threshold_down = GRADIENT_THRESHOLD_DOWN;  
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
      case PERIOD_M3:
         a = ARRAYINDEX_M3;
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
//   OutputDebug(StringConcatenate("MACD_Histogram ", TimeFrameToString(m_timeframe), ": current_fast ", current_fast));
   if ((err = GetLastError()) != ERR_NO_ERROR)
   {
      return err;
   }
   
   double current_slow = iCustom(m_symb, m_timeframe, "MACD_Histogram", "", 7, 14, 9, "", false, false, false, 1, 0);
//   OutputDebug(StringConcatenate("MACD_Histogram ", TimeFrameToString(m_timeframe), ": current_slow ", current_slow));
   if ((err = GetLastError()) != ERR_NO_ERROR)
   {
      return err;
   }
   
   double last_fast = iCustom(m_symb, m_timeframe, "MACD_Histogram", "", 7, 14, 9, "", false, false, false, 0, 1);
//   OutputDebug(StringConcatenate("MACD_Histogram ", TimeFrameToString(m_timeframe), ": last_fast ", last_fast));
   if ((err = GetLastError()) != ERR_NO_ERROR)
   {
      return err;
   }
   
   double last_slow = iCustom(m_symb, m_timeframe, "MACD_Histogram", "", 7, 14, 9, "", false, false, false, 1, 1);
//   OutputDebug(StringConcatenate("MACD_Histogram ", TimeFrameToString(m_timeframe), ": last_slow ", last_slow));
   if ((err = GetLastError()) != ERR_NO_ERROR)
   {
      return err;
   }
   
   double llast_fast = iCustom(m_symb, m_timeframe, "MACD_Histogram", "", 7, 14, 9, "", false, false, false, 0, 2);
//   OutputDebug(StringConcatenate("MACD_Histogram ", TimeFrameToString(m_timeframe), ": llast_fast ", llast_fast));
   if ((err = GetLastError()) != ERR_NO_ERROR)
   {
      return err;
   }
   
   double llast_slow = iCustom(m_symb, m_timeframe, "MACD_Histogram", "", 7, 14, 9, "", false, false, false, 1, 2);
//   OutputDebug(StringConcatenate("MACD_Histogram ", TimeFrameToString(m_timeframe), ": llast_slow ", llast_slow));
   if ((err = GetLastError()) != ERR_NO_ERROR)
   {
      return err;
   }
   
   double lfourth_fast = iCustom(m_symb, m_timeframe, "MACD_Histogram", "", 7, 14, 9, "", false, false, false, 0, 3);
//   OutputDebug(StringConcatenate("MACD_Histogram ", TimeFrameToString(m_timeframe), ": llast_slow ", llast_slow));
   if ((err = GetLastError()) != ERR_NO_ERROR)
   {
      return err;
   }
   
   double lfourth_slow = iCustom(m_symb, m_timeframe, "MACD_Histogram", "", 7, 14, 9, "", false, false, false, 1, 3);
//   OutputDebug(StringConcatenate("MACD_Histogram ", TimeFrameToString(m_timeframe), ": llast_slow ", llast_slow));
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
         if (m_timeframe == PERIOD_M5 || m_timeframe == PERIOD_M3)
            status = STATUS_UNKNOWN;
         else
            status = STATUS_CLOSE_DOWN;
         break;
      case LINERELATION_DOWNCLOSE:
         if (m_timeframe == PERIOD_M5 || m_timeframe == PERIOD_M3)
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
// OutputDebug(StringConcatenate("EMA ", TimeFrameToString(m_timeframe), ": current_5 ", current_5));
   if ((err = GetLastError()) != ERR_NO_ERROR)
   {
      return err;
   }
   
	double current_10 = iMA(m_symb, m_timeframe, Period_EMA_10, 0, MODE_EMA, PRICE_CLOSE, 0);
//	OutputDebug(StringConcatenate("EMA ", TimeFrameToString(m_timeframe), ": current_10 ", current_10));
	if ((err = GetLastError()) != ERR_NO_ERROR)
   {
      return err;
   }
   
	double last_5 = iMA(m_symb, m_timeframe, Period_EMA_5, 0, MODE_EMA, PRICE_CLOSE, 1);
//	OutputDebug(StringConcatenate("EMA ", TimeFrameToString(m_timeframe), ": last_5 ", last_5));
	if ((err = GetLastError()) != ERR_NO_ERROR)
   {
      return err;
   }
   
	double last_10 = iMA(m_symb, m_timeframe, Period_EMA_10, 0, MODE_EMA, PRICE_CLOSE, 1);
//	OutputDebug(StringConcatenate("EMA ", TimeFrameToString(m_timeframe), ": last_10 ", last_10));
	if ((err = GetLastError()) != ERR_NO_ERROR)
   {
      return err;
   }
   
	double llast_5 = iMA(m_symb, m_timeframe, Period_EMA_5, 0, MODE_EMA, PRICE_CLOSE, 2);
//	OutputDebug(StringConcatenate("EMA ", TimeFrameToString(m_timeframe), ": llast_5 ", llast_5));
	if ((err = GetLastError()) != ERR_NO_ERROR)
   {
      return err;
   }
   
	double llast_10 = iMA(m_symb, m_timeframe, Period_EMA_10, 0, MODE_EMA, PRICE_CLOSE, 2);
//	OutputDebug(StringConcatenate("EMA ", TimeFrameToString(m_timeframe), ": llast_10 ", llast_10));
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
         if (m_timeframe == PERIOD_M5 || m_timeframe == PERIOD_M3)
            status = STATUS_UNKNOWN;
         else
            status = STATUS_CLOSE_UP;
         break;
      case LINERELATION_DOWNCLOSE:
         if (m_timeframe == PERIOD_M5 || m_timeframe == PERIOD_M3)
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
   
//   GetTimeRange(time_range);
   if (m_timeframe == PERIOD_H4)
      adx_threshold_h = 20;
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
   
   if (m_timeframe == PERIOD_H4 || m_timeframe == PERIOD_H1 || m_timeframe == PERIOD_M15 || m_timeframe == PERIOD_M30)
   {
      if (adx_sth_last > adx_sth && adx_ndi < adx_threshold_h && adx_pdi < adx_threshold_h)
      {
         status = STATUS_BAD;
         OutputDebug(StringConcatenate("ADX ", TimeFrameToString(m_timeframe), ": STATUS_BAD. ", " Current strength ", adx_sth, " Last strength ", adx_sth_last, " +DI ", adx_pdi, " -DI ", adx_ndi));         
      }
   }
      
//   if (adx_ndi > adx_threshold_h || adx_pdi > adx_threshold_h)
//   {
//      if (adx_ndi > adx_pdi)
//      {
//         status = STATUS_CROSS_DOWN;
//         OutputDebug(StringConcatenate("ADX ", TimeFrameToString(m_timeframe), ": STATUS_CROSS_DOWN. ", " Strength ", adx_sth, " +DI ", adx_pdi, " -DI ", adx_ndi));
//      }
//      else if (adx_pdi > adx_ndi)
//      {
//         status = STATUS_CROSS_UP;
//         OutputDebug(StringConcatenate("ADX ", TimeFrameToString(m_timeframe), ": STATUS_CROSS_UP. ", " Strength ", adx_sth, " +DI ", adx_pdi, " -DI ", adx_ndi));
//      }
//      else
//      {
//         status = STATUS_UNKNOWN;
//         OutputDebug(StringConcatenate("ADX ", TimeFrameToString(m_timeframe), ": STATUS_UNKNOWN. ", " Strength ", adx_sth, " +DI ", adx_pdi, " -DI ", adx_ndi));
//      }
//   }
//   else
//   {      
//      status = STATUS_BAD;
//      OutputDebug(StringConcatenate("ADX ", TimeFrameToString(m_timeframe), ": STATUS_BAD. ", " Strength ", adx_sth, " +DI ", adx_pdi, " -DI ", adx_ndi));
//   }

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
   
   double current_upper = iBands(m_symb, m_timeframe, m_bbperiod, m_bb_deviation, 0, PRICE_CLOSE, MODE_UPPER, 0);
   if ((err = GetLastError()) != ERR_NO_ERROR)
   {
      return err;
   }
   
   double current_lower = iBands(m_symb, m_timeframe, m_bbperiod, m_bb_deviation, 0, PRICE_CLOSE, MODE_LOWER, 0);
   if ((err = GetLastError()) != ERR_NO_ERROR)
   {
      return err;
   }
   
   if (current_upper - current_lower < g_bbthreshold)
   {
      status = STATUS_BAD;
      OutputDebug(StringConcatenate("Bollinger ", TimeFrameToString(m_timeframe), ": STATUS_BAD. ", " MODE_UPPER ", current_upper, " MODE_LOWER ", current_lower));
   }
   else
      OutputDebug(StringConcatenate("Bollinger ", TimeFrameToString(m_timeframe), ": Good to trade. ", " MODE_UPPER ", current_upper, " MODE_LOWER ", current_lower));
   
   if (AssignValueSM(smatrix, ARRAYINDEX_BBBAND, status))
      err = ERR_NO_ERROR;
   else
      err = ERROR_VALUEASSIGN;

   return err;
}

int CheckCCIM5()
{
   int cci_status = STATUS_CCI_UNKNOWN;
   int err = ERR_NO_ERROR;
   double cci_m5_current = iCCI(Symb, PERIOD_M5, 14, PRICE_TYPICAL, 0);
   if ((err = GetLastError()) != ERR_NO_ERROR)
   {
      return STATUS_CCI_ERROR;
   }
      
   double cci_m5_last = iCCI(Symb, PERIOD_M5, 14, PRICE_TYPICAL, 1);
   if ((err = GetLastError()) != ERR_NO_ERROR)
   {
      return STATUS_CCI_ERROR;
   }
   
   double cci_m5_llast = iCCI(Symb, PERIOD_M5, 14, PRICE_TYPICAL, 2);
   if ((err = GetLastError()) != ERR_NO_ERROR)
   {
      return STATUS_CCI_ERROR;
   }
   
   if (cci_m5_llast >= 100.0 && cci_m5_last < 100.0)
   {
      cci_status = STATUS_CCI_COME_DOWN;
   }
   else if (cci_m5_llast <= -100.0 && cci_m5_last > -100.0)
   {
      cci_status = STATUS_CCI_COME_UP;
   }
   else if (cci_m5_current > 100)
   {
      cci_status = STATUS_CCI_UP_STRONG;
   }
   else if (cci_m5_current < -100)
   {
      cci_status = STATUS_CCI_DOWN_STRONG;
   }
   else
   {
   }
   
   OutputDebug(StringConcatenate("CheckCCIM5, cci_status is: ", cci_status));
   return cci_status;   
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
   
//   if ((((macd2c_pos_last > 0 && macd2c_neg_last == 0) && (macd2c_pos_cur == 0 && macd2c_neg_cur < 0))
//      || ((macd2c_pos_llast > 0 && macd2c_neg_llast == 0) && (macd2c_pos_last == 0 && macd2c_neg_last == 0) && (macd2c_pos_cur == 0 && macd2c_neg_cur < 0))) 
//      && (macd2c_wave_last > macd2c_neg_last) && (macd2c_wave_cur > macd2c_pos_cur))
//   {
//      status = STATUS_MACD2C_V1_DOWN;
//   }
   
//   if ((((macd2c_pos_last == 0 && macd2c_neg_last < 0) && (macd2c_pos_cur > 0 && macd2c_neg_cur == 0))
//      || ((macd2c_pos_llast == 0 && macd2c_neg_llast < 0) && (macd2c_pos_last == 0 && macd2c_neg_last == 0) && (macd2c_pos_cur > 0 && macd2c_neg_cur == 0))) 
//      && (macd2c_wave_last < macd2c_pos_last) && (macd2c_wave_cur < macd2c_pos_cur))
//   {
//      status = STATUS_MACD2C_V1_UP;
//   }
   
   if (status == 0)
   {
      if (m_timeframe == PERIOD_M5 || m_timeframe == PERIOD_M3 || m_timeframe == PERIOD_M15)
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
      else
      {
         if ((macd2c_pos_cur > 0 && macd2c_neg_cur == 0 && macd2c_pos_cur < macd2c_wave_cur)
            || (macd2c_pos_cur == 0 && macd2c_neg_cur <= 0 && macd2c_neg_cur < macd2c_wave_cur))
            status = STATUS_MACD2C_BELOW_YL;
         
         if ((macd2c_pos_cur == 0 && macd2c_neg_cur < 0 && macd2c_neg_cur > macd2c_wave_cur)
            || (macd2c_pos_cur >= 0 && macd2c_neg_cur == 0 && macd2c_pos_cur > macd2c_wave_cur))
            status = STATUS_MACD2C_ABOVE_YL;
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
void CStatusM3::CStatusM3(string s)
{
   m_timeframe = PERIOD_M3;
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
	if(lots > Min_Lot) 
		lots = Min_Lot;               // Not less than minimal  
	if (lots * One_Lot > Free)                      // Lot larger than free margin   
	{      
		Print(" Not enough money for ", lots," lots");     
		return 1;                                   // Exit start()    
	}
	
	return 0;
}

bool SelectOrder(string symb, int& count)
{
	int Total = 0;                                        // Amount of orders   
	int ordertotal = OrdersTotal();                                   
	
	for(int i = 0; i < ordertotal; i++)          // Loop through orders    
	{      
		if (OrderSelect(i, SELECT_BY_POS) == true) // If there is the next one        
		{                                       // Analyzing orders:         
			if (OrderSymbol() != symb)
				continue;      // Another security         
			if (OrderType() < 1)                     // Pending order found           
			{            
				count = 0;        
				return false;                             // Exit start()           
			}         
			
			Total++;                               // Counter of market orders         
			
			if (Total < 1)                           // No more than one order           
			{            
				count = 0;          
				return false;                             // Exit start()   				        
			} 
		}  
	} 
	
	count = Total;
	if (Total > 1)  
	   return false;

   return true;
}

int Decide(int& smatrix[][], string symb, int ordertotal, int& result)
{
   int err = ERR_NO_ERROR;   
   int i = 0;
   double gradient_cur = 0.0;
   double gradient_old = 0.0;
   double gradient_sec = 0.0;
   double gradient_cur_m3 = 0.0;
   double gradient_old_m3 = 0.0;
   double gradient_sec_m3 = 0.0;
   double profit = 0.0;
   
   result = 0;
   
   for (i = STATUS_OBJARR_SIZE - 2; i >= 0; i--)
   {
      //no order opened
      err = g_pstatus[i].CheckADX(smatrix);
      if (err != ERR_NO_ERROR)
         return err;
//      if (smatrix[i][ARRAYINDEX_ADX] == STATUS_BAD && ordertotal == 0)
//      {
//         result = ORDER_NO; 
//         return err;
//      }        
      
//      err = g_pstatus[i].CheckBollinger(smatrix);
//      if (err != ERR_NO_ERROR)
//         return err;
//      if (i != ARRAYINDEX_M3 && smatrix[i][ARRAYINDEX_BBBAND] == STATUS_BAD && ordertotal == 0)
//      {
//         result = ORDER_NO; 
//         return err;  
//      } 
      
      err = g_pstatus[i].CheckEMA(smatrix);
      if (err != ERR_NO_ERROR)
         return err;      
      
      err = g_pstatus[i].CheckMACDH(smatrix, gradient_sec, gradient_old, gradient_cur);
      if (err != ERR_NO_ERROR)
         return err;
         
      err = g_pstatus[i].CheckMACD2C(smatrix);
      if (err != ERR_NO_ERROR)
         return err; 
         
      err = g_pstatus[i].CheckSpike(smatrix);
      if (err != ERR_NO_ERROR)
         return err;            

   }   
     
   if (ordertotal == 0)
   {
      if (smatrix[ARRAYINDEX_M30][ARRAYINDEX_SPIKE_REVERSE] == STATUS_SPIKE_NO)
      {
         if (smatrix[ARRAYINDEX_H4][ARRAYINDEX_ADX] == STATUS_BAD || smatrix[ARRAYINDEX_M15][ARRAYINDEX_ADX] == STATUS_BAD 
            || smatrix[ARRAYINDEX_M30][ARRAYINDEX_ADX] == STATUS_BAD
            || smatrix[ARRAYINDEX_H1][ARRAYINDEX_ADX] == STATUS_BAD)
            return err;
      }
      else
      {
         OutputDebug(StringConcatenate("Found M30 spike reverse, ignore ADX restrictions."));
      }
      
//      if (smatrix[ARRAYINDEX_M15][ARRAYINDEX_EMA] == STATUS_CROSS_UP 
//         && (smatrix[ARRAYINDEX_M15][ARRAYINDEX_MACDH] == STATUS_KEEP_UP || smatrix[ARRAYINDEX_M15][ARRAYINDEX_MACDH] == STATUS_CROSS_UP)
//         && (smatrix[ARRAYINDEX_M15][ARRAYINDEX_MACD2C] == STATUS_MACD2C_ABOVE_YL || smatrix[ARRAYINDEX_M15][ARRAYINDEX_MACD2C] == STATUS_MACD2C_ABOVE_YL_CLOSE)
//         && (smatrix[ARRAYINDEX_M30][ARRAYINDEX_MACDH] == STATUS_KEEP_UP || smatrix[ARRAYINDEX_M30][ARRAYINDEX_MACDH] == STATUS_CROSS_UP
//         || smatrix[ARRAYINDEX_M30][ARRAYINDEX_MACDH] == STATUS_TMP_CROSSUP || smatrix[ARRAYINDEX_M30][ARRAYINDEX_MACDH] == STATUS_CLOSE_UP)
//         && (smatrix[ARRAYINDEX_M30][ARRAYINDEX_MACD2C] == STATUS_MACD2C_ABOVE_YL || smatrix[ARRAYINDEX_M30][ARRAYINDEX_MACD2C] == STATUS_MACD2C_ABOVE_YL_CLOSE
//         || smatrix[ARRAYINDEX_M30][ARRAYINDEX_MACD2C_G] == GRADIENT_RED_UP || smatrix[ARRAYINDEX_M30][ARRAYINDEX_MACD2C_G] == GRADIENT_RED_REVERT_UP)
//         && (smatrix[ARRAYINDEX_H1][ARRAYINDEX_MACDH] == STATUS_KEEP_UP || smatrix[ARRAYINDEX_H1][ARRAYINDEX_MACDH] == STATUS_CROSS_UP
//         || smatrix[ARRAYINDEX_H1][ARRAYINDEX_MACDH] ==STATUS_TMP_CROSSUP || smatrix[ARRAYINDEX_H1][ARRAYINDEX_MACDH] == STATUS_CLOSE_UP)
//         && (smatrix[ARRAYINDEX_H4][ARRAYINDEX_MACDH] == STATUS_KEEP_UP || smatrix[ARRAYINDEX_H4][ARRAYINDEX_MACDH] == STATUS_CROSS_UP 
//         || smatrix[ARRAYINDEX_H4][ARRAYINDEX_MACDH] ==STATUS_TMP_CROSSUP || smatrix[ARRAYINDEX_H4][ARRAYINDEX_MACDH] == STATUS_CLOSE_UP))
//         {
//            result = ORDER_OPEN_BUY; 
//            OutputDebug(StringConcatenate("Order decision: ORDER_OPEN_BUY. Condition 1 EMA cross enter."));
//         }
         
//      if (smatrix[ARRAYINDEX_M15][ARRAYINDEX_EMA] == STATUS_CROSS_DOWN 
//         && (smatrix[ARRAYINDEX_M15][ARRAYINDEX_MACDH] == STATUS_KEEP_DOWN || smatrix[ARRAYINDEX_M15][ARRAYINDEX_MACDH] == STATUS_CROSS_DOWN)
//         && (smatrix[ARRAYINDEX_M15][ARRAYINDEX_MACD2C] == STATUS_MACD2C_BELOW_YL || smatrix[ARRAYINDEX_M15][ARRAYINDEX_MACD2C] == STATUS_MACD2C_BELOW_YL_CLOSE)
//         && (smatrix[ARRAYINDEX_M30][ARRAYINDEX_MACDH] == STATUS_KEEP_DOWN || smatrix[ARRAYINDEX_M30][ARRAYINDEX_MACDH] == STATUS_CROSS_DOWN
//         || smatrix[ARRAYINDEX_M30][ARRAYINDEX_MACDH] == STATUS_TMP_CROSSDOWN || smatrix[ARRAYINDEX_M30][ARRAYINDEX_MACDH] == STATUS_CLOSE_DOWN)
//         && (smatrix[ARRAYINDEX_M30][ARRAYINDEX_MACD2C] == STATUS_MACD2C_BELOW_YL || smatrix[ARRAYINDEX_M30][ARRAYINDEX_MACD2C] == STATUS_MACD2C_BELOW_YL_CLOSE
//         || smatrix[ARRAYINDEX_M30][ARRAYINDEX_MACD2C_G] == GRADIENT_GREEN_DOWN || smatrix[ARRAYINDEX_M30][ARRAYINDEX_MACD2C_G] == GRADIENT_GREEN_REVERT_DOWN)
//         && (smatrix[ARRAYINDEX_H1][ARRAYINDEX_MACDH] == STATUS_KEEP_DOWN || smatrix[ARRAYINDEX_H1][ARRAYINDEX_MACDH] == STATUS_CROSS_DOWN
//         || smatrix[ARRAYINDEX_H1][ARRAYINDEX_MACDH] ==STATUS_TMP_CROSSDOWN || smatrix[ARRAYINDEX_H1][ARRAYINDEX_MACDH] == STATUS_CLOSE_DOWN)
//         && (smatrix[ARRAYINDEX_H4][ARRAYINDEX_MACDH] == STATUS_KEEP_DOWN || smatrix[ARRAYINDEX_H4][ARRAYINDEX_MACDH] == STATUS_CROSS_DOWN
//         || smatrix[ARRAYINDEX_H4][ARRAYINDEX_MACDH] ==STATUS_TMP_CROSSDOWN || smatrix[ARRAYINDEX_H4][ARRAYINDEX_MACDH] == STATUS_CLOSE_DOWN))
//         {
//            result = ORDER_OPEN_SELL;
//            OutputDebug(StringConcatenate("Order decision: ORDER_OPEN_SELL. Condition 2 EMA cross enter."));
//         }
         
//      if ((smatrix[ARRAYINDEX_M15][ARRAYINDEX_EMA] == STATUS_KEEP_UP || smatrix[ARRAYINDEX_M15][ARRAYINDEX_EMA] == STATUS_CROSS_UP
//         || smatrix[ARRAYINDEX_M15][ARRAYINDEX_EMA] == STATUS_TMP_CROSSUP)
//         && smatrix[ARRAYINDEX_M15][ARRAYINDEX_MACDH] == STATUS_CROSS_UP
//         && (smatrix[ARRAYINDEX_M30][ARRAYINDEX_MACDH] == STATUS_KEEP_UP || smatrix[ARRAYINDEX_M30][ARRAYINDEX_MACDH] == STATUS_CLOSE_DOWN)
//         && smatrix[ARRAYINDEX_M30][ARRAYINDEX_MACD2C] == STATUS_MACD2C_ABOVE_YL
//         && (smatrix[ARRAYINDEX_H1][ARRAYINDEX_MACDH] == STATUS_KEEP_UP || smatrix[ARRAYINDEX_H1][ARRAYINDEX_MACDH] == STATUS_CROSS_UP
//         || smatrix[ARRAYINDEX_H1][ARRAYINDEX_MACDH] ==STATUS_TMP_CROSSUP || smatrix[ARRAYINDEX_H1][ARRAYINDEX_MACDH] == STATUS_CLOSE_UP)
//         && (smatrix[ARRAYINDEX_H4][ARRAYINDEX_MACDH] == STATUS_KEEP_UP || smatrix[ARRAYINDEX_H4][ARRAYINDEX_MACDH] == STATUS_CROSS_UP
//         || smatrix[ARRAYINDEX_H4][ARRAYINDEX_MACDH] ==STATUS_TMP_CROSSUP || smatrix[ARRAYINDEX_H4][ARRAYINDEX_MACDH] == STATUS_CLOSE_UP))
//         {
//            result = ORDER_OPEN_BUY; 
//            OutputDebug(StringConcatenate("Order decision: ORDER_OPEN_BUY. Condition 3 MACD_Histogram CCI cross re-enter."));
//         }
         
//      if ((smatrix[ARRAYINDEX_M15][ARRAYINDEX_EMA] == STATUS_KEEP_DOWN || smatrix[ARRAYINDEX_M15][ARRAYINDEX_EMA] == STATUS_CROSS_DOWN
//         || smatrix[ARRAYINDEX_M15][ARRAYINDEX_EMA] == STATUS_TMP_CROSSDOWN)
//         && smatrix[ARRAYINDEX_M15][ARRAYINDEX_MACDH] == STATUS_CROSS_DOWN
//         && (smatrix[ARRAYINDEX_M30][ARRAYINDEX_MACDH] == STATUS_KEEP_DOWN || smatrix[ARRAYINDEX_M30][ARRAYINDEX_MACDH] == STATUS_CLOSE_UP)
//         && smatrix[ARRAYINDEX_M30][ARRAYINDEX_MACD2C] == STATUS_MACD2C_BELOW_YL
//         && (smatrix[ARRAYINDEX_H1][ARRAYINDEX_MACDH] == STATUS_KEEP_DOWN || smatrix[ARRAYINDEX_H1][ARRAYINDEX_MACDH] == STATUS_CROSS_DOWN
//         || smatrix[ARRAYINDEX_H1][ARRAYINDEX_MACDH] ==STATUS_TMP_CROSSDOWN || smatrix[ARRAYINDEX_H1][ARRAYINDEX_MACDH] == STATUS_CLOSE_DOWN)
//         && (smatrix[ARRAYINDEX_H4][ARRAYINDEX_MACDH] == STATUS_KEEP_DOWN || smatrix[ARRAYINDEX_H4][ARRAYINDEX_MACDH] == STATUS_CROSS_DOWN
//         || smatrix[ARRAYINDEX_H4][ARRAYINDEX_MACDH] ==STATUS_TMP_CROSSDOWN || smatrix[ARRAYINDEX_H4][ARRAYINDEX_MACDH] == STATUS_CLOSE_DOWN))
//         {
//            result = ORDER_OPEN_SELL;
//            OutputDebug(StringConcatenate("Order decision: ORDER_OPEN_SELL. Condition 4 MACD_Histogram CCI cross re-enter."));
//         }
         
//      if ((smatrix[ARRAYINDEX_M15][ARRAYINDEX_EMA] == STATUS_KEEP_UP || smatrix[ARRAYINDEX_M15][ARRAYINDEX_EMA] == STATUS_CLOSE_DOWN)
//         && (smatrix[ARRAYINDEX_M15][ARRAYINDEX_MACDH] == STATUS_KEEP_UP || smatrix[ARRAYINDEX_M15][ARRAYINDEX_MACDH] == STATUS_CLOSE_DOWN)
//         && (smatrix[ARRAYINDEX_M30][ARRAYINDEX_MACDH] == STATUS_KEEP_UP || smatrix[ARRAYINDEX_M30][ARRAYINDEX_MACDH] == STATUS_CLOSE_DOWN)
//         && (smatrix[ARRAYINDEX_M5][ARRAYINDEX_EMA] == STATUS_KEEP_UP || smatrix[ARRAYINDEX_M5][ARRAYINDEX_EMA] == STATUS_CROSS_UP
//         || smatrix[ARRAYINDEX_M5][ARRAYINDEX_EMA] == STATUS_TMP_CROSSUP)
//         && smatrix[ARRAYINDEX_M5][ARRAYINDEX_MACDH] == STATUS_CROSS_UP
//         && smatrix[ARRAYINDEX_M30][ARRAYINDEX_MACD2C] == STATUS_MACD2C_ABOVE_YL
//         && (smatrix[ARRAYINDEX_H1][ARRAYINDEX_MACDH] == STATUS_KEEP_UP || smatrix[ARRAYINDEX_H1][ARRAYINDEX_MACDH] == STATUS_CROSS_UP
//         || smatrix[ARRAYINDEX_H1][ARRAYINDEX_MACDH] ==STATUS_TMP_CROSSUP)
//         && (smatrix[ARRAYINDEX_H4][ARRAYINDEX_MACDH] == STATUS_KEEP_UP || smatrix[ARRAYINDEX_H4][ARRAYINDEX_MACDH] == STATUS_CROSS_UP
//         || smatrix[ARRAYINDEX_H4][ARRAYINDEX_MACDH] ==STATUS_TMP_CROSSUP))
//         {
//            result = ORDER_OPEN_BUY; 
//            OutputDebug(StringConcatenate("Order decision: ORDER_OPEN_BUY. Condition 5 MACD_Histogram M5 cross re-enter."));
//         }
         
//      if ((smatrix[ARRAYINDEX_M15][ARRAYINDEX_EMA] == STATUS_KEEP_DOWN || smatrix[ARRAYINDEX_M15][ARRAYINDEX_EMA] == STATUS_CLOSE_UP)
//         && (smatrix[ARRAYINDEX_M15][ARRAYINDEX_MACDH] == STATUS_KEEP_DOWN || smatrix[ARRAYINDEX_M15][ARRAYINDEX_MACDH] == STATUS_CLOSE_UP)
//         && (smatrix[ARRAYINDEX_M30][ARRAYINDEX_MACDH] == STATUS_KEEP_DOWN || smatrix[ARRAYINDEX_M30][ARRAYINDEX_MACDH] == STATUS_CLOSE_UP)
//         && (smatrix[ARRAYINDEX_M5][ARRAYINDEX_EMA] == STATUS_KEEP_DOWN || smatrix[ARRAYINDEX_M5][ARRAYINDEX_EMA] == STATUS_CROSS_DOWN
//         || smatrix[ARRAYINDEX_M5][ARRAYINDEX_EMA] == STATUS_TMP_CROSSDOWN)
//         && smatrix[ARRAYINDEX_M5][ARRAYINDEX_MACDH] == STATUS_CROSS_DOWN
//         && smatrix[ARRAYINDEX_M30][ARRAYINDEX_MACD2C] == STATUS_MACD2C_BELOW_YL
//         && (smatrix[ARRAYINDEX_H1][ARRAYINDEX_MACDH] == STATUS_KEEP_DOWN || smatrix[ARRAYINDEX_H1][ARRAYINDEX_MACDH] == STATUS_CROSS_DOWN
//         || smatrix[ARRAYINDEX_H1][ARRAYINDEX_MACDH] ==STATUS_TMP_CROSSDOWN)
//         && (smatrix[ARRAYINDEX_H4][ARRAYINDEX_MACDH] == STATUS_KEEP_DOWN || smatrix[ARRAYINDEX_H4][ARRAYINDEX_MACDH] == STATUS_CROSS_DOWN
//         || smatrix[ARRAYINDEX_H4][ARRAYINDEX_MACDH] ==STATUS_TMP_CROSSDOWN))
//         {
//            result = ORDER_OPEN_SELL;
//            OutputDebug(StringConcatenate("Order decision: ORDER_OPEN_SELL. Condition 6 MACD_Histogram M5 cross re-enter."));
//         } 
         
      if ((smatrix[ARRAYINDEX_M15][ARRAYINDEX_EMA] == STATUS_CROSS_UP || smatrix[ARRAYINDEX_M15][ARRAYINDEX_EMA] == STATUS_TMP_CROSSUP)
         && smatrix[ARRAYINDEX_M15][ARRAYINDEX_MACDH] == STATUS_CROSS_UP         
         && (smatrix[ARRAYINDEX_M30][ARRAYINDEX_EMA] == STATUS_CROSS_UP || smatrix[ARRAYINDEX_M30][ARRAYINDEX_EMA] == STATUS_TMP_CROSSUP)
         && (smatrix[ARRAYINDEX_M30][ARRAYINDEX_MACDH] == STATUS_CROSS_UP || smatrix[ARRAYINDEX_M30][ARRAYINDEX_MACDH] == STATUS_KEEP_UP)
         && (smatrix[ARRAYINDEX_H1][ARRAYINDEX_EMA] == STATUS_CROSS_UP || smatrix[ARRAYINDEX_H1][ARRAYINDEX_EMA] == STATUS_TMP_CROSSUP)
         && (smatrix[ARRAYINDEX_H1][ARRAYINDEX_MACDH] == STATUS_CROSS_UP || smatrix[ARRAYINDEX_H1][ARRAYINDEX_MACDH] == STATUS_KEEP_UP))
         {
            result = ORDER_OPEN_BUY;
            OutputDebug(StringConcatenate("Order decision: ORDER_OPEN_BUY. Condition 7 MACD_Histogram H1, M30, M15 cross up at the same time."));
         }
         
      if ((smatrix[ARRAYINDEX_M15][ARRAYINDEX_EMA] == STATUS_CROSS_DOWN || smatrix[ARRAYINDEX_M15][ARRAYINDEX_EMA] == STATUS_TMP_CROSSDOWN)
         && smatrix[ARRAYINDEX_M15][ARRAYINDEX_MACDH] == STATUS_CROSS_DOWN         
         && (smatrix[ARRAYINDEX_M30][ARRAYINDEX_EMA] == STATUS_CROSS_DOWN || smatrix[ARRAYINDEX_M30][ARRAYINDEX_EMA] == STATUS_TMP_CROSSDOWN)
         && (smatrix[ARRAYINDEX_M30][ARRAYINDEX_MACDH] == STATUS_CROSS_DOWN || smatrix[ARRAYINDEX_M30][ARRAYINDEX_MACDH] == STATUS_KEEP_DOWN)
         && (smatrix[ARRAYINDEX_H1][ARRAYINDEX_EMA] == STATUS_CROSS_DOWN || smatrix[ARRAYINDEX_H1][ARRAYINDEX_EMA] == STATUS_TMP_CROSSDOWN)
         && (smatrix[ARRAYINDEX_H1][ARRAYINDEX_MACDH] == STATUS_CROSS_DOWN || smatrix[ARRAYINDEX_H1][ARRAYINDEX_MACDH] == STATUS_KEEP_DOWN))
         {
            result = ORDER_OPEN_SELL;
            OutputDebug(StringConcatenate("Order decision: ORDER_OPEN_SELL. Condition 8 MACD_Histogram H1, M30, M15 cross down at the same time."));
         }   
         
      if ((smatrix[ARRAYINDEX_M30][ARRAYINDEX_EMA] == STATUS_CROSS_UP || smatrix[ARRAYINDEX_M30][ARRAYINDEX_EMA] == STATUS_KEEP_UP)
         && (smatrix[ARRAYINDEX_M30][ARRAYINDEX_MACDH] == STATUS_CROSS_UP || smatrix[ARRAYINDEX_M30][ARRAYINDEX_MACDH] == STATUS_KEEP_UP)       
         && (smatrix[ARRAYINDEX_H1][ARRAYINDEX_EMA] == STATUS_CROSS_UP || smatrix[ARRAYINDEX_H1][ARRAYINDEX_EMA] == STATUS_TMP_CROSSUP)
         && (smatrix[ARRAYINDEX_H1][ARRAYINDEX_MACDH] == STATUS_CROSS_UP || smatrix[ARRAYINDEX_H1][ARRAYINDEX_MACDH] == STATUS_TMP_CROSSUP)
         && (smatrix[ARRAYINDEX_H4][ARRAYINDEX_EMA] == STATUS_KEEP_UP || smatrix[ARRAYINDEX_H4][ARRAYINDEX_EMA] == STATUS_CLOSE_UP)
         && (smatrix[ARRAYINDEX_H4][ARRAYINDEX_MACDH] == STATUS_KEEP_UP || smatrix[ARRAYINDEX_H4][ARRAYINDEX_MACDH] == STATUS_REVER_UP))
         {
            result = ORDER_OPEN_BUY;
            OutputDebug(StringConcatenate("Order decision: ORDER_OPEN_BUY. Condition 9 sudden charge in H4 continue up."));
         }
 
      if ((smatrix[ARRAYINDEX_M30][ARRAYINDEX_EMA] == STATUS_CROSS_DOWN || smatrix[ARRAYINDEX_M30][ARRAYINDEX_EMA] == STATUS_KEEP_DOWN)
         && (smatrix[ARRAYINDEX_M30][ARRAYINDEX_MACDH] == STATUS_CROSS_DOWN || smatrix[ARRAYINDEX_M30][ARRAYINDEX_MACDH] == STATUS_KEEP_DOWN)       
         && (smatrix[ARRAYINDEX_H1][ARRAYINDEX_EMA] == STATUS_CROSS_DOWN || smatrix[ARRAYINDEX_H1][ARRAYINDEX_EMA] == STATUS_TMP_CROSSDOWN)
         && (smatrix[ARRAYINDEX_H1][ARRAYINDEX_MACDH] == STATUS_CROSS_DOWN || smatrix[ARRAYINDEX_H1][ARRAYINDEX_MACDH] == STATUS_TMP_CROSSDOWN)
         && (smatrix[ARRAYINDEX_H4][ARRAYINDEX_EMA] == STATUS_KEEP_DOWN || smatrix[ARRAYINDEX_H4][ARRAYINDEX_EMA] == STATUS_CLOSE_DOWN)
         && (smatrix[ARRAYINDEX_H4][ARRAYINDEX_MACDH] == STATUS_KEEP_DOWN || smatrix[ARRAYINDEX_H4][ARRAYINDEX_MACDH] == STATUS_REVER_DOWN))
         {
            result = ORDER_OPEN_SELL;
            OutputDebug(StringConcatenate("Order decision: ORDER_OPEN_SELL. Condition 10 sudden charge in H4 continue down."));
         }

      if (smatrix[ARRAYINDEX_M30][ARRAYINDEX_EMA] == STATUS_KEEP_UP
         && smatrix[ARRAYINDEX_M30][ARRAYINDEX_MACDH] == STATUS_CROSS_UP       
         && smatrix[ARRAYINDEX_H1][ARRAYINDEX_EMA] == STATUS_KEEP_UP
         && smatrix[ARRAYINDEX_H1][ARRAYINDEX_MACDH] == STATUS_KEEP_UP
         && (smatrix[ARRAYINDEX_H4][ARRAYINDEX_EMA] == STATUS_KEEP_UP || smatrix[ARRAYINDEX_H4][ARRAYINDEX_EMA] == STATUS_CROSS_UP)
         && (smatrix[ARRAYINDEX_H4][ARRAYINDEX_MACDH] == STATUS_KEEP_UP || smatrix[ARRAYINDEX_H4][ARRAYINDEX_MACDH] == STATUS_CROSS_UP))
         {
            result = ORDER_OPEN_BUY;
            OutputDebug(StringConcatenate("Order decision: ORDER_OPEN_BUY. Condition 11 M30 EMA open MACD cross up."));
         }
         
      if (smatrix[ARRAYINDEX_M30][ARRAYINDEX_EMA] == STATUS_KEEP_DOWN
         && smatrix[ARRAYINDEX_M30][ARRAYINDEX_MACDH] == STATUS_CROSS_DOWN       
         && smatrix[ARRAYINDEX_H1][ARRAYINDEX_EMA] == STATUS_KEEP_DOWN
         && smatrix[ARRAYINDEX_H1][ARRAYINDEX_MACDH] == STATUS_KEEP_DOWN
         && (smatrix[ARRAYINDEX_H4][ARRAYINDEX_EMA] == STATUS_KEEP_DOWN || smatrix[ARRAYINDEX_H4][ARRAYINDEX_EMA] == STATUS_CROSS_DOWN)
         && (smatrix[ARRAYINDEX_H4][ARRAYINDEX_MACDH] == STATUS_KEEP_DOWN || smatrix[ARRAYINDEX_H4][ARRAYINDEX_MACDH] == STATUS_CROSS_DOWN))         
         {
            result = ORDER_OPEN_SELL;
            OutputDebug(StringConcatenate("Order decision: ORDER_OPEN_SELL. Condition 12 M30 EMA open MACD cross down."));
         }
         
      if (smatrix[ARRAYINDEX_M30][ARRAYINDEX_EMA] == STATUS_CROSS_UP
         && (smatrix[ARRAYINDEX_M30][ARRAYINDEX_MACDH] == STATUS_KEEP_UP || smatrix[ARRAYINDEX_M30][ARRAYINDEX_MACDH] == STATUS_CROSS_UP)
         && (smatrix[ARRAYINDEX_M30][ARRAYINDEX_MACD2C] == STATUS_MACD2C_ABOVE_YL || smatrix[ARRAYINDEX_M30][ARRAYINDEX_MACD2C] == STATUS_MACD2C_ABOVE_YL_CLOSE
         || smatrix[ARRAYINDEX_M30][ARRAYINDEX_MACD2C_G] == GRADIENT_RED_UP || smatrix[ARRAYINDEX_M30][ARRAYINDEX_MACD2C_G] == GRADIENT_RED_REVERT_UP)
         && (smatrix[ARRAYINDEX_H1][ARRAYINDEX_MACDH] == STATUS_KEEP_UP || smatrix[ARRAYINDEX_H1][ARRAYINDEX_MACDH] == STATUS_CROSS_UP
         || smatrix[ARRAYINDEX_H1][ARRAYINDEX_MACDH] ==STATUS_TMP_CROSSUP || smatrix[ARRAYINDEX_H1][ARRAYINDEX_MACDH] == STATUS_CLOSE_UP)
         && (smatrix[ARRAYINDEX_H4][ARRAYINDEX_MACDH] == STATUS_KEEP_UP || smatrix[ARRAYINDEX_H4][ARRAYINDEX_MACDH] == STATUS_CROSS_UP 
         || smatrix[ARRAYINDEX_H4][ARRAYINDEX_MACDH] ==STATUS_TMP_CROSSUP || smatrix[ARRAYINDEX_H4][ARRAYINDEX_MACDH] == STATUS_CLOSE_UP))
         {
            result = ORDER_OPEN_BUY; 
            OutputDebug(StringConcatenate("Order decision: ORDER_OPEN_BUY. Condition 13 M30 EMA cross up enter."));
         }

      if (smatrix[ARRAYINDEX_M30][ARRAYINDEX_EMA] == STATUS_CROSS_DOWN
         && (smatrix[ARRAYINDEX_M30][ARRAYINDEX_MACDH] == STATUS_KEEP_DOWN || smatrix[ARRAYINDEX_M30][ARRAYINDEX_MACDH] == STATUS_CROSS_DOWN)
         && (smatrix[ARRAYINDEX_M30][ARRAYINDEX_MACD2C] == STATUS_MACD2C_BELOW_YL || smatrix[ARRAYINDEX_M30][ARRAYINDEX_MACD2C] == STATUS_MACD2C_BELOW_YL_CLOSE
         || smatrix[ARRAYINDEX_M30][ARRAYINDEX_MACD2C_G] == GRADIENT_GREEN_DOWN || smatrix[ARRAYINDEX_M30][ARRAYINDEX_MACD2C_G] == GRADIENT_GREEN_REVERT_DOWN)
         && (smatrix[ARRAYINDEX_H1][ARRAYINDEX_MACDH] == STATUS_KEEP_DOWN || smatrix[ARRAYINDEX_H1][ARRAYINDEX_MACDH] == STATUS_CROSS_DOWN
         || smatrix[ARRAYINDEX_H1][ARRAYINDEX_MACDH] ==STATUS_TMP_CROSSDOWN || smatrix[ARRAYINDEX_H1][ARRAYINDEX_MACDH] == STATUS_CLOSE_DOWN)
         && (smatrix[ARRAYINDEX_H4][ARRAYINDEX_MACDH] == STATUS_KEEP_DOWN || smatrix[ARRAYINDEX_H4][ARRAYINDEX_MACDH] == STATUS_CROSS_DOWN 
         || smatrix[ARRAYINDEX_H4][ARRAYINDEX_MACDH] ==STATUS_TMP_CROSSDOWN || smatrix[ARRAYINDEX_H4][ARRAYINDEX_MACDH] == STATUS_CLOSE_DOWN))        
         {
            result = ORDER_OPEN_SELL;
            OutputDebug(StringConcatenate("Order decision: ORDER_OPEN_SELL. Condition 14 M30 EMA cross down enter."));
         }

      if (smatrix[ARRAYINDEX_H1][ARRAYINDEX_EMA] == STATUS_CROSS_UP
         && (smatrix[ARRAYINDEX_H1][ARRAYINDEX_MACDH] == STATUS_KEEP_UP || smatrix[ARRAYINDEX_H1][ARRAYINDEX_MACDH] == STATUS_CROSS_UP)
         && (smatrix[ARRAYINDEX_H1][ARRAYINDEX_MACD2C] == STATUS_MACD2C_ABOVE_YL || smatrix[ARRAYINDEX_H1][ARRAYINDEX_MACD2C] == STATUS_MACD2C_ABOVE_YL_CLOSE
         || smatrix[ARRAYINDEX_H1][ARRAYINDEX_MACD2C_G] == GRADIENT_RED_UP || smatrix[ARRAYINDEX_H1][ARRAYINDEX_MACD2C_G] == GRADIENT_RED_REVERT_UP)
         && (smatrix[ARRAYINDEX_H4][ARRAYINDEX_MACDH] == STATUS_KEEP_UP || smatrix[ARRAYINDEX_H4][ARRAYINDEX_MACDH] == STATUS_CROSS_UP
         || smatrix[ARRAYINDEX_H4][ARRAYINDEX_MACDH] ==STATUS_TMP_CROSSUP || smatrix[ARRAYINDEX_H4][ARRAYINDEX_MACDH] == STATUS_CLOSE_UP))
         {
            result = ORDER_OPEN_BUY; 
            OutputDebug(StringConcatenate("Order decision: ORDER_OPEN_BUY. Condition 15 H1 EMA cross up enter."));
         }

      if (smatrix[ARRAYINDEX_H1][ARRAYINDEX_EMA] == STATUS_CROSS_DOWN
         && (smatrix[ARRAYINDEX_H1][ARRAYINDEX_MACDH] == STATUS_KEEP_DOWN || smatrix[ARRAYINDEX_H1][ARRAYINDEX_MACDH] == STATUS_CROSS_DOWN)
         && (smatrix[ARRAYINDEX_H1][ARRAYINDEX_MACD2C] == STATUS_MACD2C_BELOW_YL || smatrix[ARRAYINDEX_H1][ARRAYINDEX_MACD2C] == STATUS_MACD2C_BELOW_YL_CLOSE
         || smatrix[ARRAYINDEX_H1][ARRAYINDEX_MACD2C_G] == GRADIENT_GREEN_DOWN || smatrix[ARRAYINDEX_H1][ARRAYINDEX_MACD2C_G] == GRADIENT_GREEN_REVERT_DOWN)
         && (smatrix[ARRAYINDEX_H4][ARRAYINDEX_MACDH] == STATUS_KEEP_DOWN || smatrix[ARRAYINDEX_H4][ARRAYINDEX_MACDH] == STATUS_CROSS_DOWN
         || smatrix[ARRAYINDEX_H4][ARRAYINDEX_MACDH] ==STATUS_TMP_CROSSDOWN || smatrix[ARRAYINDEX_H4][ARRAYINDEX_MACDH] == STATUS_CLOSE_DOWN))        
         {
            result = ORDER_OPEN_SELL;
            OutputDebug(StringConcatenate("Order decision: ORDER_OPEN_SELL. Condition 16 H1 EMA cross down enter."));
         }
         
         
      if (smatrix[ARRAYINDEX_H1][ARRAYINDEX_EMA] == STATUS_KEEP_UP
         && smatrix[ARRAYINDEX_H1][ARRAYINDEX_MACDH] == STATUS_CROSS_UP       
         && (smatrix[ARRAYINDEX_H4][ARRAYINDEX_MACDH] == STATUS_KEEP_UP || smatrix[ARRAYINDEX_H4][ARRAYINDEX_MACDH] == STATUS_CROSS_UP
         || smatrix[ARRAYINDEX_H4][ARRAYINDEX_MACDH] == STATUS_TMP_CROSSUP || smatrix[ARRAYINDEX_H4][ARRAYINDEX_MACDH] == STATUS_CLOSE_UP))
         {
            result = ORDER_OPEN_BUY;
            OutputDebug(StringConcatenate("Order decision: ORDER_OPEN_BUY. Condition 17 H1 EMA open MACD cross up."));
         }
         
      if (smatrix[ARRAYINDEX_H1][ARRAYINDEX_EMA] == STATUS_KEEP_DOWN
         && smatrix[ARRAYINDEX_H1][ARRAYINDEX_MACDH] == STATUS_CROSS_DOWN       
         && (smatrix[ARRAYINDEX_H4][ARRAYINDEX_MACDH] == STATUS_KEEP_DOWN || smatrix[ARRAYINDEX_H4][ARRAYINDEX_MACDH] == STATUS_CROSS_DOWN
         || smatrix[ARRAYINDEX_H4][ARRAYINDEX_MACDH] == STATUS_TMP_CROSSDOWN || smatrix[ARRAYINDEX_H4][ARRAYINDEX_MACDH] == STATUS_CLOSE_DOWN))         
         {
            result = ORDER_OPEN_SELL;
            OutputDebug(StringConcatenate("Order decision: ORDER_OPEN_SELL. Condition 18 H1 EMA open MACD cross down."));
         }
                  
      if (result == ORDER_OPEN_BUY || result == ORDER_OPEN_SELL)
      {
         if (smatrix[ARRAYINDEX_H4][ARRAYINDEX_ADX] == STATUS_CROSS_UP)
         {
            TakeProfit = 500;
         }
         if (smatrix[ARRAYINDEX_H4][ARRAYINDEX_ADX] == STATUS_CROSS_DOWN)
         {
            TakeProfit = 300;
         }
         if (smatrix[ARRAYINDEX_H4][ARRAYINDEX_ADX] == STATUS_UNKNOWN)
         {
            TakeProfit = 100;
         }
      }        
   }
   else if(ordertotal == 1)
   {
      if ((g_ticketopenedbuy == true && smatrix[ARRAYINDEX_M30][ARRAYINDEX_MACDH] == STATUS_TMP_CROSSDOWN)
         || (g_ticketopenedsell == true && smatrix[ARRAYINDEX_M30][ARRAYINDEX_MACDH] == STATUS_TMP_CROSSUP))
      {
         result = ORDER_CLOSE;
         OutputDebug(StringConcatenate("Order decision: Close. Failed on M30 MACDH cross back close condition."));
      }    
      else
         result = ORDER_KEEP;

      //only use for debug
      if (StopLoss != 0)
      {
         if ((g_Tip == OP_BUY && (Ask <= g_SL))
            || (g_Tip == OP_SELL && (Bid >= g_SL)))
         {
            result = ORDER_CLOSE_SL;  
            //OutputDebug
            Print(StringConcatenate("Hit stop loss: ", g_SL, " going to close this order.")); 
         } 
         
         if (g_Tip == OP_BUY)
         {
            profit = Ask - g_Price;
            if (profit > g_profit)
               g_profit = profit;
            
            if (g_profit > 150*Point)            
               g_SL = g_Price + 10*Point; 
               
            if (g_profit > 300*Point)
               g_SL = g_Price + 150*Point;  

            if (g_profit > 400*Point)
               g_SL = g_Price + 300*Point;            
//            if (g_profit > 500*Point)
//               g_SL = g_Price + 300*Point;           
         }
         
         if (g_Tip == OP_SELL)
         {
            profit = g_Price - Bid;
            if (profit > g_profit)
               g_profit = profit;
            
            if (g_profit > 150*Point)            
               g_SL = g_Price - 10*Point; 
               
            if (g_profit > 300*Point)
               g_SL = g_Price - 150*Point;  

            if (g_profit > 400*Point)
               g_SL = g_Price + 250*Point;
         }  
      }      
      
      if (TakeProfit != 0)
      {
         if ((g_Tip == OP_BUY && (Ask >= g_TP))
            || (g_Tip == OP_SELL && (Bid <= g_TP)))
         {
            result = ORDER_CLOSE_TP;            
            //OutputDebug
            Print(StringConcatenate("Hit take profit, going to close this order.")); 
         }
      }      
   }
   
   return err;
}

bool WriteToCSV(int type, int operation)
{
   int iHandle = INVALID_HANDLE;
   int iErrorCode = ERR_NO_ERROR;
   string terminal_data_path = TerminalInfoString(TERMINAL_DATA_PATH);
   string logfilename = StringConcatenate("tradelog_", Year(), "_", Month(), "_", Day(), ".csv");
   string filename = terminal_data_path + "\\MQL4\\Files\\" + logfilename;   

//   if (!FileIsExist(logfilepath, FILE_CSV))
//   {
//      Print("Error: File ", logfilepath, "does not exist.");
//     return false;
//   }
      
   iHandle = FileOpen(logfilename, FILE_CSV|FILE_READ|FILE_WRITE, ',');
   if (iHandle < 1)
   {
      iErrorCode = GetLastError();
      Print("Error updating file: ", iErrorCode);
      return false;
   }
   
   if (type == OP_BUY)
   {
      if (operation == ORDER_OPEN_BUY)
      {   
         if (FileWrite(iHandle, TimeToString(g_time, TIME_DATE|TIME_SECONDS), 
               "Buy", DoubleToString(g_Lts), Symbol(), DoubleToString(g_Price), DoubleToString(g_SL), "Open") == 0)
         {
            Print("Error: File ", filename, " write error.");
            FileClose(iHandle);
            return false;
         }
      }
      else if(operation == ORDER_CLOSE || operation == ORDER_CLOSE_SL || operation == ORDER_CLOSE_TP)
      {
         if (FileWrite(iHandle, TimeToString(g_time, TIME_DATE|TIME_SECONDS), 
               "Buy", DoubleToString(g_Lts), Symbol(), DoubleToString(Ask), DoubleToString(g_SL), "Close") == 0)
         {
            Print("Error: File ", filename, " write error.");
            FileClose(iHandle);
            return false;
         }               
      }
   }
   else if (type == OP_SELL)
   {
      if (operation == ORDER_OPEN_SELL)
      {   
         if (FileWrite(iHandle, TimeToString(g_time, TIME_DATE|TIME_SECONDS), 
               "Sell", DoubleToString(g_Lts), Symbol(), DoubleToString(g_Price), DoubleToString(g_SL), "Open") == 0)
         {
            Print("Error: File ", filename, " write error.");
            FileClose(iHandle);
            return false;
         }
      }
      else if(operation == ORDER_CLOSE || operation == ORDER_CLOSE_SL || operation == ORDER_CLOSE_TP)
      {
         if (FileWrite(iHandle, TimeToString(g_time, TIME_DATE|TIME_SECONDS), 
               "Sell", DoubleToString(g_Lts), Symbol(), DoubleToString(Bid), DoubleToString(g_SL), "Close") == 0)
         {
            Print("Error: File ", filename, " write error.");
            FileClose(iHandle);
            return false;
         }               
      }
   }
   FileClose(iHandle);
   return true;
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
	
	double M30lopen = iOpen(Symb, PERIOD_M30, SHIFT_LAST_ONE);
	double M30lclose = iClose(Symb, PERIOD_M30, SHIFT_LAST_ONE);
	double M30lhigh = iHigh(Symb, PERIOD_M30, SHIFT_LAST_ONE);
	double M30llow = iLow(Symb, PERIOD_M30, SHIFT_LAST_ONE);
	
	bool Ans = false;                     // Server response after closing   
	int err = ERR_NO_ERROR;
	int ordertotal = 0;
	int result = ORDER_NO;
	int status_matrix[STATUS_OBJARR_SIZE][INDICATOR_COUNT] = {0}; //record all the status of the trade windows and indicators	
	string subject = "Test EA order operation notification";
//	int cci_status = STATUS_CCI_LONG;
	
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
	
//	if (SelectOrder(Symb, ordertotal) == true)
//   {
//      if (ordertotal > 1)
//         return ERROR_MULTORDER;
//   }   
   
//   Ticket = OrderTicket();
//   Lot = OrderLots();
//   Tip = OrderType();

	//--------------------------------------------------------------- 5 --   // Trading criteria    
   CStatusH4 sh4(Symb);
   CStatusH1 sh1(Symb);
   CStatusM30 sm30(Symb);
   CStatusM15 sm15(Symb);
   CStatusM5 sm5(Symb);
//   CStatusM3 sm3(Symb);
	  
   g_pstatus[ARRAYINDEX_H4] = &sh4;
   g_pstatus[ARRAYINDEX_H1] = &sh1;
   g_pstatus[ARRAYINDEX_M30] = &sm30;
   g_pstatus[ARRAYINDEX_M15] = &sm15;
   g_pstatus[ARRAYINDEX_M5] = &sm5;
//   g_pstatus[ARRAYINDEX_M3] = &sm3; 

   err = Decide(status_matrix, Symb, g_ordertotal, result);
   if (err != ERR_NO_ERROR)
   {
      Print("Critical error ", err, ". EA doesn't work.");
      return err;
   }
//   err = CheckCCIM5(cci_status);
//   if (err != ERR_NO_ERROR)
//   {
//      Print("Critical error ", err, ". EA doesn't work.");
//      return err;
//   }

	//--------------------------------------------------------------- 6 --   // Closing orders   
	while(true)                                  // Loop of closing orders     
	{  
		if ((result == ORDER_CLOSE || result == ORDER_CLOSE_SL || result == ORDER_CLOSE_TP)
		   && g_ticketopenedbuy == true)//Tip == OP_BUY)                // Order Buy is opened..        
		{                                       // and there is criterion to close         
			Print("Attempt to close Buy ", Ticket,". Waiting for response..");         
			RefreshRates();                        // Refresh rates         
//			Ans=OrderClose(Ticket,Lot,Bid,2);      // Closing Buy         
//			if (Ans==true)                         // Success :) 
        
			g_time = TimeCurrent(); 
			{
			   string tmpstr = StringConcatenate("Closed order Buy at ", g_time, ", price ", Ask, ", lots ", g_Lts);            
				Print (tmpstr); //Ticket); 
//				SendMail(subject, tmpstr);  
//				WriteToCSV(OP_BUY, ORDER_CLOSE);
				g_ticketopenedbuy = false;
				g_ordertotal = 0;
				g_profit = 0;
				
            //Order closed in the same M30 candle, not good, suppress coming orders until this candle closes.
      	   if ((g_M30lopen != 0 || g_M30lclose != 0 || g_M30lhigh != 0 || g_M30llow != 0) && result == ORDER_CLOSE_SL)
      	   {
      	      if (g_M30lopen == M30lopen && g_M30lclose == M30lclose && g_M30lhigh == M30lhigh && g_M30llow == M30llow)
      	      {
      	         g_bM30Suppression = true;
      	         OutputDebug(StringConcatenate("Order closed in the same M30 candle, set suppression flag."));
      	      }
      	   }	
				
            for (int k = 0; k < 5; k++)
            {
               PlaySound("expert"); 
               Sleep(1000);
            } 
//				Print("Closed at ", Bid);   //OrderClosePrice();   
				break;                              // Exit closing loop           
			}   

			if (Fun_Error(GetLastError())==1)      // Processing errors            
				continue;                           // Retrying         
			return 0;                                // Exit start()        
		}       
			
		if ((result == ORDER_CLOSE || result == ORDER_CLOSE_SL || result == ORDER_CLOSE_TP)
		   && g_ticketopenedsell == true)//Tip == OP_SELL)                // Order Sell is opened..        
		{                                       // and there is criterion to close         
			Print("Attempt to close Sell ",Ticket,". Waiting for response..");        
			RefreshRates();                        // Refresh rates        
//			Ans=OrderClose(Ticket,Lot,Ask,2);      // Closing Sell         
//			if (Ans==true)                         // Success :)   

         g_time = TimeCurrent();     
			{  
			   string tmpstr = StringConcatenate("Closed order Sell at ", g_time, ", price ", Bid, ", lots ", g_Lts); 
			   Print(tmpstr);  //Ticket);  
//			   SendMail(subject, tmpstr);
//			   WriteToCSV(OP_SELL, ORDER_CLOSE);  
			   g_ticketopenedsell = false;    
			   g_ordertotal = 0;
			   g_profit = 0;
			   
            //Order closed in the same M30 candle, not good, suppress coming orders until this candle closes.
      	   if ((g_M30lopen != 0 || g_M30lclose != 0 || g_M30lhigh != 0 || g_M30llow != 0) && result == ORDER_CLOSE_SL)
      	   {
      	      if (g_M30lopen == M30lopen && g_M30lclose == M30lclose && g_M30lhigh == M30lhigh && g_M30llow == M30llow)
      	      {
      	         g_bM30Suppression = true;
      	         OutputDebug(StringConcatenate("Order closed in the same M30 candle, set suppression flag."));
      	      }
      	   }			   
			   
            for (int k = 0; k < 5; k++)
            {
               PlaySound("expert"); 
               Sleep(1000);
            }  
//				Print("Closed at ", Ask);         //OrderClosePrice(); 
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
//		if (ordertotal == 0 && result == ORDER_OPEN_BUY)              // No new orders +      
      if (g_ticketopenedbuy == false && result == ORDER_OPEN_BUY)
		{                                       // criterion for opening Buy 
         //check whether enter again in the same M30 candle right after last order closed.
   	   if (g_M30lopen != 0 || g_M30lclose != 0 || g_M30lhigh != 0 || g_M30llow != 0) 
   	   {
   	      if (g_M30lopen == M30lopen && g_M30lclose == M30lclose && g_M30lhigh == M30lhigh && g_M30llow == M30llow 
   	         && g_bM30Suppression == true)
   	      {
   	         OutputDebug(StringConcatenate("Suppression happened, block open order in the same candle right after last order is closed."));
   	         return 0;
   	      }
   	      else
   	         g_bM30Suppression = false;
   	   }
	   
			RefreshRates();                        // Refresh rates       
			SL = Ask - New_Stop(StopLoss)*Point;     // Calculating SL of opened
//			if (cci_status == STATUS_CCI_SHORT)
//			{
//			   TakeProfit = 500.0;
//			   OutputDebug(StringConcatenate("CCI under 100, set take profit to 5 pips."));
//			}
//			else
//			{
//			   TakeProfit = 0.0;
//			   OutputDebug(StringConcatenate("CCI above or equal 100, set no take profit."));
//			}
         TP = Ask + TakeProfit*Point;   // Calculating TP of opened       
			Print("Attempt to open Buy. Waiting for response.. TP ", TP, " Point ", Point);       
//			Ticket=OrderSend(Symb,OP_BUY,Lts, Ask,2,SL,TP);//Opening Buy
       
         g_TP = TP;
         g_SL = SL;
         g_Price = Ask;
         g_Lts = Lts;
         g_Tip = OP_BUY;
         g_time = TimeCurrent();
//			if (Ticket > 0)                        // Success :) 
			{
			string tmpstr = StringConcatenate("Opened order Buy at ", g_time, ", price ", Ask, ", stop lost ", g_SL, ", lots ", g_Lts);
			Print(tmpstr);   //Ticket);
//			SendMail(subject, tmpstr);
//			WriteToCSV(OP_BUY, ORDER_OPEN_BUY); 
			g_ticketopenedbuy = true;
			g_ordertotal = 1;
			
			g_M30lopen = M30lopen;
			g_M30lclose = M30lclose;
			g_M30lhigh = M30lhigh;
			g_M30llow = M30llow;
			
         for (int k = 0; k < 5; k++)
         {
            PlaySound("news"); 
            Sleep(1000);
         }
//				Print("Opened at ", Ask);           //OrderOpenPrice();
				return 0;                             // Exit start()
			}
			if (Fun_Error(GetLastError())==1)      // Processing errors
				continue;                           // Retrying
			return 0;                                // Exit start()
		}   

//		if (ordertotal == 0 && result == ORDER_OPEN_SELL)              // No opened orders +
		if (g_ticketopenedsell == false && result == ORDER_OPEN_SELL)
		{
         //check whether enter again in the same M30 candle right after last order closed.
   	   if (g_M30lopen != 0 || g_M30lclose != 0 || g_M30lhigh != 0 || g_M30llow != 0) 
   	   {
   	      if (g_M30lopen == M30lopen && g_M30lclose == M30lclose && g_M30lhigh == M30lhigh && g_M30llow == M30llow 
   	         && g_bM30Suppression == true)
   	      {
   	         OutputDebug(StringConcatenate("Suppression happened, block open order in the same candle right after last order is closed."));
   	         return 0;
   	      }
   	      else
   	         g_bM30Suppression = false;
   	   }
   	   		
			// criterion for opening Sell
			RefreshRates();                        // Refresh rates
			SL = Bid + New_Stop(StopLoss)*Point;     // Calculating SL of opened
//         if (cci_status == STATUS_CCI_SHORT)
//         {
//			   TakeProfit = 500.0;
//			   OutputDebug(StringConcatenate("CCI above -100, set take profit to 5 pips."));
//			}
//			else
//			{
//			   TakeProfit = 0.0;  
//			   OutputDebug(StringConcatenate("CCI under or equal -100, set no take profit."));
//			} 
			TP = Bid - TakeProfit*Point;   // Calculating TP of opened
			Print("Attempt to open Sell. Waiting for response.. TP ", TP, " Point ", Point);
//			Ticket=OrderSend(Symb,OP_SELL,Lts,Bid,2,SL,TP);//Opening Sell

         g_TP = TP;
         g_SL = SL;
         g_Price = Bid;
         g_Lts = Lts;
         g_Tip = OP_SELL;
         g_time = TimeCurrent();
//			if (Ticket > 0)                        // Success :)
			{
			string tmpstr = StringConcatenate("Opened order Sell at ", g_time, ", price ", Bid, ", stop lost ", g_SL, ", lots ", g_Lts);
		   Print(tmpstr);
//		   SendMail(subject, tmpstr);
//		   WriteToCSV(OP_SELL, ORDER_OPEN_SELL); 
		   g_ticketopenedsell = true;
		   g_ordertotal = 1;
		   
			g_M30lopen = M30lopen;
			g_M30lclose = M30lclose;
			g_M30lhigh = M30lhigh;
			g_M30llow = M30llow;		   
		   
         for (int k = 0; k < 5; k++)
         {
            PlaySound("news"); 
            Sleep(1000);
         }
//				Print("Opened at ", Bid);           //OrderOpenPrice();
				return 0;                             // Exit start()
			}
			if (Fun_Error(GetLastError())==1)      // Processing errors
				continue;                           // Retrying
			return 0;                                // Exit start()
		}      
		break;                                    // Exit while     
	}//--------------------------------------------------------------- 9 --   
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
			Print("Error occurred: ",Error);  // Other variants    
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
   
   dt = TimeLocal();
   hour = TimeHour(dt);
   min = TimeMinute(dt);
   
   if (TimeDaylightSavings()) //not winter time, EU market start from 2:00pm to 9:30pm, US market start from 9:30pm to 12:00am
   {
      if ((hour >= 14 && hour <= 20) || (hour == 21 && min < 30))
      {
         time_range = TIMERANGE_EU;
      }
      else if ((hour == 21 && min >= 30) || (hour >= 22 && hour < 24))
      {
         time_range = TIMERANGE_US;
      }
      else
         time_range = TIMERANGE_NO;
   }
   else                       //winter time, EU market start from 3:00pm to 10:30pm, US market start from 10:30pm to 12:00am
   {
      if ((hour >= 15 && hour <= 21) || (hour == 22 && min < 30))
      {
         time_range = TIMERANGE_EU;
      }
      else if ((hour == 22 && min >= 30) || (hour >= 23 && hour < 24))
      {
         time_range = TIMERANGE_US;
      }
      else
         time_range = TIMERANGE_NO;
   }
   
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
      ChartSetSymbolPeriod(0, "XAUUSD", PERIOD_M5);       
      err = GetLastError();
      if (err != ERR_NO_ERROR)
      {
         Print("Failed to init chart to XAUUSD.");
         return(INIT_FAILED);
      }
   }
   
   string terminal_data_path = TerminalInfoString(TERMINAL_DATA_PATH);
   string logfilename = StringConcatenate("tradelog_", Year(), "_", Month(), "_", Day(), ".txt");
   string filename = terminal_data_path + "\\MQL4\\Files\\" + logfilename; 
   
   iHandle = FileOpen(logfilename, FILE_WRITE, ',');
   if (iHandle < 1)
   {
      err = GetLastError();
      Print("Error updating file: ", err);
      return false;
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
   FileClose(iHandle);
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
//---
//   int time_range = 0;
//   GetTimeRange(time_range);
   
//   if (time_range == TIMERANGE_NO)
//   {
//      return; 
//    }   
//   if (time_range == TIMERANGE_EU)
//      g_bbthreshold = 20;
      
//   if (time_range == TIMERANGE_US)
//      g_bbthreshold = 15;
      
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
