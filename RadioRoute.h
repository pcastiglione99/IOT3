

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
  MAX_CAPACITY = 7;
};

// Routing Table
typedef struct routing_entry_t {
    uint16_t destination;
    uint16_t next_hop;
    uint16_t cost;
    struct routing_entry_t* next;
} routing_entry_t;


typedef struct {
    routing_entry_t* head;
    routing_entry_t* tail;
    uint16_t size;
    uint16_t max_capacity;
} routing_table_t;


#endif
