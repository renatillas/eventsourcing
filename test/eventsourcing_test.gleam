import birdie
import eventsourcing
import example_bank_account
import gleam/option.{None, Some}
import gleeunit
import gleeunit/should
import inmemory as memory_store
import pprint

pub fn main() {
  gleeunit.main()
}

pub fn execute_test() {
  let event_sourcing =
    eventsourcing.new(
      memory_store.new(),
      [],
      example_bank_account.handle,
      example_bank_account.apply,
      example_bank_account.UnopenedBankAccount,
    )
  eventsourcing.execute(
    event_sourcing,
    "92085b42-032c-4d7a-84de-a86d67123858",
    example_bank_account.OpenAccount("92085b42-032c-4d7a-84de-a86d67123858"),
  )
  |> should.be_ok
  |> should.equal(Nil)
}

pub fn query_test() {
  let query = fn(aggregate_id, events) {
    #(aggregate_id, events)
    |> pprint.format
    |> birdie.snap(title: "query event")
  }
  let event_sourcing =
    eventsourcing.new(
      memory_store.new(),
      [query],
      example_bank_account.handle,
      example_bank_account.apply,
      example_bank_account.UnopenedBankAccount,
    )
  eventsourcing.execute(
    event_sourcing,
    "92085b42-032c-4d7a-84de-a86d67123858",
    example_bank_account.OpenAccount("92085b42-032c-4d7a-84de-a86d67123858"),
  )
  |> should.be_ok
  |> should.equal(Nil)
}

pub fn load_events_test() {
  let event_sourcing =
    eventsourcing.new(
      memory_store.new(),
      [],
      example_bank_account.handle,
      example_bank_account.apply,
      example_bank_account.UnopenedBankAccount,
    )
  eventsourcing.execute(
    event_sourcing,
    "92085b42-032c-4d7a-84de-a86d67123858",
    example_bank_account.OpenAccount("92085b42-032c-4d7a-84de-a86d67123858"),
  )
  |> should.be_ok
  |> should.equal(Nil)

  eventsourcing.execute(
    event_sourcing,
    "92085b42-032c-4d7a-84de-a86d67123858",
    example_bank_account.DepositMoney(10.0),
  )
  |> should.be_ok
  |> should.equal(Nil)

  eventsourcing.execute(
    event_sourcing,
    "92085b42-032c-4d7a-84de-a86d67123858",
    example_bank_account.WithDrawMoney(5.99),
  )
  |> should.be_ok
  |> should.equal(Nil)

  eventsourcing.load_events(
    event_sourcing,
    "92085b42-032c-4d7a-84de-a86d67123858",
  )
  |> pprint.format
  |> birdie.snap(title: "load 3 events: open, deposit, withdraw")
}

