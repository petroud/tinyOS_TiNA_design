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

	components new AMSenderC(AM_REAGGREGATE) as ReaggregateSenderC;
	components new AMReceiverC(AM_REAGGREGATE) as ReaggregateReceiverC;

	components new PacketQueueC(SENDER_QUEUE_SIZE) as RoutingSendQueueC;
	components new PacketQueueC(RECEIVER_QUEUE_SIZE) as RoutingReceiveQueueC;
	
	components new PacketQueueC(SENDER_QUEUE_SIZE) as DistributionSendQueueC;
	components new PacketQueueC(RECEIVER_QUEUE_SIZE) as DistributionReceiveQueueC;

	components new PacketQueueC(SENDER_QUEUE_SIZE) as ReaggregateSendQueueC;
	components new PacketQueueC(RECEIVER_QUEUE_SIZE) as ReaggregateReceiveQueueC;
	
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

	SRTreeC.ReaggregatePacket->ReaggregateSenderC.Packet;
	SRTreeC.ReaggregateAMPacket->ReaggregateSenderC.AMPacket;
	SRTreeC.ReaggregateAMSend->ReaggregateSenderC.AMSend;
	SRTreeC.ReaggregateReceive->ReaggregateReceiverC.Receive;
		
	/*
		Queues
	*/
	SRTreeC.RoutingSendQueue->RoutingSendQueueC;
	SRTreeC.RoutingReceiveQueue->RoutingReceiveQueueC;
	SRTreeC.DistributionSendQueue->DistributionSendQueueC;
	SRTreeC.DistributionReceiveQueue->DistributionReceiveQueueC;
	SRTreeC.ReaggregateSendQueue->ReaggregateSendQueueC;
	SRTreeC.ReaggregateReceiveQueue->ReaggregateReceiveQueueC;
}
