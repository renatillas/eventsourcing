import eventsourcing
import gleam/dict.{type Dict}
import gleam/erlang/process
import gleam/list
import gleam/otp/actor
import gleam/pair
import gleam/result

pub opaque type MemoryStore(entity, command, event, error) {
  MemoryStore(subject: process.Subject(Message(event)))
}

type State(event) =
  Dict(eventsourcing.AggregateId, List(eventsourcing.EventEnvelop(event)))

type Message(event) {
  Set(key: String, value: List(eventsourcing.EventEnvelop(event)))
  Get(
    key: String,
    response: process.Subject(
      Result(List(eventsourcing.EventEnvelop(event)), Nil),
    ),
  )
}

/// Create a new memory store record.
pub fn new() {
  let assert Ok(actor) =
    actor.start(dict.new(), handle_message)
    |> result.try(fn(subject) { Ok(MemoryStore(subject)) })
  eventsourcing.EventStore(
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
  aggregate_id: eventsourcing.AggregateId,
) {
  actor.call(memory_store.subject, Get(aggregate_id, _), 10_000)
  |> result.unwrap([])
}

fn commit(
  memory_store: MemoryStore(entity, command, event, error),
  aggregate: eventsourcing.Aggregate(entity, command, event, error),
  events: List(event),
  metadata: List(#(String, String)),
) -> List(eventsourcing.EventEnvelop(event)) {
  let eventsourcing.Aggregate(aggregate_id, _, sequence) = aggregate
  let wrapped_events = wrap_events(aggregate_id, sequence, events, metadata)
  let past_events = load_commited_events(memory_store, aggregate_id)
  let events = list.append(past_events, wrapped_events)
  actor.send(memory_store.subject, Set(aggregate_id, events))
  wrapped_events
}

fn wrap_events(
  aggregate_id: eventsourcing.AggregateId,
  current_sequence: Int,
  events: List(event),
  metadata: List(#(String, String)),
) -> List(eventsourcing.EventEnvelop(event)) {
  list.map_fold(
    over: events,
    from: current_sequence,
    with: fn(sequence: Int, event: event) {
      let next_sequence = sequence + 1
      #(
        next_sequence,
        eventsourcing.MemoryStoreEventEnvelop(
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