pub fn load_events_with_metadata_test() {
  let event_sourcing =
    eventsourcing.new(
      memory_store.new(),
      [],
      example_bank_account.handle,
      example_bank_account.apply,
      example_bank_account.UnopenedBankAccount,
    )
  eventsourcing.execute_with_metadata(
    event_sourcing,
    "92085b42-032c-4d7a-84de-a86d67123858",
    example_bank_account.OpenAccount("92085b42-032c-4d7a-84de-a86d67123858"),
    [#("Hello", "World"), #("Fizz", "Buzz")],
  )
  |> should.be_ok
  |> should.equal(Nil)

  eventsourcing.load_events(
    event_sourcing,
    "92085b42-032c-4d7a-84de-a86d67123858",
  )
  |> pprint.format
  |> birdie.snap(title: "load event with metadata")
}

pub fn load_events_emtpy_aggregate_test() {
  let event_sourcing =
    eventsourcing.new(
      memory_store.new(),
      [],
      example_bank_account.handle,
      example_bank_account.apply,
      example_bank_account.UnopenedBankAccount,
    )
  eventsourcing.load_events(
    event_sourcing,
    "92085b42-032c-4d7a-84de-a86d67123858",
  )
  |> pprint.format
  |> birdie.snap(title: "load events empty aggregate return empty list")
}

pub fn load_aggregate_test() {
  let event_sourcing =
    eventsourcing.new(
      memory_store.new(),
      [],
      example_bank_account.handle,
      example_bank_account.apply,
      example_bank_account.UnopenedBankAccount,
    )
  eventsourcing.execute(
    event_sourcing,
    "92085b42-032c-4d7a-84de-a86d67123858",
    example_bank_account.OpenAccount("92085b42-032c-4d7a-84de-a86d67123858"),
  )
  |> should.be_ok
  |> should.equal(Nil)

  eventsourcing.execute(
    event_sourcing,
    "92085b42-032c-4d7a-84de-a86d67123858",
    example_bank_account.DepositMoney(10.0),
  )
  |> should.be_ok
  |> should.equal(Nil)

  eventsourcing.execute(
    event_sourcing,
    "92085b42-032c-4d7a-84de-a86d67123858",
    example_bank_account.WithDrawMoney(5.99),
  )
  |> should.be_ok
  |> should.equal(Nil)

  eventsourcing.load_aggregate(
    event_sourcing,
    "92085b42-032c-4d7a-84de-a86d67123858",
  )
  |> pprint.format
  |> birdie.snap(title: "load aggregate")
}

pub fn load_emtpy_aggregate_test() {
  let event_sourcing =
    eventsourcing.new(
      memory_store.new(),
      [],
      example_bank_account.handle,
      example_bank_account.apply,
      example_bank_account.UnopenedBankAccount,
    )
  eventsourcing.load_aggregate(
    event_sourcing,
    "92085b42-032c-4d7a-84de-a86d67123858",
  )
  |> pprint.format
  |> birdie.snap(title: "load aggregate not found raises error EntityNotFound")
}

pub fn load_emtpy_aggregate_with_snapshots_test() {
  let event_sourcing =
    eventsourcing.new(
      memory_store.new(),
      [],
      example_bank_account.handle,
      example_bank_account.apply,
      example_bank_account.UnopenedBankAccount,
    )
    |> eventsourcing.with_snapshots(eventsourcing.SnapshotConfig(2))

  eventsourcing.execute(
    event_sourcing,
    "92085b42-032c-4d7a-84de-a86d67123858",
    example_bank_account.OpenAccount("92085b42-032c-4d7a-84de-a86d67123858"),
  )
  |> should.be_ok
  |> should.equal(Nil)

  eventsourcing.execute(
    event_sourcing,
    "92085b42-032c-4d7a-84de-a86d67123858",
    example_bank_account.DepositMoney(10.0),
  )
  |> should.be_ok
  |> should.equal(Nil)

  eventsourcing.load_aggregate(
    event_sourcing,
    "92085b42-032c-4d7a-84de-a86d67123858",
  )
  |> pprint.format
  |> birdie.snap(title: "load aggregate entity with snapshots")
}

// Test creating and loading a snapshot after a specific number of events
pub fn snapshot_creation_test() {
  let event_sourcing =
    eventsourcing.new(
      memory_store.new(),
      [],
      example_bank_account.handle,
      example_bank_account.apply,
      example_bank_account.UnopenedBankAccount,
    )
    |> eventsourcing.with_snapshots(eventsourcing.SnapshotConfig(2))
  // Snapshot every 2 events

  let account_id = "92085b42-032c-4d7a-84de-a86d67123858"

  // Open account (1st event)
  eventsourcing.execute(
    event_sourcing,
    account_id,
    example_bank_account.OpenAccount(account_id),
  )
  |> should.be_ok

  // Check no snapshot yet
  eventsourcing.get_latest_snapshot(event_sourcing, account_id)
  |> should.be_ok
  |> should.equal(None)

  // Deposit money (2nd event - should trigger snapshot)
  eventsourcing.execute(
    event_sourcing,
    account_id,
    example_bank_account.DepositMoney(100.0),
  )
  |> should.be_ok

  // Check snapshot exists and has correct state
  eventsourcing.get_latest_snapshot(event_sourcing, account_id)
  |> should.be_ok
  |> fn(result) {
    case result {
      Some(snapshot) -> {
        snapshot.sequence |> should.equal(2)
        snapshot.entity |> should.equal(example_bank_account.BankAccount(100.0))
      }
      None -> panic as "Expected snapshot but got None"
    }
  }
}

// Test rebuilding aggregate from snapshot and subsequent events
pub fn rebuild_from_snapshot_test() {
  let event_sourcing =
    eventsourcing.new(
      memory_store.new(),
      [],
      example_bank_account.handle,
      example_bank_account.apply,
      example_bank_account.UnopenedBankAccount,
    )
    |> eventsourcing.with_snapshots(eventsourcing.SnapshotConfig(2))

  let account_id = "92085b42-032c-4d7a-84de-a86d67123858"

  // Create initial events
  eventsourcing.execute(
    event_sourcing,
    account_id,
    example_bank_account.OpenAccount(account_id),
  )
  |> should.be_ok
  eventsourcing.execute(
    event_sourcing,
    account_id,
    example_bank_account.DepositMoney(100.0),
  )
  |> should.be_ok
  // Should create snapshot

  // Add more events after snapshot
  eventsourcing.execute(
    event_sourcing,
    account_id,
    example_bank_account.WithDrawMoney(30.0),
  )
  |> should.be_ok

  // Load aggregate and verify state
  eventsourcing.load_aggregate(event_sourcing, account_id)
  |> should.be_ok
  |> fn(aggregate) {
    case aggregate.entity {
      example_bank_account.BankAccount(balance) -> balance |> should.equal(70.0)
      _ -> panic as "Unexpected aggregate state"
    }
  }
}

// Test snapshot frequency
pub fn snapshot_frequency_test() {
  let event_sourcing =
    eventsourcing.new(
      memory_store.new(),
      [],
      example_bank_account.handle,
      example_bank_account.apply,
      example_bank_account.UnopenedBankAccount,
    )
    |> eventsourcing.with_snapshots(eventsourcing.SnapshotConfig(3))
  // Snapshot every 3 events

  let account_id = "92085b42-032c-4d7a-84de-a86d67123858"

  // Execute 5 events
  eventsourcing.execute(
    event_sourcing,
    account_id,
    example_bank_account.OpenAccount(account_id),
  )
  |> should.be_ok
  eventsourcing.execute(
    event_sourcing,
    account_id,
    example_bank_account.DepositMoney(100.0),
  )
  |> should.be_ok
  eventsourcing.execute(
    event_sourcing,
    account_id,
    example_bank_account.WithDrawMoney(20.0),
  )
  |> should.be_ok
  // Should create first snapshot
  eventsourcing.execute(
    event_sourcing,
    account_id,
    example_bank_account.DepositMoney(50.0),
  )
  |> should.be_ok
  eventsourcing.execute(
    event_sourcing,
    account_id,
    example_bank_account.WithDrawMoney(10.0),
  )
  |> should.be_ok

  // Verify snapshot sequence is correct (should be at event 3)
  eventsourcing.get_latest_snapshot(event_sourcing, account_id)
  |> should.be_ok
  |> fn(result) {
    case result {
      Some(snapshot) -> {
        snapshot.sequence |> should.equal(3)
        case snapshot.entity {
          example_bank_account.BankAccount(balance) ->
            balance |> should.equal(80.0)
          _ -> panic as "Unexpected snapshot state"
        }
      }
      None -> panic as "Expected snapshot but got None"
    }
  }
}

// Test multiple aggregates with snapshots
pub fn multiple_aggregates_snapshot_test() {
  let event_sourcing =
    eventsourcing.new(
      memory_store.new(),
      [],
      example_bank_account.handle,
      example_bank_account.apply,
      example_bank_account.UnopenedBankAccount,
    )
    |> eventsourcing.with_snapshots(eventsourcing.SnapshotConfig(2))

  let account1_id = "account-1"
  let account2_id = "account-2"

  // Create events for first account
  eventsourcing.execute(
    event_sourcing,
    account1_id,
    example_bank_account.OpenAccount(account1_id),
  )
  |> should.be_ok
  eventsourcing.execute(
    event_sourcing,
    account1_id,
    example_bank_account.DepositMoney(100.0),
  )
  |> should.be_ok
  // Should create snapshot for account1

  // Create events for second account
  eventsourcing.execute(
    event_sourcing,
    account2_id,
    example_bank_account.OpenAccount(account2_id),
  )
  |> should.be_ok
  eventsourcing.execute(
    event_sourcing,
    account2_id,
    example_bank_account.DepositMoney(200.0),
  )
  |> should.be_ok
  // Should create snapshot for account2

  // Verify both accounts have correct snapshots
  eventsourcing.get_latest_snapshot(event_sourcing, account1_id)
  |> should.be_ok
  |> fn(result) {
    case result {
      Some(snapshot) -> {
        case snapshot.entity {
          example_bank_account.BankAccount(balance) ->
            balance |> should.equal(100.0)
          _ -> panic as "Unexpected snapshot state for account1"
        }
      }
      None -> panic as "Expected snapshot for account1 but got None"
    }
  }

  eventsourcing.get_latest_snapshot(event_sourcing, account2_id)
  |> should.be_ok
  |> fn(result) {
    case result {
      Some(snapshot) -> {
        case snapshot.entity {
          example_bank_account.BankAccount(balance) ->
            balance |> should.equal(200.0)
          _ -> panic as "Unexpected snapshot state for account2"
        }
      }
      None -> panic as "Expected snapshot for account2 but got None"
    }
  }
}

// Test disabling snapshots
pub fn disable_snapshots_test() {
  let event_sourcing =
    eventsourcing.new(
      memory_store.new(),
      [],
      example_bank_account.handle,
      example_bank_account.apply,
      example_bank_account.UnopenedBankAccount,
    )
  // Don't call with_snapshots

  let account_id = "92085b42-032c-4d7a-84de-a86d67123858"

  // Execute some events
  eventsourcing.execute(
    event_sourcing,
    account_id,
    example_bank_account.OpenAccount(account_id),
  )
  |> should.be_ok
  eventsourcing.execute(
    event_sourcing,
    account_id,
    example_bank_account.DepositMoney(100.0),
  )
  |> should.be_ok

  // Verify no snapshots were created
  eventsourcing.get_latest_snapshot(event_sourcing, account_id)
  |> should.be_ok
  |> should.equal(None)
}

pub fn handle_invalid_command_test() {
  let event_sourcing =
    eventsourcing.new(
      memory_store.new(),
      [],
      example_bank_account.handle,
      example_bank_account.apply,
      example_bank_account.UnopenedBankAccount,
    )

  // Test withdrawing from unopened account
  eventsourcing.execute(
    event_sourcing,
    "test-account",
    example_bank_account.WithDrawMoney(100.0),
  )
  |> should.be_error
  |> should.equal(eventsourcing.DomainError(
    example_bank_account.CantOperateOnUnopenedAccount,
  ))
}

pub fn invalid_deposit_amount_test() {
  let event_sourcing =
    eventsourcing.new(
      memory_store.new(),
      [],
      example_bank_account.handle,
      example_bank_account.apply,
      example_bank_account.UnopenedBankAccount,
    )

  eventsourcing.execute(
    event_sourcing,
    "test-account",
    example_bank_account.OpenAccount("test-account"),
  )
  |> should.be_ok

  eventsourcing.execute(
    event_sourcing,
    "test-account",
    example_bank_account.DepositMoney(-50.0),
  )
  |> should.be_error
  |> should.equal(eventsourcing.DomainError(
    example_bank_account.CantDepositNegativeAmount,
  ))
}

pub fn zero_snapshot_interval_test() {
  let event_sourcing =
    eventsourcing.new(
      memory_store.new(),
      [],
      example_bank_account.handle,
      example_bank_account.apply,
      example_bank_account.UnopenedBankAccount,
    )
    |> eventsourcing.with_snapshots(eventsourcing.SnapshotConfig(0))

  let account_id = "zero-interval-test"

  // Create some events
  eventsourcing.execute(
    event_sourcing,
    account_id,
    example_bank_account.OpenAccount(account_id),
  )
  |> should.be_ok

  eventsourcing.execute(
    event_sourcing,
    account_id,
    example_bank_account.DepositMoney(100.0),
  )
  |> should.be_ok

  // Verify no snapshot was created despite events
  eventsourcing.get_latest_snapshot(event_sourcing, account_id)
  |> should.be_ok
  |> should.equal(None)
}

// Test snapshot behavior with large intervals
pub fn large_snapshot_interval_test() {
  let event_sourcing =
    eventsourcing.new(
      memory_store.new(),
      [],
      example_bank_account.handle,
      example_bank_account.apply,
      example_bank_account.UnopenedBankAccount,
    )
    |> eventsourcing.with_snapshots(eventsourcing.SnapshotConfig(1000))

  let account_id = "large-interval-test"

  // Create multiple events but less than snapshot interval
  eventsourcing.execute(
    event_sourcing,
    account_id,
    example_bank_account.OpenAccount(account_id),
  )
  |> should.be_ok

  eventsourcing.execute(
    event_sourcing,
    account_id,
    example_bank_account.DepositMoney(100.0),
  )
  |> should.be_ok

  // Verify no snapshot was created as we haven't reached the interval
  eventsourcing.get_latest_snapshot(event_sourcing, account_id)
  |> should.be_ok
  |> should.equal(None)
}

// Test snapshot with empty events list
pub fn snapshot_empty_events_test() {
  let event_sourcing =
    eventsourcing.new(
      memory_store.new(),
      [],
      example_bank_account.handle,
      example_bank_account.apply,
      example_bank_account.UnopenedBankAccount,
    )
    |> eventsourcing.with_snapshots(eventsourcing.SnapshotConfig(1))

  let account_id = "empty-events-test"

  // Try to load snapshot for non-existent aggregate
  eventsourcing.get_latest_snapshot(event_sourcing, account_id)
  |> should.be_ok
  |> should.equal(None)

  // Load aggregate with no events
  eventsourcing.load_aggregate(event_sourcing, account_id)
  |> should.be_error()
  |> should.equal(eventsourcing.EntityNotFound)
}

// Test snapshot recovery after failures
pub fn snapshot_recovery_test() {
  let event_sourcing =
    eventsourcing.new(
      memory_store.new(),
      [],
      example_bank_account.handle,
      example_bank_account.apply,
      example_bank_account.UnopenedBankAccount,
    )
    |> eventsourcing.with_snapshots(eventsourcing.SnapshotConfig(2))

  let account_id = "recovery-test"

  // Create initial state
  eventsourcing.execute(
    event_sourcing,
    account_id,
    example_bank_account.OpenAccount(account_id),
  )
  |> should.be_ok

  eventsourcing.execute(
    event_sourcing,
    account_id,
    example_bank_account.DepositMoney(100.0),
  )
  |> should.be_ok

  // Verify initial snapshot
  let initial_snapshot =
    eventsourcing.get_latest_snapshot(event_sourcing, account_id)
    |> should.be_ok
    |> fn(result) {
      case result {
        Some(snapshot) -> snapshot
        None -> panic as "Expected initial snapshot"
      }
    }

  // Add more events
  eventsourcing.execute(
    event_sourcing,
    account_id,
    example_bank_account.WithDrawMoney(30.0),
  )
  |> should.be_ok

  eventsourcing.execute(
    event_sourcing,
    account_id,
    example_bank_account.DepositMoney(50.0),
  )
  |> should.be_ok

  // Verify new snapshot was created and is different from initial
  let new_snapshot =
    eventsourcing.get_latest_snapshot(event_sourcing, account_id)
    |> should.be_ok
    |> fn(result) {
      case result {
        Some(snapshot) -> snapshot
        None -> panic as "Expected new snapshot"
      }
    }

  should.be_true(new_snapshot.sequence > initial_snapshot.sequence)
}

// Test concurrent snapshot operations
pub fn concurrent_snapshot_test() {
  let event_sourcing =
    eventsourcing.new(
      memory_store.new(),
      [],
      example_bank_account.handle,
      example_bank_account.apply,
      example_bank_account.UnopenedBankAccount,
    )
    |> eventsourcing.with_snapshots(eventsourcing.SnapshotConfig(2))

  let account1_id = "concurrent-1"
  let account2_id = "concurrent-2"

  // Create concurrent events for both accounts
  eventsourcing.execute(
    event_sourcing,
    account1_id,
    example_bank_account.OpenAccount(account1_id),
  )
  |> should.be_ok

  eventsourcing.execute(
    event_sourcing,
    account2_id,
    example_bank_account.OpenAccount(account2_id),
  )
  |> should.be_ok

  eventsourcing.execute(
    event_sourcing,
    account1_id,
    example_bank_account.DepositMoney(100.0),
  )
  |> should.be_ok

  eventsourcing.execute(
    event_sourcing,
    account2_id,
    example_bank_account.DepositMoney(200.0),
  )
  |> should.be_ok

  // Verify snapshots are independent and correct
  eventsourcing.get_latest_snapshot(event_sourcing, account1_id)
  |> should.be_ok
  |> fn(result) {
    case result {
      Some(snapshot) -> {
        case snapshot.entity {
          example_bank_account.BankAccount(balance) ->
            balance |> should.equal(100.0)
          _ -> panic as "Unexpected snapshot state for account1"
        }
      }
      None -> panic as "Expected snapshot for account1"
    }
  }

  eventsourcing.get_latest_snapshot(event_sourcing, account2_id)
  |> should.be_ok
  |> fn(result) {
    case result {
      Some(snapshot) -> {
        case snapshot.entity {
          example_bank_account.BankAccount(balance) ->
            balance |> should.equal(200.0)
          _ -> panic as "Unexpected snapshot state for account2"
        }
      }
      None -> panic as "Expected snapshot for account2"
    }
  }
}
