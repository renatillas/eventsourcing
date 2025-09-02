import gleam/dict.{type Dict}
import gleam/erlang/process
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/otp/static_supervisor
import gleam/otp/supervision
import gleam/pair
import gleam/result

import eventsourcing.{
  type Aggregate, type AggregateId, type EventEnvelop, type EventSourcingError,
  Aggregate, EventStore, MemoryStoreEventEnvelop,
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

pub type EventMessage(event) {
  SetEvents(key: String, value: List(EventEnvelop(event)))
  GetEvents(
    key: String,
    response: process.Subject(Option(List(EventEnvelop(event)))),
  )
}

pub type SnapshotMessage(entity) {
  SetSnapshot(key: String, value: eventsourcing.Snapshot(entity))
  GetSnapshot(
    key: String,
    response: process.Subject(Option(eventsourcing.Snapshot(entity))),
  )
}

/// Create a new memory store record.
pub fn new() {
  use event_actor <- result.try(
    actor.new(dict.new())
    |> actor.on_message(handle_events_message)
    |> actor.start(),
  )
  use snapshot_actor <- result.try(
    actor.new(dict.new())
    |> actor.on_message(handle_snapshot_message)
    |> actor.start(),
  )

  let memory_store =
    MemoryStore(
      events_subject: event_actor.data,
      snapshot_subject: snapshot_actor.data,
    )

  Ok(
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
    ),
  )
}

fn supervised_events_actor(events_actor_receiver) {
  supervision.worker(fn() {
    use started <- result.map(
      actor.new(dict.new())
      |> actor.on_message(handle_events_message)
      |> actor.start(),
    )
    process.send(events_actor_receiver, started)
    started
  })
}

fn supervised_snapshot_actor(snapshot_actor_receiver) {
  supervision.worker(fn() {
    use started <- result.map(
      actor.new(dict.new())
      |> actor.on_message(handle_snapshot_message)
      |> actor.start(),
    )
    process.send(snapshot_actor_receiver, started)
    started
  })
}

pub fn supervised(
  event_store_receiver: process.Subject(
    eventsourcing.EventStore(
      MemoryStore(entity, command, event, error),
      entity,
      command,
      event,
      error,
      MemoryStore(entity, command, event, error),
    ),
  ),
  strategy: static_supervisor.Strategy,
) -> supervision.ChildSpecification(static_supervisor.Supervisor) {
  let events_actor_receiver = process.new_subject()
  let supervised_events_actor_spec =
    supervised_events_actor(events_actor_receiver)

  let snapshot_actor_receiver = process.new_subject()
  let supervised_snapshot_actor_spec =
    supervised_snapshot_actor(snapshot_actor_receiver)

  let assert Ok(event_actor) = process.receive(events_actor_receiver, 1000)
  let assert Ok(snapshot_actor) = process.receive(snapshot_actor_receiver, 1000)
  let memory_store =
    MemoryStore(
      events_subject: event_actor.data,
      snapshot_subject: snapshot_actor.data,
    )

  process.send(
    event_store_receiver,
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
    ),
  )

  static_supervisor.new(strategy)
  |> static_supervisor.add(supervised_events_actor_spec)
  |> static_supervisor.add(supervised_snapshot_actor_spec)
  |> static_supervisor.supervised()
}

fn handle_events_message(state: EventState(event), message: EventMessage(event)) {
  case message {
    SetEvents(key, value) -> {
      state |> dict.insert(key, value) |> actor.continue
    }
    GetEvents(key, response) -> {
      let value = state |> dict.get(key) |> option.from_result()
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
  let events =
    process.call(
      memory_store.events_subject,
      load_commited_events_time,
      GetEvents(aggregate_id, _),
    )
  case events {
    Some(events) -> Ok(events |> list.drop(start_from))
    None -> Ok([])
  }
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
  let all_events = list.append(past_events, wrapped_events)
  actor.send(memory_store.events_subject, SetEvents(aggregate_id, all_events))
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
  state: SnapshotState(entity),
  message: SnapshotMessage(entity),
) {
  case message {
    SetSnapshot(key, value) -> {
      state |> dict.insert(key, value) |> actor.continue
    }
    GetSnapshot(key, response) -> {
      let value = state |> dict.get(key) |> option.from_result()
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
  Ok(
    process.call(memory_store.snapshot_subject, load_snapshot_time, GetSnapshot(
      aggregate_id,
      _,
    )),
  )
}
