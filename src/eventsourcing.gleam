import gleam/list
import gleam/result

// TYPES ----
pub type AggregateId =
  String

pub type Aggregate(entity, command, event, error) {
  Aggregate(aggregate_id: AggregateId, entity: entity, sequence: Int)
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
  EventStoreError(String)
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
pub opaque type EventSourcing(eventstore, entity, command, event, error) {
  EventSourcing(
    event_store: EventStore(eventstore, entity, command, event, error),
    queries: List(Query(event)),
    handle: Handle(entity, command, event, error),
    apply: Apply(entity, event),
    empty_state: entity,
  )
}

/// Wrapper around the event store implementations
pub type EventStore(eventstore, entity, command, event, error) {
  EventStore(
    eventstore: eventstore,
    load_events: fn(eventstore, AggregateId) -> List(EventEnvelop(event)),
    commit: fn(
      eventstore,
      Aggregate(entity, command, event, error),
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
pub fn new(event_store, queries, handle, apply, empty_state) {
  EventSourcing(event_store:, queries:, handle:, apply:, empty_state:)
}

// PUBLIC FUNCTIONS ----

/// Execute the given command on the event sourcing instance.
///
/// This function loads the aggregate, handles the command,
/// applies the resulting events, commits them to the event store,
/// and runs any registered queries.
pub fn execute(
  event_sourcing event_sourcing: EventSourcing(
    eventstore,
    entity,
    command,
    event,
    error,
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
pub fn execute_with_metadata(
  event_sourcing event_sourcing: EventSourcing(
    eventstore,
    entity,
    command,
    event,
    error,
  ),
  aggregate_id aggregate_id: AggregateId,
  command command: command,
  metadata metadata: List(#(String, String)),
) -> Result(Nil, EventSourcingError(error)) {
  let aggregate_context = load_aggregate(event_sourcing, aggregate_id)
  case aggregate_context {
    Ok(aggregate_context) ->
      execute_with_aggregate_context(
        event_sourcing,
        aggregate_context,
        command,
        metadata,
      )
    Error(error) -> Error(error)
  }
}

fn execute_with_aggregate_context(
  eventsourcing eventsourcing: EventSourcing(
    eventstore,
    entity,
    command,
    event,
    error,
  ),
  aggregate aggregate: Aggregate(entity, command, event, error),
  command command: command,
  metadata metadata: List(#(String, String)),
) -> Result(Nil, EventSourcingError(error)) {
  let entity = aggregate.entity
  use events <- result.try(
    eventsourcing.handle(entity, command)
    |> result.map_error(fn(error) { DomainError(error) }),
  )
  events |> list.map(eventsourcing.apply(entity, _))
  let commited_events =
    eventsourcing.event_store.commit(
      eventsourcing.event_store.eventstore,
      aggregate,
      events,
      metadata,
    )
  eventsourcing.queries
  |> list.map(fn(query) { query(aggregate.aggregate_id, commited_events) })
  Ok(Nil)
}

pub fn load_aggregate(
  eventsourcing eventsourcing: EventSourcing(
    eventstore,
    entity,
    command,
    event,
    error,
  ),
  aggregate_id aggregate_id: AggregateId,
) -> Result(Aggregate(entity, command, event, error), EventSourcingError(error)) {
  let commited_events = load_events(eventsourcing, aggregate_id)

  let #(instance, sequence) =
    list.fold(
      over: commited_events,
      from: #(eventsourcing.empty_state, 0),
      with: fn(aggregate_and_sequence, event_envelop) {
        let #(aggregate, sequence) = aggregate_and_sequence
        #(eventsourcing.apply(aggregate, event_envelop.payload), sequence + 1)
      },
    )
  Ok(Aggregate(aggregate_id, instance, sequence))
}

/// Add a query to the EventSourcing instance.
///
/// Queries are functions that run when events are committed.
/// They can be used for things like updating read models or sending notifications.
pub fn add_query(
  eventsouring eventsourcing: EventSourcing(
    eventstore,
    entity,
    command,
    event,
    error,
  ),
  query query,
) {
  EventSourcing(..eventsourcing, queries: [query, ..eventsourcing.queries])
}

/// Load the events for a given aggregate ID.
pub fn load_events(
  eventsourcing eventsourcing: EventSourcing(
    eventstore,
    entity,
    command,
    event,
    error,
  ),
  aggregate_id aggregate_id: AggregateId,
) -> List(EventEnvelop(event)) {
  eventsourcing.event_store.load_events(
    eventsourcing.event_store.eventstore,
    aggregate_id,
  )
}
