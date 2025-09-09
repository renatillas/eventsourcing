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

pub fn supervised_architecture_test() {
  let events_actor_name = process.new_name("events_actor")
  let snapshot_actor_name = process.new_name("snapshot_actor")
  let #(eventstore, child_spec) =
    memory_store.supervised(
      events_actor_name,
      snapshot_actor_name,
      static_supervisor.OneForOne,
    )

  let assert Ok(_) =
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.add(child_spec)
    |> static_supervisor.start()

  let query_executed_subject = process.new_subject()
  let queries = [
    #(process.new_name("query_actor"), fn(aggregate_id, events) {
      process.send(query_executed_subject, #(aggregate_id, list.length(events)))
    }),
  ]

  let name = process.new_name("eventsourcing_actor")
  let assert Ok(eventsourcing_spec) =
    eventsourcing.supervised(
      name:,
      eventstore:,
      handle: example_bank_account.handle,
      apply: example_bank_account.apply,
      empty_state: example_bank_account.UnopenedBankAccount,
      queries:,
      snapshot_config: None,
    )

  let assert Ok(supervisor) =
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.add(eventsourcing_spec)
    |> static_supervisor.start()

  let eventsourcing = process.named_subject(name)

  // Give time for actors to start
  process.sleep(100)

  // Test that the supervisor is alive and managing child processes
  assert process.is_alive(supervisor.pid)

  let Nil =
    eventsourcing.execute(
      eventsourcing,
      "acc-123",
      example_bank_account.OpenAccount("acc-123"),
    )

  assert process.receive(query_executed_subject, 1000) == Ok(#("acc-123", 1))
}

