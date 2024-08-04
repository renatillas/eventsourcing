import eventsourcing
import gleam/dynamic
import gleam/int
import gleam/io
import gleam/list
import gleam/pair
import gleam/pgo
import gleam/result

pub opaque type PostgresStore(entity, command, event, error) {
  PostgresStore(
    db: pgo.Connection,
    empty_aggregate: eventsourcing.Aggregate(entity, command, event, error),
    event_encoder: fn(event) -> String,
    event_decoder: fn(String) -> Result(event, List(dynamic.DecodeError)),
    event_type: String,
    event_version: String,
    aggregate_type: String,
  )
}

pub fn new(
  pgo_config pgo_config: pgo.Config,
  emtpy_entity empty_entity: entity,
  handle_command_function handle: eventsourcing.Handle(
    entity,
    command,
    event,
    error,
  ),
  apply_function apply: eventsourcing.Apply(entity, event),
  event_encoder event_encoder: fn(event) -> String,
  event_decoder event_decoder: fn(String) ->
    Result(event, List(dynamic.DecodeError)),
  event_type event_type: String,
  event_version event_version: String,
  aggregate_type aggregate_type: String,
) {
  let db = pgo.connect(pgo_config)

  let eventstore =
    PostgresStore(
      db:,
      empty_aggregate: eventsourcing.Aggregate(empty_entity, handle, apply),
      event_encoder:,
      event_decoder:,
      event_type:,
      event_version:,
      aggregate_type:,
    )

  eventsourcing.EventStore(
    eventstore:,
    commit: commit,
    load_aggregate: load_aggregate,
  )
}

fn load_aggregate(
  postgres_store: PostgresStore(entity, command, event, error),
  aggregate_id: eventsourcing.AggregateId,
) {
  let assert Ok(commited_events) = load_events(postgres_store, aggregate_id)

  let #(aggregate, sequence) =
    list.fold(
      over: commited_events,
      from: #(postgres_store.empty_aggregate, 0),
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
  eventsourcing.AggregateContext(aggregate_id:, aggregate:, sequence:)
}

fn load_events(
  postgres_store: PostgresStore(entity, command, event, error),
  aggregate_id: eventsourcing.AggregateId,
) {
  use resulted <- result.map(pgo.execute(
    select_events(),
    on: postgres_store.db,
    with: [pgo.text(postgres_store.aggregate_type), pgo.text(aggregate_id)],
    expecting: dynamic.decode6(
      eventsourcing.SerializedEventEnvelop,
      dynamic.element(1, dynamic.string),
      dynamic.element(2, dynamic.int),
      dynamic.element(5, fn(dyn) {
        let assert Ok(payload) =
          dynamic.string(dyn) |> result.map(postgres_store.event_decoder)
        payload
      }),
      dynamic.element(3, dynamic.string),
      dynamic.element(4, dynamic.string),
      dynamic.element(0, dynamic.string),
    ),
  ))
  resulted.rows
}

fn commit(
  postgres_store: PostgresStore(entity, command, event, error),
  context: eventsourcing.AggregateContext(entity, command, event, error),
  events: List(event),
) {
  let eventsourcing.AggregateContext(aggregate_id, _, sequence) = context
  let wrapped_events =
    wrap_events(postgres_store, aggregate_id, events, sequence)
  persist_events(postgres_store, wrapped_events)
  io.println(
    "storing: "
    <> wrapped_events |> list.length |> int.to_string
    <> " events for Aggregate ID '"
    <> aggregate_id
    <> "'",
  )
  wrapped_events
}

fn wrap_events(
  postgres_store: PostgresStore(entity, command, event, error),
  aggregate_id: eventsourcing.AggregateId,
  events: List(event),
  sequence: Int,
) -> List(eventsourcing.EventEnvelop(event)) {
  list.map_fold(
    over: events,
    from: sequence,
    with: fn(sequence: Int, event: event) {
      let next_sequence = sequence + 1
      #(
        next_sequence,
        eventsourcing.SerializedEventEnvelop(
          aggregate_id:,
          sequence: sequence + 1,
          payload: event,
          event_type: postgres_store.event_type,
          event_version: postgres_store.event_version,
          aggregate_type: postgres_store.aggregate_type,
        ),
      )
    },
  )
  |> pair.second
}

fn persist_events(
  postgres_store: PostgresStore(entity, command, event, error),
  wrapped_events: List(eventsourcing.EventEnvelop(event)),
) {
  wrapped_events
  |> list.map(fn(event) {
    let assert eventsourcing.SerializedEventEnvelop(
      aggregate_id,
      sequence,
      payload,
      event_type,
      event_version,
      aggregate_type,
    ) = event

    pgo.execute(
      query: insert_event(),
      on: postgres_store.db,
      with: [
        pgo.text(aggregate_type),
        pgo.text(aggregate_id),
        pgo.int(sequence),
        pgo.text(event_type),
        pgo.text(event_version),
        pgo.text(payload |> postgres_store.event_encoder),
      ],
      expecting: dynamic.dynamic,
    )
  })
}

fn insert_event() {
  "
    INSERT INTO event 
    (aggregate_type, aggregate_id, sequence, event_type, event_version, payload)
    VALUES 
    ($1, $2, $3, $4, $5, $6)
    "
}

fn select_events() {
  "
  SELECT aggregate_type, aggregate_id, sequence, event_type, event_version, payload
  FROM event
  WHERE aggregate_type = $1 AND aggregate_id = $2
  ORDER BY sequence
  "
}
