import gleam/erlang/process
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/otp/static_supervisor
import gleam/otp/supervision
import gleam/result
import gleam/string
import gleam/time/timestamp

pub opaque type Timeout {
  Timeout(milliseconds: Int)
}

pub opaque type Frequency {
  Frequency(n: Int)
}

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
    timestamp: timestamp.Timestamp,
  )
}

pub type SnapshotConfig {
  SnapshotConfig(snapshot_frequency: Frequency)
}

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
  NonPositiveArgument
  EntityNotFound
  TransactionFailed
  TransactionRolledBack
  ActorTimeout(operation: String, timeout_ms: Int)
}

pub type SystemStats {
  SystemStats(query_actors_count: Int, total_commands_processed: Int)
}

pub type AggregateStats {
  AggregateStats(
    aggregate_id: String,
    event_count: Int,
    current_sequence: Int,
    has_snapshot: Bool,
  )
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

pub type QueryActor(event) {
  QueryActor(
    actor: actor.Started(process.Subject(QueryMessage(event))),
    query: Query(event),
  )
}

pub type QueryMessage(event) {
  ProcessEvents(aggregate_id: AggregateId, events: List(EventEnvelop(event)))
}

pub type AggregateMessage(entity, command, event, error) {
  ExecuteCommand(
    aggregate_id: AggregateId,
    command: command,
    metadata: List(#(String, String)),
  )
  RegisterQueryActor(QueryActor(event))
  LoadAggregate(
    aggregate_id: AggregateId,
    reply_to: process.Subject(
      Result(
        Aggregate(entity, command, event, error),
        EventSourcingError(error),
      ),
    ),
  )
  LoadAllEvents(
    aggregate_id: AggregateId,
    reply_to: process.Subject(
      Result(List(EventEnvelop(event)), EventSourcingError(error)),
    ),
  )
  LoadEvents(
    aggregate_id: AggregateId,
    start_from: Int,
    reply_to: process.Subject(
      Result(List(EventEnvelop(event)), EventSourcingError(error)),
    ),
  )
  LoadLatestSnapshot(
    aggregate_id: AggregateId,
    reply_to: process.Subject(
      Result(Option(Snapshot(entity)), EventSourcingError(error)),
    ),
  )
  GetSystemStats(reply_to: process.Subject(SystemStats))
  GetAggregateStats(
    aggregate_id: AggregateId,
    reply_to: process.Subject(Result(AggregateStats, EventSourcingError(error))),
  )
}

pub type ManagerMessage(entity, command, event, error) {
  QueryActorStarted(QueryActor(event))
  GetEventSourcingActor(
    reply_to: process.Subject(
      process.Subject(AggregateMessage(entity, command, event, error)),
    ),
  )
}

pub type ManagerState(
  eventstore,
  entity,
  command,
  event,
  error,
  transaction_handle,
) {
  ManagerState(
    eventsourcing_actor: Option(
      process.Subject(AggregateMessage(entity, command, event, error)),
    ),
    expected_queries: Int,
    registered_queries: Int,
    eventstore: EventStore(
      eventstore,
      entity,
      command,
      event,
      error,
      transaction_handle,
    ),
    handle: Handle(entity, command, event, error),
    apply: Apply(entity, event),
    empty_state: entity,
  )
}

pub opaque type EventSourcing(
  eventstore,
  entity,
  command,
  event,
  error,
  transaction_handle,
) {
  EventSourcing(
    event_store: EventStore(
      eventstore,
      entity,
      command,
      event,
      error,
      transaction_handle,
    ),
    query_actors: List(QueryActor(event)),
    handle: Handle(entity, command, event, error),
    apply: Apply(entity, event),
    empty_state: entity,
    snapshot_config: Option(SnapshotConfig),
    start_time: timestamp.Timestamp,
    commands_processed: Int,
  )
}

pub type EventStore(
  eventstore,
  entity,
  command,
  event,
  error,
  transaction_handle,
) {
  EventStore(
    execute_transaction: fn(
      fn(transaction_handle) -> Result(Nil, EventSourcingError(error)),
    ) ->
      Result(Nil, EventSourcingError(error)),
    load_aggregate_transaction: fn(
      fn(transaction_handle) ->
        Result(
          Aggregate(entity, command, event, error),
          EventSourcingError(error),
        ),
    ) ->
      Result(
        Aggregate(entity, command, event, error),
        EventSourcingError(error),
      ),
    load_events_transaction: fn(
      fn(transaction_handle) ->
        Result(List(EventEnvelop(event)), EventSourcingError(error)),
    ) ->
      Result(List(EventEnvelop(event)), EventSourcingError(error)),
    get_latest_snapshot_transaction: fn(
      fn(transaction_handle) ->
        Result(Option(Snapshot(entity)), EventSourcingError(error)),
    ) ->
      Result(Option(Snapshot(entity)), EventSourcingError(error)),
    commit_events: fn(
      transaction_handle,
      Aggregate(entity, command, event, error),
      List(event),
      List(#(String, String)),
    ) ->
      Result(#(List(EventEnvelop(event)), Int), EventSourcingError(error)),
    load_events: fn(eventstore, transaction_handle, AggregateId, Int) ->
      Result(List(EventEnvelop(event)), EventSourcingError(error)),
    load_snapshot: fn(transaction_handle, AggregateId) ->
      Result(Option(Snapshot(entity)), EventSourcingError(error)),
    save_snapshot: fn(transaction_handle, Snapshot(entity)) ->
      Result(Nil, EventSourcingError(error)),
    eventstore: eventstore,
  )
}

pub type AggregateActorState(
  eventstore,
  entity,
  command,
  event,
  error,
  transaction_handle,
) {
  AggregateActorState(
    aggregate: Aggregate(entity, command, event, error),
    eventsourcing: EventSourcing(
      eventstore,
      entity,
      command,
      event,
      error,
      transaction_handle,
    ),
  )
}

/// Creates a supervised event sourcing architecture with fault tolerance.
/// Sets up a supervision tree where the main event sourcing actor and query actors
/// are managed by a supervisor that can restart them if they fail. This is the 
/// recommended approach for production applications.
///
/// ## Example
/// ```gleam
/// let assert Ok(eventstore) = memory_store.new()
/// let eventsourcing_actor_receiver = process.new_subject()
/// let query_actor_receiver = process.new_subject()
/// let assert Ok(spec) = eventsourcing.supervised(
///   eventstore:,
///   handle: my_handle,
///   apply: my_apply,
///   empty_state: MyState,
///   queries: [],
///   eventsourcing_actor_receiver:,
///   query_actors_receiver:,
///   snapshot_config: None
/// )
/// ```
pub fn supervised(
  eventstore eventstore: EventStore(
    eventstore,
    entity,
    command,
    event,
    error,
    transaction_handle,
  ),
  handle handle: Handle(entity, command, event, error),
  apply apply: Apply(entity, event),
  empty_state empty_state: entity,
  queries queries: List(Query(event)),
  eventsourcing_actor_receiver eventsourcing_actor_receiver: process.Subject(
    actor.Started(
      process.Subject(AggregateMessage(entity, command, event, error)),
    ),
  ),
  query_actors_receiver query_actors_receiver: process.Subject(
    QueryActor(event),
  ),
  snapshot_config snapshot_config: Option(SnapshotConfig),
) -> Result(supervision.ChildSpecification(static_supervisor.Supervisor), Nil) {
  // Create a single coordinator that manages everything properly under supervision
  let queries_child_specs =
    list.map(queries, fn(query) {
      supervision.worker(fn() {
        use query_actor <- result.try(start_query(query))
        process.send(query_actors_receiver, query_actor)
        Ok(query_actor.actor)
      })
    })
  let eventsourcing_spec =
    supervision.worker(fn() {
      use eventsourcing_actor <- result.try(start(
        eventstore: eventstore,
        handle: handle,
        query_actors: [],
        apply: apply,
        empty_state: empty_state,
        snapshot_config:,
      ))
      process.send(eventsourcing_actor_receiver, eventsourcing_actor)
      Ok(eventsourcing_actor)
    })

  let supervisor =
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.add(eventsourcing_spec)
    |> list.fold(queries_child_specs, _, fn(supervisor, spec) {
      static_supervisor.add(supervisor, spec)
    })
    |> static_supervisor.supervised()
    |> Ok

  supervisor
}

/// Registers query actors with the event sourcing system after supervisor startup.
/// Queries must be added beforehand to the supervised() function to ensure their actors are started and supervised.
///
/// ## Example
/// ```gleam
/// let queries = [projection_query, analytics_query]
/// let assert Ok(query_actors) = list.try_map(queries, fn(_) { 
///   process.receive(query_receiver, 1000) 
/// })
/// eventsourcing.register_queries(eventsourcing_actor, query_actors)
/// ```
pub fn register_queries(
  eventsourcing_actor: actor.Started(
    process.Subject(AggregateMessage(entity, command, event, error)),
  ),
  query_actors: List(QueryActor(event)),
) -> Nil {
  query_actors
  |> list.each(fn(query_actor) {
    process.send(eventsourcing_actor.data, RegisterQueryActor(query_actor))
  })
}

/// Executes a command against an aggregate in the event sourcing system.
/// The command will be validated, events generated if successful, and the events
/// will be persisted and sent to all registered query actors. Commands that violate
/// business rules will be rejected without affecting system stability.
///
/// ## Example
/// ```gleam
/// eventsourcing.execute(actor, "bank-account-123", OpenAccount("123"))
/// // Command is processed asynchronously via message passing
/// ```
pub fn execute(
  eventsourcing_actor: actor.Started(
    process.Subject(AggregateMessage(entity, command, event, error)),
  ),
  aggregate_id: AggregateId,
  command: command,
) -> Nil {
  process.send(
    eventsourcing_actor.data,
    ExecuteCommand(aggregate_id, command, []),
  )
}

/// Executes a command against an aggregate with additional metadata.
/// The metadata will be stored with the generated events and can be used for
/// tracking, auditing, or enriching events with contextual information.
///
/// ## Example
/// ```gleam
/// let metadata = [("user_id", "alice"), ("session_id", "abc123")]
/// eventsourcing.execute_with_metadata(actor, "bank-123", DepositMoney(100.0), metadata)
/// ```
pub fn execute_with_metadata(
  eventsourcing_actor: actor.Started(
    process.Subject(AggregateMessage(entity, command, event, error)),
  ),
  aggregate_id: AggregateId,
  command: command,
  metadata: List(#(String, String)),
) -> Nil {
  process.send(
    eventsourcing_actor.data,
    ExecuteCommand(aggregate_id, command, metadata),
  )
}

fn start(
  eventstore eventstore: EventStore(
    eventstore,
    entity,
    command,
    event,
    error,
    transaction_handle,
  ),
  handle handle: Handle(entity, command, event, error),
  query_actors query_actors: List(QueryActor(event)),
  apply apply: Apply(entity, event),
  empty_state empty_state: entity,
  snapshot_config snapshot_config: Option(SnapshotConfig),
) -> actor.StartResult(
  process.Subject(AggregateMessage(entity, command, event, error)),
) {
  actor.new(EventSourcing(
    event_store: eventstore,
    query_actors: query_actors,
    handle: handle,
    apply: apply,
    empty_state: empty_state,
    snapshot_config: snapshot_config,
    start_time: timestamp.system_time(),
    commands_processed: 0,
  ))
  |> actor.on_message(on_message)
  |> actor.start()
}

fn on_message(
  state: EventSourcing(
    eventstore,
    entity,
    command,
    event,
    error,
    transaction_handle,
  ),
  message: AggregateMessage(entity, command, event, error),
) -> actor.Next(
  EventSourcing(eventstore, entity, command, event, error, transaction_handle),
  AggregateMessage(entity, command, event, error),
) {
  case message {
    LoadLatestSnapshot(aggregate_id, reply_to) -> {
      let result = {
        use tx <- state.event_store.get_latest_snapshot_transaction()
        case state.snapshot_config {
          None -> Ok(None)
          Some(_) -> state.event_store.load_snapshot(tx, aggregate_id)
        }
      }
      process.send(reply_to, result)
      actor.continue(state)
    }
    LoadEvents(aggregate_id, start_from, reply_to) -> {
      let result = {
        use tx <- state.event_store.load_events_transaction()
        state.event_store.load_events(
          state.event_store.eventstore,
          tx,
          aggregate_id,
          start_from,
        )
      }
      process.send(reply_to, result)
      actor.continue(state)
    }
    LoadAllEvents(aggregate_id, reply_to) -> {
      let result = {
        use tx <- state.event_store.load_events_transaction()
        state.event_store.load_events(
          state.event_store.eventstore,
          tx,
          aggregate_id,
          0,
        )
      }
      process.send(reply_to, result)
      actor.continue(state)
    }
    LoadAggregate(aggregate_id, reply_to) -> {
      let result = {
        use tx <- state.event_store.load_aggregate_transaction()
        load_aggregate_or_create_new(state, tx, aggregate_id)
        |> result.try(fn(aggregate) {
          case aggregate.entity == state.empty_state {
            True -> Error(EntityNotFound)
            False -> Ok(aggregate)
          }
        })
      }
      process.send(reply_to, result)
      actor.continue(state)
    }
    RegisterQueryActor(query_actor) -> {
      let new_state =
        EventSourcing(..state, query_actors: [query_actor, ..state.query_actors])
      actor.continue(new_state)
    }
    ExecuteCommand(aggregate_id, command, metadata) -> {
      let result = {
        use tx <- state.event_store.execute_transaction()
        use aggregate <- result.try(load_aggregate_or_create_new(
          state,
          tx,
          aggregate_id,
        ))

        use events <- result.try(
          state.handle(aggregate.entity, command)
          |> result.map_error(fn(error) { DomainError(error) }),
        )

        let aggregate =
          Aggregate(
            ..aggregate,
            entity: events
              |> list.fold(aggregate.entity, fn(entity, event) {
                state.apply(entity, event)
              }),
          )

        use #(commited_events, sequence) <- result.try(
          state.event_store.commit_events(tx, aggregate, events, metadata),
        )

        use _ <- result.try(case state.snapshot_config {
          Some(config) if sequence % config.snapshot_frequency.n == 0 -> {
            let snapshot =
              Snapshot(
                aggregate_id: aggregate.aggregate_id,
                entity: aggregate.entity,
                sequence: sequence,
                timestamp: timestamp.system_time(),
              )
            state.event_store.save_snapshot(tx, snapshot)
          }
          _ -> Ok(Nil)
        })

        state.query_actors
        |> list.each(fn(query) {
          process.send(
            query.actor.data,
            ProcessEvents(aggregate_id, commited_events),
          )
        })
        Ok(Nil)
      }

      case result {
        Ok(_) -> {
          let updated_state =
            EventSourcing(
              ..state,
              commands_processed: state.commands_processed + 1,
            )
          actor.continue(updated_state)
        }
        Error(DomainError(_)) -> {
          let updated_state =
            EventSourcing(
              ..state,
              commands_processed: state.commands_processed + 1,
            )
          actor.continue(updated_state)
        }
        Error(error) -> {
          actor.stop_abnormal(describe_error(error))
        }
      }
    }
    GetSystemStats(reply_to) -> {
      let stats =
        SystemStats(
          query_actors_count: list.length(state.query_actors),
          total_commands_processed: state.commands_processed,
        )

      process.send(reply_to, stats)
      actor.continue(state)
    }
    GetAggregateStats(aggregate_id, reply_to) -> {
      // First get the events
      let events_result = {
        use tx <- state.event_store.load_events_transaction()
        state.event_store.load_events(
          state.event_store.eventstore,
          tx,
          aggregate_id,
          0,
        )
      }

      // Then process them into stats
      let result = case events_result {
        Ok(events) -> {
          let event_count = list.length(events)
          let current_sequence = case events {
            [] -> 0
            _ ->
              events
              |> list.last()
              |> result.map(fn(envelope) { envelope.sequence })
              |> result.unwrap(0)
          }

          // Check if snapshot exists for this aggregate
          let has_snapshot = case state.snapshot_config {
            Some(_) -> {
              case
                {
                  use tx_snap <- state.event_store.get_latest_snapshot_transaction()
                  state.event_store.load_snapshot(tx_snap, aggregate_id)
                }
              {
                Ok(_) -> True
                Error(_) -> False
              }
            }
            None -> False
          }

          let stats =
            AggregateStats(
              aggregate_id: aggregate_id,
              event_count: event_count,
              current_sequence: current_sequence,
              has_snapshot: has_snapshot,
            )

          Ok(stats)
        }
        Error(error) -> Error(error)
      }

      process.send(reply_to, result)
      actor.continue(state)
    }
  }
}

fn describe_error(error: EventSourcingError(_)) -> String {
  case error {
    DomainError(domainerror) -> "Domain error: " <> string.inspect(domainerror)
    EventStoreError(msg) -> "Event store error: " <> msg
    NonPositiveArgument -> "Non-positive argument"
    EntityNotFound -> "Entity not found"
    TransactionFailed -> "Transaction failed"
    TransactionRolledBack -> "Transaction rolled back"
    ActorTimeout(operation, timeout_ms) ->
      "Actor timeout: "
      <> operation
      <> " failed after "
      <> int.to_string(timeout_ms)
      <> "ms"
  }
}

fn load_aggregate_or_create_new(
  eventsourcing: EventSourcing(
    eventstore,
    entity,
    command,
    event,
    error,
    transaction_handle,
  ),
  tx: transaction_handle,
  aggregate_id: AggregateId,
) -> Result(Aggregate(entity, command, event, error), EventSourcingError(error)) {
  use maybe_snapshot <- result.try(case eventsourcing.snapshot_config {
    None -> Ok(None)
    Some(_) -> eventsourcing.event_store.load_snapshot(tx, aggregate_id)
  })

  let #(starting_state, starting_sequence) = case maybe_snapshot {
    None -> #(eventsourcing.empty_state, 0)
    Some(snapshot) -> #(snapshot.entity, snapshot.sequence)
  }

  use events <- result.map(eventsourcing.event_store.load_events(
    eventsourcing.event_store.eventstore,
    tx,
    aggregate_id,
    starting_sequence,
  ))

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

/// Loads the current state of an aggregate asynchronously by replaying all its events.
/// Returns a subject that will receive the aggregate with its current entity state and sequence number.
/// Use process.receive() to get the result. Returns EntityNotFound error if aggregate doesn't exist.
///
/// ## Example
/// ```gleam
/// let result = eventsourcing.load_aggregate(actor, "bank-account-123")
/// let assert Ok(aggregate) = process.receive(result, 1000)
/// // aggregate.entity contains current state, aggregate.sequence shows current version
/// ```
pub fn load_aggregate(
  eventsourcing_actor: actor.Started(
    process.Subject(AggregateMessage(entity, command, event, error)),
  ),
  aggregate_id: AggregateId,
) -> process.Subject(
  Result(Aggregate(entity, command, event, error), EventSourcingError(error)),
) {
  let receiver = process.new_subject()
  process.send(eventsourcing_actor.data, LoadAggregate(aggregate_id, receiver))
  receiver
}

/// Loads all events for a specific aggregate asynchronously from the beginning.
/// Returns a subject that will receive a chronologically ordered list of all events
/// that have occurred for the aggregate. Use process.receive() to get the result.
///
/// ## Example
/// ```gleam
/// let result = eventsourcing.load_events(actor, "bank-account-123")
/// let assert Ok(events) = process.receive(result, 1000)
/// // events contains all EventEnvelop items for this aggregate
/// ```
pub fn load_events(
  eventsourcing_actor: actor.Started(
    process.Subject(AggregateMessage(entity, command, event, error)),
  ),
  aggregate_id: AggregateId,
) -> process.Subject(
  Result(List(EventEnvelop(event)), EventSourcingError(error)),
) {
  let receiver = process.new_subject()
  process.send(eventsourcing_actor.data, LoadAllEvents(aggregate_id, receiver))
  receiver
}

/// Loads events for an aggregate asynchronously starting from a specific sequence number.
/// Returns a subject that will receive the events list. Useful for pagination or continuing
/// event processing from a known point. Use process.receive() to get the result.
///
/// ## Example
/// ```gleam
/// let result = eventsourcing.load_events_from(actor, "bank-account-123", start_from: 10)
/// let assert Ok(events) = process.receive(result, 1000)
/// // events contains EventEnvelop items starting from sequence 10
/// ```
pub fn load_events_from(
  eventsourcing_actor: actor.Started(
    process.Subject(AggregateMessage(entity, command, event, error)),
  ),
  aggregate_id aggregate_id: AggregateId,
  start_from start_from: Int,
) -> process.Subject(
  Result(List(EventEnvelop(event)), EventSourcingError(error)),
) {
  let receiver = process.new_subject()
  process.send(
    eventsourcing_actor.data,
    LoadEvents(aggregate_id, start_from, receiver),
  )
  receiver
}

/// Gets system statistics including uptime, command count, and query actor health.
/// Returns a subject that will receive the SystemStats. Use process.receive() to get the result.
/// Useful for monitoring system health and performance in production.
///
/// ## Example
/// ```gleam
/// let result = eventsourcing.system_stats(actor)
/// let assert Ok(stats) = process.receive(result, 1000)
/// io.println("Uptime: " <> int.to_string(stats.uptime_seconds) <> " seconds")
/// ```
pub fn system_stats(
  eventsourcing_actor: actor.Started(
    process.Subject(AggregateMessage(entity, command, event, error)),
  ),
) -> process.Subject(SystemStats) {
  let receiver = process.new_subject()
  process.send(eventsourcing_actor.data, GetSystemStats(receiver))
  receiver
}

/// Gets statistics for a specific aggregate including event count and snapshot status.
/// Returns a subject that will receive the AggregateStats result. Use process.receive() to get the result.
/// Useful for debugging and monitoring individual aggregate health.
///
/// ## Example
/// ```gleam
/// let result = eventsourcing.aggregate_stats(actor, "bank-account-123")
/// let assert Ok(stats) = process.receive(result, 1000)
/// io.println("Events: " <> int.to_string(stats.event_count))
/// ```
pub fn aggregate_stats(
  eventsourcing_actor: actor.Started(
    process.Subject(AggregateMessage(entity, command, event, error)),
  ),
  aggregate_id: AggregateId,
) -> process.Subject(Result(AggregateStats, EventSourcingError(error))) {
  let receiver = process.new_subject()
  process.send(
    eventsourcing_actor.data,
    GetAggregateStats(aggregate_id, receiver),
  )
  receiver
}

/// Retrieves the most recent snapshot for an aggregate asynchronously if snapshots are enabled.
/// Returns a subject that will receive the snapshot option. Snapshots provide a point-in-time
/// capture of aggregate state for faster reconstruction. Use process.receive() to get the result.
///
/// ## Example
/// ```gleam
/// let result = eventsourcing.latest_snapshot(actor, "bank-account-123")
/// let assert Ok(Some(snapshot)) = process.receive(result, 1000)
/// // snapshot.entity contains the saved state, snapshot.sequence shows version
/// ```
pub fn latest_snapshot(
  eventsourcing_actor: actor.Started(
    process.Subject(AggregateMessage(entity, command, event, error)),
  ),
  aggregate_id aggregate_id: AggregateId,
) -> process.Subject(
  Result(Option(Snapshot(entity)), EventSourcingError(error)),
) {
  let receiver = process.new_subject()
  process.send(
    eventsourcing_actor.data,
    LoadLatestSnapshot(aggregate_id, receiver),
  )
  receiver
}

fn start_query(
  query: Query(event),
) -> Result(QueryActor(event), actor.StartError) {
  use actor <- result.try(
    actor.new(Nil)
    |> actor.on_message(fn(_, message) {
      case message {
        ProcessEvents(aggregate_id, events) -> {
          query(aggregate_id, events)
          actor.continue(Nil)
        }
      }
    })
    |> actor.start(),
  )
  Ok(QueryActor(actor:, query:))
}

/// Creates a validated timeout value for use with process operations.
/// Ensures that timeout values are positive, preventing invalid configurations
/// that could cause system operations to behave unexpectedly.
///
/// ## Example
/// ```gleam
/// let assert Ok(timeout) = eventsourcing.timeout(5000)
/// let result = process.receive(subject, timeout)
/// ```
pub fn timeout(ms ms: Int) -> Result(Timeout, EventSourcingError(_)) {
  case ms <= 0 {
    True -> Error(NonPositiveArgument)
    False -> Ok(Timeout(ms))
  }
}

/// Creates a validated frequency value for snapshot configuration.
/// Snapshots will be created every N events when this frequency is used.
/// Ensures that frequency values are positive to prevent division by zero or infinite loops.
///
/// ## Example
/// ```gleam
/// let assert Ok(freq) = eventsourcing.frequency(5)
/// let config = eventsourcing.SnapshotConfig(freq)
/// ```
pub fn frequency(n n: Int) -> Result(Frequency, EventSourcingError(_)) {
  case n <= 0 {
    True -> Error(NonPositiveArgument)
    False -> Ok(Frequency(n))
  }
}
