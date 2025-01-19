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
/// used by the Event Stores.
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

pub type EventSourcingError(domainerror) {
  DomainError(domainerror)
  ImplementationError
  EntityNotFound
}

@internal
pub type Apply(entity, event) =
  fn(entity, event) -> entity

@internal
pub type Handle(entity, command, event, error) =
  fn(entity, command) -> Result(List(event), error)

@internal
pub type Query(event) =
  fn(AggregateId, List(EventEnvelop(event))) -> Nil

/// The main record of the library. 
/// It holds everything together and serves as a reference point 
/// for other functions such as execute, load_aggregate_entity, and load_events
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

/// Wrapper around the event store implementations
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

/// Execute the given command on the event sourcing instance.
///
/// This function loads the aggregate, handles the command,
/// applies the resulting events, commits them to the event store,
/// and runs any registered queries.
///
/// @param event_sourcing The EventSourcing instance.
/// @param aggregate_id The ID of the aggregate to act upon.
/// @param command The command to execute.
/// @return A Result containing either Nil on success or an EventSourcingError on failure.
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
) -> Result(Nil, EventSourcingError(error)) {
  execute_with_metadata(event_sourcing:, aggregate_id:, command:, metadata: [])
}

/// Execute the given command with metadata on the event sourcing instance.
///
/// This function works similarly to `execute`, but additionally allows
/// passing metadata for the events.
///
/// @param event_sourcing The EventSourcing instance.
/// @param aggregate_id The ID of the aggregate to act upon.
/// @param command The command to execute.
/// @param metadata Metadata to associate with the events.
/// @return A Result containing either Nil on success or an EventSourcingError on failure.
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
) -> Result(Nil, EventSourcingError(error)) {
  let aggregate_context =
    event_sourcing.event_store.load_aggregate(
      event_sourcing.event_store.eventstore,
      aggregate_id,
    )
  let aggregate = aggregate_context.aggregate
  let entity = aggregate.entity
  use events <- result.try(
    aggregate.handle(entity, command)
    |> result.map_error(fn(error) { DomainError(error) }),
  )
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
  Ok(Nil)
}

/// Add a query to the EventSourcing instance.
///
/// Queries are functions that run when events are committed.
/// They can be used for things like updating read models or sending notifications.
///
/// @param eventsourcing The EventSourcing instance.
/// @param query The query function to add.
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

/// Load the events for a given aggregate ID.
///
/// @param eventsourcing The EventSourcing instance.
/// @param aggregate_id The ID of the aggregate to load events for.
/// @return A list of EventEnvelops containing the events for the aggregate.
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

/// Load the aggregate entity for a given aggregate ID.
///
/// @param eventsourcing The EventSourcing instance.
/// @param aggregate_id The ID of the aggregate to load.
/// @return The aggregate entity.
pub fn load_aggregate(
  eventsourcing eventsourcing: EventSourcing(
    eventstore,
    entity,
    command,
    event,
    error,
    aggregatecontext,
  ),
  aggregate_id aggregate_id: AggregateId,
) -> entity {
  eventsourcing.event_store.load_aggregate(
    eventsourcing.event_store.eventstore,
    aggregate_id,
  ).aggregate.entity
}
