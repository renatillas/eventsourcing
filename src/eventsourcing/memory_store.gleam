import eventsourcing
import gleam/dict.{type Dict}
import gleam/erlang/process
import gleam/io
import gleam/list
import gleam/otp/actor
import gleam/pair
import gleam/result

type State(event) =
  Dict(eventsourcing.AggregateId, List(eventsourcing.EventEnvelop(event)))

pub opaque type MemoryStore(entity, command, event, error) {
  MemoryStore(
    subject: process.Subject(Message(event)),
    empty_aggregate: eventsourcing.Aggregate(entity, command, event, error),
  )
}

pub fn new(
  emtpy_entity empty_entity: entity,
  handle_command_function handle: eventsourcing.Handle(
    entity,
    command,
    event,
    error,
  ),
  apply_function apply: eventsourcing.Apply(entity, event),
) {
  let assert Ok(actor) =
    actor.start(dict.new(), handle_message)
    |> result.try(fn(subject) {
      Ok(MemoryStore(
        subject,
        eventsourcing.Aggregate(empty_entity, handle:, apply:),
      ))
    })
  eventsourcing.EventStore(
    eventstore: actor,
    commit: commit,
    load_aggregate: load_aggregate,
  )
}

type Message(event) {
  Set(key: String, value: List(eventsourcing.EventEnvelop(event)))
  Get(
    key: String,
    response: process.Subject(
      Result(List(eventsourcing.EventEnvelop(event)), Nil),
    ),
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

fn load_aggregate(
  memory_store: MemoryStore(entity, command, event, error),
  aggregate_id: eventsourcing.AggregateId,
) -> eventsourcing.AggregateContext(entity, command, event, error) {
  let commited_events = load_commited_events(memory_store, aggregate_id)

  let #(aggregate, sequence) =
    list.fold(
      over: commited_events |> list.reverse,
      from: #(memory_store.empty_aggregate, 0),
      with: fn(aggregate_and_sequence, event_envelop) {
        let #(aggregate, _) = aggregate_and_sequence
        #(
          eventsourcing.Aggregate(
            ..aggregate,
            entity: aggregate.apply(aggregate.entity, event_envelop.payload),
          ),
          event_envelop.sequence,
        )
      },
    )
  eventsourcing.MemoryStoreAggregateContext(
    aggregate_id:,
    aggregate:,
    sequence:,
  )
}

fn commit(
  memory_store: MemoryStore(entity, command, event, error),
  context: eventsourcing.AggregateContext(entity, command, event, error),
  events: List(event),
  metadata: Dict(String, String),
) {
  let eventsourcing.MemoryStoreAggregateContext(aggregate_id, _, sequence) =
    context
  let wrapped_events = wrap_events(aggregate_id, sequence, events, metadata)
  let past_events = load_commited_events(memory_store, aggregate_id)
  let events =
    list.append(wrapped_events, past_events)
    |> io.debug
  actor.send(memory_store.subject, Set(aggregate_id, events))
}

fn wrap_events(
  aggregate_id: eventsourcing.AggregateId,
  current_sequence: Int,
  events: List(event),
  base_metadata: Dict(String, String),
) -> List(eventsourcing.EventEnvelop(event)) {
  list.map_fold(
    over: events,
    from: current_sequence,
    with: fn(sequence: Int, event: event) {
      let next_sequence = sequence + 1
      #(
        next_sequence,
        eventsourcing.EventEnvelop(
          aggregate_id:,
          sequence: sequence + 1,
          payload: event,
          metadata: base_metadata,
        ),
      )
    },
  )
  |> pair.second
}
