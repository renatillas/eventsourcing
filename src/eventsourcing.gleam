import birl
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

/// Type representing an aggregate's unique identifier.
/// This is used to identify different aggregates in the event sourcing system.
pub type AggregateId =
  String

/// Represents the current state of an aggregate in the event sourcing system.
/// 
/// ## Fields
/// - `aggregate_id`: Unique identifier for the aggregate
/// - `entity`: The current state of the entity
/// - `sequence`: The current sequence number of the aggregate
pub type Aggregate(entity, command, event, error) {
  Aggregate(aggregate_id: AggregateId, entity: entity, sequence: Int)
}

/// Represents a snapshot of an aggregate's state at a specific point in time.
/// Snapshots are used to optimize aggregate rebuilding by providing a starting point.
/// 
/// ## Fields
/// - `aggregate_id`: The aggregate this snapshot belongs to
/// - `entity`: The state of the entity at the time of snapshot
/// - `sequence`: The sequence number at which this snapshot was taken
/// - `timestamp`: Unix timestamp when the snapshot was created
pub type Snapshot(entity) {
  Snapshot(
    aggregate_id: AggregateId,
    entity: entity,
    sequence: Int,
    timestamp: Int,
  )
}

/// Configuration for snapshot creation behavior.
/// 
/// ## Fields
/// - `snapshot_frequency`: Number of events after which a new snapshot should be created
pub type SnapshotConfig {
  SnapshotConfig(snapshot_frequency: Int)
}

/// Wrapper around domain events that includes metadata and sequencing information.
/// Used by Event Stores to persist and retrieve events.
/// 
/// ## Variants
/// - `MemoryStoreEventEnvelop`: Used for in-memory event storage
/// - `SerializedEventEnvelop`: Used for persistent storage with serialization support
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

/// Represents errors that can occur in the event sourcing system.
/// 
/// ## Variants
/// - `DomainError`: Domain-specific errors from command handling
/// - `EventStoreError`: Errors related to event storage operations
/// - `EntityNotFound`: When attempting to load a non-existent aggregate
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
/// for other functions such as execute, load_aggregate, and load_events
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

/// The main type of the event sourcing system that coordinates all operations.
/// 
/// ## Fields
/// - `event_store`: The storage implementation for events and snapshots
/// - `queries`: List of query handlers to process events
/// - `handle`: Command handler function
/// - `apply`: Event application function
/// - `empty_state`: Initial state for new aggregates
/// - `snapshot_config`: Optional configuration for snapshot creation
pub type EventStore(eventstore, entity, command, event, error) {
  EventStore(
    eventstore: eventstore,
    load_events: fn(eventstore, AggregateId, Int) ->
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

/// Creates a new EventSourcing instance with the provided configuration.
/// 
/// ## Arguments
/// - `event_store`: The storage implementation to use
/// - `queries`: List of query handlers to process events
/// - `handle`: Function to handle commands
/// - `apply`: Function to apply events
/// - `empty_state`: Initial state for new aggregates
/// 
/// ## Returns
/// A new EventSourcing instance without snapshot support
pub fn new(
  event_store event_store: EventStore(eventstore, entity, command, event, error),
  queries queries: List(Query(event)),
  handle handle: Handle(entity, command, event, error),
  apply apply: Apply(entity, event),
  emtpy_state empty_state: entity,
) {
  EventSourcing(
    event_store:,
    queries:,
    handle:,
    apply:,
    empty_state:,
    snapshot_config: None,
  )
}

// Enables snapshot support for an EventSourcing instance.
/// 
/// ## Arguments
/// - `event_sourcing`: The EventSourcing instance to modify
/// - `config`: Snapshot configuration specifying creation frequency
/// 
/// ## Returns
/// A new EventSourcing instance with snapshot support enabled
pub fn with_snapshots(
  event_sourcing: EventSourcing(eventstore, entity, command, event, error),
  config: SnapshotConfig,
) -> EventSourcing(eventstore, entity, command, event, error) {
  EventSourcing(..event_sourcing, snapshot_config: Some(config))
}

/// Executes a command against an aggregate.
/// 
/// ## Arguments
/// - `event_sourcing`: The EventSourcing instance
/// - `aggregate_id`: ID of the aggregate to execute command against
/// - `command`: The command to execute
/// 
/// ## Returns
/// Ok(Nil) if successful, or an error if command handling fails
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

/// Executes a command with additional metadata.
/// 
/// ## Arguments
/// - `event_sourcing`: The EventSourcing instance
/// - `aggregate_id`: ID of the aggregate to execute command against
/// - `command`: The command to execute
/// - `metadata`: Additional metadata to store with generated events
/// 
/// ## Returns
/// Ok(Nil) if successful, or an error if command handling fails
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

/// Loads the current state of an aggregate.
/// 
/// ## Arguments
/// - `event_sourcing`: The EventSourcing instance
/// - `aggregate_id`: ID of the aggregate to load
/// 
/// ## Returns
/// The current state of the aggregate, or an error if loading fails
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

/// Loads all events for an aggregate from a specified sequence number.
/// 
/// This function retrieves all events for an aggregate starting from a given sequence number,
/// allowing for partial event stream loading and event replay from a specific point in time.
/// 
/// ## Arguments
/// - `event_sourcing`: The EventSourcing instance
/// - `aggregate_id`: ID of the aggregate whose events should be loaded
/// - `start_from`: The sequence number to start loading events from
/// 
/// ## Returns
/// A Result containing:
/// - Ok(List(EventEnvelop(event))): List of events if successful
/// - Error(EventSourcingError): If loading fails
/// 
/// ## Example
/// ```gleam
/// let assert Ok(events) = load_events(event_sourcing, "account-123", 5)
/// // events will contain all events for account-123 starting from sequence 5
/// ```
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
    0,
  )
}

