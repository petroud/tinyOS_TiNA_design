#include "SimpleRoutingTree.h"

configuration SRTreeAppC @safe() { }
implementation{
	components SRTreeC;

#if defined(DELUGE) //defined(DELUGE_BASESTATION) || defined(DELUGE_LIGHT_BASESTATION)
	components DelugeC;
#endif

#ifdef PRINTFDBG_MODE
		components PrintfC;
#endif
	components MainC, ActiveMessageC, RandomC, RandomMlcgC;
	components new TimerMilliC() as RoutingMsgTimerC;
	components new TimerMilliC() as RoutingTimerC;
	components new TimerMilliC() as RoundTimerC;
	components new TimerMilliC() as DistributionTimerC;
	
	components new AMSenderC(AM_ROUTINGMSG) as RoutingSenderC;
	components new AMReceiverC(AM_ROUTINGMSG) as RoutingReceiverC;

	components new AMSenderC(AM_DISTR) as DistributionSenderC;
	components new AMReceiverC(AM_DISTR) as DistributionReceiverC;

	components new PacketQueueC(SENDER_QUEUE_SIZE) as RoutingSendQueueC;
	components new PacketQueueC(RECEIVER_QUEUE_SIZE) as RoutingReceiveQueueC;
	
	components new PacketQueueC(SENDER_QUEUE_SIZE) as DistributionSendQueueC;
	components new PacketQueueC(RECEIVER_QUEUE_SIZE) as DistributionReceiveQueueC;
	
	SRTreeC.Boot->MainC.Boot;
	SRTreeC.RadioControl -> ActiveMessageC;

	/*
		Random Components
	*/
	SRTreeC.Random->RandomC;
	SRTreeC.Seed->RandomMlcgC.SeedInit;
	
	/*
		Timers
	*/
	SRTreeC.RoutingMsgTimer->RoutingMsgTimerC;
	SRTreeC.RoutingTimer->RoutingTimerC;
	SRTreeC.RoundTimer->RoundTimerC;
	SRTreeC.DataDistrTimer->DistributionTimerC;

	/*
		Packets, Senders & Receivers
	*/
	SRTreeC.RoutingPacket->RoutingSenderC.Packet;
	SRTreeC.RoutingAMPacket->RoutingSenderC.AMPacket;
	SRTreeC.RoutingAMSend->RoutingSenderC.AMSend;
	SRTreeC.RoutingReceive->RoutingReceiverC.Receive;

	SRTreeC.DistributionPacket->DistributionSenderC.Packet;
	SRTreeC.DistributionAMPacket->DistributionSenderC.AMPacket;
	SRTreeC.DistributionAMSend->DistributionSenderC.AMSend;
	SRTreeC.DistributionReceive->DistributionReceiverC.Receive;
		
	/*
		Queues
	*/
	SRTreeC.RoutingSendQueue->RoutingSendQueueC;
	SRTreeC.RoutingReceiveQueue->RoutingReceiveQueueC;
	SRTreeC.DistributionSendQueue->DistributionSendQueueC;
	SRTreeC.DistributionReceiveQueue->DistributionReceiveQueueC;
	
}
