#ifndef SIMPLEROUTINGTREE_H
#define SIMPLEROUTINGTREE_H

enum{
	SENDER_QUEUE_SIZE=5,
	RECEIVER_QUEUE_SIZE=3,
	AM_SIMPLEROUTINGTREEMSG=22,
	AM_ROUTINGMSG=22,
	AM_DISTR=30,
	SEND_CHECK_MILLIS=70000,
	TIMER_PERIOD_MILLI=30720,
	TIMER_FAST_PERIOD=128,
	//Aggregates flags
	MAX = 0,
	COUNT = 1,
	MAXCOUNT = 2,
};

typedef struct childNode{
	nx_uint8_t nodeID;
	nx_uint8_t maxVal;
	nx_uint8_t countVal;
} childNode;


typedef nx_struct RoutingMsg
{
	nx_uint8_t depth;
	//This variable holds the flag for the selection of the aggregate function and the TCT.
	nx_uint8_t executionParameters;
} RoutingMsg;



typedef nx_struct DistributionMsgFull
{
	nx_uint16_t max; //16 bits are not required but this is the only way to tell messages apart
	nx_uint8_t count;

} DistributionMsgFull;



typedef nx_struct DistributionMsgSemi
{
	nx_uint8_t flag; //Used to mark if COUNT or MAX was sent during double aggregation but signle TiNA transmission
	nx_uint8_t data;

} DistributionMsgSemi;


typedef nx_struct DistributionMsgSingle
{
	nx_uint8_t data;

} DistributionMsgSingle;




typedef nx_struct BufferMsg
{
	nx_uint8_t data8bit;
} BufferMsg;

#endif
