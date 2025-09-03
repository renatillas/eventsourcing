import eventsourcing
import eventsourcing/memory_store
import example_bank_account
import gleam/erlang/process
import gleam/list
import gleam/option.{None}
import gleam/otp/static_supervisor
import gleeunit

pub fn main() {
  gleeunit.main()
}

pub fn supervised_architecture_test() {
  // Create memory store
  let assert Ok(memory_store) = memory_store.new()

  // Create a query that signals when executed
  let query_executed_subject = process.new_subject()
  let queries = [
    fn(aggregate_id, events) {
      process.send(query_executed_subject, #(aggregate_id, list.length(events)))
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

  let assert Ok(supervisor) =
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.add(eventsourcing_spec)
    |> static_supervisor.start()

  let assert Ok(eventsourcing_actor) =
    process.receive(eventsourcing_actor_receiver, 2000)

  let assert Ok(query_actors) =
    list.try_map(queries, fn(_) { process.receive(query_actors_receiver, 1000) })

  eventsourcing.register_queries(eventsourcing_actor, query_actors)

  // Give time for actors to start
  process.sleep(100)

  // Test that the supervisor is alive and managing child processes
  assert process.is_alive(supervisor.pid)

  let Nil =
    eventsourcing.execute(
      eventsourcing_actor,
      "acc-123",
      example_bank_account.OpenAccount("acc-123"),
    )

  assert process.receive(query_executed_subject, 1000) == Ok(#("acc-123", 1))
}
