import gleam/list
import gleam/result

// TYPES ----

/// Used by the EventStore implementations
pub type Aggregate(entity, command, event, error) {
  Aggregate(
    entity: entity,
    handle: Handle(entity, command, event, error),
    apply: Apply(entity, event),
  )
}

/// Used by the EventStore implementations
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

type AggregateId =
  String

type Handle(entity, command, event, error) =
  fn(entity, command) -> Result(List(event), error)

type Apply(entity, event) =
  fn(entity, event) -> entity

type Query(event) =
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

/// Wrapper around the event store implementations
pub type EventStore(eventstore, entity, command, event, error) {
  EventStore(
    eventstore: eventstore,
    load_aggregate: fn(eventstore, AggregateId) ->
      AggregateContext(entity, command, event, error),
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
/// # Examples
/// ```gleam
/// pub type BankAccount {
///   BankAccount(opened: Bool, balance: Float)
/// }
///
/// pub type BankAccountCommand {
///   OpenAccount(account_id: String)
///   DepositMoney(amount: Float)
///   WithDrawMoney(amount: Float)
/// }
///
/// pub type BankAccountEvent {
///   AccountOpened(account_id: String)
///   CustomerDepositedCash(amount: Float, balance: Float)
///   CustomerWithdrewCash(amount: Float, balance: Float)
/// }
///
/// pub fn handle(
///   bank_account: BankAccount,
///   command: BankAccountCommand,
/// ) -> Result(List(BankAccountEvent), Nil) {
///   case command {
///     OpenAccount(account_id) -> Ok([AccountOpened(account_id)])
///     DepositMoney(amount) -> {
///       let balance = bank_account.balance +. amount
///       case amount >. 0.0 {
///         True -> Ok([CustomerDepositedCash(amount:, balance:)])
///         False -> Error(Nil)
///       }
///     }
///     WithDrawMoney(amount) -> {
///       let balance = bank_account.balance -. amount
///       case amount >. 0.0 && balance >. 0.0 {
///         True -> Ok([CustomerWithdrewCash(amount:, balance:)])
///         False -> Error(Nil)
///       }
///     }
///   }
/// }
/// 
/// pub fn apply(bank_account: BankAccount, event: BankAccountEvent) {
///   case event {
///     AccountOpened(_) -> BankAccount(..bank_account, opened: True)
///     CustomerDepositedCash(_, balance) -> BankAccount(..bank_account, balance:)
///     CustomerWithdrewCash(_, balance) -> BankAccount(..bank_account, balance:)
///   }
/// }
/// fn main() {
///   let mem_store =
///     memory_store.new(BankAccount(opened: False, balance: 0.0), handle, apply)
///   let query = fn(
///     aggregate_id: String,
///     events: List(eventsourcing.EventEnvelop(BankAccountEvent)),
///   ) {
///     io.println(
///       "Aggregate Bank Account with ID: "
///       <> aggregate_id
///       <> " commited "
///       <> events |> list.length |> int.to_string
///       <> " events.",
///     )
///   }
///   let event_sourcing = eventsourcing.new(mem_store, [query])
/// }
/// ```
pub fn new(event_store, queries) {
  EventSourcing(event_store:, queries:)
}

// PUBLIC FUNCTIONS ----

/// The main function of the package. 
/// Run execute with your event_sourcing instance and the command you want to apply.
/// It will return a Result with Ok(Nil) or Error(your domain error) if the command failed.
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
