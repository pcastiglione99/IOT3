
/*
*	IMPORTANT:
*	The code will be avaluated based on:
*		Code design  
*
*/
 
#include "Timer.h"
#include "RadioRoute.h"

module RadioRouteC @safe() {
  uses {
  
	interface Boot;
    interface Leds;
    interface Receive;
    interface AMSend;
    interface Timer<TMilli> as Timer0;    
    interface Timer<TMilli> as Timer1;
    interface SplitControl as AMControl;
    interface Packet;
  }
}
implementation {

  routing_table_t routing_table;
  message_t waiting_packet;
  uint16_t waiting_address = 0;

  const uint8_t codice_persona[8] = {1,0,6,5,7,8,1,6};
  uint8_t digit_index = 0; 
  uint8_t msg_counter = 0;
  uint8_t led_index = 0;
  
  message_t packet;
  
  // Variables to store the message to send
  message_t queued_packet;
  uint16_t queue_addr;

  uint16_t time_delays[7]={61,173,267,371,479,583,689}; //Time delay in milli seconds
  
  
  
  bool route_req_sent=FALSE;
  bool route_rep_sent=FALSE;

  bool locked = FALSE;

  
  bool actual_send (uint16_t address, message_t* packet);
  bool generate_send (uint16_t address, message_t* packet, uint8_t type);
  void dbgPacketInfo(radio_route_msg_t* rrm, char* topic, char* type);
  
  void initializeRoutingTable(routing_table_t* table);
  void addRoutingEntry(routing_table_t* table, uint16_t destination, uint16_t next_hop, uint16_t cost);
  route_entry_t* getRoutingEntry(routing_table_t* table, uint16_t destination);


  void addRoutingEntry(routing_table_t* table, uint16_t destination, uint16_t next_hop, uint16_t cost) {
    if (destination <= 0 || destination > CAPACITY) {
        dbg("RadioRouteC", "Destination is not valid. Cannot add this entry.\n");
        return;
    }else{
      route_entry_t* routing_entry = &(table->entries[destination - 1]);
      routing_entry->next_hop = next_hop;
      routing_entry->cost = cost;
    }
  }

  void initializeRoutingTable(routing_table_t* routing_table) {
    uint16_t i;
    for (i = 1; i <= CAPACITY; i++) {
      addRoutingEntry(routing_table, i, 0, 0);
    }
  }

  void dbgPacketInfo(radio_route_msg_t* rrm, char* topic, char* type){
    dbg(topic, type);
    switch(rrm->type){
      case 0:
        dbg_clear(topic, "[Data message] Type:%hu Sender:%hu Destination:%hu Value:%hu\n", rrm->type, rrm->sender, rrm->destination, rrm->value);
        break;
      case 1:
        dbg_clear(topic, "[Route request] Type:%hu Node Requested:%hu\n", rrm->type, rrm->destination);
        break;
      case 2:
        dbg_clear(topic, "[Route reply] Type:%hu Sender:%hu Node Requested:%hu Cost:%hu\n", rrm->type, rrm->sender, rrm->destination, rrm->value);
        break;
      default:
    }
  }

  route_entry_t* getRoutingEntry(routing_table_t* table, uint16_t destination) {
    if (destination <= 0 || destination > CAPACITY) {
        dbg("RadioRouteC", "Destination is not valid. Cannot get this entry.\n");
        return NULL;
    }else{
      route_entry_t* routing_entry = &(table->entries[destination - 1]);
      return (routing_entry->next_hop > 0 && routing_entry->next_hop <= CAPACITY) ? routing_entry : NULL;
    }
  }
    
  bool generate_send (uint16_t address, message_t* packet, uint8_t type){
    /*
    * 
    * Function to be used when performing the send after the receive message event.
    * It store the packet and address into a global variable and start the timer execution to schedule the send.
    * It allow the sending of only one message for each REQ and REP type
    * @Input:
    *		address: packet destination address
    *		packet: full packet to be sent (Not only Payload)
    *		type: payload message type
    *
    * MANDATORY: DO NOT MODIFY THIS FUNCTION
    */
  	if (call Timer0.isRunning()){
  		return FALSE;
  	}else{
      if (type == 1 && !route_req_sent ){
        route_req_sent = TRUE;
        call Timer0.startOneShot( time_delays[TOS_NODE_ID-1] );
        queued_packet = *packet;
        queue_addr = address;
      }else if (type == 2 && !route_rep_sent){
        route_rep_sent = TRUE;
        call Timer0.startOneShot( time_delays[TOS_NODE_ID-1] );
        queued_packet = *packet;
        queue_addr = address;
      }else if (type == 0){
        call Timer0.startOneShot( time_delays[TOS_NODE_ID-1] );
        queued_packet = *packet;
        queue_addr = address;	
      }
  	}
  	return TRUE;
  }
  
  event void Timer0.fired() {
  	/*
  	* Timer triggered to perform the send.
  	* MANDATORY: DO NOT MODIFY THIS FUNCTION
  	*/
  	actual_send (queue_addr, &queued_packet);
  }
  
  bool actual_send (uint16_t address, message_t* packet){
    /*
    * Implement here the logic to perform the actual send of the packet using the tinyOS interfaces
    */
    if (locked){
      dbg("radio_send", "Sending aborted due to locking..\n");
    }else{
      radio_route_msg_t* rrm = (radio_route_msg_t*)call Packet.getPayload(packet, sizeof(radio_route_msg_t));
      route_entry_t* entry = getRoutingEntry(&routing_table, rrm->destination);
      if (rrm->type == 0 && rrm->sender == TOS_NODE_ID && entry == NULL){
        //set the buffer so we can send the packet later
        dbg("radio_send", "Queuing packets to be sent on route_reply...\n");
        waiting_packet = *packet;
        waiting_address = address;

        //creating route_req
        rrm->type = 1;
        return actual_send(AM_BROADCAST_ADDR, packet);
      }else{
        if (call AMSend.send((rrm->type == 0 && entry != NULL) ? entry->next_hop : address, packet, sizeof(radio_route_msg_t)) == SUCCESS) {
          locked = TRUE;
          dbgPacketInfo(rrm, "radio_send", "Packet sent...");
        }
      }
    }
    return TRUE;
  }
  
  
  event void Boot.booted() {
  	dbg("boot", "APP BOOTED.\n");
  	initializeRoutingTable(&routing_table);
    call AMControl.start();
  }

  event void AMControl.startDone(error_t err) {
	  if (err == SUCCESS) {
	    dbg("radio", "Radio started.\n");
      if(TOS_NODE_ID == 1){
       call Timer1.startOneShot(5000);
      }
    }
    else {
      call AMControl.start();
    }
  }

  event void AMControl.stopDone(error_t err) { /* do nothing */ }
  
  
  event void Timer1.fired() {
    /*
    * Implement here the logic to trigger the Node 1 to send the first REQ packet
    */      
    radio_route_msg_t* rrm = (radio_route_msg_t*)call Packet.getPayload(&packet, sizeof(radio_route_msg_t));
    rrm->type = 0;
    rrm->sender = 1;
    rrm->destination = 7;
    rrm->value = 5;
    generate_send(rrm->destination, &packet, rrm->type);
  }

  event message_t* Receive.receive(message_t* bufPtr, void* payload, uint8_t len) {
    /*
    * Parse the receive packet.
    * Implement all the functionalities
    * Perform the packet send using the genera§te_send function if needed
    * Implement the LED logic and print LED status on Debug
    */
	  if (len == sizeof(radio_route_msg_t)){   
      // radio_route_msg_t* rrm = (radio_route_msg_t*)call Packet.getPayload(&packet, sizeof(radio_route_msg_t));
      route_entry_t* entry = NULL;
      radio_route_msg_t* rrm = (radio_route_msg_t*)payload;
      dbgPacketInfo(rrm, "radio_rec", "Packet received...");
      switch (rrm->type){
        case 0:
          // data_message
          if (rrm->destination == TOS_NODE_ID){
            dbg("radio_rec", "[Data Message] packet received hop by hop!!\n");
          }else{
            entry = getRoutingEntry(&routing_table, rrm->destination);
            generate_send((entry != NULL) ? entry -> next_hop : rrm->destination, bufPtr, rrm->type);
          }
          break;
        case 1:
          // route_req
          if (rrm->destination == TOS_NODE_ID){
            //node is the requested one, reply in broadcast with a route_reply
            rrm->type = 2;
            rrm->sender = TOS_NODE_ID;
            rrm->value = 1;
          }else{
            entry = getRoutingEntry(&routing_table, rrm->destination);
            if (entry != NULL){
              rrm->type = 2;
              rrm->sender = TOS_NODE_ID;
              rrm->value = entry->cost + 1;
            }
          }
          //if no modification to the packet, just broadcast the route request
          generate_send(AM_BROADCAST_ADDR, bufPtr, rrm->type);
          break;
        case 2:
          // route_reply
          entry = getRoutingEntry(&routing_table, rrm->destination);
          if (rrm->destination != TOS_NODE_ID && (entry == NULL || rrm->value <= entry->cost)){
            //routing table update
            dbg("radio_rec", "Update routing table, destination:%hu next_hop:%hu cost:%hu\n", rrm->destination, rrm->sender, rrm->value);
            addRoutingEntry(&routing_table, rrm->destination, rrm->sender, rrm->value);
          
            //check if some packet was waiting for a routing table update
            if (rrm->destination == waiting_address){
              radio_route_msg_t* waiting_payload = (radio_route_msg_t*)call Packet.getPayload(&waiting_packet, sizeof(radio_route_msg_t));
              generate_send(waiting_address, &waiting_packet, waiting_payload->type);
              //reset
              waiting_address = 0;
            }
            //continue sending in broadcast
            rrm->value = rrm->value + 1;
            rrm->sender = TOS_NODE_ID;
            rrm->type = 2;
            generate_send(AM_BROADCAST_ADDR, bufPtr, rrm->type);
          }
          break;
        default:
          dbgerror("radio_rec", "Invalid message type\n");
          return;

      }      
      
      //LED
      led_index = codice_persona[msg_counter % 8] % 3;  // msg_counter % 8 select the digit in a round robin cycle

      switch (led_index){
        case 0:
          call Leds.led0Toggle(); 
          dbg("led_0","Led0 Toggled.\n");
          break;
        case 1:
          call Leds.led1Toggle(); 
          dbg("led_1","Led1 Toggled.\n");
          break;
        case 2:
          call Leds.led2Toggle(); 
          dbg("led_2","Led2 Toggled.\n");
          break;
        default:
          dbgerror("radio_rec", "Led index %d out of range\n", led_index);
          return;

      }
      msg_counter++;
    }
    return bufPtr;
	
  }

  event void AMSend.sendDone(message_t* bufPtr, error_t error) {
    if (&queued_packet == bufPtr) {
      locked = FALSE;
      dbg("radio_send", "Packet sent... at time %s\n", sim_time_string());
    }
  }
}




