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

const load_commited_events_time: Int = 1000

const load_snapshot_time: Int = 1000

/// In-memory event store implementation for development and testing.
/// This store persists events and snapshots in memory using supervised actors.
/// Data is lost when the application restarts.
pub opaque type MemoryStore(entity, command, event, error) {
  MemoryStore(
    events_subject: process.Name(EventMessage(event)),
    snapshot_subject: process.Name(SnapshotMessage(entity)),
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

fn supervised_events_actor(
  events_actor_receiver: process.Subject(
    actor.Started(process.Subject(EventMessage(event))),
  ),
  name: process.Name(EventMessage(event)),
) -> supervision.ChildSpecification(process.Subject(EventMessage(event))) {
  supervision.worker(fn() {
    use started <- result.map(
      actor.new(dict.new())
      |> actor.on_message(handle_events_message)
      |> actor.named(name)
      |> actor.start(),
    )
    process.send(events_actor_receiver, started)
    started
  })
}

fn supervised_snapshot_actor(
  snapshot_actor_receiver: process.Subject(
    actor.Started(process.Subject(SnapshotMessage(entity))),
  ),
  name: process.Name(SnapshotMessage(entity)),
) -> supervision.ChildSpecification(process.Subject(SnapshotMessage(entity))) {
  supervision.worker(fn() {
    use started <- result.map(
      actor.new(dict.new())
      |> actor.on_message(handle_snapshot_message)
      |> actor.named(name)
      |> actor.start(),
    )
    process.send(snapshot_actor_receiver, started)
    started
  })
}

/// Creates a supervised in-memory event store with separate actors for events and snapshots.
/// Returns both the EventStore interface and a supervision specification that manages
/// the underlying storage actors.
///
/// ## Example
/// ```gleam
/// let events_name = process.new_name("events_actor")
/// let snapshot_name = process.new_name("snapshot_actor")
/// let #(eventstore, supervisor_spec) = memory_store.supervised(
///   events_name,
///   snapshot_name,
///   static_supervisor.OneForOne
/// )
/// ```
pub fn supervised(
  events_actor_name: process.Name(EventMessage(event)),
  snapshot_actor_name: process.Name(SnapshotMessage(entity)),
  strategy: static_supervisor.Strategy,
) -> #(
  eventsourcing.EventStore(
    MemoryStore(entity, command, event, error),
    entity,
    command,
    event,
    error,
    MemoryStore(entity, command, event, error),
  ),
  supervision.ChildSpecification(static_supervisor.Supervisor),
) {
  let events_actor_receiver = process.new_subject()
  let supervised_events_actor_spec =
    supervised_events_actor(events_actor_receiver, events_actor_name)

  let snapshot_actor_receiver = process.new_subject()
  let supervised_snapshot_actor_spec =
    supervised_snapshot_actor(snapshot_actor_receiver, snapshot_actor_name)

  let memory_store =
    MemoryStore(
      events_subject: events_actor_name,
      snapshot_subject: snapshot_actor_name,
    )

  let eventstore =
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

  #(
    eventstore,
    static_supervisor.new(strategy)
      |> static_supervisor.add(supervised_events_actor_spec)
      |> static_supervisor.add(supervised_snapshot_actor_spec)
      |> static_supervisor.supervised(),
  )
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
      process.named_subject(memory_store.events_subject),
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
  actor.send(
    process.named_subject(memory_store.events_subject),
    SetEvents(aggregate_id, all_events),
  )
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
    process.named_subject(memory_store.snapshot_subject),
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
    process.call(
      process.named_subject(memory_store.snapshot_subject),
      load_snapshot_time,
      GetSnapshot(aggregate_id, _),
    ),
  )
}
