import backend/banking
import eventsourcing
import eventsourcing/memory_store
import gleam/dict
import gleam/erlang/process
import gleam/float
import gleam/io
import gleam/list
import gleam/option
import gleam/otp/actor
import gleam/otp/static_supervisor
import gleam/otp/supervision
import gleam/time/timestamp

/// Configuration for banking services
pub type ServiceConfig {
  ServiceConfig(websocket_broadcaster: process.Subject(banking.AccountView))
}


/// Messages for WebSocket broadcaster actor
pub type BroadcasterMsg {
  AddClient(String, process.Subject(WebSocketClientMsg))
  RemoveClient(String)
  BroadcastAccountView(banking.AccountView)
  GetLatestAccountViews(process.Subject(List(banking.AccountView)))
  Shutdown
}

/// Messages sent to individual WebSocket client handlers
pub type WebSocketClientMsg {
  SendAccountSnapshot(banking.AccountView)
}

type ViewActorMessage {
  AccountEvent(account_id: String, event: banking.Event)
  GetAccountView(
    account_id: String,
    receiver: process.Subject(banking.AccountView),
  )
}

/// Start banking services
pub fn start_banking_services(
  _config: ServiceConfig,
) -> Result(
  #(
    eventsourcing.EventStore(_, _, _, _, _, _),
    supervision.ChildSpecification(static_supervisor.Supervisor),
  ),
  String,
) {
  // Command Processing Service - handles business logic
  let command_events = process.new_name("command_events")
  let command_snapshots = process.new_name("command_snapshots")
  let #(command_eventstore, command_memory_spec) =
    memory_store.supervised(
      command_events,
      command_snapshots,
      static_supervisor.OneForOne,
    )

  // Create combined supervisor for all services
  let services_supervisor =
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.add(command_memory_spec)
    |> static_supervisor.supervised()

  Ok(#(command_eventstore, services_supervisor))
}

/// Start the main event sourcing command processor
pub fn start_command_processor(
  eventstore: eventsourcing.EventStore(_, _, _, _, _, _),
  broadcaster,
) -> Result(
  process.Subject(
    eventsourcing.AggregateMessage(
      banking.BankAccount,
      banking.Command,
      banking.Event,
      banking.Error,
    ),
  ),
  a,
) {
  let es_name = process.new_name("banking-command-processor")
  let assert Ok(actor) =
    actor.new(dict.new())
    |> actor.on_message(fn(state, msg) {
      case msg {
        AccountEvent(account_id, event) -> {
          let current_events = case dict.get(state, account_id) {
            Ok(view) -> view
            Error(Nil) -> banking.AccountView("", "", 0.0, 0)
          }
          let state = case event {
            banking.AccountOpened(_, account_holder) -> {
              let new_view =
                banking.AccountView(
                  account_id: account_id,
                  account_holder: account_holder,
                  balance: 0.0,
                  last_updated: timestamp.system_time()
                    |> timestamp.to_unix_seconds
                    |> float.round,
                )
              dict.insert(state, account_id, new_view)
            }
            banking.CustomerDepositedCash(_, new_balance) -> {
              let new_view =
                banking.AccountView(
                  account_id: account_id,
                  account_holder: current_events.account_holder,
                  balance: new_balance,
                  last_updated: timestamp.system_time()
                    |> timestamp.to_unix_seconds
                    |> float.round,
                )
              dict.insert(state, account_id, new_view)
            }
            banking.CustomerWithdrewCash(_, new_balance) -> {
              let new_view =
                banking.AccountView(
                  account_id: account_id,
                  account_holder: current_events.account_holder,
                  balance: new_balance,
                  last_updated: timestamp.system_time()
                    |> timestamp.to_unix_seconds
                    |> float.round,
                )
              dict.insert(state, account_id, new_view)
            }
            banking.AccountClosed -> dict.delete(state, account_id)
          }
          actor.continue(state)
        }
        GetAccountView(account_id, receiver) -> {
          let view = case dict.get(state, account_id) {
            Ok(view) -> view
            Error(Nil) -> banking.AccountView("", "", 0.0, 0)
          }
          process.send(receiver, view)
          actor.continue(state)
        }
      }
    })
    |> actor.start()

  let assert Ok(es_spec) =
    eventsourcing.supervised(
      name: es_name,
      eventstore: eventstore,
      handle: banking.handle,
      apply: banking.apply,
      empty_state: banking.UnopenedBankAccount,
      queries: [
        #(
          process.new_name("websocket-broadcaster"),
          fn(
            account_id: String,
            events: List(eventsourcing.EventEnvelop(banking.Event)),
          ) -> Nil {
            let events = list.map(events, fn(envelope) { envelope.payload })
            list.each(events, fn(event) {
              actor.send(actor.data, AccountEvent(account_id, event))
            })
            let receiver = process.new_subject()
            actor.send(actor.data, GetAccountView(account_id, receiver))
            let account_view = process.receive(receiver, 5000)
            case account_view {
              Error(_) -> {
                io.println("⚠️ Failed to get AccountView for account")
              }
              Ok(view) -> {
                io.println(
                  "📢 AccountView updated: "
                  <> account_id
                  <> " (balance: "
                  <> float.to_string(view.balance)
                  <> ")",
                )

                // Send AccountView to WebSocket broadcaster
                process.send(broadcaster, BroadcastAccountView(view))
              }
            }
          },
        ),
      ],
      snapshot_config: option.None,
    )

  let assert Ok(_es_sup) =
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.add(es_spec)
    |> static_supervisor.start()

  Ok(process.named_subject(es_name))
}

