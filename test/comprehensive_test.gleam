import eventsourcing
import eventsourcing/memory_store
import example_bank_account
import gleam/erlang/process
import gleam/int
import gleam/list
import gleam/option.{None, Some}
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
      snapshot_config: None,
    )

  let assert Ok(_supervisor) =
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.add(eventsourcing_spec)
    |> static_supervisor.start()

  let assert Ok(eventsourcing_actor) =
    process.receive(eventsourcing_actor_receiver, 2000)

  let assert Ok(query_actors) =
    list.try_map(queries, fn(_) { process.receive(query_actors_receiver, 1000) })

  eventsourcing.register_queries(eventsourcing_actor, query_actors)
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
      snapshot_config: None,
    )

  let assert Ok(_supervisor) =
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.add(eventsourcing_spec)
    |> static_supervisor.start()

  let assert Ok(eventsourcing_actor) =
    process.receive(eventsourcing_actor_receiver, 2000)

  // Try to load non-existent aggregate
  let load_subject =
    eventsourcing.load_aggregate(eventsourcing_actor, "nonexistent")
  let assert Ok(Error(eventsourcing.EntityNotFound)) =
    process.receive(load_subject, 1000)

  // Create aggregate
  eventsourcing.execute(
    eventsourcing_actor,
    "load-test",
    example_bank_account.OpenAccount("load-test"),
  )
  process.sleep(100)

  // Now load should work
  let load_subject2 =
    eventsourcing.load_aggregate(eventsourcing_actor, "load-test")
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
      snapshot_config: None,
    )

  let assert Ok(_supervisor) =
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.add(eventsourcing_spec)
    |> static_supervisor.start()

  let assert Ok(eventsourcing_actor) =
    process.receive(eventsourcing_actor_receiver, 2000)

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

  // Load events from sequence 2 (drops first 2, leaves 1)
  let events_subject =
    eventsourcing.load_events_from(eventsourcing_actor, "events-test", 2)
  let assert Ok(Ok(partial_events)) = process.receive(events_subject, 1000)
  assert list.length(partial_events) == 1

  // Load events from non-existent aggregate
  let empty_events_subject =
    eventsourcing.load_events_from(eventsourcing_actor, "nonexistent", 0)
  let assert Ok(Ok(empty_events)) = process.receive(empty_events_subject, 1000)
  assert empty_events == []
}

pub fn snapshot_functionality_test() {
  let assert Ok(memory_store) = memory_store.new()

  // Test snapshot frequency validation
  let assert Ok(frequency) = eventsourcing.frequency(3)
  let assert Error(eventsourcing.NonPositiveArgument) =
    eventsourcing.frequency(0)
  let assert Error(eventsourcing.NonPositiveArgument) =
    eventsourcing.frequency(-1)

  let snapshot_config = eventsourcing.SnapshotConfig(frequency)
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
      snapshot_config: Some(snapshot_config),
    )

  let assert Ok(_supervisor) =
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.add(eventsourcing_spec)
    |> static_supervisor.start()

  let assert Ok(eventsourcing_actor) =
    process.receive(eventsourcing_actor_receiver, 2000)

  // Test no snapshot initially
  let snapshot_subject =
    eventsourcing.latest_snapshot(eventsourcing_actor, "snap-test")
  let assert Ok(Ok(None)) = process.receive(snapshot_subject, 1000)

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
      snapshot_config: None,
    )

  let assert Ok(_supervisor) =
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.add(eventsourcing_spec)
    |> static_supervisor.start()

  let assert Ok(eventsourcing_actor) =
    process.receive(eventsourcing_actor_receiver, 2000)

  let assert Ok(query_actors) =
    list.try_map(queries, fn(_) { process.receive(query_actors_receiver, 1000) })

  eventsourcing.register_queries(eventsourcing_actor, query_actors)
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
      snapshot_config: None,
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
      snapshot_config: None,
    )

  let assert Ok(_supervisor) =
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.add(eventsourcing_spec)
    |> static_supervisor.start()

  let assert Ok(eventsourcing_actor) =
    process.receive(eventsourcing_actor_receiver, 2000)

  let assert Ok(query_actors) =
    list.try_map(queries, fn(_) { process.receive(query_actors_receiver, 1000) })

  eventsourcing.register_queries(eventsourcing_actor, query_actors)
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

  // Test aggregate stats
  let stats_result =
    eventsourcing.aggregate_stats(eventsourcing_actor, "acc-001")
  let assert Ok(Ok(stats)) = process.receive(stats_result, 1000)
  assert stats.aggregate_id == "acc-001"
  assert stats.event_count == 2
  // OpenAccount + DepositMoney
  assert stats.current_sequence == 2
  assert stats.has_snapshot == False
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
      snapshot_config: None,
    )

  let assert Ok(_supervisor) =
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.add(eventsourcing_spec)
    |> static_supervisor.start()

  let assert Ok(eventsourcing_actor) =
    process.receive(eventsourcing_actor_receiver, 2000)

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
  let load_subject =
    eventsourcing.load_aggregate(eventsourcing_actor, "complex-001")
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
    eventsourcing.load_events_from(eventsourcing_actor, "complex-001", 0)
  let assert Ok(Ok(events)) = process.receive(events_subject, 1000)
  assert list.length(events) == 6
}

pub fn new_features_test() {
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
      snapshot_config: None,
    )

  let assert Ok(_supervisor) =
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.add(eventsourcing_spec)
    |> static_supervisor.start()

  let assert Ok(eventsourcing_actor) =
    process.receive(eventsourcing_actor_receiver, 2000)

  // Test load_events function (vs load_events_from)
  eventsourcing.execute(
    eventsourcing_actor,
    "new-features",
    example_bank_account.OpenAccount("new-features"),
  )
  process.sleep(100)

  let events_subject =
    eventsourcing.load_events(eventsourcing_actor, "new-features")
  let assert Ok(Ok(events)) = process.receive(events_subject, 1000)
  assert list.length(events) == 1

  // Test execute_with_metadata
  eventsourcing.execute_with_metadata(
    eventsourcing_actor,
    "new-features",
    example_bank_account.DepositMoney(100.0),
    [#("user_id", "test-user"), #("source", "test")],
  )
  process.sleep(100)

  // Test system stats
  let stats_subject = eventsourcing.system_stats(eventsourcing_actor)
  let assert Ok(stats) = process.receive(stats_subject, 1000)
  assert stats.query_actors_count == 0
  assert stats.total_commands_processed == 2

  // Test aggregate stats
  let agg_stats_subject =
    eventsourcing.aggregate_stats(eventsourcing_actor, "new-features")
  let assert Ok(Ok(agg_stats)) = process.receive(agg_stats_subject, 1000)
  assert agg_stats.aggregate_id == "new-features"
  assert agg_stats.has_snapshot == False
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
      snapshot_config: None,
    )

  let assert Ok(_supervisor) =
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.add(eventsourcing_spec)
    |> static_supervisor.start()

  let assert Ok(eventsourcing_actor) =
    process.receive(eventsourcing_actor_receiver, 2000)

  let assert Ok(query_actors) =
    list.try_map(queries, fn(_) { process.receive(query_actors_receiver, 1000) })

  eventsourcing.register_queries(eventsourcing_actor, query_actors)
  process.sleep(100)

  // Rapid fire commands on different aggregates
  list.range(1, 10)
  |> list.each(fn(i) {
    let id = "concurrent-" <> int.to_string(i)
    eventsourcing.execute(
      eventsourcing_actor,
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
