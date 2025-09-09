# Real-time Banking with Lustre, WebSockets & eventsourcing_glyn

This example demonstrates a complete real-time banking application that showcases:

- **Backend Event Sourcing**: Using `eventsourcing_glyn` for distributed command processing
- **Real-time Updates**: WebSocket integration for instant UI updates
- **Frontend**: Lustre SPA with reactive state management
- **Bidirectional Communication**: Commands from UI → Backend, Events from Backend → UI

## Architecture

```
┌─────────────────┐     WebSocket     ┌──────────────────────┐
│   Lustre SPA    │ ←──────────────→ │   WebSocket Server   │
│                 │   Commands &      │                      │
│ • Account View  │   Real-time       │ • Command Routing    │
│ • Transaction   │   Updates         │ • Event Broadcasting │
│   History       │                   │ • Session Management │
└─────────────────┘                   └──────────────────────┘
                                                │
                                      ┌─────────┼─────────┐
                                      │         │         │
                              ┌───────▼───┐ ┌─────▼─────┐ ┌─────▼──────┐
                              │ Command   │ │ Balance   │ │ Audit      │
                              │ Processor │ │ Service   │ │ Service    │
                              │           │ │           │ │            │
                              │ (Glyn     │ │ (Glyn     │ │ (Glyn      │
                              │ PubSub)   │ │ PubSub)   │ │ PubSub)    │
                              └───────────┘ └───────────┘ └────────────┘
                                      │         │              │
                                      ▼         ▼              ▼
                              ┌─────────────────────────────────────────┐
                              │        Event Store (Memory/Postgres)    │
                              └─────────────────────────────────────────┘
```

## Features

### Backend Services

1. **Command Processor**: Handles account operations (open, deposit, withdraw)
2. **Balance Service**: Maintains real-time account balances 
3. **Transaction Service**: Tracks transaction history
4. **Audit Service**: Logs all operations for compliance
5. **WebSocket Service**: Manages client connections and real-time updates

### Frontend Features

1. **Real-time Balance Updates**: Balance updates instantly across all connected clients
2. **Transaction History**: Live transaction feed with real-time additions
3. **Command Processing**: Send banking commands through WebSocket
4. **Connection Status**: Visual indication of WebSocket connection state
5. **Multi-account Support**: Handle multiple bank accounts simultaneously

## Key Concepts Demonstrated

### Auto Snapshots & Subscriber Modes

The example shows different subscriber patterns:

```gleam
// Real-time subscriber - gets all events immediately
let realtime_queries = [
  #(process.new_name("balance-realtime"), fn(aggregate_id, events) {
    // Update balance immediately for WebSocket clients
    broadcast_balance_update(aggregate_id, calculate_balance(events))
  }),
]

// Batch subscriber - processes events in batches for efficiency  
let batch_queries = [
  #(process.new_name("audit-batch"), fn(aggregate_id, events) {
    // Process multiple events together for audit logging
    batch_audit_events(aggregate_id, events)
  }),
]

// Snapshot-aware subscriber - requests snapshots on startup
let snapshot_queries = [
  #(process.new_name("transaction-history"), fn(aggregate_id, events) {
    // Request snapshot if this is the first event we're seeing
    case is_first_event(aggregate_id) {
      True -> request_snapshot(aggregate_id)
      False -> Nil
    }
    update_transaction_history(aggregate_id, events)
  }),
]
```

### WebSocket Event Broadcasting

Events are automatically distributed from the backend to all connected WebSocket clients:

```gleam
// Backend publishes events via Glyn PubSub
eventsourcing.execute(
  command_processor,
  "account-123", 
  DepositMoney(100.0)
)

// WebSocket service subscribes to events and broadcasts to clients
let websocket_queries = [
  #(process.new_name("websocket-broadcaster"), fn(aggregate_id, events) {
    list.each(connected_clients, fn(client) {
      case client.subscribed_accounts {
        accounts if list.contains(accounts, aggregate_id) ->
          websocket.send(client.connection, json.encode(events))
        _ -> Nil
      }
    })
  }),
]
```

### Bidirectional Command Flow

The Lustre app can send commands back to the event sourcing system:

```gleam
// Frontend sends command via WebSocket
let on_deposit_click = fn(amount) {
  websocket.send(ws_connection, json.object([
    #("command", json.string("deposit")),
    #("account_id", json.string(account_id)),
    #("amount", json.float(amount))
  ]))
}

// Backend WebSocket handler processes commands  
let handle_websocket_message = fn(client, message) {
  case json.decode(message, command_decoder) {
    Ok(DepositCommand(account_id, amount)) ->
      eventsourcing.execute(command_processor, account_id, DepositMoney(amount))
    Ok(WithdrawCommand(account_id, amount)) ->
      eventsourcing.execute(command_processor, account_id, WithDrawMoney(amount))
    Error(_) -> websocket.send(client, error_response("Invalid command"))
  }
}
```

## Running the Example

```bash
# Start the backend services
gleam run -- server

# In another terminal, serve the frontend
gleam run -- client

# Open http://localhost:8080 in multiple browser tabs to see real-time sync
```

## Files

- `src/backend/` - Event sourcing backend with distributed services
- `src/frontend/` - Lustre SPA with WebSocket integration  
- `src/shared/` - Shared types and utilities
- `src/websocket/` - WebSocket server and client management
- `src/main.gleam` - Application entry point

## Testing Multi-client Real-time Updates

1. Open the app in multiple browser tabs
2. Perform a deposit in one tab
3. See the balance update instantly in all other tabs
4. Check the transaction history appearing in real-time
5. Test connection recovery by temporarily killing the backend