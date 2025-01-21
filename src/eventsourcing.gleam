import birl
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

// TYPES ----
pub type AggregateId =
  String

pub type Aggregate(entity, command, event, error) {
  Aggregate(aggregate_id: AggregateId, entity: entity, sequence: Int)
}

pub type Snapshot(entity) {
  Snapshot(
    aggregate_id: AggregateId,
    entity: entity,
    sequence: Int,
    timestamp: Int,
  )
}

pub type SnapshotConfig {
  SnapshotConfig(snapshot_frequency: Int)
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
pub opaque type EventSourcing(eventstore, entity, command, event, error) {
  EventSourcing(
    event_store: EventStore(eventstore, entity, command, event, error),
    queries: List(Query(event)),
    handle: Handle(entity, command, event, error),
    apply: Apply(entity, event),
    empty_state: entity,
    snapshot_config: Option(SnapshotConfig),
  )
}

/// Wrapper around the event store implementations
pub type EventStore(eventstore, entity, command, event, error) {
  EventStore(
    eventstore: eventstore,
    load_events: fn(eventstore, AggregateId) ->
      Result(List(EventEnvelop(event)), EventSourcingError(error)),
    commit: fn(
      eventstore,
      Aggregate(entity, command, event, error),
      List(event),
      List(#(String, String)),
    ) ->
      Result(#(List(EventEnvelop(event)), Int), EventSourcingError(error)),
    // New optional snapshot methods
    save_snapshot: fn(eventstore, Snapshot(entity)) -> Nil,
    load_snapshot: fn(eventstore, AggregateId) ->
      Result(Option(Snapshot(entity)), EventSourcingError(error)),
  )
}

// CONSTRUCTORS ----

/// Create a new EventSourcing instance providing 
/// an Event Store and a list of queries you want
/// run whenever events are commited.
///
pub fn new(event_store, queries, handle, apply, empty_state) {
  EventSourcing(
    event_store:,
    queries:,
    handle:,
    apply:,
    empty_state:,
    snapshot_config: None,
  )
}

pub fn with_snapshots(
  event_sourcing: EventSourcing(eventstore, entity, command, event, error),
  config: SnapshotConfig,
) -> EventSourcing(eventstore, entity, command, event, error) {
  EventSourcing(..event_sourcing, snapshot_config: Some(config))
}

// PUBLIC FUNCTIONS ----

/// Execute the given command on the event sourcing instance.
///
/// This function loads the aggregate, handles the command,
/// applies the resulting events, commits them to the event store,
/// and runs any registered queries.
pub fn execute(
  eventsourcing eventsourcing: EventSourcing(
    eventstore,
    entity,
    command,
    event,
    error,
  ),
  aggregate_id aggregate_id: AggregateId,
  command command: command,
) -> Result(Nil, EventSourcingError(error)) {
  execute_with_metadata(eventsourcing:, aggregate_id:, command:, metadata: [])
}

/// Execute the given command with metadata on the event sourcing instance.
///
/// This function works similarly to `execute`, but additionally allows
/// passing metadata for the events.
pub fn execute_with_metadata(
  eventsourcing eventsourcing: EventSourcing(
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
  use aggregate <- result.try(load_aggregate_or_emtpy_aggregate(
    eventsourcing,
    aggregate_id,
  ))
  let entity = aggregate.entity

  use events <- result.try(
    eventsourcing.handle(entity, command)
    |> result.map_error(fn(error) { DomainError(error) }),
  )

  let post_command_aggregate =
    Aggregate(
      ..aggregate,
      entity: events
        |> list.fold(aggregate.entity, fn(event, entity) {
          eventsourcing.apply(event, entity)
        }),
    )

  use #(commited_events, sequence) <- result.try(
    eventsourcing.event_store.commit(
      eventsourcing.event_store.eventstore,
      post_command_aggregate,
      events,
      metadata,
    ),
  )

  // Check if we need to create a snapshot
  case eventsourcing.snapshot_config {
    Some(config) -> {
      case
        sequence % config.snapshot_frequency == 0
        && config.snapshot_frequency != 0
      {
        True -> {
          let snapshot =
            Snapshot(
              aggregate_id: aggregate.aggregate_id,
              entity: post_command_aggregate.entity,
              sequence: sequence,
              timestamp: birl.to_unix(birl.now()),
            )
          eventsourcing.event_store.save_snapshot(
            eventsourcing.event_store.eventstore,
            snapshot,
          )
        }
        False -> Nil
      }
    }
    None -> Nil
  }

  eventsourcing.queries
  |> list.map(fn(query) { query(aggregate.aggregate_id, commited_events) })
  Ok(Nil)
}

fn load_aggregate_or_emtpy_aggregate(
  eventsourcing eventsourcing: EventSourcing(
    eventstore,
    entity,
    command,
    event,
    error,
  ),
  aggregate_id aggregate_id: AggregateId,
) -> Result(Aggregate(entity, command, event, error), EventSourcingError(error)) {
  use maybe_snapshot <- result.try(eventsourcing.event_store.load_snapshot(
    eventsourcing.event_store.eventstore,
    aggregate_id,
  ))

  use events <- result.map(load_events(eventsourcing, aggregate_id))

  let #(starting_state, starting_sequence) = case maybe_snapshot {
    None -> #(eventsourcing.empty_state, 0)
    Some(snapshot) -> #(snapshot.entity, snapshot.sequence)
  }

  let #(instance, sequence) =
    events
    |> list.drop_while(fn(event) { event.sequence <= starting_sequence })
    |> list.fold(
      from: #(starting_state, starting_sequence),
      with: fn(aggregate_and_sequence, event_envelop) {
        let #(aggregate, sequence) = aggregate_and_sequence
        #(eventsourcing.apply(aggregate, event_envelop.payload), sequence + 1)
      },
    )
  Aggregate(aggregate_id, instance, sequence)
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
  load_aggregate_or_emtpy_aggregate(eventsourcing, aggregate_id)
  |> result.try(fn(aggregate) {
    case aggregate.entity == eventsourcing.empty_state {
      True -> Error(EntityNotFound)
      False -> Ok(aggregate)
    }
  })
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
) -> Result(List(EventEnvelop(event)), EventSourcingError(error)) {
  eventsourcing.event_store.load_events(
    eventsourcing.event_store.eventstore,
    aggregate_id,
  )
}

/// Get the latest snapshot for a given aggregate ID.
/// Returns None if no snapshot exists or if snapshots are not configured.
pub fn get_latest_snapshot(
  eventsourcing eventsourcing: EventSourcing(
    eventstore,
    entity,
    command,
    event,
    error,
  ),
  aggregate_id aggregate_id: AggregateId,
) -> Result(Option(Snapshot(entity)), EventSourcingError(error)) {
  // If snapshots are not configured, return None
  case eventsourcing.snapshot_config {
    None -> Ok(None)
    Some(_) -> {
      // Load snapshot from event store
      eventsourcing.event_store.load_snapshot(
        eventsourcing.event_store.eventstore,
        aggregate_id,
      )
    }
  }
}
