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
  QueryActor(actor: process.Subject(QueryMessage(event)))
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
    query_actors: List(process.Name(QueryMessage(event))),
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
/// For the queries to work you have to register them after the supervisor is started using register_queries().
///
/// ## Example
/// ```gleam
/// // First set up memory store
/// let events_name = process.new_name("events_actor")
/// let snapshot_name = process.new_name("snapshot_actor")
/// let #(store, _) = memory_store.supervised(events_name, snapshot_name, static_supervisor.OneForOne)
/// 
/// // Then create event sourcing system
/// let balance_query = #(process.new_name("balance_query"), fn(aggregate_id, events) { /* update read model */ })
/// let assert Ok(spec) = eventsourcing.supervised(
///   name: process.new_name("eventsourcing_actor"),
///   eventstore: store,
///   handle: my_handle,
///   apply: my_apply,
///   empty_state: MyState,
///   queries: [balance_query],
///   snapshot_config: None
/// )
/// ```
pub fn supervised(
  name name: process.Name(AggregateMessage(entity, command, event, error)),
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
  queries queries: List(#(process.Name(QueryMessage(event)), Query(event))),
  snapshot_config snapshot_config: Option(SnapshotConfig),
) -> Result(supervision.ChildSpecification(static_supervisor.Supervisor), Nil) {
  // Create a single coordinator that manages everything properly under supervision
  let queries =
    list.map(queries, fn(query) {
      let #(name, query) = query
      #(name, supervision.worker(fn() { start_query(name, query) }))
    })
  let names = list.map(queries, fn(query) { query.0 })
  let specs = list.map(queries, fn(query) { query.1 })

  let eventsourcing_spec =
    supervision.worker(fn() {
      use eventsourcing <- result.try(start(
        name:,
        eventstore: eventstore,
        handle: handle,
        query_actors: names,
        apply: apply,
        empty_state: empty_state,
        snapshot_config:,
      ))
      Ok(eventsourcing)
    })

  let supervisor =
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.add(eventsourcing_spec)
    |> list.fold(specs, _, fn(supervisor, spec) {
      static_supervisor.add(supervisor, spec)
    })
    |> static_supervisor.supervised()
    |> Ok

  supervisor
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
  eventsourcing_actor: process.Subject(
    AggregateMessage(entity, command, event, error),
  ),
  aggregate_id: AggregateId,
  command: command,
) -> Nil {
  process.send(eventsourcing_actor, ExecuteCommand(aggregate_id, command, []))
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
  eventsourcing_actor: process.Subject(
    AggregateMessage(entity, command, event, error),
  ),
  aggregate_id: AggregateId,
  command: command,
  metadata: List(#(String, String)),
) -> Nil {
  process.send(
    eventsourcing_actor,
    ExecuteCommand(aggregate_id, command, metadata),
  )
}

fn start(
  name name: process.Name(AggregateMessage(entity, command, event, error)),
  eventstore eventstore: EventStore(
    eventstore,
    entity,
    command,
    event,
    error,
    transaction_handle,
  ),
  handle handle: Handle(entity, command, event, error),
  query_actors query_actors,
  apply apply: Apply(entity, event),
  empty_state empty_state: entity,
  snapshot_config snapshot_config: Option(SnapshotConfig),
) -> actor.StartResult(
  process.Subject(AggregateMessage(entity, command, event, error)),
) {
  actor.new(EventSourcing(
    event_store: eventstore,
    query_actors:,
    handle: handle,
    apply: apply,
    empty_state: empty_state,
    snapshot_config: snapshot_config,
    start_time: timestamp.system_time(),
    commands_processed: 0,
  ))
  |> actor.on_message(on_message)
  |> actor.named(name)
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
            process.named_subject(query),
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
  eventsourcing: process.Subject(
    AggregateMessage(entity, command, event, error),
  ),
  aggregate_id: AggregateId,
) -> process.Subject(
  Result(Aggregate(entity, command, event, error), EventSourcingError(error)),
) {
  let receiver = process.new_subject()
  process.send(eventsourcing, LoadAggregate(aggregate_id, receiver))
  receiver
}

/// Loads all events for a specific aggregate asynchronously from the beginning.
/// Returns a subject that will receive a chronologically ordered list of all events
/// that have occurred for the aggregate. Use process.receive() to get the result.
///
/// ## Example
/// ```gleam
/// let result = eventsourcing.load_events(eventsourcing, "bank-account-123")
/// let assert Ok(events) = process.receive(result, 1000)
/// // events contains all EventEnvelop items for this aggregate
/// ```
pub fn load_events(
  eventsourcing: process.Subject(
    AggregateMessage(entity, command, event, error),
  ),
  aggregate_id: AggregateId,
) -> process.Subject(
  Result(List(EventEnvelop(event)), EventSourcingError(error)),
) {
  let receiver = process.new_subject()
  process.send(eventsourcing, LoadAllEvents(aggregate_id, receiver))
  receiver
}

/// Loads events for an aggregate asynchronously starting from a specific sequence number.
/// Returns a subject that will receive the events list. Useful for pagination or continuing
/// event processing from a known point. Use process.receive() to get the result.
///
/// ## Example
/// ```gleam
/// let result = eventsourcing.load_events_from(eventsourcing, "bank-account-123", start_from: 10)
/// let assert Ok(events) = process.receive(result, 1000)
/// // events contains EventEnvelop items starting from sequence 10
/// ```
pub fn load_events_from(
  eventsourcing: process.Subject(
    AggregateMessage(entity, command, event, error),
  ),
  aggregate_id aggregate_id: AggregateId,
  start_from start_from: Int,
) -> process.Subject(
  Result(List(EventEnvelop(event)), EventSourcingError(error)),
) {
  let receiver = process.new_subject()
  process.send(eventsourcing, LoadEvents(aggregate_id, start_from, receiver))
  receiver
}

/// Gets system statistics including command count and query actor health.
/// Returns a subject that will receive the SystemStats. Use process.receive() to get the result.
/// Useful for monitoring system health and performance in production.
///
/// ## Example
/// ```gleam
/// let stats_subject = eventsourcing.system_stats(eventsourcing_actor)
/// let assert Ok(stats) = process.receive(stats_subject, 1000)
/// io.println("Query actors: " <> int.to_string(stats.query_actors_count))
/// io.println("Commands processed: " <> int.to_string(stats.total_commands_processed))
/// ```
pub fn system_stats(
  eventsourcing: process.Subject(
    AggregateMessage(entity, command, event, error),
  ),
) -> process.Subject(SystemStats) {
  let receiver = process.new_subject()
  process.send(eventsourcing, GetSystemStats(receiver))
  receiver
}

/// Gets statistics for a specific aggregate including event count and snapshot status.
/// Returns a subject that will receive the AggregateStats result. Use process.receive() to get the result.
/// Useful for debugging and monitoring individual aggregate health.
///
/// ## Example
/// ```gleam
/// let result = eventsourcing.aggregate_stats(eventsourcing, "bank-account-123")
/// let assert Ok(stats) = process.receive(result, 1000)
/// io.println("Events: " <> int.to_string(stats.event_count))
/// ```
pub fn aggregate_stats(
  eventsourcing: process.Subject(
    AggregateMessage(entity, command, event, error),
  ),
  aggregate_id: AggregateId,
) -> process.Subject(Result(AggregateStats, EventSourcingError(error))) {
  let receiver = process.new_subject()
  process.send(eventsourcing, GetAggregateStats(aggregate_id, receiver))
  receiver
}

/// Retrieves the most recent snapshot for an aggregate asynchronously if snapshots are enabled.
/// Returns a subject that will receive the snapshot option. Snapshots provide a point-in-time
/// capture of aggregate state for faster reconstruction. Use process.receive() to get the result.
///
/// ## Example
/// ```gleam
/// let result = eventsourcing.latest_snapshot(eventsourcing, "bank-account-123")
/// let assert Ok(Some(snapshot)) = process.receive(result, 1000)
/// // snapshot.entity contains the saved state, snapshot.sequence shows version
/// ```
pub fn latest_snapshot(
  eventsourcing: process.Subject(
    AggregateMessage(entity, command, event, error),
  ),
  aggregate_id aggregate_id: AggregateId,
) -> process.Subject(
  Result(Option(Snapshot(entity)), EventSourcingError(error)),
) {
  let receiver = process.new_subject()
  process.send(eventsourcing, LoadLatestSnapshot(aggregate_id, receiver))
  receiver
}

fn start_query(name: process.Name(QueryMessage(event)), query: Query(event)) {
  actor.new(Nil)
  |> actor.on_message(fn(_, message) {
    case message {
      ProcessEvents(aggregate_id, events) -> {
        query(aggregate_id, events)
        actor.continue(Nil)
      }
    }
  })
  |> actor.named(name)
  |> actor.start()
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
