import gleam/dict.{type Dict}
import gleam/list
import gleam/result

type AggregateId =
  String

pub type EventSourcing(
  eventstore,
  entity,
  command,
  event,
  error,
  aggregatecontext,
) {
  EventSourcing(
    event_store: EventStore(eventstore, entity, command, event, error),
    queries: List(Query(event)),
  )
}

pub fn new(event_store, queries) {
  EventSourcing(event_store:, queries:)
}

pub type EventStore(eventstore, entity, command, event, error) {
  EventStore(
    eventstore: eventstore,
    load_aggregate: fn(eventstore, AggregateId) ->
      AggregateContext(entity, command, event, error),
    commit: fn(
      eventstore,
      AggregateContext(entity, command, event, error),
      List(event),
      Dict(String, String),
    ) ->
      Nil,
  )
}

pub type AggregateContext(entity, command, event, error) {
  MemoryStoreAggregateContext(
    aggregate_id: AggregateId,
    aggregate: Aggregate(entity, command, event, error),
    sequence: Int,
  )
}

/// Aggregate
type Handle(entity, command, event, error) =
  fn(entity, command) -> Result(List(event), error)

type Apply(entity, event) =
  fn(entity, event) -> entity

type Query(event) =
  fn(AggregateId, List(EventEnvelop(event))) -> Nil

pub type Aggregate(entity, command, event, error) {
  Aggregate(
    entity: entity,
    handle: Handle(entity, command, event, error),
    apply: Apply(entity, event),
  )
}

pub fn execute(
  event_sourcing: EventSourcing(
    eventstore,
    entity,
    command,
    event,
    error,
    aggregatecontext,
  ),
  aggregate_id aggregate_id: AggregateId,
  command command: command,
) -> Result(Nil, error) {
  let aggregate_context =
    event_sourcing.event_store.load_aggregate(
      event_sourcing.event_store.eventstore,
      aggregate_id,
    )
  let aggregate = aggregate_context.aggregate
  let entity = aggregate.entity

  use events <- result.map(aggregate.handle(entity, command))
  events |> list.map(aggregate.apply(entity, _))
  event_sourcing.event_store.commit(
    event_sourcing.event_store.eventstore,
    aggregate_context,
    events,
    dict.new(),
  )
  Nil
}

pub type EventEnvelop(event) {
  EventEnvelop(
    aggregate_id: AggregateId,
    sequence: Int,
    payload: event,
    metadata: Dict(String, String),
  )
}
