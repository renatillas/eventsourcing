import gleam/dict.{type Dict}
import gleam/erlang/process
import gleam/list
import gleam/otp/actor
import gleam/pair
import gleam/result

import eventsourcing.{
  type Aggregate, type AggregateId, type EventEnvelop, type EventSourcingError,
  Aggregate, EventStore, EventStoreError, MemoryStoreEventEnvelop,
}

const load_commited_events_time = 1000

pub opaque type MemoryStore(entity, command, event, error) {
  MemoryStore(subject: process.Subject(Message(event)))
}

type State(event) =
  Dict(AggregateId, List(EventEnvelop(event)))

type Message(event) {
  Set(key: String, value: List(EventEnvelop(event)))
  Get(
    key: String,
    response: process.Subject(Result(List(EventEnvelop(event)), Nil)),
  )
}

/// Create a new memory store record.
pub fn new() {
  let assert Ok(actor) =
    actor.start(dict.new(), handle_message)
    |> result.try(fn(subject) { Ok(MemoryStore(subject)) })
  EventStore(
    eventstore: actor,
    commit: commit,
    load_events: load_commited_events,
  )
}

fn handle_message(message: Message(event), state: State(event)) {
  case message {
    Set(key, value) -> {
      state |> dict.insert(key, value) |> actor.continue
    }
    Get(key, response) -> {
      let value = state |> dict.get(key)
      actor.send(response, value)
      actor.continue(state)
    }
  }
}

fn load_commited_events(
  memory_store: MemoryStore(entity, command, event, error),
  aggregate_id: AggregateId,
) -> Result(List(EventEnvelop(event)), EventSourcingError(error)) {
  process.try_call(
    memory_store.subject,
    Get(aggregate_id, _),
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
      Ok(events) -> Ok(events)
      Error(Nil) -> Ok([])
    }
  })
}

fn commit(
  memory_store: MemoryStore(entity, command, event, error),
  aggregate: Aggregate(entity, command, event, error),
  events: List(event),
  metadata: List(#(String, String)),
) -> Result(List(EventEnvelop(event)), EventSourcingError(error)) {
  let Aggregate(aggregate_id, _, sequence) = aggregate
  let wrapped_events = wrap_events(aggregate_id, sequence, events, metadata)
  use past_events <- result.map(load_commited_events(memory_store, aggregate_id))
  let events = list.append(past_events, wrapped_events)
  actor.send(memory_store.subject, Set(aggregate_id, events))
  wrapped_events
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