/// Retrieves the most recent snapshot for an aggregate if it exists.
/// 
/// This function attempts to load the latest snapshot for an aggregate, which can be
/// used as a starting point for rebuilding aggregate state without replaying all events
/// from the beginning.
/// 
/// ## Arguments
/// - `event_sourcing`: The EventSourcing instance
/// - `aggregate_id`: ID of the aggregate to get the snapshot for
/// 
/// ## Returns
/// A Result containing:
/// - Ok(Some(Snapshot)): The latest snapshot if one exists
/// - Ok(None): If no snapshot exists for the aggregate
/// - Error(EventSourcingError): If snapshot retrieval fails
/// 
/// ## Example
/// ```gleam
/// let assert Ok(maybe_snapshot) = get_latest_snapshot(event_sourcing, "account-123")
/// case maybe_snapshot {
///   Some(snapshot) -> // Use snapshot as starting point
///   None -> // No snapshot exists, start from initial state
/// }
/// ```
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

fn load_aggregate_or_emtpy_aggregate(
  eventsourcing: EventSourcing(eventstore, entity, command, event, error),
  aggregate_id: AggregateId,
) -> Result(Aggregate(entity, command, event, error), EventSourcingError(error)) {
  use maybe_snapshot <- result.try(eventsourcing.event_store.load_snapshot(
    eventsourcing.event_store.eventstore,
    aggregate_id,
  ))

  let start_from = case maybe_snapshot {
    Some(snapshot) -> snapshot.sequence
    None -> 0
  }
  use events <- result.map(eventsourcing.event_store.load_events(
    eventsourcing.event_store.eventstore,
    aggregate_id,
    start_from,
  ))

  let #(starting_state, starting_sequence) = case maybe_snapshot {
    None -> #(eventsourcing.empty_state, 0)
    Some(snapshot) -> #(snapshot.entity, snapshot.sequence)
  }

  let #(instance, sequence) =
    events
    |> list.fold(
      from: #(starting_state, starting_sequence),
      with: fn(aggregate_and_sequence, event_envelop) {
        let #(aggregate, sequence) = aggregate_and_sequence
        #(eventsourcing.apply(aggregate, event_envelop.payload), sequence + 1)
      },
    )
  Aggregate(aggregate_id, instance, sequence)
}