pub fn basic_command_execution_test() {
  let events_actor_name = process.new_name("events_actor")
  let snapshot_actor_name = process.new_name("snapshot_actor")
  let #(eventstore, child_spec) =
    memory_store.supervised(
      events_actor_name,
      snapshot_actor_name,
      static_supervisor.OneForOne,
    )

  let assert Ok(_) =
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.add(child_spec)
    |> static_supervisor.start()

  let query_results = process.new_subject()
  let queries = [
    #(process.new_name("basic-commands-query"), fn(aggregate_id, events) {
      process.send(query_results, #(aggregate_id, list.length(events)))
    }),
  ]

  let name = process.new_name("basic-commands-eventsourcing")
  let assert Ok(eventsourcing_spec) =
    eventsourcing.supervised(
      name:,
      eventstore:,
      handle: example_bank_account.handle,
      apply: example_bank_account.apply,
      empty_state: example_bank_account.UnopenedBankAccount,
      queries:,
      snapshot_config: None,
    )

  let assert Ok(_supervisor) =
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.add(eventsourcing_spec)
    |> static_supervisor.start()

  let eventsourcing = process.named_subject(name)

  process.sleep(100)

  // Open account
  eventsourcing.execute(
    eventsourcing,
    "test-001",
    example_bank_account.OpenAccount("test-001"),
  )
  let assert Ok(#("test-001", 1)) = process.receive(query_results, 1000)

  // Deposit money
  eventsourcing.execute(
    eventsourcing,
    "test-001",
    example_bank_account.DepositMoney(100.0),
  )
  let assert Ok(#("test-001", 1)) = process.receive(query_results, 1000)

  // Withdraw money
  eventsourcing.execute(
    eventsourcing,
    "test-001",
    example_bank_account.WithDrawMoney(50.0),
  )
  let assert Ok(#("test-001", 1)) = process.receive(query_results, 1000)
}

pub fn basic_command_execution_with_response_test() {
  let events_actor_name = process.new_name("events_actor")
  let snapshot_actor_name = process.new_name("snapshot_actor")
  let #(eventstore, child_spec) =
    memory_store.supervised(
      events_actor_name,
      snapshot_actor_name,
      static_supervisor.OneForOne,
    )

  let assert Ok(_) =
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.add(child_spec)
    |> static_supervisor.start()

  let query_results = process.new_subject()
  let queries = [
    #(process.new_name("basic-commands-query"), fn(aggregate_id, events) {
      process.send(query_results, #(aggregate_id, list.length(events)))
    }),
  ]

  let name = process.new_name("basic-commands-eventsourcing")
  let assert Ok(eventsourcing_spec) =
    eventsourcing.supervised(
      name:,
      eventstore:,
      handle: example_bank_account.handle,
      apply: example_bank_account.apply,
      empty_state: example_bank_account.UnopenedBankAccount,
      queries:,
      snapshot_config: None,
    )

  let assert Ok(_supervisor) =
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.add(eventsourcing_spec)
    |> static_supervisor.start()

  let eventsourcing = process.named_subject(name)

  process.sleep(100)

  // Open account
  let response =
    eventsourcing.execute_with_response(
      eventsourcing,
      "test-001",
      example_bank_account.OpenAccount("test-001"),
      [],
    )
  let assert Ok(Ok(Nil)) = process.receive(response, 1000)
  let assert Ok(#("test-001", 1)) = process.receive(query_results, 1000)

  // Deposit money
  eventsourcing.execute(
    eventsourcing,
    "test-001",
    example_bank_account.DepositMoney(100.0),
  )
  let assert Ok(#("test-001", 1)) = process.receive(query_results, 1000)

  // Withdraw money
  eventsourcing.execute(
    eventsourcing,
    "test-001",
    example_bank_account.WithDrawMoney(50.0),
  )
  let assert Ok(#("test-001", 1)) = process.receive(query_results, 1000)
}

pub fn aggregate_loading_test() {
  let events_actor_name = process.new_name("events_actor")
  let snapshot_actor_name = process.new_name("snapshot_actor")
  let #(eventstore, child_spec) =
    memory_store.supervised(
      events_actor_name,
      snapshot_actor_name,
      static_supervisor.OneForOne,
    )

  let assert Ok(_) =
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.add(child_spec)
    |> static_supervisor.start()

  let name = process.new_name("load-aggregate-eventsourcing")
  let assert Ok(eventsourcing_spec) =
    eventsourcing.supervised(
      name:,
      eventstore:,
      handle: example_bank_account.handle,
      apply: example_bank_account.apply,
      empty_state: example_bank_account.UnopenedBankAccount,
      queries: [],
      snapshot_config: None,
    )

  let assert Ok(_supervisor) =
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.add(eventsourcing_spec)
    |> static_supervisor.start()

  let eventsourcing = process.named_subject(name)

  // Try to load non-existent aggregate
  let load_subject = eventsourcing.load_aggregate(eventsourcing, "nonexistent")
  let assert Ok(Error(eventsourcing.EntityNotFound)) =
    process.receive(load_subject, 1000)

  // Create aggregate
  eventsourcing.execute(
    eventsourcing,
    "load-test",
    example_bank_account.OpenAccount("load-test"),
  )
  process.sleep(100)

  // Now load should work
  let load_subject2 = eventsourcing.load_aggregate(eventsourcing, "load-test")
  let assert Ok(Ok(aggregate)) = process.receive(load_subject2, 1000)
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
  let events_actor_name = process.new_name("events_actor")
  let snapshot_actor_name = process.new_name("snapshot_actor")
  let #(eventstore, child_spec) =
    memory_store.supervised(
      events_actor_name,
      snapshot_actor_name,
      static_supervisor.OneForOne,
    )

  let assert Ok(_) =
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.add(child_spec)
    |> static_supervisor.start()
  let name = process.new_name("load-events-eventsourcing")
  let assert Ok(eventsourcing_spec) =
    eventsourcing.supervised(
      name:,
      eventstore:,
      handle: example_bank_account.handle,
      apply: example_bank_account.apply,
      empty_state: example_bank_account.UnopenedBankAccount,
      queries: [],
      snapshot_config: None,
    )

  let assert Ok(_supervisor) =
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.add(eventsourcing_spec)
    |> static_supervisor.start()

  let eventsourcing = process.named_subject(name)

  eventsourcing.execute(
    eventsourcing,
    "events-test",
    example_bank_account.OpenAccount("events-test"),
  )
  eventsourcing.execute(
    eventsourcing,
    "events-test",
    example_bank_account.DepositMoney(100.0),
  )
  eventsourcing.execute(
    eventsourcing,
    "events-test",
    example_bank_account.DepositMoney(50.0),
  )
  process.sleep(200)

  // Load events from sequence 2 (drops first 2, leaves 1)
  let events_subject =
    eventsourcing.load_events_from(eventsourcing, "events-test", 2)
  let assert Ok(Ok(partial_events)) = process.receive(events_subject, 1000)
  assert list.length(partial_events) == 1

  // Load events from non-existent aggregate
  let empty_events_subject =
    eventsourcing.load_events_from(eventsourcing, "nonexistent", 0)
  let assert Ok(Ok(empty_events)) = process.receive(empty_events_subject, 1000)
  assert empty_events == []
}

pub fn snapshot_functionality_test() {
  let events_actor_name = process.new_name("events_actor")
  let snapshot_actor_name = process.new_name("snapshot_actor")
  let #(eventstore, child_spec) =
    memory_store.supervised(
      events_actor_name,
      snapshot_actor_name,
      static_supervisor.OneForOne,
    )

  let assert Ok(_) =
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.add(child_spec)
    |> static_supervisor.start()

  // Test snapshot frequency validation
  let assert Ok(frequency) = eventsourcing.frequency(3)
  let assert Error(eventsourcing.NonPositiveArgument) =
    eventsourcing.frequency(0)
  let assert Error(eventsourcing.NonPositiveArgument) =
    eventsourcing.frequency(-1)

  let snapshot_config = eventsourcing.SnapshotConfig(frequency)
  let name = process.new_name("snapshot-eventsourcing")
  let assert Ok(eventsourcing_spec) =
    eventsourcing.supervised(
      name:,
      eventstore:,
      handle: example_bank_account.handle,
      apply: example_bank_account.apply,
      empty_state: example_bank_account.UnopenedBankAccount,
      queries: [],
      snapshot_config: option.Some(snapshot_config),
    )

  let assert Ok(_supervisor) =
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.add(eventsourcing_spec)
    |> static_supervisor.start()

  let eventsourcing = process.named_subject(name)
  // Test no snapshot initially
  let snapshot_subject =
    eventsourcing.latest_snapshot(eventsourcing, "snap-test")
  let assert Ok(Ok(None)) = process.receive(snapshot_subject, 1000)

  // Execute 3 commands to trigger snapshot
  eventsourcing.execute(
    eventsourcing,
    "snap-test",
    example_bank_account.OpenAccount("snap-test"),
  )
  eventsourcing.execute(
    eventsourcing,
    "snap-test",
    example_bank_account.DepositMoney(100.0),
  )
  eventsourcing.execute(
    eventsourcing,
    "snap-test",
    example_bank_account.DepositMoney(50.0),
  )
  process.sleep(200)
}

pub fn multiple_query_actors_test() {
  let events_actor_name = process.new_name("events_actor")
  let snapshot_actor_name = process.new_name("snapshot_actor")
  let #(eventstore, child_spec) =
    memory_store.supervised(
      events_actor_name,
      snapshot_actor_name,
      static_supervisor.OneForOne,
    )

  let assert Ok(_) =
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.add(child_spec)
    |> static_supervisor.start()

  let query1_results = process.new_subject()
  let query2_results = process.new_subject()
  let query3_results = process.new_subject()

  let queries = [
    #(process.new_name("query1"), fn(aggregate_id, events) {
      process.send(query1_results, #(
        "query1",
        aggregate_id,
        list.length(events),
      ))
    }),
    #(process.new_name("query2"), fn(aggregate_id, events) {
      process.send(query1_results, #(
        "query1",
        aggregate_id,
        list.length(events),
      ))
    }),
    #(process.new_name("query3"), fn(aggregate_id, events) {
      process.send(query2_results, #(
        "query2",
        aggregate_id,
        list.length(events),
      ))
    }),
    #(process.new_name("query4"), fn(aggregate_id, events) {
      process.send(query3_results, #(
        "query3",
        aggregate_id,
        list.length(events),
      ))
    }),
  ]

  let name = process.new_name("multi-query-eventsourcing")
  let assert Ok(eventsourcing_spec) =
    eventsourcing.supervised(
      name:,
      eventstore:,
      handle: example_bank_account.handle,
      apply: example_bank_account.apply,
      empty_state: example_bank_account.UnopenedBankAccount,
      queries:,
      snapshot_config: None,
    )

  let assert Ok(_supervisor) =
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.add(eventsourcing_spec)
    |> static_supervisor.start()

  let eventsourcing = process.named_subject(name)

  process.sleep(100)

  // Execute command
  eventsourcing.execute(
    eventsourcing,
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
  let events_actor_name = process.new_name("events_actor")
  let snapshot_actor_name = process.new_name("snapshot_actor")
  let #(eventstore, child_spec) =
    memory_store.supervised(
      events_actor_name,
      snapshot_actor_name,
      static_supervisor.OneForOne,
    )

  let assert Ok(_) =
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.add(child_spec)
    |> static_supervisor.start()

  let name = process.new_name("error-handling-eventsourcing")
  let assert Ok(eventsourcing_spec) =
    eventsourcing.supervised(
      name:,
      eventstore:,
      handle: example_bank_account.handle,
      apply: example_bank_account.apply,
      empty_state: example_bank_account.UnopenedBankAccount,
      queries: [],
      snapshot_config: None,
    )

  let assert Ok(_supervisor) =
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.add(eventsourcing_spec)
    |> static_supervisor.start()

  let eventsourcing = process.named_subject(name)

  eventsourcing.execute(
    eventsourcing,
    "error-test",
    example_bank_account.WithDrawMoney(50.0),
  )

  // Test domain error - try to deposit negative amount
  eventsourcing.execute(
    eventsourcing,
    "error-test2",
    example_bank_account.OpenAccount("error-test2"),
  )
  process.sleep(100)

  eventsourcing.execute(
    eventsourcing,
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
  let events_actor_name = process.new_name("events_actor")
  let snapshot_actor_name = process.new_name("snapshot_actor")
  let #(eventstore, child_spec) =
    memory_store.supervised(
      events_actor_name,
      snapshot_actor_name,
      static_supervisor.OneForOne,
    )

  let assert Ok(_) =
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.add(child_spec)
    |> static_supervisor.start()

  let query_results = process.new_subject()
  let queries = [
    #(process.new_name("multi-aggregate-query"), fn(aggregate_id, events) {
      process.send(query_results, #(aggregate_id, list.length(events)))
    }),
  ]

  let name = process.new_name("multi-aggregate-eventsourcing")
  let assert Ok(eventsourcing_spec) =
    eventsourcing.supervised(
      name:,
      eventstore:,
      handle: example_bank_account.handle,
      apply: example_bank_account.apply,
      empty_state: example_bank_account.UnopenedBankAccount,
      queries:,
      snapshot_config: None,
    )

  let assert Ok(_supervisor) =
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.add(eventsourcing_spec)
    |> static_supervisor.start()

  let eventsourcing = process.named_subject(name)

  process.sleep(100)

  // Create multiple aggregates
  let aggregate_ids = ["acc-001", "acc-002", "acc-003", "acc-004", "acc-005"]

  list.each(aggregate_ids, fn(id) {
    eventsourcing.execute(
      eventsourcing,
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
      eventsourcing,
      id,
      example_bank_account.DepositMoney(100.0),
    )
  })

  // Verify all deposits
  list.each(aggregate_ids, fn(id) {
    let assert Ok(#(received_id, 1)) = process.receive(query_results, 1000)
    assert received_id == id
  })

  // Test aggregate stats
  let stats_result = eventsourcing.aggregate_stats(eventsourcing, "acc-001")
  let assert Ok(Ok(stats)) = process.receive(stats_result, 1000)
  assert stats.aggregate_id == "acc-001"
  assert stats.event_count == 2
  // OpenAccount + DepositMoney
  assert stats.current_sequence == 2
  assert stats.has_snapshot == False
}

pub fn complex_business_logic_test() {
  let events_actor_name = process.new_name("events_actor")
  let snapshot_actor_name = process.new_name("snapshot_actor")
  let #(eventstore, child_spec) =
    memory_store.supervised(
      events_actor_name,
      snapshot_actor_name,
      static_supervisor.OneForOne,
    )

  let assert Ok(_) =
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.add(child_spec)
    |> static_supervisor.start()

  let name = process.new_name("complex-business-eventsourcing")
  let assert Ok(eventsourcing_spec) =
    eventsourcing.supervised(
      name:,
      eventstore:,
      handle: example_bank_account.handle,
      apply: example_bank_account.apply,
      empty_state: example_bank_account.UnopenedBankAccount,
      queries: [],
      snapshot_config: None,
    )

  let assert Ok(_supervisor) =
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.add(eventsourcing_spec)
    |> static_supervisor.start()
  let eventsourcing = process.named_subject(name)

  // Complex banking scenario
  eventsourcing.execute(
    eventsourcing,
    "complex-001",
    example_bank_account.OpenAccount("complex-001"),
  )

  // Multiple deposits
  eventsourcing.execute(
    eventsourcing,
    "complex-001",
    example_bank_account.DepositMoney(1000.0),
  )
  eventsourcing.execute(
    eventsourcing,
    "complex-001",
    example_bank_account.DepositMoney(500.0),
  )
  eventsourcing.execute(
    eventsourcing,
    "complex-001",
    example_bank_account.DepositMoney(250.0),
  )

  // Multiple withdrawals
  eventsourcing.execute(
    eventsourcing,
    "complex-001",
    example_bank_account.WithDrawMoney(300.0),
  )
  eventsourcing.execute(
    eventsourcing,
    "complex-001",
    example_bank_account.WithDrawMoney(200.0),
  )

  process.sleep(300)

  // Verify final state
  let load_subject = eventsourcing.load_aggregate(eventsourcing, "complex-001")
  let assert Ok(Ok(aggregate)) = process.receive(load_subject, 1000)
  case aggregate.entity {
    example_bank_account.BankAccount(balance) -> {
      assert balance == 1250.0
    }
    _ -> panic as "Expected BankAccount with correct balance"
  }
  assert aggregate.sequence == 6

  // Verify all events - load events from sequence 0 (all events)
  let events_subject =
    eventsourcing.load_events_from(eventsourcing, "complex-001", 0)
  let assert Ok(Ok(events)) = process.receive(events_subject, 1000)
  assert list.length(events) == 6
}

pub fn new_features_test() {
  let events_actor_name = process.new_name("events_actor")
  let snapshot_actor_name = process.new_name("snapshot_actor")
  let #(eventstore, child_spec) =
    memory_store.supervised(
      events_actor_name,
      snapshot_actor_name,
      static_supervisor.OneForOne,
    )

  let assert Ok(_) =
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.add(child_spec)
    |> static_supervisor.start()

  let name = process.new_name("new-features-eventsourcing")
  let assert Ok(eventsourcing_spec) =
    eventsourcing.supervised(
      name:,
      eventstore:,
      handle: example_bank_account.handle,
      apply: example_bank_account.apply,
      empty_state: example_bank_account.UnopenedBankAccount,
      queries: [],
      snapshot_config: None,
    )

  let assert Ok(_supervisor) =
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.add(eventsourcing_spec)
    |> static_supervisor.start()

  let eventsourcing = process.named_subject(name)
  // Test load_events function (vs load_events_from)
  eventsourcing.execute(
    eventsourcing,
    "new-features",
    example_bank_account.OpenAccount("new-features"),
  )
  process.sleep(100)

  let events_subject = eventsourcing.load_events(eventsourcing, "new-features")
  let assert Ok(Ok(events)) = process.receive(events_subject, 1000)
  assert list.length(events) == 1

  // Test execute_with_metadata
  eventsourcing.execute_with_metadata(
    eventsourcing,
    "new-features",
    example_bank_account.DepositMoney(100.0),
    [#("user_id", "test-user"), #("source", "test")],
  )
  process.sleep(100)

  // Test system stats
  let stats_subject = eventsourcing.system_stats(eventsourcing)
  let assert Ok(stats) = process.receive(stats_subject, 1000)
  assert stats.query_actors_count == 0
  assert stats.total_commands_processed == 2

  // Test aggregate stats
  let agg_stats_subject =
    eventsourcing.aggregate_stats(eventsourcing, "new-features")
  let assert Ok(Ok(agg_stats)) = process.receive(agg_stats_subject, 1000)
  assert agg_stats.aggregate_id == "new-features"
  assert agg_stats.has_snapshot == False
}

pub fn concurrent_operations_test() {
  let events_actor_name = process.new_name("events_actor")
  let snapshot_actor_name = process.new_name("snapshot_actor")
  let #(eventstore, child_spec) =
    memory_store.supervised(
      events_actor_name,
      snapshot_actor_name,
      static_supervisor.OneForOne,
    )

  let assert Ok(_) =
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.add(child_spec)
    |> static_supervisor.start()

  let query_counter = process.new_subject()
  let queries = [
    #(
      process.new_name("concurrent-operations-query"),
      fn(_aggregate_id, events) {
        list.each(events, fn(_) { process.send(query_counter, 1) })
      },
    ),
  ]

  let name = process.new_name("concurrent-operations-eventsourcing")
  let assert Ok(eventsourcing_spec) =
    eventsourcing.supervised(
      name:,
      eventstore:,
      handle: example_bank_account.handle,
      apply: example_bank_account.apply,
      empty_state: example_bank_account.UnopenedBankAccount,
      queries:,
      snapshot_config: None,
    )

  let assert Ok(_supervisor) =
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.add(eventsourcing_spec)
    |> static_supervisor.start()

  let eventsourcing = process.named_subject(name)

  process.sleep(100)

  // Rapid fire commands on different aggregates
  list.range(1, 10)
  |> list.each(fn(i) {
    let id = "concurrent-" <> int.to_string(i)
    eventsourcing.execute(
      eventsourcing,
      id,
      example_bank_account.OpenAccount(id),
    )
  })

  // Count processed events 
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
