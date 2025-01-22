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
- [Features](#features)
- [Example](#example)
  - [Command Handling](#command-handling)
  - [Event Application](#event-application)
  - [Snapshot Configuration](#snapshot-configuration)
  - [Running the Example](#running-the-example)
- [Philosophy](#philosophy)
- [Installation](#installation)
- [Support](#support)
- [Contributing](#contributing)
- [License](#license)

## Introduction

Eventsourcing is a Gleam library designed to help developers build event-sourced systems. Event sourcing is a pattern where changes to the application's state are stored as a sequence of events. This library provides a simple, type-safe way to implement event sourcing in your Gleam applications.

## Features

- **Event Sourcing**: Build systems based on the event sourcing pattern.
- **Event Stores**: Supports multiple event store implementations:
  - [In-memory Store](https://github.com/renatillas/eventsourcing_inmemory): Simple in-memory event store for development and testing.
  - [Postgres Store](https://github.com/renatillas/eventsourcing_postgres): Event store implementation using PostgreSQL.
  - [SQLite Store](https://github.com/renatillas/eventsourcing_sqlite): Event store implementation using SQLite.
- **Command Handling**: Handle commands and produce events with robust error handling.
- **Event Application**: Apply events to update aggregates.
- **Snapshotting**: Optimize aggregate rebuilding with configurable snapshots.
- **Type-safe Error Handling**: Comprehensive error types and Result-based API.

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

### Running the Example

```gleam
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
  
  let event_sourcing = 
    eventsourcing.new(
      event_store: memory_store.new(),
      queries: [query],
      handle: handle,
      apply: apply,
      empty_state: UnopenedBankAccount,
    )
    
  case eventsourcing.execute(
    event_sourcing,
    "account-123",
    OpenAccount("account-123"),
  ) {
    Ok(_) -> io.println("Account created successfully")
    Error(error) -> io.println("Failed to create account: " <> debug(error))
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

Eventsourcing is designed to make building event-sourced systems easy and intuitive.
It encourages a clear separation between command handling and event application,
making your code more maintainable and testable.

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
