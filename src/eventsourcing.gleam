import gleam/list
import gleam/result

// TYPES ----
pub type AggregateId =
  String

@internal
pub type Aggregate(entity, command, event, error) {
  Aggregate(
    entity: entity,
    handle: Handle(entity, command, event, error),
    apply: Apply(entity, event),
  )
}

@internal
pub type AggregateContext(entity, command, event, error) {
  AggregateContext(
    aggregate_id: AggregateId,
    aggregate: Aggregate(entity, command, event, error),
    sequence: Int,
  )
}

/// An EventEnvelop is a wrapper around your domain events
/// used by the Event Stores. You can use this type constructor
/// if the event store provides a `load_events` function.
pub type EventEnvelop(event) {
  MemoryStoreEventEnvelop(
    aggregate_id: AggregateId,
    sequence: Int,
    payload: event,
    metadata: List(#(String, String)),
  )
  SerializedEventEnvelop(
    aggregate_id: AggregateId,
    sequence: Int,
    payload: event,
    metadata: List(#(String, String)),
    event_type: String,
    event_version: String,
    aggregate_type: String,
  )
}

@internal
pub type Handle(entity, command, event, error) =
  fn(entity, command) -> Result(List(event), error)

@internal
pub type Apply(entity, event) =
  fn(entity, event) -> entity

@internal
pub type Query(event) =
  fn(AggregateId, List(EventEnvelop(event))) -> Nil

/// The main record of the library. 
/// It holds everything together and serves as a reference point 
/// for other functions such as execute, load_aggregate_entity, and load_events.
pub opaque type EventSourcing(
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

@internal
pub type EventStore(eventstore, entity, command, event, error) {
  EventStore(
    eventstore: eventstore,
    load_aggregate: fn(eventstore, AggregateId) ->
      AggregateContext(entity, command, event, error),
    load_events: fn(eventstore, AggregateId) -> List(EventEnvelop(event)),
    commit: fn(
      eventstore,
      AggregateContext(entity, command, event, error),
      List(event),
      List(#(String, String)),
    ) ->
      List(EventEnvelop(event)),
  )
}

// CONSTRUCTORS ----

/// Create a new EventSourcing instance providing 
/// an Event Store and a list of queries you want
/// run whenever events are commited.
///
pub fn new(event_store, queries) {
  EventSourcing(event_store:, queries:)
}

// PUBLIC FUNCTIONS ----

/// **Execute**
/// The main function of the package. 
/// Run execute with your event_sourcing instance and the command you want to apply.
/// It will return a Result with Ok(Nil) or Error(your domain error) if the command failed.
pub fn execute(
  event_sourcing event_sourcing: EventSourcing(
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
  execute_with_metadata(event_sourcing:, aggregate_id:, command:, metadata: [])
}

pub fn execute_with_metadata(
  event_sourcing event_sourcing: EventSourcing(
    eventstore,
    entity,
    command,
    event,
    error,
    aggregatecontext,
  ),
  aggregate_id aggregate_id: AggregateId,
  command command: command,
  metadata metadata: List(#(String, String)),
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
  let commited_events =
    event_sourcing.event_store.commit(
      event_sourcing.event_store.eventstore,
      aggregate_context,
      events,
      metadata,
    )
  event_sourcing.queries
  |> list.map(fn(query) { query(aggregate_id, commited_events) })
  Nil
}

pub fn add_query(
  eventsouring eventsourcing: EventSourcing(
    eventstore,
    entity,
    command,
    event,
    error,
    aggregatecontext,
  ),
  query query,
) {
  EventSourcing(..eventsourcing, queries: [query, ..eventsourcing.queries])
}

pub fn load_events(
  eventsourcing eventsourcing: EventSourcing(
    eventstore,
    entity,
    command,
    event,
    error,
    aggregatecontext,
  ),
  aggregate_id aggregate_id: AggregateId,
) -> List(EventEnvelop(event)) {
  eventsourcing.event_store.load_events(
    eventsourcing.event_store.eventstore,
    aggregate_id,
  )
}
