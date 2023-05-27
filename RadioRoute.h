

#ifndef RADIO_ROUTE_H
#define RADIO_ROUTE_H

typedef nx_struct radio_route_msg_t {

	nx_uint16_t type;
	nx_uint16_t sender;
	nx_uint16_t destination; // node_requested
	nx_uint16_t value; // cost

} radio_route_msg_t;

enum {
  AM_RADIO_COUNT_MSG = 10,
  CAPACITY = 7;
};

// Routing Table
typedef struct routing_entry_t{
    uint16_t next_hop;
    uint16_t cost;
} routing_entry_t;

typedef struct routing_table_t{
    routing_entry_t entries[CAPACITY];
} routing_table_t;


#endif
