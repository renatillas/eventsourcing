import gleam/dict.{type Dict}
import gleam/erlang/process
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/pair
import gleam/result

import eventsourcing.{
  type Aggregate, type AggregateId, type EventEnvelop, type EventSourcingError,
  Aggregate, EventStore, EventStoreError, MemoryStoreEventEnvelop,
}

const load_commited_events_time = 1000

const load_snapshot_time = 1000

pub opaque type MemoryStore(entity, command, event, error) {
  MemoryStore(
    events_subject: process.Subject(EventMessage(event)),
    snapshot_subject: process.Subject(SnapshotMessage(entity)),
  )
}

type EventState(event) =
  Dict(AggregateId, List(EventEnvelop(event)))

type SnapshotState(entity) =
  Dict(AggregateId, eventsourcing.Snapshot(entity))

type EventMessage(event) {
  SetEvents(key: String, value: List(EventEnvelop(event)))
  GetEvents(
    key: String,
    response: process.Subject(Result(List(EventEnvelop(event)), Nil)),
  )
}

type SnapshotMessage(entity) {
  SetSnapshot(key: String, value: eventsourcing.Snapshot(entity))
  GetSnapshot(
    key: String,
    response: process.Subject(Result(eventsourcing.Snapshot(entity), Nil)),
  )
}

/// Create a new memory store record.
pub fn new() {
  let assert Ok(event_actor) = actor.start(dict.new(), handle_events_message)
  let assert Ok(snapshot_actor) =
    actor.start(dict.new(), handle_snapshot_message)

  let memory_store =
    MemoryStore(events_subject: event_actor, snapshot_subject: snapshot_actor)

  EventStore(
    eventstore: memory_store,
    commit_events: commit_events,
    load_events: load_events,
    load_snapshot: load_snapshot,
    save_snapshot: save_snapshot,
    execute_transaction: fn(f) { f(memory_store) },
    get_latest_snapshot_transaction: fn(f) { f(memory_store) },
    load_aggregate_transaction: fn(f) { f(memory_store) },
    load_events_transaction: fn(f) { f(memory_store) },
  )
}

fn handle_events_message(message: EventMessage(event), state: EventState(event)) {
  case message {
    SetEvents(key, value) -> {
      state |> dict.insert(key, value) |> actor.continue
    }
    GetEvents(key, response) -> {
      let value = state |> dict.get(key)
      actor.send(response, value)
      actor.continue(state)
    }
  }
}

fn load_events(
  memory_store: MemoryStore(entity, command, event, error),
  _,
  aggregate_id: AggregateId,
  start_from: Int,
) -> Result(List(EventEnvelop(event)), EventSourcingError(error)) {
  process.try_call(
    memory_store.events_subject,
    GetEvents(aggregate_id, _),
    load_commited_events_time,
  )
  |> result.map_error(fn(error) {
    case error {
      process.CallTimeout -> EventStoreError("timeout")
      process.CalleeDown(_) ->
        EventStoreError("process responsible of getting events is down")
    }
  })
  |> result.try(fn(result) {
    case result {
      Ok(events) -> Ok(events |> list.drop(start_from))
      Error(Nil) -> Ok([])
    }
  })
}

fn commit_events(
  memory_store: MemoryStore(entity, command, event, error),
  aggregate: Aggregate(entity, command, event, error),
  events: List(event),
  metadata: List(#(String, String)),
) -> Result(#(List(EventEnvelop(event)), Int), EventSourcingError(error)) {
  let Aggregate(aggregate_id, _, sequence) = aggregate
  let wrapped_events = wrap_events(aggregate_id, sequence, events, metadata)
  use past_events <- result.map(load_events(memory_store, Nil, aggregate_id, 0))
  let events = list.append(past_events, wrapped_events)
  actor.send(memory_store.events_subject, SetEvents(aggregate_id, events))
  let assert Ok(last_event) = list.last(wrapped_events)

  #(wrapped_events, last_event.sequence)
}

fn wrap_events(
  aggregate_id: AggregateId,
  current_sequence: Int,
  events: List(event),
  metadata: List(#(String, String)),
) -> List(EventEnvelop(event)) {
  list.map_fold(
    over: events,
    from: current_sequence,
    with: fn(sequence: Int, event: event) {
      let next_sequence = sequence + 1
      #(
        next_sequence,
        MemoryStoreEventEnvelop(
          aggregate_id:,
          sequence: sequence + 1,
          payload: event,
          metadata:,
        ),
      )
    },
  )
  |> pair.second
}

fn handle_snapshot_message(
  message: SnapshotMessage(entity),
  state: SnapshotState(entity),
) {
  case message {
    SetSnapshot(key, value) -> {
      state |> dict.insert(key, value) |> actor.continue
    }
    GetSnapshot(key, response) -> {
      let value = state |> dict.get(key)
      actor.send(response, value)
      actor.continue(state)
    }
  }
}

fn save_snapshot(
  memory_store: MemoryStore(entity, command, event, error),
  snapshot: eventsourcing.Snapshot(entity),
) -> Result(Nil, EventSourcingError(error)) {
  actor.send(
    memory_store.snapshot_subject,
    SetSnapshot(snapshot.aggregate_id, snapshot),
  )
  |> Ok
}

fn load_snapshot(
  memory_store: MemoryStore(entity, command, event, error),
  aggregate_id: eventsourcing.AggregateId,
) -> Result(
  Option(eventsourcing.Snapshot(entity)),
  eventsourcing.EventSourcingError(error),
) {
  process.try_call(
    memory_store.snapshot_subject,
    GetSnapshot(aggregate_id, _),
    load_snapshot_time,
  )
  |> result.map_error(fn(error) {
    case error {
      process.CallTimeout -> eventsourcing.EventStoreError("timeout")
      process.CalleeDown(_) ->
        eventsourcing.EventStoreError(
          "process responsible for getting snapshots is down",
        )
    }
  })
  |> result.try(fn(result) {
    case result {
      Ok(snapshot) -> Ok(Some(snapshot))
      Error(Nil) -> Ok(None)
    }
  })
}
