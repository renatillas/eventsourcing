<h1 align="center">Eventsourcing</h1>

<div align="center">
  ✨ <strong>Event Sourcing Library for Gleam</strong> ✨
</div>

<div align="center">
  A Gleam library for building event-sourced systems.
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
- [Actor Architecture](#actor-architecture)
- [Features](#features)
- [Example](#example)
  - [Command Handling](#command-handling)
  - [Event Application](#event-application)
  - [Snapshot Configuration](#snapshot-configuration)
  - [Usage](#usage)
- [Philosophy](#philosophy)
- [Installation](#installation)
- [Support](#support)
- [Contributing](#contributing)
- [License](#license)

## Introduction

Eventsourcing is a Gleam library designed to help developers build robust, concurrent event-sourced systems using OTP actors. Event sourcing is a pattern where changes to the application's state are stored as a sequence of events. This library provides a type-safe way to implement event sourcing in your Gleam applications with built-in concurrency, fault tolerance, and query processing capabilities.

**The library focuses on core event sourcing functionality** with automatic query actor spawning and snapshot support for optimal performance.

## Actor Architecture

The library is built on an OTP actor architecture:

- **Query Actors**: Event processing queries execute in separate actor processes for non-blocking, parallel processing  
- **Fault Tolerance**: Actor crashes are isolated and don't affect the overall system
- **Automatic Lifecycle**: Query actors are spawned automatically when creating the EventSourcing instance

## Features

- **Actor-Based Query Processing**: Event processing queries execute in separate actor processes for maximum concurrency
- **Automatic Query Actor Management**: Query actors are spawned automatically with proper lifecycle management
- **Fault Tolerance**: Actor crashes are isolated and don't cascade through the system
- **Event Stores**: Supports multiple event store implementations:
  - [In-memory Store](https://github.com/renatillas/eventsourcing_inmemory): Simple in-memory event store for development and testing.
  - [Postgres Store](https://github.com/renatillas/eventsourcing_postgres): Event store implementation using PostgreSQL.
  - [SQLite Store](https://github.com/renatillas/eventsourcing_sqlite): Event store implementation using SQLite.
- **Command Handling**: Handle commands and produce events with robust error handling via actors
- **Event Application**: Apply events to update aggregates within actor processes
- **Snapshotting**: Optimize aggregate rebuilding with configurable snapshots
- **Registry Management**: Built-in aggregate actor registry for efficient actor lifecycle management
- **Monitoring & Telemetry**: Real-time system metrics and aggregate performance monitoring
- **Type-safe Error Handling**: Comprehensive error types and Result-based API

## Example

### Command Handling

```gleam
import eventsourcing
import eventsourcing/memory_store

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

pub fn handle(
  bank_account: BankAccount,
  command: BankAccountCommand,
) -> Result(List(BankAccountEvent), BankAccountError) {
  case bank_account, command {
    UnopenedBankAccount, OpenAccount(account_id) ->
      Ok([AccountOpened(account_id)])
    BankAccount(balance), DepositMoney(amount) -> {
      let balance = balance +. amount
      case amount >. 0.0 {
        True -> Ok([CustomerDepositedCash(amount:, balance:)])
        False -> Error(CantDepositNegativeAmount)
      }
    }
    _, _ -> Error(CantOperateOnUnopenedAccount)
  }
}
```

### Event Application

```gleam
pub fn apply(bank_account: BankAccount, event: BankAccountEvent) {
  case bank_account, event {
    UnopenedBankAccount, AccountOpened(_) -> BankAccount(0.0)
    BankAccount(_), CustomerDepositedCash(_, balance) -> BankAccount(balance:)
    BankAccount(_), CustomerWithdrewCash(_, balance) -> BankAccount(balance:)
    _, _ -> panic
  }
}
```

### Snapshot Configuration

```Gleam
// Enable snapshots every 100 events
let event_sourcing = 
  eventsourcing.new(mem_store, [query])
  |> eventsourcing.with_snapshots(eventsourcing.SnapshotConfig(100))

// Load latest snapshot if available
let assert Ok(maybe_snapshot) = eventsourcing.get_latest_snapshot(
  event_sourcing,
  "account-123"
)
```

### Usage

```gleam
import eventsourcing
import eventsourcing/memory_store

pub fn main() {
  let query = fn(aggregate_id, events) {
    io.println_error(
      "Aggregate Bank Account with ID: "
      <> aggregate_id
      <> " committed "
      <> events |> list.length |> int.to_string
      <> " events.",
    )
  }
  
  // Create the event sourcing system with query actors
  let assert Ok(store) = memory_store.new()
  let event_sourcing = 
    eventsourcing.new(
      event_store: store,
      queries: [query],  // Automatically spawns query actors
      handle: handle,
      apply: apply,
      empty_state: UnopenedBankAccount,
    )
    
  // Execute commands
  case eventsourcing.execute(
    event_sourcing,
    "account-123",
    OpenAccount("account-123"),
    timeout_ms: 5000,
  ) {
    Ok(updated_eventsourcing) -> {
      io.println("Account created successfully")
    }
    Error(eventsourcing.DomainError(domain_error)) -> {
      io.println("Domain validation failed: " <> debug(domain_error))
    }
    Error(eventsourcing.EventStoreError(msg)) -> {
      io.println("EventStore error: " <> msg)
    }
    Error(eventsourcing.EntityNotFound) -> {
      io.println("Aggregate not found")
    }
  }
}
```


### Error Handling

The library now provides comprehensive error handling through the
EventSourcingError type:

```Gleam
pub type EventSourcingError(domainerror) {
  DomainError(domainerror)
  EventStoreError(String)
  EntityNotFound
}
```

All operations that might fail return a Result type, making
error handling explicit and type-safe.


## Philosophy

Eventsourcing embraces the actor model and OTP principles to build robust, concurrent event-sourced systems. The library encourages:

- **Clear Separation**: Command handling, event application, and query processing are distinct concerns
- **Concurrent Query Processing**: Queries run in separate actor processes for non-blocking event processing
- **Fault Isolation**: Query actor crashes don't affect command processing or other queries
- **Simplicity**: Focused on core event sourcing functionality without unnecessary complexity
- **Type Safety**: Full Gleam type safety throughout the event sourcing pipeline

This design makes your event-sourced systems naturally concurrent and fault-tolerant while maintaining simplicity and type safety.

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
