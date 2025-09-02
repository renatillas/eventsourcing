import gleam/erlang/process
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

pub fn register_queries(
  eventsourcing_actor: process.Subject(
    AggregateMessage(entity, command, event, error),
  ),
  query_actors: List(QueryActor(event)),
) -> Nil {
  query_actors
  |> list.each(fn(query_actor) {
    process.send(eventsourcing_actor, RegisterQueryActor(query_actor))
  })
}

pub fn new(
  eventstore eventstore: EventStore(
    eventstore,
    entity,
    command,
    event,
    error,
    transaction_handle,
  ),
  queries queries: List(Query(event)),
  handle handle: Handle(entity, command, event, error),
  apply apply: Apply(entity, event),
  empty_state empty_state: entity,
) -> Result(
  EventSourcing(eventstore, entity, command, event, error, transaction_handle),
  actor.StartError,
) {
  use query_actors <- result.try(
    queries
    |> list.map(start_query)
    |> result.all,
  )

  Ok(EventSourcing(
    event_store: eventstore,
    query_actors: query_actors,
    handle: handle,
    apply: apply,
    empty_state: empty_state,
    snapshot_config: None,
  ))
}

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
) -> actor.StartResult(
  process.Subject(AggregateMessage(entity, command, event, error)),
) {
  actor.new(EventSourcing(
    event_store: eventstore,
    query_actors: query_actors,
    handle: handle,
    apply: apply,
    empty_state: empty_state,
    snapshot_config: None,
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
        Ok(_) -> actor.continue(state)
        Error(DomainError(_)) -> actor.continue(state)
        Error(error) -> {
          actor.stop_abnormal(describe_error(error))
        }
      }
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
  }
}

pub fn with_snapshots(
  event_sourcing: EventSourcing(
    eventstore,
    entity,
    command,
    event,
    error,
    transaction_handle,
  ),
  config: SnapshotConfig,
) -> Result(
  EventSourcing(eventstore, entity, command, event, error, transaction_handle),
  String,
) {
  case config.snapshot_frequency.n <= 0 {
    True -> Error("Snapshot frequency must be greater than 0")
    False -> Ok(EventSourcing(..event_sourcing, snapshot_config: Some(config)))
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

pub fn load_aggregate(
  event_sourcing event_sourcing: EventSourcing(
    eventstore,
    entity,
    command,
    event,
    error,
    transaction_handle,
  ),
  aggregate_id aggregate_id: AggregateId,
) -> Result(Aggregate(entity, command, event, error), EventSourcingError(error)) {
  use tx <- event_sourcing.event_store.load_aggregate_transaction()
  load_aggregate_or_create_new(event_sourcing, tx, aggregate_id)
  |> result.try(fn(aggregate) {
    case aggregate.entity == event_sourcing.empty_state {
      True -> Error(EntityNotFound)
      False -> Ok(aggregate)
    }
  })
}

pub fn load_events(
  event_sourcing event_sourcing: EventSourcing(
    eventstore,
    entity,
    command,
    event,
    error,
    transaction_handle,
  ),
  aggregate_id aggregate_id: AggregateId,
) -> Result(List(EventEnvelop(event)), EventSourcingError(error)) {
  use tx <- event_sourcing.event_store.load_events_transaction()
  event_sourcing.event_store.load_events(
    event_sourcing.event_store.eventstore,
    tx,
    aggregate_id,
    0,
  )
}

pub fn load_events_from(
  event_sourcing event_sourcing: EventSourcing(
    eventstore,
    entity,
    command,
    event,
    error,
    transaction_handle,
  ),
  aggregate_id aggregate_id: AggregateId,
  start_from start_from: Int,
) -> Result(List(EventEnvelop(event)), EventSourcingError(error)) {
  use tx <- event_sourcing.event_store.load_events_transaction()
  event_sourcing.event_store.load_events(
    event_sourcing.event_store.eventstore,
    tx,
    aggregate_id,
    start_from,
  )
}

pub fn get_latest_snapshot(
  event_sourcing event_sourcing: EventSourcing(
    eventstore,
    entity,
    command,
    event,
    error,
    transaction_handle,
  ),
  aggregate_id aggregate_id: AggregateId,
) -> Result(Option(Snapshot(entity)), EventSourcingError(error)) {
  use tx <- event_sourcing.event_store.get_latest_snapshot_transaction()
  case event_sourcing.snapshot_config {
    None -> Ok(None)
    Some(_) -> {
      event_sourcing.event_store.load_snapshot(tx, aggregate_id)
    }
  }
}

pub fn start_queries(
  queries: List(Query(event)),
) -> Result(List(QueryActor(event)), actor.StartError) {
  list.map(queries, start_query)
  |> result.all
}

pub fn query_actor_count(eventsourcing: EventSourcing(_, _, _, _, _, _)) -> Int {
  list.length(eventsourcing.query_actors)
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

pub fn timeout(ms ms: Int) -> Result(Timeout, EventSourcingError(_)) {
  case ms <= 0 {
    True -> Error(NonPositiveArgument)
    False -> Ok(Timeout(ms))
  }
}

pub fn frequency(n n: Int) -> Result(Frequency, EventSourcingError(_)) {
  case n <= 0 {
    True -> Error(NonPositiveArgument)
    False -> Ok(Frequency(n))
  }
}
