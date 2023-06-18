#include "SimpleRoutingTree.h"

module SRTreeC
{
	uses interface Boot;
	uses interface SplitControl as RadioControl;

	uses interface Random;
	uses interface ParameterInit<uint16_t> as Seed;

	//Used for routing
	uses interface Packet as RoutingPacket;
	uses interface AMSend as RoutingAMSend;
	uses interface AMPacket as RoutingAMPacket;

	//Used for data distribution among nodes
	uses interface Packet as DistributionPacket;
	uses interface AMSend as DistributionAMSend;
	uses interface AMPacket as DistributionAMPacket;
	
	//Timers
	// 1st-> Used for routing
	// 2nd-> Used for detecting routing completion
	// 3rd-> User for calculating and distributing aggregate functions for each node
	uses interface Timer<TMilli> as RoutingMsgTimer;
	uses interface Timer<TMilli> as RoutingTimer;
	uses interface Timer<TMilli> as RoundTimer;
	uses interface Timer<TMilli> as DataDistrTimer;
	
	uses interface Receive as RoutingReceive;
	uses interface Receive as DistributionReceive;
	
	uses interface PacketQueue as RoutingSendQueue;
	uses interface PacketQueue as RoutingReceiveQueue;
	
	uses interface PacketQueue as DistributionSendQueue;
	uses interface PacketQueue as DistributionReceiveQueue;
}


