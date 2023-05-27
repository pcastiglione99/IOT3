#ifndef RADIO_ROUTE_H
#define RADIO_ROUTE_H

typedef nx_struct radio_route_msg {
	nx_uint16_t type;
  	nx_uint16_t sender;
  	nx_uint16_t destination; // node_requested
  	nx_uint16_t value; // cost
} radio_route_msg_t;

typedef struct route_entry_t {
	uint16_t next_hop;
  	uint16_t cost;
} route_entry_t;



enum {
  AM_RADIO_ROUTE_MSG = 10,
  CAPACITY = 7,
};

typedef struct routing_table_t{
    route_entry_t entries[CAPACITY];
} routing_table_t;

#endif
