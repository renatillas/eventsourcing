<h1 align="center">Eventsourcing</h1>

<div align="center">
  ✨ <strong>Event Sourcing Library for Gleam</strong> ✨
</div>

<div align="center">
  A Gleam library for building event-sourced systems with supervision trees.
</div>

<br />

<div align="center">
  <a href="https://hex.pm/packages/eventsourcing">
    <img src="https://img.shields.io/hexpm/v/eventsourcing"
      alt="Available on Hex" />
  </a>
  <a href="https://hexdocs.pm/eventsourcing">
    <img src="https://img.shields.io/badge/hex-docs-ffaff3"
      alt="Documentation" />
  </a>
</div>

---

## Table of contents

- [Introduction](#introduction)
- [Architecture](#architecture)
- [Features](#features)
- [Quick Start](#quick-start)
- [Example](#example)
  - [Define Your Domain](#define-your-domain)
  - [Command Handling](#command-handling)
  - [Event Application](#event-application)
  - [Supervised Usage (Recommended)](#supervised-usage-recommended)
  - [Async API Usage](#async-api-usage)
  - [Snapshot Configuration](#snapshot-configuration)
  - [Error Handling](#error-handling)
- [Migration Guide](#migration-guide)
- [Philosophy](#philosophy)
- [Installation](#installation)
- [Support](#support)
- [Contributing](#contributing)
- [License](#license)

## Introduction

Eventsourcing is a Gleam library for building robust, concurrent event-sourced systems using OTP supervision trees. Event sourcing stores changes to application state as a sequence of immutable events, providing excellent auditability, debugging capabilities, and system resilience.

**Version 9.0** introduces API simplifications with cleaner function signatures and streamlined message passing for improved developer experience while maintaining all the production-ready features from v8.0.

## Architecture

The library is built on a supervised actor architecture:

- **Supervision Trees**: Production-ready fault tolerance with automatic actor restarts
- **Query Actors**: Event processing runs in separate supervised actors for non-blocking processing
- **Domain Error Resilience**: Business rule violations don't crash the system
- **Asynchronous Processing**: Commands and queries are processed independently

## Features

### 🏗️ **Supervision & Fault Tolerance**

- **Supervised architecture** with built-in supervision trees
- **Graceful domain error handling** - business rule violations don't crash actors
- **Automatic actor recovery** - failed components restart automatically
- **Fault isolation** - actor crashes don't cascade through the system

### ⚡ **Concurrent Processing**

- **Asynchronous query processing** - queries don't block command execution
- **Multi-aggregate support** - process multiple aggregates simultaneously  
- **Actor-based isolation** - queries run in independent processes

### 📊 **Event Sourcing Core**

- **Command validation** and event generation
- **Event persistence** with multiple store implementations
- **Aggregate reconstruction** from event streams
- **Partial event loading** from specific sequence numbers
- **Snapshot support** for performance optimization

### 🔧 **Event Store Support**

- [**In-memory Store**](https://github.com/renatillas/eventsourcing_inmemory): Development and testing
- [**Postgres Store**](https://github.com/renatillas/eventsourcing_postgres): PostgreSQL persistence  
- [**SQLite Store**](https://github.com/renatillas/eventsourcing_sqlite): SQLite persistence

### 🛡️ **Type Safety**

- **Comprehensive error types** with Result-based API
- **Input validation** for timeouts and frequencies
- **Type-safe event sourcing pipeline**

## Quick Start

```gleam
import eventsourcing
import eventsourcing/memory_store
import gleam/otp/static_supervisor
import gleam/erlang/process

// 1. Create memory store with supervision
let events_actor_name = process.new_name("events_actor")
let snapshot_actor_name = process.new_name("snapshot_actor")
let #(eventstore, memory_store_spec) = memory_store.supervised(
  events_actor_name,
  snapshot_actor_name, 
  static_supervisor.OneForOne
)

// 2. Start memory store supervisor
let assert Ok(_) = static_supervisor.new(static_supervisor.OneForOne)
  |> static_supervisor.add(memory_store_spec)
  |> static_supervisor.start()

// 3. Create event sourcing system
let name = process.new_name("eventsourcing_actor")
let queries = [#(process.new_name("my_query"), my_query)]
let assert Ok(eventsourcing_spec) = eventsourcing.supervised(
  name: name,
  eventstore: eventstore,
  handle: my_handle,
  apply: my_apply,
  empty_state: MyEmptyState,
  queries: queries,
  snapshot_config: None
)

// 4. Start event sourcing supervisor
let assert Ok(_supervisor) = static_supervisor.new(static_supervisor.OneForOne)
  |> static_supervisor.add(eventsourcing_spec)
  |> static_supervisor.start()

// 5. Get actor from name
let eventsourcing_actor = process.named_subject(name)

// 6. Execute commands
eventsourcing.execute(eventsourcing_actor, "aggregate-123", MyCommand)

// 7. Load events and monitor system
let events_subject = eventsourcing.load_events(eventsourcing_actor, "aggregate-123")
let stats_subject = eventsourcing.system_stats(eventsourcing_actor)
```

## Example

### Define Your Domain

```gleam
pub type BankAccount {
  BankAccount(balance: Float)
  UnopenedBankAccount
}

pub type BankAccountCommand {
  OpenAccount(account_id: String)
  DepositMoney(amount: Float)
  WithDrawMoney(amount: Float)
}

pub type BankAccountEvent {
  AccountOpened(account_id: String)
  CustomerDepositedCash(amount: Float, balance: Float)
  CustomerWithdrewCash(amount: Float, balance: Float)
}

pub type BankAccountError {
  CantDepositNegativeAmount
  CantOperateOnUnopenedAccount
  CantWithdrawMoreThanCurrentBalance
}
```

### Command Handling

```gleam
pub fn handle(
  bank_account: BankAccount,
  command: BankAccountCommand,
) -> Result(List(BankAccountEvent), BankAccountError) {
  case bank_account, command {
    UnopenedBankAccount, OpenAccount(account_id) ->
      Ok([AccountOpened(account_id)])
    BankAccount(balance), DepositMoney(amount) -> {
      case amount >. 0.0 {
        True -> {
          let new_balance = balance +. amount
          Ok([CustomerDepositedCash(amount, new_balance)])
        }
        False -> Error(CantDepositNegativeAmount)
      }
    }
    BankAccount(balance), WithDrawMoney(amount) -> {
      case amount >. 0.0 && balance >=. amount {
        True -> {
          let new_balance = balance -. amount
          Ok([CustomerWithdrewCash(amount, new_balance)])
        }
        False -> Error(CantWithdrawMoreThanCurrentBalance)
      }
    }
    _, _ -> Error(CantOperateOnUnopenedAccount)
  }
}
```

### Event Application

```gleam
pub fn apply(bank_account: BankAccount, event: BankAccountEvent) -> BankAccount {
  case event {
    AccountOpened(_) -> BankAccount(0.0)
    CustomerDepositedCash(_, balance) -> BankAccount(balance)
    CustomerWithdrewCash(_, balance) -> BankAccount(balance)
  }
}
```

### Supervised Usage (Recommended)

```gleam
import eventsourcing
import eventsourcing/memory_store
import gleam/otp/static_supervisor
import gleam/erlang/process

pub fn main() {
  // Define query for read model updates
  let balance_query = fn(aggregate_id, events) {
    io.println(
      "Account " <> aggregate_id <> " processed " 
      <> int.to_string(list.length(events)) <> " events"
    )
  }

  // 1. Create memory store with supervision
  let events_actor_name = process.new_name("events_actor")
  let snapshot_actor_name = process.new_name("snapshot_actor")
  let #(eventstore, memory_store_spec) = memory_store.supervised(
    events_actor_name,
    snapshot_actor_name,
    static_supervisor.OneForOne
  )

  // 2. Start memory store supervisor
  let assert Ok(_) = static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.add(memory_store_spec)
    |> static_supervisor.start()

  // 3. Create supervised event sourcing system
  let name = process.new_name("eventsourcing_actor")
  let queries = [#(process.new_name("balance_query"), balance_query)]
  let assert Ok(eventsourcing_spec) = eventsourcing.supervised(
    name: name,
    eventstore: eventstore,
    handle: handle,
    apply: apply,
    empty_state: UnopenedBankAccount,
    queries: queries,
    snapshot_config: None
  )

  // 4. Start event sourcing supervision tree
  let assert Ok(_supervisor) = static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.add(eventsourcing_spec)
    |> static_supervisor.start()

  // 5. Get actor from name
  let eventsourcing_actor = process.named_subject(name)

  // Give time for actors to start
  process.sleep(100)

  // 6. Execute commands - they will be processed asynchronously
  eventsourcing.execute(
    eventsourcing_actor,
    "account-123",
    OpenAccount("account-123")
  )
  
  eventsourcing.execute(
    eventsourcing_actor,
    "account-123",
    DepositMoney(100.0)
  )
}
```

### Async API Usage

All data operations now use an asynchronous message-passing pattern:

```gleam
pub fn async_example() {
  // Set up supervised system (memory store setup omitted for brevity)
  let name = process.new_name("eventsourcing_actor")
  let assert Ok(eventsourcing_spec) = eventsourcing.supervised(
    name: name,
    eventstore: eventstore, // from memory_store.supervised()
    handle: handle,
    apply: apply,
    empty_state: UnopenedBankAccount,
    queries: [],
    snapshot_config: None
  )

  let assert Ok(_supervisor) = static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.add(eventsourcing_spec)
    |> static_supervisor.start()

  let eventsourcing_actor = process.named_subject(name)
  process.sleep(100) // Give time for actors to start

  // Load aggregate state asynchronously
  let load_subject = eventsourcing.load_aggregate(eventsourcing_actor, "account-123")
  case process.receive(load_subject, 1000) {
    Ok(Ok(aggregate)) -> io.println("Account loaded: " <> aggregate.aggregate_id)
    Ok(Error(eventsourcing.EntityNotFound)) -> io.println("Account not found")
    Ok(Error(other)) -> io.println("Error: " <> string.inspect(other))
    Error(_) -> io.println("Timeout waiting for response")
  }
  
  // Load events asynchronously
  let events_subject = eventsourcing.load_events_from(eventsourcing_actor, "account-123", 0)
  case process.receive(events_subject, 1000) {
    Ok(Ok(events)) -> io.println("Loaded " <> int.to_string(list.length(events)) <> " events")
    Ok(Error(error)) -> io.println("Error loading events: " <> string.inspect(error))
    Error(_) -> io.println("Timeout waiting for events")
  }
}
```

### Snapshot Configuration

```gleam
// Create validated frequency (snapshots every 100 events)
let assert Ok(frequency) = eventsourcing.frequency(100)
let snapshot_config = eventsourcing.SnapshotConfig(frequency)

// Enable snapshots during supervised system setup
let name = process.new_name("eventsourcing_actor")
let assert Ok(eventsourcing_spec) = eventsourcing.supervised(
  name: name,
  eventstore: eventstore, // from memory_store.supervised()
  handle: handle,
  apply: apply,
  empty_state: UnopenedBankAccount,
  queries: [],
  snapshot_config: Some(snapshot_config) // Enable snapshots
)

// Get actor and load latest snapshot asynchronously
let eventsourcing_actor = process.named_subject(name)
let snapshot_subject = eventsourcing.latest_snapshot(eventsourcing_actor, "account-123")
case process.receive(snapshot_subject, 1000) {
  Ok(Ok(Some(snapshot))) -> {
    io.println("Using snapshot from sequence " <> int.to_string(snapshot.sequence))
  }
  Ok(Ok(None)) -> io.println("No snapshot available, loading from events")
  Ok(Error(error)) -> io.println("Error loading snapshot: " <> string.inspect(error))
  Error(_) -> io.println("Timeout waiting for snapshot")
}
```

### Enhanced API Features

**Execute Commands with Metadata**

```gleam
// Execute with additional tracking information
eventsourcing.execute_with_metadata(
  eventsourcing_actor,
  "account-123",
  DepositMoney(100.0),
  [#("user_id", "user-456"), #("source", "mobile_app"), #("trace_id", "abc-123")]
)
```

**System Monitoring and Stats**

```gleam
// Get system health statistics
let stats_subject = eventsourcing.system_stats(eventsourcing_actor)
case process.receive(stats_subject, 1000) {
  Ok(stats) -> {
    io.println("Query actors: " <> int.to_string(stats.query_actors_count))
    io.println("Commands processed: " <> int.to_string(stats.total_commands_processed))
  }
  Error(_) -> io.println("Timeout getting stats")
}

// Get individual aggregate statistics  
let agg_stats_subject = eventsourcing.aggregate_stats(eventsourcing_actor, "account-123")
case process.receive(agg_stats_subject, 1000) {
  Ok(Ok(stats)) -> {
    io.println("Aggregate: " <> stats.aggregate_id)
    io.println("Has snapshot: " <> string.inspect(stats.has_snapshot))
  }
  Ok(Error(error)) -> io.println("Error: " <> string.inspect(error))
  Error(_) -> io.println("Timeout")
}
```

## Migration Guide

### Migrating from v8 to v9

**Version 9.0** introduces API simplifications to improve the developer experience:

#### Key Changes
- **Simplified function signatures**: All public functions now accept `process.Subject(...)` directly instead of `actor.Started(...)`
- **Cleaner function names**: Removed `get_` prefixes from stats functions (`system_stats`, `aggregate_stats`, `latest_snapshot`)
- **Direct message passing**: Functions send messages directly without `.data` accessor

#### Migration Steps

**1. Update Function Calls - Remove .data accessor**
```gleam
// v8.0
eventsourcing.execute(eventsourcing_actor.data, "agg-123", command)
eventsourcing.load_aggregate(eventsourcing_actor.data, "agg-123")

// v9.0 - Direct subject passing
eventsourcing.execute(eventsourcing_actor, "agg-123", command)
eventsourcing.load_aggregate(eventsourcing_actor, "agg-123")
```

**2. Update Statistics Function Names**
```gleam
// v8.0
let stats = eventsourcing.get_system_stats(eventsourcing_actor.data)
let agg_stats = eventsourcing.get_aggregate_stats(eventsourcing_actor.data, "agg-123")
let snapshot = eventsourcing.get_latest_snapshot(eventsourcing_actor.data, "agg-123")

// v9.0 - Cleaner names
let stats = eventsourcing.system_stats(eventsourcing_actor)
let agg_stats = eventsourcing.aggregate_stats(eventsourcing_actor, "agg-123") 
let snapshot = eventsourcing.latest_snapshot(eventsourcing_actor, "agg-123")
```

**3. Add Named Actor Support**
```gleam
// v8.0
let assert Ok(spec) = eventsourcing.supervised(
  eventstore, handle: handle, apply: apply,
  empty_state: state, queries: [balance_query],
  eventsourcing_actor_receiver: receiver1,
  query_actors_receiver: receiver2,
  snapshot_config: None
)

// v9.0 - Named actors required
let assert Ok(spec) = eventsourcing.supervised(
  name: process.new_name("eventsourcing_actor"),
  eventstore: eventstore, handle: handle, apply: apply,
  empty_state: state, 
  queries: [#(process.new_name("balance_query"), balance_query)],
  snapshot_config: None
)
```

### Migrating from v7 to v9

### Key Changes

- **Supervision required** for production use
- **Query registration** needed after supervisor startup  
- **Asynchronous execution** via actor message passing
- **Async data loading** - all load operations return subjects and require `process.receive()`
- **Enhanced error handling** with graceful domain error recovery
- **Snapshot config** now passed during system initialization

### Migration Steps

**1. Update Initialization**

```gleam
// v7.x
let eventsourcing = eventsourcing.new(store, queries, handle, apply, empty_state)

// v8.0 - Supervised (Recommended)  
let eventsourcing_spec = eventsourcing.supervised(
  store, handle, apply, empty_state, queries,
  eventsourcing_receiver, query_receiver
)
```

**2. Query Registration (No Longer Needed)**

```gleam
// v8.0 - Required after supervisor start
eventsourcing.register_queries(eventsourcing_actor, query_actors)

// v9.0 - Not needed! Queries are automatically registered through supervised() function
```

**3. Update Command Execution**

```gleam  
// v7.x
eventsourcing.execute(eventsourcing, "agg-123", command)

// v8.0  
eventsourcing.execute(eventsourcing_actor, "agg-123", command)
```

**4. Update Data Loading (Now Async)**

```gleam
// v7.x - Synchronous
let assert Ok(aggregate) = eventsourcing.load_aggregate(eventsourcing, "agg-123")

// v8.0 - Asynchronous message passing
let load_subject = eventsourcing.load_aggregate(eventsourcing_actor, "agg-123")
let assert Ok(Ok(aggregate)) = process.receive(load_subject, 1000)
```

**5. Update Snapshot Configuration**

```gleam
// v7.x
let config = eventsourcing.SnapshotConfig(5)

// v8.0
let assert Ok(frequency) = eventsourcing.frequency(5)
let config = eventsourcing.SnapshotConfig(frequency)
```

## Philosophy

Eventsourcing v8 embraces OTP supervision principles to build production-ready, fault-tolerant event-sourced systems:

- **Fault Tolerance First**: Supervision trees ensure system resilience
- **Let It Crash**: System errors crash actors for clean recovery, business errors don't
- **Clear Separation**: Commands, events, and queries are distinct supervised processes  
- **Concurrent by Design**: Asynchronous processing maximizes throughput
- **Type Safety**: Full Gleam type safety with comprehensive error handling
- **Production Ready**: Built for real-world concurrent systems

This design makes your event-sourced systems naturally concurrent, fault-tolerant, and maintainable while preserving Gleam's excellent type safety.

## Installation

Eventsourcing is published on [Hex](https://hex.pm/packages/eventsourcing)!
You can add it to your Gleam projects from the command line:

```sh
gleam add eventsourcing
```

## Support

Eventsourcing is built by [Renatillas](https://github.com/renatillas).
Contributions are very welcome!
If you've spotted a bug, or would like to suggest a feature,
please open an issue or a pull request.

## Contributing

Contributions are welcome! Please follow these steps:

1. Fork the repository.
2. Create a new branch (`git checkout -b my-feature-branch`).
3. Make your changes and commit them (`git commit -m 'Add new feature'`).
4. Push to the branch (`git push origin my-feature-branch`).
5. Open a pull request.

Please ensure your code adheres to the project's coding standards and
includes appropriate tests.

## License

This project is licensed under the MIT License.
See the [LICENSE](LICENSE) file for details.