implementation
{
	uint16_t  roundCounter;
	
	message_t radioRoutingSendPkt;
	message_t radioDistributionSendPkt;
	
	bool RoutingSendBusy=FALSE;
	bool DistributionSendBusy=FALSE;

	uint8_t curdepth;
	uint16_t parentID;
	
	// Function to store the aggregate function to be 
	// calculated by flag
	// 0: MAX
	// 1: COUNT
	// 2: MAX & COUNT
	uint8_t aggregateSelection;

	//TCT selection flag
	uint8_t tct;

	//Encoded bitwised
	uint8_t encodedParam;

	//Used for storing the last and current measurement of each node
	uint8_t lastMeasurement;
	uint8_t currMeasurement;

	//Used for storing the last aggregate calculation of the node at each aggregate case
	uint8_t lastAggregate = 0;
	//Used for the case of 2 aggregates to seperate them
	uint8_t lastAggregateMAX = 0;
	uint8_t lastAggregateCOUNT = 0;	

	//Used to store the aggregate measurements received from the children of the current node
	//Lets suppose that a node could have up to 64 children (should be enough)
	childNode children[64];

	//Used for seeding
	uint16_t seed;
	FILE *fp;

	//Routing tasks
	task void sendRoutingTask();
	task void receiveRoutingTask();	

	//Distribution task
	task void sendDistributionTask();
	task void receiveDistributionTask();


    ///////////////////////////////////////////////////////////////////////
	/////////////////////////// Data Methods //////////////////////////////
	///////////////////////////////////////////////////////////////////////

	uint8_t aggregate(uint8_t aggrFlag, uint8_t measurement){

		uint8_t result;

		//Calculate aggregate appropriately respecting the children's values

		if(aggrFlag == MAX){

     		int i;
			result = measurement;
			for(i = 0 ; i < 64 ; i++){
				if(children[i].nodeID !=0){
					dbg("Aggregation","Child Node [%d] MAX = %d\n", children[i].nodeID, children[i].maxVal);
					
					result = result < children[i].maxVal ? children[i].maxVal : result;
				}
			}

		}else if(aggrFlag == COUNT){
			
			int i;
			result = 1;
			for(i = 0 ; i < 64 ; i++){
				if(children[i].nodeID !=0){
					dbg("Aggregation","Child Node [%d] COUNT = %d\n", children[i].nodeID, children[i].countVal);

					result += children[i].countVal;
				}
			}

		}else{
			dbg("Aggregation","aggregate(): Bad Aggregate Flag...Aborting...\n");
			return -1;
		}

		return result;
	}


	/*
		Encodes execution parameters in order to minimize the transmitting message
		and reduce power consumption
	*/
	uint8_t encodeParameters(uint8_t aggr, uint8_t tctArg){

		uint8_t encoded = 0;
		encoded = encoded | aggr;
		encoded = encoded<<2;
		encoded = encoded | tctArg;
		return encoded;

	}

	/*
		Decodes execution parameters from the received message and puts
		the results in the global variables
	*/
	void decodeParameters(uint8_t encoded){

		uint8_t constantValue = 3;
		// Basically perform XX-XX-XX-XX AND 00-00-00-11 to keep
		// the tct flag that is encoded last
		tct = encoded & constantValue;

		//Shift right to remove the tct;
		encoded = encoded>>2;
		//Whats left now in the array is the aggregate flag
		aggregateSelection = encoded;
	}


	void setRoutingSendBusy(bool state)
	{
		atomic{
		RoutingSendBusy=state;
		}
	}

	
	void setDistributionSendBusy(bool state)
	{
		atomic{
		DistributionSendBusy=state;
		}
	}

	/*
		This is the entrypoint
	*/
	event void Boot.booted()
	{
		call RadioControl.start();
		
		setRoutingSendBusy(FALSE);

		roundCounter =0;

		//Allocate seed for generating random numbers based on the node's ID.
		fp = fopen("/dev/urandom", "r");
		fread(&seed, sizeof(seed), 1, fp);
		fclose(fp);
		call Seed.init(seed + TOS_NODE_ID + 1);

		if(TOS_NODE_ID==0)
		{
			curdepth=0;
			parentID=0;

			//Make a decision about the aggregate functions that will be used
			// Mod 3 will produce any number from 0 to 2
			// 0: MAX
			// 1: COUNT
			// 2: MAX & COUNT
			// The selection is made at this point in order not to consume time from routing
			// The selection is made though by Root Node 0 
			aggregateSelection = call Random.rand16()%3;

			//Generate TCT
			// 0: 5%
			// 1: 10%
			// 2: 15%
			// 3: 20%
			tct = (call Random.rand16()%4);

			//Encode message context
			encodedParam = encodeParameters(aggregateSelection, tct);

			dbg("Tina","Selected Aggregate Case: [%d] | Selected TCT Case: [%d] | Encoded bitwise to: [%u]\n", aggregateSelection, tct, encodedParam);
		}
		else
		{
			curdepth=-1;
			parentID=-1;
		}
	}
	
	event void RadioControl.startDone(error_t err)
	{
		if (err == SUCCESS)
		{
			int i;
			for(i=0; i<64;i++){
				children[i].nodeID = 0;
				children[i].maxVal = 0;
				children[i].countVal = 0;
			}
						
			// Allow 5 seconds for routing to be completed
			call RoutingTimer.startOneShot(6400);
			call RoundTimer.startPeriodicAt(0,TIMER_PERIOD_MILLI);


			if (TOS_NODE_ID==0)
			{
				call RoutingMsgTimer.startOneShot(TIMER_FAST_PERIOD);
			}
		}
		else
		{
			dbg("Radio" , "Radio initialization failed! Retrying...\n");

			call RadioControl.start();
		}
	}
	
	event void RadioControl.stopDone(error_t err)
	{ 
		dbg("Radio", "Radio stopped!\n");

	}



	//////////////////////////////////////////////////////////
	////////////////////// Timer events //////////////////////
	////////////////////////////////////////////////////////// 

	event void RoundTimer.fired(){

		roundCounter++;

		if(TOS_NODE_ID==0){
			dbg("Rounds", "############################################\n");
			dbg("Rounds", "                  ROUND   %u                \n", roundCounter);
			dbg("Rounds", "############################################\n");
		}

	}


	/*
		When the timer is fired begin routing
	*/
	event void RoutingMsgTimer.fired()
	{
		message_t tmp;
		error_t enqueueDone;
		
		RoutingMsg* mrpkt;

		roundCounter+=1;

		if (TOS_NODE_ID==0)
		{
			
			dbg("Rounds", "############################################\n");
			dbg("Rounds", "                  ROUND   %u                \n", roundCounter);
			dbg("Rounds", "############################################\n");			
		}
		
		if(call RoutingSendQueue.full())
		{
			dbg("Routing","RoutingSendQueue is FULL!!! \n");
			return;
		}
		
		
		mrpkt = (RoutingMsg*) (call RoutingPacket.getPayload(&tmp, sizeof(RoutingMsg)));
		if(mrpkt==NULL)
		{
			dbg("Routing","RoutingMsgTimer.fired(): No valid payload... \n");
			return;
		}
		atomic{
		mrpkt->depth = curdepth;
		mrpkt->executionParameters = encodeParameters(aggregateSelection,tct);
		}
	
		call RoutingAMPacket.setDestination(&tmp, AM_BROADCAST_ADDR);
		call RoutingPacket.setPayloadLength(&tmp, sizeof(RoutingMsg));
		
		enqueueDone=call RoutingSendQueue.enqueue(tmp);
		
		if( enqueueDone==SUCCESS)
		{
			if (call RoutingSendQueue.size()==1)
			{
				post sendRoutingTask();
			}
			
		}
		else
		{
			dbg("Routing","RoutingMsg failed to be enqueued in SendingQueue!!!");
		}		
	}



	/*
		The RoutingTimer fires when routing is completed (5secs). At that time begging measurement distribution
	*/
	event void RoutingTimer.fired(){

		//Call the Data Distributuion Timer to run periodically for each Node 
		//respecting the curdepth of the Node (Each depth transmits at the same time)
		//In order to prevent collissions among nodes that belong to the same depth 
		//the period for each of them is adjusted to start late 
		//based to their ID multiplied by 3
		call DataDistrTimer.startPeriodicAt( -((curdepth+1)*TIMER_FAST_PERIOD)+(TOS_NODE_ID*4), TIMER_PERIOD_MILLI);
	}



	/* 
		This timer is fired periodically for each Node after the Routing each completed. This fires the measurement 
		distribution among nodes
	*/
	event void DataDistrTimer.fired(){
		message_t tmp;
		error_t enqueueDone;
		DistributionMsgSingle* msg;

		dbg("Distribution","Distribution Timer fired for Node [%d] at depth -%d-\n", TOS_NODE_ID, curdepth);
		
		//Initially the last measurement is set to 0 so we generate the entry point
		//for random measurement generation. When the first measurement is generated 
		//then every next measurement will be randomly selected withing a range of +-10%.

		if(lastMeasurement==0){
			currMeasurement = call Random.rand16()%80+1;
		}else{
			uint8_t upper = (int)lastMeasurement + 0.1*lastMeasurement;
			uint8_t lower = (int)lastMeasurement - 0.1*lastMeasurement;

			currMeasurement = call Random.rand16()%(upper-lower + 1) + lower;
		}

		//Update lastMeasurement var used to calculate the new value upon +-10% deviation rule.
		lastMeasurement = currMeasurement;

		dbg("TinaMeasurements","Node [%d] at depth -%d- measuring now: %d\n", TOS_NODE_ID, curdepth, currMeasurement);

		//Encapsulate data in a buffer message that is only processed locally. The buffer message is 
		//used to prevent data loss in an event of collision.

		if(call DistributionSendQueue.full()){
			dbg("Distribution","Distr Queue Full!!\nAbort...\n");
			return;
		}

		call DistributionAMPacket.setDestination(&tmp, parentID);
		msg = (DistributionMsgSingle*)(call DistributionPacket.getPayload(&tmp, sizeof(DistributionMsgSingle)));
		call DistributionPacket.setPayloadLength(&tmp, sizeof(DistributionMsgSingle));

		if(msg==NULL){
			dbg("Distribution","Payload Error!!\nAbort...\n");
			return;
		}

		msg->data=currMeasurement;
		enqueueDone = call DistributionSendQueue.enqueue(tmp);

		if(enqueueDone == SUCCESS){
			dbg("Distribution","Provisioning distribution chain...\n");
			post sendDistributionTask();
		}
		

	}	


	///////////////////////////////////////////////////////////////////////
	//************************* Event Senders ****************************/
	///////////////////////////////////////////////////////////////////////
	event void RoutingAMSend.sendDone(message_t * msg , error_t err)
	{		
		dbg("Routing" , "Package sent %s \n", (err==SUCCESS)?"True":"False");
		
		setRoutingSendBusy(FALSE);
		
		if(!(call RoutingSendQueue.empty()))
		{
			post sendRoutingTask();
		}
	}
	
	
	event void DistributionAMSend.sendDone(message_t * msg , error_t err)
	{
		dbg("Distribution", "A Data Distribution package sent... %s \n",(err==SUCCESS)?"True":"False");

		setDistributionSendBusy(FALSE);
		
		if(!(call DistributionSendQueue.empty()))
		{
			post sendDistributionTask();
		}
	}

	///////////////////////////////////////////////////////////////////////
	//************************ Event Receivers ***************************/
	///////////////////////////////////////////////////////////////////////
	event message_t* RoutingReceive.receive( message_t * msg , void * payload, uint8_t len)
	{
		error_t enqueueDone;
		message_t tmp;
		uint16_t msource;
		
		msource =call RoutingAMPacket.source(msg);
				
		atomic{
		memcpy(&tmp,msg,sizeof(message_t));
		}
		enqueueDone=call RoutingReceiveQueue.enqueue(tmp);
		if(enqueueDone == SUCCESS)
		{
			post receiveRoutingTask();
		}
		else
		{
			dbg("Routing","RoutingMsg enqueue failed!!! \n");		
		}
				
		return msg;
	}
	

	event message_t* DistributionReceive.receive( message_t * msg , void * payload, uint8_t len)
	{
		error_t enqueueDone;
		message_t tmp;
		uint16_t msource;
		
		msource =call DistributionAMPacket.source(msg);

		dbg("Distribution", "ID [%d]: Data Distribution package receivede from Node [%d]\n", TOS_NODE_ID, msource);
				
		atomic{
		memcpy(&tmp,msg,sizeof(message_t));
		}
		enqueueDone=call DistributionReceiveQueue.enqueue(tmp);
		if(enqueueDone == SUCCESS)
		{
			post receiveDistributionTask();
		}
		else
		{
			dbg("SRTreeC","DistributionMsg enqueue failed!!! \n");		
		}
				
		return msg;
	}



	
	///////////////////////////////////////////////////////////////////////
	//******************************Senders*******************************/
	///////////////////////////////////////////////////////////////////////
	task void sendRoutingTask()
	{
		uint8_t mlen;
		uint16_t mdest;
		error_t sendDone;
		
		dbg("Routing","SendRoutingTask(): Starting....\n");

		if (call RoutingSendQueue.empty())
		{
			dbg("Routing","sendRoutingTask(): Q is empty!\n");
			return;
		}
		
		
		if(RoutingSendBusy)
		{
			dbg("Routing","sendRoutingTask(): RoutingSendBusy= TRUE!!!\n");
			return;
		}
		
		radioRoutingSendPkt = call RoutingSendQueue.dequeue();
	
		mlen= call RoutingPacket.payloadLength(&radioRoutingSendPkt);
		mdest=call RoutingAMPacket.destination(&radioRoutingSendPkt);
		if(mlen!=sizeof(RoutingMsg))
		{
			dbg("Routing","\t\tsendRoutingTask(): Unknown message!!!\n");
			return;
		}
		sendDone=call RoutingAMSend.send(mdest,&radioRoutingSendPkt,mlen);
		
		if ( sendDone== SUCCESS)
		{
			dbg("Routing","sendRoutingTask(): Send returned success!!!\n");
			setRoutingSendBusy(TRUE);
		}
		else
		{
			dbg("Routing","send failed!!!\n");
		}
	}

	/*	
		Used for getting an internal (in-node) measurement message
		containing the measurement for the node at the current round and 
		calculating and transmitting the appropriate aggregates based on the TiNA setup.
	*/
	task void sendDistributionTask()
	{
		error_t sendDone;
		message_t buffer;
		uint8_t mLen;
	
		uint8_t measurementData;
		uint16_t mDest;
		BufferMsg* mPayload;
		uint8_t tctFactor;
		float tctNumeric;

		//Select TCT based on the flag
		switch(tct){
			case 0:
				tctFactor = 5;
				break;
			case 1:
				tctFactor = 10;
				break;
			case 2:
				tctFactor = 15;
				break;
			case 3:
				tctFactor = 20;
				break;
			default:
				tctFactor = 0;
				break;
		}

		tctNumeric = ((float)tctFactor)/100;
		dbg("TinaRuntime","TCT is %f\n",tctNumeric);

		dbg("TinaRuntime", "Will be executing measurement distribution...\n");
		
		if (call DistributionSendQueue.empty()){
			dbg("TinaRuntime","sendDistributionTask(): Q is empty!\n");
			return;
		}

		if(DistributionSendBusy){
			dbg("TinaRuntime","sendDistributionTask(): Distribution  Q is busy!...");
			return;
		}
	
		radioDistributionSendPkt = call DistributionSendQueue.dequeue();
		mLen = call DistributionPacket.payloadLength(&radioDistributionSendPkt);
		mPayload = call DistributionPacket.getPayload(&radioDistributionSendPkt, mLen);

		if(mLen != sizeof(BufferMsg)){
			dbg("TinaRuntime","sendDistributionTask(): Unknown message!\n");
			return;
		} 

		measurementData = mPayload->data8bit;

		/*
			Construct message based on the TiNA's principles
		*/

		if(aggregateSelection == MAX || aggregateSelection == COUNT){

			uint8_t result;
			DistributionMsgSingle* msg;

			// Initiliaze the size of the message to be sent
			call DistributionPacket.setPayloadLength(&buffer,sizeof(DistributionMsgSingle));
			msg = (DistributionMsgSingle*)(call DistributionPacket.getPayload(&buffer,sizeof(DistributionMsgSingle)));
			
			if(msg==NULL){
				dbg("TinaRuntime","sendDistributionTask(): Na valid payload for SingleMsg!\nAbort..\n");
				return;
			}

			/*
				Calculate the aggregate for the specific node
				respecting the saved children measurements
			*/

			//If root then print the result
			if(aggregateSelection == MAX){
				result = aggregate(MAX, measurementData);
				if(TOS_NODE_ID==0){
					dbg("TinaMeasurements","Node [%d] --> For this round MAX()= %d\n", TOS_NODE_ID, result);
				}
			
			}else if(aggregateSelection == COUNT){
				result = aggregate(COUNT, measurementData);
				if(TOS_NODE_ID==0){
					dbg("TinaMeasurements","Node [%d] --> For this round COUNT()= %d\n", TOS_NODE_ID, result);
				}
		    }


			/*
				Check if TiNA standards are qualified and transmit measurement to grid  
				No transmission if node 
			*/
			if(TOS_NODE_ID!=0){
				
				//Transmit only at first round (obviously, to create data) and when the measurement is outside TCT's range
				if(roundCounter==1 || result > lastAggregate + tctNumeric * lastAggregate || result < lastAggregate - tctNumeric * lastAggregate){
					
					
					dbg("TinaMeasurements","Node [%d] --> Over-TCT measurements: Last= %d| New= %d ==>Transmitting...\n", TOS_NODE_ID, lastAggregate, result);

					//TiNA Condition is qualified so keep the new calculated aggregate value of the Node as the latest TiNA Measurements 
					lastAggregate = result;

					//Prepare the message fields
					atomic
					{
					
						call DistributionAMPacket.setDestination(&buffer, parentID);
						((DistributionMsgSingle*) msg)->data = result;
					}

					atomic
					{
						memcpy(&radioDistributionSendPkt,&buffer,sizeof(message_t));
					}	
					//Set destination and message length
					mDest = call DistributionAMPacket.destination(&radioDistributionSendPkt);
					mLen = call DistributionPacket.payloadLength(&radioDistributionSendPkt);

					//Send the message
					sendDone = call DistributionAMSend.send(mDest,&radioDistributionSendPkt, mLen);

				}else{
					dbg("TinaMeasurements","Node [%d] --> Under-TCT measurements: Last= %d| New= %d\n", TOS_NODE_ID, lastAggregate, result);
					return;
				}
			}


		}else if(aggregateSelection == MAXCOUNT){
	
			/*
				Initialize two messages. Not both of them are going to be used.
				Only one of them will be used at each round but the selection
				depends on the TiNA qualification of the current aggregate calculation
			*/
			DistributionMsgFull* msgFull;
			DistributionMsgSemi* msgSemi;
			uint8_t resultMAX, resultCOUNT;


			/*
				Calculate the aggregate for the specific node
				respecting the saved children measurements
			*/
			resultMAX = aggregate(MAX, measurementData);
			resultCOUNT = aggregate(COUNT, measurementData);

			/*
				If root then print the result 
			*/
			if(TOS_NODE_ID==0){
				dbg("TinaMeasurements","Node [0] --> For this round MAX()= %d\n", resultMAX);
				dbg("TinaMeasurements","Node [0] --> For this round COUNT()= %d\n", resultCOUNT);
			}else{

				//Transmit only at first round (obviously, to create data) and when the measurement is outside TCT's range
				//This is the optimal case when both of the aggregates needs to be transmitted because they overshoot the TCT
				if(roundCounter==1 || (resultMAX > lastAggregateMAX + tctNumeric * lastAggregateMAX || resultMAX < lastAggregateMAX - tctNumeric * lastAggregateMAX) && (resultCOUNT> lastAggregateCOUNT + tctNumeric * lastAggregateCOUNT || resultCOUNT < lastAggregateCOUNT - tctNumeric * lastAggregateCOUNT) ){
					
					dbg("TinaMeasurements","ID:[%d] --> Over-TCT  MAX    measurements: Last= %d| New= %d ==>Transmitting...\n", TOS_NODE_ID, lastAggregateMAX, resultMAX);
					dbg("TinaMeasurements","ID:[%d] --> Over-TCT  COUNT  measurements: Last= %d| New= %d ==>Transmitting...\n", TOS_NODE_ID, lastAggregateCOUNT, resultCOUNT);
					
					//TiNA Condition is qualified so keep the new calculated aggregate value of the Node as the latest TiNA Measurements 
					lastAggregateMAX = resultMAX;
					lastAggregateCOUNT = resultCOUNT;
			

					// Initiliaze the size of the message to be sent
					call DistributionPacket.setPayloadLength(&buffer,sizeof(DistributionMsgFull));
					msgFull = (DistributionMsgFull*)(call DistributionPacket.getPayload(&buffer,sizeof(DistributionMsgFull)));

					//Prepare the message fields
					atomic
					{
				
						call DistributionAMPacket.setDestination(&buffer, parentID);
						((DistributionMsgFull*) msgFull)->max = resultMAX;
						((DistributionMsgFull*) msgFull)->count = resultCOUNT;
					}

					atomic
					{
						memcpy(&radioDistributionSendPkt,&buffer,sizeof(message_t));
					}	

					//Set destination and message length
					mDest = call DistributionAMPacket.destination(&radioDistributionSendPkt);
					mLen = call DistributionPacket.payloadLength(&radioDistributionSendPkt);

					//Send the message
					sendDone = call DistributionAMSend.send(mDest,&radioDistributionSendPkt, mLen);


				}else if((resultMAX > lastAggregateMAX + tctNumeric * lastAggregateMAX || resultMAX < lastAggregateMAX - tctNumeric * lastAggregateMAX) && (resultCOUNT < lastAggregateCOUNT + tctNumeric * lastAggregateCOUNT || resultCOUNT > lastAggregateCOUNT - tctNumeric * lastAggregateCOUNT)){
				//When we need to transmit only MAX

					dbg("TinaMeasurements","ID:[%d] --> Over-TCT  MAX    measurements: Last= %d| New= %d ==>Transmitting...\n", TOS_NODE_ID, lastAggregateMAX, resultMAX);
					dbg("TinaMeasurements","ID:[%d] --> Over-TCT  COUNT  measurements: Last= %d| New= %d \n", TOS_NODE_ID, lastAggregateCOUNT, resultCOUNT);
					
					//TiNA Condition is qualified so keep the new calculated aggregate value of the Node as the latest TiNA Measurements 
					lastAggregateMAX = resultMAX;


					// Initiliaze the size of the message to be sent
					call DistributionPacket.setPayloadLength(&buffer,sizeof(DistributionMsgSemi));
					msgSemi = (DistributionMsgSemi*)(call DistributionPacket.getPayload(&buffer,sizeof(DistributionMsgSemi)));

					//Prepare the message fields
					atomic
					{
						call DistributionAMPacket.setDestination(&buffer, parentID);
						((DistributionMsgSemi*) msgSemi)->data = resultMAX;
						((DistributionMsgSemi*) msgSemi)->flag = MAX;
					}


					atomic
					{
						memcpy(&radioDistributionSendPkt,&buffer,sizeof(message_t));
					}	
					
					//Send the message
					mDest = call DistributionAMPacket.destination(&radioDistributionSendPkt);
					mLen = call DistributionPacket.payloadLength(&radioDistributionSendPkt);

					//Send the message
					sendDone = call DistributionAMSend.send(mDest,&radioDistributionSendPkt, mLen);
					if(sendDone == SUCCESS){
						dbg("SRTreeC","MESSAGE SENT!!!!\n");
					}

				}else if((resultMAX < lastAggregateMAX + tctNumeric * lastAggregateMAX || resultMAX > lastAggregateMAX - tctNumeric * lastAggregateMAX) && (resultCOUNT> lastAggregateCOUNT + tctNumeric * lastAggregateCOUNT || resultCOUNT < lastAggregateCOUNT - tctNumeric * lastAggregateCOUNT)){
				//When we need to transmit only COUNT

					dbg("TinaMeasurements","ID:[%d] --> Over-TCT  MAX    measurements: Last= %d| New= %d \n", TOS_NODE_ID, lastAggregateMAX, resultMAX);
					dbg("TinaMeasurements","ID:[%d] --> Over-TCT  COUNT  measurements: Last= %d| New= %d  ==>Transmitting...\n", TOS_NODE_ID, lastAggregateCOUNT, resultCOUNT);
					
					//TiNA Condition is qualified so keep the new calculated aggregate value of the Node as the latest TiNA Measurements 
					lastAggregateCOUNT = resultCOUNT;

					// Initiliaze the size of the message to be sent
					call DistributionPacket.setPayloadLength(&buffer,sizeof(DistributionMsgSemi));
					msgSemi = (DistributionMsgSemi*)(call DistributionPacket.getPayload(&buffer,sizeof(DistributionMsgSemi)));

					//Prepare the message fields
					atomic
					{
						call DistributionAMPacket.setDestination(&buffer, parentID);
						((DistributionMsgSemi*) msgSemi)->data = resultCOUNT;
						((DistributionMsgSemi*) msgSemi)->flag = COUNT;
					}

					//Set destination and message length
					mDest = call DistributionAMPacket.destination(&radioDistributionSendPkt);
					mLen = call DistributionPacket.payloadLength(&radioDistributionSendPkt);

					atomic
					{
						memcpy(&radioDistributionSendPkt,&buffer,sizeof(message_t));
					}	

					//Send the message
					sendDone = call DistributionAMSend.send(mDest,&radioDistributionSendPkt, mLen);

				}else{
					//Nothing should be transimitted. TiNA is not qualified
					dbg("TinaMeasurements","ID:[%d] --> Under-TCT   MAX    measurements: Last= %d| New= %d \n", TOS_NODE_ID, lastAggregateMAX, resultMAX);
					dbg("TinaMeasurements","ID:[%d] --> Under-TCT   COUNT  measurements: Last= %d| New= %d \n", TOS_NODE_ID, lastAggregateCOUNT, resultCOUNT);				
					return;
				}		
			}	

		}else{
			dbg("TinaRuntime","Bad Query !\nAbort...\n");
			return;
		}

	}
	
	///////////////////////////////////////////////////////////////////////
	//*****************************Receivers******************************/
	///////////////////////////////////////////////////////////////////////

	/*
		Get a routing task & dequeue message
	*/
	task void receiveRoutingTask()
	{
		uint8_t len;
		message_t radioRoutingRecPkt;

		radioRoutingRecPkt= call RoutingReceiveQueue.dequeue();
		
		len= call RoutingPacket.payloadLength(&radioRoutingRecPkt);
		
		dbg("Routing","ReceiveRoutingTask(): len=%u \n",len);

		if(len == sizeof(RoutingMsg))
		{
			RoutingMsg * mpkt = (RoutingMsg*) (call RoutingPacket.getPayload(&radioRoutingRecPkt,len));
			uint8_t msource = call DistributionAMPacket.source(&radioRoutingRecPkt);
			
			dbg("TinaSetup" , "receiveRoutingTask(): senderID=[%d] at depth -%d-, encoded  exec parameters: [%d]\n", msource , mpkt->depth, mpkt->executionParameters);
			

			//Decode received message and update global variables
		    decodeParameters(mpkt->executionParameters);
 
			dbg("TinaSetup","Node [%d]: Received in the RoutingMsg and decoded the following: Aggregate Selection: [%d] | TCT: [%u]\n", TOS_NODE_ID, aggregateSelection, tct);

			/* No father yet */
			if ( (parentID<0)||(parentID>=65535))
			{
				parentID= call RoutingAMPacket.source(&radioRoutingRecPkt);
				curdepth= mpkt->depth + 1;

				dbg("RoutingRes" , "New parent for NodeID= %d : curdepth= %d , parentID= %d \n", TOS_NODE_ID ,curdepth , parentID);
				
				if (TOS_NODE_ID!=0)
				{
					call RoutingMsgTimer.startOneShot(TIMER_FAST_PERIOD);
				}
			}
			
			/* Based on TAG if a parent has been found then stop there */
			
		}
		else
		{
			dbg("Routing","receiveRoutingTask():Empty message!!! \n");
			return;
		}
		
	}


	/*
		Get a distribution task & dequeue message
	*/
	task void receiveDistributionTask()
	{
		uint8_t len;
		uint8_t msource;
		message_t radioDistributionRecPkt;

		radioDistributionRecPkt= call DistributionReceiveQueue.dequeue();
		
		len= call DistributionPacket.payloadLength(&radioDistributionRecPkt);
		msource = call DistributionAMPacket.source(&radioDistributionRecPkt);
		
		dbg("Distribution","receiveDistributionTask(): len=%u \n",len);

		if(aggregateSelection == MAX || aggregateSelection == COUNT){

			void* msg = (DistributionMsgSingle*)(call DistributionPacket.getPayload(&radioDistributionRecPkt,len));
			
			int i=0;
			for( i=0 ; i < 64 ; i++){
				//Update the existing child node 
				//Or insert a new child for the newly received child measurement
				if(children[i].nodeID == msource || children[i].nodeID == 0){

					//Insert child
					if(children[i].nodeID == 0){
						children[i].nodeID = msource;
					}

					
					if(aggregateSelection == MAX){
						children[i].maxVal = ((DistributionMsgSingle*)msg)->data;
						dbg("TinaMeasurements","ID:[%d] received from child [%d] MAX data = %d\n",TOS_NODE_ID, msource, children[i].maxVal);

					}else if(aggregateSelection == COUNT){
						children[i].countVal = ((DistributionMsgSingle*)msg)->data;
						dbg("TinaMeasurements","ID:[%d] received from child [%d] COUNT data = %d\n",TOS_NODE_ID, msource, children[i].countVal);
					}

					//Operation completed
					break;
				}
			}

		}else if(aggregateSelection == MAXCOUNT){

			if(len == sizeof(DistributionMsgFull)){
				void* msg = (DistributionMsgFull*)(call DistributionPacket.getPayload(&radioDistributionRecPkt,len));
				
				int i;
				for(i=0; i < 64; i++){
					if(children[i].nodeID == msource || children[i].nodeID ==0 ){

						//Insert child
						if(children[i].nodeID == 0){
							children[i].nodeID = msource;
						}

						children[i].maxVal = ((DistributionMsgFull*)msg)->max;
						children[i].countVal = ((DistributionMsgFull*)msg)->count;

						dbg("TinaMeasurements","ID:[%d] received from child [%d] MAX data = %d | COUNT data = %d\n",TOS_NODE_ID, msource, children[i].maxVal, children[i].countVal);
					}
					break;
				}			
				

			}else if(len == sizeof(DistributionMsgSemi)){

				void* msg = (DistributionMsgSemi*)(call DistributionPacket.getPayload(&radioDistributionRecPkt,len));
				uint8_t aggrFlag = ((DistributionMsgSemi*)msg)->flag;

				int i;
				for(i=0; i < 64; i++){
					if(children[i].nodeID == msource || children[i].nodeID ==0){
						
						//Check what kind of aggregate data the message contains based on the flag sent within it

						if(aggrFlag == MAX){

							children[i].maxVal = ((DistributionMsgSemi*)msg)->data;
							dbg("TinaMeasurements","ID:[%d] received from child [%d] MAX data = %d\n",TOS_NODE_ID, msource, children[i].maxVal);

						}else if(aggrFlag == COUNT){

							children[i].countVal = ((DistributionMsgSemi*)msg)->data;
							dbg("TinaMeasurements","ID:[%d] received from child [%d] COUNT data = %d\n",TOS_NODE_ID, msource, children[i].countVal);

						}else{
							dbg("Distribution","receiveDistributionTask: Bad Aggr Flag...Aborting...\n");
							return;
						}

					}
					break;
				}		

			}else{
				dbg("Distribution","receiveDistributionTask: Bad Message...Aborting...\n");
				return;
			}

		}else{
			dbg("TinaRuntime","receiveDistributionTask: Bad Query...Aborting...\n");
		    return;
		}

		
	}

}
