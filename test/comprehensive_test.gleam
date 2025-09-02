import eventsourcing
import eventsourcing/memory_store
import example_bank_account
import gleam/erlang/process
import gleam/int
import gleam/list
import gleam/option.{None}
import gleam/otp/static_supervisor
import gleeunit

pub fn main() {
  gleeunit.main()
}

pub fn basic_command_execution_test() {
  let assert Ok(memory_store) = memory_store.new()

  let query_results = process.new_subject()
  let queries = [
    fn(aggregate_id, events) {
      process.send(query_results, #(aggregate_id, list.length(events)))
    },
  ]

  let eventsourcing_actor_receiver = process.new_subject()
  let query_actors_receiver = process.new_subject()
  let assert Ok(eventsourcing_spec) =
    eventsourcing.supervised(
      memory_store,
      handle: example_bank_account.handle,
      apply: example_bank_account.apply,
      empty_state: example_bank_account.UnopenedBankAccount,
      queries:,
      eventsourcing_actor_receiver:,
      query_actors_receiver:,
    )

  let assert Ok(_supervisor) =
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.add(eventsourcing_spec)
    |> static_supervisor.start()

  let assert Ok(eventsourcing_actor) =
    process.receive(eventsourcing_actor_receiver, 2000)

  let assert Ok(query_actors) =
    list.try_map(queries, fn(_) { process.receive(query_actors_receiver, 1000) })

  eventsourcing.register_queries(eventsourcing_actor.data, query_actors)
  process.sleep(100)

  // Open account
  eventsourcing.execute(
    eventsourcing_actor,
    "test-001",
    example_bank_account.OpenAccount("test-001"),
  )
  let assert Ok(#("test-001", 1)) = process.receive(query_results, 1000)

  // Deposit money
  eventsourcing.execute(
    eventsourcing_actor,
    "test-001",
    example_bank_account.DepositMoney(100.0),
  )
  let assert Ok(#("test-001", 1)) = process.receive(query_results, 1000)

  // Withdraw money
  eventsourcing.execute(
    eventsourcing_actor,
    "test-001",
    example_bank_account.WithDrawMoney(50.0),
  )
  let assert Ok(#("test-001", 1)) = process.receive(query_results, 1000)
}

pub fn aggregate_loading_test() {
  let assert Ok(memory_store) = memory_store.new()
  let assert Ok(eventsourcing) =
    eventsourcing.new(
      memory_store,
      queries: [],
      handle: example_bank_account.handle,
      apply: example_bank_account.apply,
      empty_state: example_bank_account.UnopenedBankAccount,
    )

  // Try to load non-existent aggregate
  let assert Error(eventsourcing.EntityNotFound) =
    eventsourcing.load_aggregate(eventsourcing, "nonexistent")

  // Execute commands to create aggregate
  let eventsourcing_actor_receiver = process.new_subject()
  let query_actors_receiver = process.new_subject()
  let assert Ok(eventsourcing_spec) =
    eventsourcing.supervised(
      memory_store,
      handle: example_bank_account.handle,
      apply: example_bank_account.apply,
      empty_state: example_bank_account.UnopenedBankAccount,
      queries: [],
      eventsourcing_actor_receiver:,
      query_actors_receiver:,
    )

  let assert Ok(_supervisor) =
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.add(eventsourcing_spec)
    |> static_supervisor.start()

  let assert Ok(eventsourcing_actor) =
    process.receive(eventsourcing_actor_receiver, 2000)

  // Create aggregate
  eventsourcing.execute(
    eventsourcing_actor,
    "load-test",
    example_bank_account.OpenAccount("load-test"),
  )
  process.sleep(100)

  // Now load should work
  let assert Ok(aggregate) =
    eventsourcing.load_aggregate(eventsourcing, "load-test")
  assert aggregate.aggregate_id == "load-test"
  assert aggregate.sequence == 1
  case aggregate.entity {
    example_bank_account.BankAccount(balance) -> {
      assert balance == 0.0
    }
    _ -> panic as "Expected BankAccount"
  }
}

pub fn event_loading_test() {
  let assert Ok(memory_store) = memory_store.new()
  let eventsourcing_actor_receiver = process.new_subject()
  let query_actors_receiver = process.new_subject()
  let assert Ok(eventsourcing_spec) =
    eventsourcing.supervised(
      memory_store,
      handle: example_bank_account.handle,
      apply: example_bank_account.apply,
      empty_state: example_bank_account.UnopenedBankAccount,
      queries: [],
      eventsourcing_actor_receiver:,
      query_actors_receiver:,
    )

  let assert Ok(_supervisor) =
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.add(eventsourcing_spec)
    |> static_supervisor.start()

  let assert Ok(eventsourcing_actor) =
    process.receive(eventsourcing_actor_receiver, 2000)

  let assert Ok(eventsourcing) =
    eventsourcing.new(
      memory_store,
      queries: [],
      handle: example_bank_account.handle,
      apply: example_bank_account.apply,
      empty_state: example_bank_account.UnopenedBankAccount,
    )

  // Create multiple events
  eventsourcing.execute(
    eventsourcing_actor,
    "events-test",
    example_bank_account.OpenAccount("events-test"),
  )
  eventsourcing.execute(
    eventsourcing_actor,
    "events-test",
    example_bank_account.DepositMoney(100.0),
  )
  eventsourcing.execute(
    eventsourcing_actor,
    "events-test",
    example_bank_account.DepositMoney(50.0),
  )
  process.sleep(200)

  // Load all events
  let assert Ok(all_events) =
    eventsourcing.load_events(eventsourcing, "events-test")
  assert list.length(all_events) == 3

  // Load events from sequence 2 (drops first 2, leaves 1)
  let assert Ok(partial_events) =
    eventsourcing.load_events_from(eventsourcing, "events-test", 2)
  assert list.length(partial_events) == 1

  // Load events from non-existent aggregate
  let assert Ok(empty_events) =
    eventsourcing.load_events(eventsourcing, "nonexistent")
  assert empty_events == []
}

pub fn snapshot_functionality_test() {
  let assert Ok(memory_store) = memory_store.new()
  let assert Ok(eventsourcing) =
    eventsourcing.new(
      memory_store,
      queries: [],
      handle: example_bank_account.handle,
      apply: example_bank_account.apply,
      empty_state: example_bank_account.UnopenedBankAccount,
    )

  // Test snapshot frequency validation
  let assert Ok(frequency) = eventsourcing.frequency(3)
  let assert Error(eventsourcing.NonPositiveArgument) =
    eventsourcing.frequency(0)
  let assert Error(eventsourcing.NonPositiveArgument) =
    eventsourcing.frequency(-1)

  // Enable snapshots
  let snapshot_config = eventsourcing.SnapshotConfig(frequency)
  let assert Ok(eventsourcing_with_snapshots) =
    eventsourcing.with_snapshots(eventsourcing, snapshot_config)

  // Test no snapshot initially
  let assert Ok(None) =
    eventsourcing.get_latest_snapshot(eventsourcing_with_snapshots, "snap-test")

  // Execute supervised commands to trigger snapshots
  let eventsourcing_actor_receiver = process.new_subject()
  let query_actors_receiver = process.new_subject()
  let assert Ok(eventsourcing_spec) =
    eventsourcing.supervised(
      memory_store,
      handle: example_bank_account.handle,
      apply: example_bank_account.apply,
      empty_state: example_bank_account.UnopenedBankAccount,
      queries: [],
      eventsourcing_actor_receiver:,
      query_actors_receiver:,
    )

  let assert Ok(_supervisor) =
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.add(eventsourcing_spec)
    |> static_supervisor.start()

  let assert Ok(eventsourcing_actor) =
    process.receive(eventsourcing_actor_receiver, 2000)

  // Execute 3 commands to trigger snapshot
  eventsourcing.execute(
    eventsourcing_actor,
    "snap-test",
    example_bank_account.OpenAccount("snap-test"),
  )
  eventsourcing.execute(
    eventsourcing_actor,
    "snap-test",
    example_bank_account.DepositMoney(100.0),
  )
  eventsourcing.execute(
    eventsourcing_actor,
    "snap-test",
    example_bank_account.DepositMoney(50.0),
  )
  process.sleep(200)
}

pub fn multiple_query_actors_test() {
  let assert Ok(memory_store) = memory_store.new()

  let query1_results = process.new_subject()
  let query2_results = process.new_subject()
  let query3_results = process.new_subject()

  let queries = [
    fn(aggregate_id, events) {
      process.send(query1_results, #(
        "query1",
        aggregate_id,
        list.length(events),
      ))
    },
    fn(aggregate_id, events) {
      process.send(query2_results, #(
        "query2",
        aggregate_id,
        list.length(events),
      ))
    },
    fn(aggregate_id, events) {
      process.send(query3_results, #(
        "query3",
        aggregate_id,
        list.length(events),
      ))
    },
  ]

  let eventsourcing_actor_receiver = process.new_subject()
  let query_actors_receiver = process.new_subject()
  let assert Ok(eventsourcing_spec) =
    eventsourcing.supervised(
      memory_store,
      handle: example_bank_account.handle,
      apply: example_bank_account.apply,
      empty_state: example_bank_account.UnopenedBankAccount,
      queries:,
      eventsourcing_actor_receiver:,
      query_actors_receiver:,
    )

  let assert Ok(_supervisor) =
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.add(eventsourcing_spec)
    |> static_supervisor.start()

  let assert Ok(eventsourcing_actor) =
    process.receive(eventsourcing_actor_receiver, 2000)

  let assert Ok(query_actors) =
    list.try_map(queries, fn(_) { process.receive(query_actors_receiver, 1000) })

  eventsourcing.register_queries(eventsourcing_actor.data, query_actors)
  process.sleep(100)

  // Execute command
  eventsourcing.execute(
    eventsourcing_actor,
    "multi-query",
    example_bank_account.OpenAccount("multi-query"),
  )

  // All queries should receive the event
  let assert Ok(#("query1", "multi-query", 1)) =
    process.receive(query1_results, 1000)
  let assert Ok(#("query2", "multi-query", 1)) =
    process.receive(query2_results, 1000)
  let assert Ok(#("query3", "multi-query", 1)) =
    process.receive(query3_results, 1000)
}

pub fn error_handling_test() {
  let assert Ok(memory_store) = memory_store.new()
  let eventsourcing_actor_receiver = process.new_subject()
  let query_actors_receiver = process.new_subject()
  let assert Ok(eventsourcing_spec) =
    eventsourcing.supervised(
      memory_store,
      handle: example_bank_account.handle,
      apply: example_bank_account.apply,
      empty_state: example_bank_account.UnopenedBankAccount,
      queries: [],
      eventsourcing_actor_receiver:,
      query_actors_receiver:,
    )

  let assert Ok(_supervisor) =
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.add(eventsourcing_spec)
    |> static_supervisor.start()

  let assert Ok(eventsourcing_actor) =
    process.receive(eventsourcing_actor_receiver, 2000)

  // Test domain error - try to withdraw from unopened account
  eventsourcing.execute(
    eventsourcing_actor,
    "error-test",
    example_bank_account.WithDrawMoney(50.0),
  )

  // Test domain error - try to deposit negative amount
  eventsourcing.execute(
    eventsourcing_actor,
    "error-test2",
    example_bank_account.OpenAccount("error-test2"),
  )
  process.sleep(100)

  eventsourcing.execute(
    eventsourcing_actor,
    "error-test2",
    example_bank_account.DepositMoney(-50.0),
  )

  // Test validation functions
  let assert Ok(_) = eventsourcing.timeout(1000)
  let assert Error(eventsourcing.NonPositiveArgument) = eventsourcing.timeout(0)
  let assert Error(eventsourcing.NonPositiveArgument) =
    eventsourcing.timeout(-1)

  let assert Ok(_) = eventsourcing.frequency(5)
  let assert Error(eventsourcing.NonPositiveArgument) =
    eventsourcing.frequency(0)
  let assert Error(eventsourcing.NonPositiveArgument) =
    eventsourcing.frequency(-5)
}

pub fn multiple_aggregates_test() {
  let assert Ok(memory_store) = memory_store.new()
  let query_results = process.new_subject()
  let queries = [
    fn(aggregate_id, events) {
      process.send(query_results, #(aggregate_id, list.length(events)))
    },
  ]

  let eventsourcing_actor_receiver = process.new_subject()
  let query_actors_receiver = process.new_subject()
  let assert Ok(eventsourcing_spec) =
    eventsourcing.supervised(
      memory_store,
      handle: example_bank_account.handle,
      apply: example_bank_account.apply,
      empty_state: example_bank_account.UnopenedBankAccount,
      queries:,
      eventsourcing_actor_receiver:,
      query_actors_receiver:,
    )

  let assert Ok(_supervisor) =
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.add(eventsourcing_spec)
    |> static_supervisor.start()

  let assert Ok(eventsourcing_actor) =
    process.receive(eventsourcing_actor_receiver, 2000)

  let assert Ok(query_actors) =
    list.try_map(queries, fn(_) { process.receive(query_actors_receiver, 1000) })

  eventsourcing.register_queries(eventsourcing_actor.data, query_actors)
  process.sleep(100)

  // Create multiple aggregates
  let aggregate_ids = ["acc-001", "acc-002", "acc-003", "acc-004", "acc-005"]

  list.each(aggregate_ids, fn(id) {
    eventsourcing.execute(
      eventsourcing_actor,
      id,
      example_bank_account.OpenAccount(id),
    )
  })

  // Verify all aggregates were created
  list.each(aggregate_ids, fn(id) {
    let assert Ok(#(received_id, 1)) = process.receive(query_results, 1000)
    assert received_id == id
  })

  // Perform operations on each aggregate
  list.each(aggregate_ids, fn(id) {
    eventsourcing.execute(
      eventsourcing_actor,
      id,
      example_bank_account.DepositMoney(100.0),
    )
  })

  // Verify all deposits
  list.each(aggregate_ids, fn(id) {
    let assert Ok(#(received_id, 1)) = process.receive(query_results, 1000)
    assert received_id == id
  })
}

pub fn complex_business_logic_test() {
  let assert Ok(memory_store) = memory_store.new()
  let eventsourcing_actor_receiver = process.new_subject()
  let query_actors_receiver = process.new_subject()
  let assert Ok(eventsourcing_spec) =
    eventsourcing.supervised(
      memory_store,
      handle: example_bank_account.handle,
      apply: example_bank_account.apply,
      empty_state: example_bank_account.UnopenedBankAccount,
      queries: [],
      eventsourcing_actor_receiver:,
      query_actors_receiver:,
    )

  let assert Ok(_supervisor) =
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.add(eventsourcing_spec)
    |> static_supervisor.start()

  let assert Ok(eventsourcing_actor) =
    process.receive(eventsourcing_actor_receiver, 2000)

  let assert Ok(eventsourcing) =
    eventsourcing.new(
      memory_store,
      queries: [],
      handle: example_bank_account.handle,
      apply: example_bank_account.apply,
      empty_state: example_bank_account.UnopenedBankAccount,
    )

  // Complex banking scenario
  eventsourcing.execute(
    eventsourcing_actor,
    "complex-001",
    example_bank_account.OpenAccount("complex-001"),
  )

  // Multiple deposits
  eventsourcing.execute(
    eventsourcing_actor,
    "complex-001",
    example_bank_account.DepositMoney(1000.0),
  )
  eventsourcing.execute(
    eventsourcing_actor,
    "complex-001",
    example_bank_account.DepositMoney(500.0),
  )
  eventsourcing.execute(
    eventsourcing_actor,
    "complex-001",
    example_bank_account.DepositMoney(250.0),
  )

  // Multiple withdrawals
  eventsourcing.execute(
    eventsourcing_actor,
    "complex-001",
    example_bank_account.WithDrawMoney(300.0),
  )
  eventsourcing.execute(
    eventsourcing_actor,
    "complex-001",
    example_bank_account.WithDrawMoney(200.0),
  )

  process.sleep(300)

  // Verify final state
  let assert Ok(aggregate) =
    eventsourcing.load_aggregate(eventsourcing, "complex-001")
  case aggregate.entity {
    example_bank_account.BankAccount(balance) -> {
      assert balance == 1250.0
    }
    _ -> panic as "Expected BankAccount with correct balance"
  }
  assert aggregate.sequence == 6

  // Verify all events
  let assert Ok(events) =
    eventsourcing.load_events(eventsourcing, "complex-001")
  assert list.length(events) == 6
}

pub fn concurrent_operations_test() {
  let assert Ok(memory_store) = memory_store.new()
  let query_counter = process.new_subject()
  let queries = [
    fn(_aggregate_id, events) {
      list.each(events, fn(_) { process.send(query_counter, 1) })
    },
  ]

  let eventsourcing_actor_receiver = process.new_subject()
  let query_actors_receiver = process.new_subject()
  let assert Ok(eventsourcing_spec) =
    eventsourcing.supervised(
      memory_store,
      handle: example_bank_account.handle,
      apply: example_bank_account.apply,
      empty_state: example_bank_account.UnopenedBankAccount,
      queries:,
      eventsourcing_actor_receiver:,
      query_actors_receiver:,
    )

  let assert Ok(_supervisor) =
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.add(eventsourcing_spec)
    |> static_supervisor.start()

  let assert Ok(eventsourcing_actor) =
    process.receive(eventsourcing_actor_receiver, 2000)

  let assert Ok(query_actors) =
    list.try_map(queries, fn(_) { process.receive(query_actors_receiver, 1000) })

  eventsourcing.register_queries(eventsourcing_actor.data, query_actors)
  process.sleep(100)

  list.range(1, 10)
  |> list.each(fn(i) {
    let id = "concurrent-" <> int.to_string(i)
    eventsourcing.execute(
      eventsourcing_actor,
      id,
      example_bank_account.OpenAccount(id),
    )
  })

  let event_count = count_events(query_counter, 0, 10)
  assert event_count == 10
}

fn count_events(
  subject: process.Subject(Int),
  current_count: Int,
  max_count: Int,
) -> Int {
  case current_count >= max_count {
    True -> current_count
    False -> {
      case process.receive(subject, 100) {
        Ok(_) -> count_events(subject, current_count + 1, max_count)
        Error(_) -> current_count
      }
    }
  }
}
