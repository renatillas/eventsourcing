import gleam/bool
import gleam/dict
import gleam/dynamic/decode
import gleam/float
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/pair
import gleam/result
import gleam/string
import gleam/time/timestamp
import lustre
import lustre/attribute
import lustre/effect
import lustre/element
import lustre/element/html
import lustre/event
import lustre_websocket as ws

/// Application model - represents the entire app state
pub type Model {
  Model(
    // WebSocket connection
    websocket: Option(ws.WebSocket),
    connection_status: ConnectionStatus,
    // Account data
    accounts: dict.Dict(String, AccountData),
    current_account: Option(String),
    // UI state
    deposit_amount: String,
    withdraw_amount: String,
    new_account_holder: String,
    // Transaction history
    recent_transactions: List(TransactionRecord),
    // Pending account creation
    pending_account_creation: Option(String),
    // Pending transaction
    pending_transaction: Option(String),
    // Info
    info: Option(String),
  )
}

pub type ConnectionStatus {
  Disconnected
  Connecting
  Connected
  Reconnecting
}

pub type AccountData {
  AccountData(
    account_id: String,
    account_holder: String,
    balance: Float,
    last_updated: Int,
  )
}

pub type TransactionRecord {
  TransactionRecord(
    account_id: String,
    transaction_type: String,
    amount: Float,
    new_balance: Float,
    timestamp: Int,
  )
}

/// Application messages
pub type Msg {
  // WebSocket events
  WebSocketMsg(ws.WebSocketEvent)

  // User interactions
  ConnectWebSocket
  SetCurrentAccount(String)
  SetDepositAmount(String)
  SetWithdrawAmount(String)
  SetNewAccountHolder(String)

  // Banking operations
  CreateAccount
  DepositMoney
  WithdrawMoney
  AccountCreated(String)
  TransactionCompleted(String)

  // System events
  UpdateAccountBalance(String, Float, String)
  ClearError
  SystemTime(Int)
}

/// Initialize the application
pub fn init(_flags) -> #(Model, effect.Effect(Msg)) {
  let initial_model =
    Model(
      websocket: None,
      connection_status: Disconnected,
      accounts: dict.new(),
      current_account: None,
      deposit_amount: "",
      withdraw_amount: "",
      new_account_holder: "",
      recent_transactions: [],
      pending_account_creation: None,
      pending_transaction: None,
      info: None,
    )

  #(initial_model, effect.none())
}

/// Update function - handles all application messages
pub fn update(model: Model, msg: Msg) -> #(Model, effect.Effect(Msg)) {
  case msg {
    ConnectWebSocket -> {
      let new_model = Model(..model, connection_status: Connecting)
      let connect_effect = ws.init("ws://localhost:8080/ws", WebSocketMsg)
      #(new_model, connect_effect)
    }

    WebSocketMsg(ws_event) -> {
      case ws_event {
        ws.OnOpen(socket) -> {
          let new_model =
            Model(
              ..model,
              websocket: Some(socket),
              connection_status: Connected,
              info: Some("DEBUG: WebSocket connected successfully"),
            )
          #(new_model, effect.none())
        }

        ws.OnClose(_reason) -> {
          let new_model =
            Model(..model, websocket: None, connection_status: Disconnected)
          #(new_model, effect.none())
        }

        ws.OnTextMessage(message) -> {
          handle_websocket_message(model, message)
        }

        ws.OnBinaryMessage(_data) -> {
          #(model, effect.none())
        }

        ws.InvalidUrl -> {
          let new_model =
            Model(
              ..model,
              connection_status: Disconnected,
              info: Some("Invalid WebSocket URL"),
            )
          #(new_model, effect.none())
        }
      }
    }

    SetCurrentAccount(account_id) -> {
      let new_model =
        Model(
          ..model,
          current_account: Some(account_id),
          info: Some("Selected account: " <> account_id),
        )
      // No need to request snapshot - the view projection system 
      // will automatically send updates via WebSocket
      #(new_model, effect.none())
    }

    SetDepositAmount(amount) -> {
      #(Model(..model, deposit_amount: amount), effect.none())
    }

    SetWithdrawAmount(amount) -> {
      #(Model(..model, withdraw_amount: amount), effect.none())
    }

    SetNewAccountHolder(holder) -> {
      #(Model(..model, new_account_holder: holder), effect.none())
    }

    CreateAccount -> {
      case model.websocket {
        None -> {
          let error = "WebSocket not connected - please connect first"
          #(Model(..model, info: Some(error)), effect.none())
        }
        Some(socket) -> {
          case string.length(model.new_account_holder) > 0 {
            True -> {
              // Generate a unique account ID based on timestamp and account holder name
              let account_id =
                "acc-"
                <> int.to_string(current_timestamp())
                <> "-"
                <> string.replace(model.new_account_holder, " ", "-")

              let command =
                json.object([
                  #("type", json.string("execute_command")),
                  #("aggregate_id", json.string(account_id)),
                  #(
                    "command",
                    json.object([
                      #("type", json.string("open_account")),
                      #("account_id", json.string(account_id)),
                      #("account_holder", json.string(model.new_account_holder)),
                    ]),
                  ),
                ])

              let new_model =
                Model(
                  ..model,
                  new_account_holder: "",
                  pending_account_creation: Some(account_id),
                  info: Some("Creating account..."),
                )

              let create_effect = send_websocket_message_effect(socket, command)

              #(new_model, create_effect)
            }
            False -> {
              let error =
                "Please fill in the account holder field (current: '"
                <> model.new_account_holder
                <> "')"
              #(Model(..model, info: Some(error)), effect.none())
            }
          }
        }
      }
    }

    DepositMoney -> {
      // Debug the deposit conditions
      let ws_status = case model.websocket {
        Some(_) -> "✅ WebSocket"
        None -> "❌ No WebSocket"
      }
      let account_status = case model.current_account {
        Some(id) -> "✅ Account: " <> id
        None -> "❌ No Account"
      }
      let parsed_amount = case float.parse(model.deposit_amount) {
        Ok(amount) -> Ok(amount)
        Error(_) ->
          model.deposit_amount |> int.parse |> result.map(int.to_float)
      }
      let amount_status = case parsed_amount {
        Ok(amount) if amount >. 0.0 -> "✅ Amount: " <> float.to_string(amount)
        Ok(amount) -> "❌ Amount not positive: " <> float.to_string(amount)
        Error(_) -> "❌ Invalid amount: '" <> model.deposit_amount <> "'"
      }

      case model.websocket, model.current_account, parsed_amount {
        Some(socket), Some(account_id), Ok(amount) if amount >. 0.0 -> {
          let command =
            json.object([
              #("type", json.string("execute_command")),
              #("aggregate_id", json.string(account_id)),
              #(
                "command",
                json.object([
                  #("type", json.string("deposit")),
                  #("amount", json.float(amount)),
                ]),
              ),
            ])

          let new_model =
            Model(
              ..model,
              deposit_amount: "",
              pending_transaction: Some(account_id),
            )
          #(new_model, send_websocket_message_effect(socket, command))
        }
        _, _, _ -> {
          let error =
            "Deposit failed - "
            <> ws_status
            <> " | "
            <> account_status
            <> " | "
            <> amount_status
          #(Model(..model, info: Some(error)), effect.none())
        }
      }
    }

    WithdrawMoney -> {
      let parsed_amount = case float.parse(model.withdraw_amount) {
        Ok(amount) -> Ok(amount)
        Error(_) ->
          model.withdraw_amount |> int.parse |> result.map(int.to_float)
      }
      case model.websocket, model.current_account, parsed_amount {
        Some(socket), Some(account_id), Ok(amount) if amount >. 0.0 -> {
          let command =
            json.object([
              #("type", json.string("execute_command")),
              #("aggregate_id", json.string(account_id)),
              #(
                "command",
                json.object([
                  #("type", json.string("withdraw")),
                  #("amount", json.float(amount)),
                ]),
              ),
            ])

          let new_model =
            Model(
              ..model,
              withdraw_amount: "",
              pending_transaction: Some(account_id),
            )
          #(new_model, send_websocket_message_effect(socket, command))
        }
        _, _, _ -> {
          let error =
            "Please enter a valid positive amount and select an account"
          #(Model(..model, info: Some(error)), effect.none())
        }
      }
    }

    UpdateAccountBalance(account_id, balance, account_holder) -> {
      let account_data =
        AccountData(account_id, account_holder, balance, current_timestamp())
      let new_accounts = dict.insert(model.accounts, account_id, account_data)
      let new_model = Model(..model, accounts: new_accounts)
      #(new_model, effect.none())
    }

    AccountCreated(_) -> {
      let new_model = Model(..model, pending_account_creation: None)
      #(new_model, effect.none())
    }

    TransactionCompleted(_) -> {
      let new_model = Model(..model, pending_transaction: None)
      #(new_model, effect.none())
    }

    ClearError -> {
      #(Model(..model, info: None), effect.none())
    }

    _ -> #(model, effect.none())
  }
}

fn handle_websocket_message(
  model: Model,
  message: String,
) -> #(Model, effect.Effect(Msg)) {
  // Parse the incoming WebSocket message
  case parse_websocket_response(message) {
    Ok(parsed_message) -> {
      case parsed_message {
        EventNotification(account_id, events) -> {
          // Process events to update account state and add new accounts to dropdown
          let updated_model =
            list.fold(events, model, fn(acc_model, event) {
              case event {
                AccountOpened(account_id, account_holder) -> {
                  // Add new account to the dropdown with initial balance of 0
                  let account_data =
                    AccountData(
                      account_id,
                      account_holder,
                      0.0,
                      current_timestamp(),
                    )
                  let new_accounts =
                    dict.insert(acc_model.accounts, account_id, account_data)

                  Model(
                    ..acc_model,
                    accounts: new_accounts,
                    // Auto-select the newly created account
                    current_account: Some(account_id),
                    info: Some(
                      "New account created: "
                      <> account_holder
                      <> " ("
                      <> account_id
                      <> ")",
                    ),
                  )
                }
                CustomerDepositedCash(amount, new_balance) -> {
                  // Update account balance for deposit
                  case dict.get(acc_model.accounts, account_id) {
                    Ok(account_data) -> {
                      let updated_account =
                        AccountData(
                          ..account_data,
                          balance: new_balance,
                          last_updated: current_timestamp(),
                        )
                      let new_accounts =
                        dict.insert(
                          acc_model.accounts,
                          account_id,
                          updated_account,
                        )

                      // Add transaction to history
                      let transaction =
                        TransactionRecord(
                          account_id,
                          "deposit",
                          amount,
                          new_balance,
                          current_timestamp(),
                        )
                      let new_transactions = [
                        transaction,
                        ..list.take(acc_model.recent_transactions, 19)
                      ]

                      Model(
                        ..acc_model,
                        accounts: new_accounts,
                        recent_transactions: new_transactions,
                        info: Some(
                          "Deposit processed: $" <> float.to_string(amount),
                        ),
                      )
                    }
                    Error(_) -> acc_model
                  }
                }
                CustomerWithdrewCash(amount, new_balance) -> {
                  // Update account balance for withdrawal
                  case dict.get(acc_model.accounts, account_id) {
                    Ok(account_data) -> {
                      let updated_account =
                        AccountData(
                          ..account_data,
                          balance: new_balance,
                          last_updated: current_timestamp(),
                        )
                      let new_accounts =
                        dict.insert(
                          acc_model.accounts,
                          account_id,
                          updated_account,
                        )

                      // Add transaction to history
                      let transaction =
                        TransactionRecord(
                          account_id,
                          "withdrawal",
                          amount,
                          new_balance,
                          current_timestamp(),
                        )
                      let new_transactions = [
                        transaction,
                        ..list.take(acc_model.recent_transactions, 19)
                      ]

                      Model(
                        ..acc_model,
                        accounts: new_accounts,
                        recent_transactions: new_transactions,
                        info: Some(
                          "Withdrawal processed: $" <> float.to_string(amount),
                        ),
                      )
                    }
                    Error(_) -> acc_model
                  }
                }
              }
            })

          #(updated_model, effect.none())
        }
        AccountSnapshot(account_id, balance, account_holder) -> {
          // Update the account data with the snapshot
          let account_data =
            AccountData(
              account_id,
              account_holder,
              balance,
              current_timestamp(),
            )
          let new_accounts =
            dict.insert(model.accounts, account_id, account_data)

          let updated_model =
            Model(
              ..model,
              accounts: new_accounts,
              info: Some(
                "Account snapshot updated - "
                <> account_holder
                <> " ($"
                <> float.to_string(balance)
                <> ")",
              ),
            )
          #(updated_model, effect.none())
        }
        ConnectionStatus(connected) -> {
          let debug_model =
            Model(
              ..model,
              connection_status: case connected {
                True -> Connected
                False -> Disconnected
              },
              info: Some(
                "DEBUG: Connection Status - Connected: "
                <> bool.to_string(connected),
              ),
            )
          // Handle connection status update
          #(debug_model, effect.none())
        }
        CommandCompleted -> {
          // Clear pending state and let view projection system handle updates
          let new_model =
            Model(
              ..model,
              pending_account_creation: None,
              pending_transaction: None,
              info: Some(
                "Command completed - waiting for view projection update",
              ),
            )
          #(new_model, effect.none())
        }
        CommandFailed(reason) -> {
          let new_model =
            Model(
              ..model,
              pending_account_creation: None,
              pending_transaction: None,
              info: Some("Command failed: " <> reason),
            )
          #(new_model, effect.none())
        }
        CommandTimedout -> {
          let new_model =
            Model(
              ..model,
              pending_account_creation: None,
              pending_transaction: None,
              info: Some("Command timed out - please try again"),
            )
          #(new_model, effect.none())
        }
      }
    }
    Error(error) -> {
      let new_model =
        Model(
          ..model,
          info: Some(
            "Failed to parse WebSocket message: "
            <> string.inspect(error)
            <> " | Message: "
            <> message,
          ),
        )
      #(new_model, effect.none())
    }
  }
}

type WebsocketResponse {
  EventNotification(account_id: String, events: List(Event))
  AccountSnapshot(account_id: String, balance: Float, account_holder: String)
  ConnectionStatus(connected: Bool)
  CommandCompleted
  CommandFailed(reason: String)
  CommandTimedout
}

type Event {
  AccountOpened(account_id: String, account_holder: String)
  CustomerDepositedCash(amount: Float, balance: Float)
  CustomerWithdrewCash(amount: Float, balance: Float)
}

fn parse_websocket_response(
  message: String,
) -> Result(WebsocketResponse, json.DecodeError) {
  let event_decoder = {
    use type_ <- decode.field("type", decode.string)
    case type_ {
      "account_opened" -> {
        use account_id <- decode.field("account_id", decode.string)
        use account_holder <- decode.field("account_holder", decode.string)
        decode.success(AccountOpened(account_id, account_holder))
      }
      "deposit" -> {
        use amount <- decode.field("amount", decode.float)
        use balance <- decode.field("balance", decode.float)
        decode.success(CustomerDepositedCash(amount, balance))
      }
      "withdrawal" -> {
        use amount <- decode.field("amount", decode.float)
        use balance <- decode.field("balance", decode.float)
        decode.success(CustomerWithdrewCash(amount, balance))
      }
      _ -> decode.failure(CustomerDepositedCash(0.0, 0.0), "Unknown event type")
    }
  }
  let decoder = {
    use type_ <- decode.field("type", decode.string)
    case type_ {
      "event_notification" -> {
        use account_id <- decode.field("account_id", decode.string)
        use events <- decode.field("events", decode.list(event_decoder))
        decode.success(EventNotification(account_id, events))
      }
      "account_snapshot" -> {
        use account_id <- decode.field("account_id", decode.string)
        use balance <- decode.field("balance", decode.float)
        use account_holder <- decode.field("account_holder", decode.string)
        decode.success(AccountSnapshot(account_id, balance, account_holder))
      }
      "connection_status" -> {
        use connected <- decode.field("connected", decode.bool)
        decode.success(ConnectionStatus(connected))
      }
      "command_completed" -> decode.success(CommandCompleted)
      "command_failed" -> {
        use reason <- decode.field("reason", decode.string)
        decode.success(CommandFailed(reason))
      }
      "command_timedout" -> decode.success(CommandTimedout)
      _ -> decode.failure(ConnectionStatus(False), "Unknown message type")
    }
  }
  json.parse(message, decoder)
}

/// Render the application UI
pub fn view(model: Model) -> element.Element(Msg) {
  html.div([], [
    render_header(model),
    render_connection_status(model),
    render_error_message(model),
    render_account_creation(model),
    render_account_selector(model),
    render_account_details(model),
    render_transaction_controls(model),
    render_transaction_history(model),
  ])
}

fn render_header(_model: Model) -> element.Element(Msg) {
  html.div([attribute.class("header")], [
    html.h1([], [element.text("Real-time Banking with eventsourcing_glyn")]),
    html.p([], [
      element.text(
        "Demonstrating distributed event sourcing with WebSocket integration",
      ),
    ]),
  ])
}

fn render_connection_status(model: Model) -> element.Element(Msg) {
  let status_text = case model.connection_status {
    Connected -> "Connected to real-time updates"
    Connecting -> "Connecting..."
    Reconnecting -> "Reconnecting..."
    Disconnected -> "Disconnected - Click to connect"
  }

  let status_class = case model.connection_status {
    Connected -> "status connected"
    Connecting | Reconnecting -> "status connecting"
    Disconnected -> "status disconnected"
  }

  html.div([attribute.class(status_class)], [
    element.text(status_text),
    case model.connection_status {
      Disconnected ->
        html.button([event.on_click(ConnectWebSocket)], [
          element.text("Connect"),
        ])
      _ -> element.text("")
    },
  ])
}

fn render_error_message(model: Model) -> element.Element(Msg) {
  case model.info {
    Some(error) ->
      html.div([attribute.class("error")], [
        element.text(error),
        html.button([event.on_click(ClearError)], [element.text("×")]),
      ])
    None -> element.text("")
  }
}

fn render_account_creation(model: Model) -> element.Element(Msg) {
  html.div([attribute.class("account-creation")], [
    html.h3([], [element.text("Create New Account")]),
    html.input([
      attribute.placeholder("Account Holder Name"),
      attribute.value(model.new_account_holder),
      event.on_input(SetNewAccountHolder),
    ]),
    html.button([event.on_click(CreateAccount)], [
      element.text("Create Account"),
    ]),
  ])
}

fn render_account_selector(model: Model) -> element.Element(Msg) {
  let account_options =
    dict.to_list(model.accounts)
    |> list.map(fn(account_pair) {
      let #(account_id, account_data) = account_pair
      html.option(
        [attribute.value(account_id)],
        account_data.account_holder <> " (" <> account_id <> ")",
      )
    })

  let current_value = case model.current_account {
    Some(account_id) -> account_id
    None -> ""
  }

  html.div([attribute.class("account-selector")], [
    html.h3([], [element.text("Select Account")]),
    html.select(
      [
        event.on_change(SetCurrentAccount),
        attribute.value(current_value),
      ],
      [
        html.option([attribute.value("")], "Select an account..."),
        ..account_options
      ],
    ),
  ])
}

fn render_account_details(model: Model) -> element.Element(Msg) {
  case model.current_account {
    Some(account_id) -> {
      case dict.get(model.accounts, account_id) {
        Ok(account_data) ->
          html.div([attribute.class("account-details")], [
            html.h3([], [element.text("Account Details")]),
            html.p([], [
              element.text("Account: " <> account_data.account_holder),
            ]),
            html.p([], [
              element.text(
                "Balance: $" <> float.to_string(account_data.balance),
              ),
            ]),
            html.p([], [element.text("ID: " <> account_data.account_id)]),
          ])
        Error(_) -> element.text("Account not found")
      }
    }
    None -> element.text("")
  }
}

fn render_transaction_controls(model: Model) -> element.Element(Msg) {
  case model.current_account {
    Some(_) ->
      html.div([attribute.class("transaction-controls")], [
        html.h3([], [element.text("Transactions")]),
        html.div([attribute.class("transaction-row")], [
          html.input([
            attribute.placeholder("Deposit amount"),
            attribute.value(model.deposit_amount),
            attribute.type_("number"),
            attribute.step("0.01"),
            event.on_input(SetDepositAmount),
          ]),
          html.button([event.on_click(DepositMoney)], [element.text("Deposit")]),
        ]),
        html.div([attribute.class("transaction-row")], [
          html.input([
            attribute.placeholder("Withdraw amount"),
            attribute.value(model.withdraw_amount),
            attribute.type_("number"),
            attribute.step("0.01"),
            event.on_input(SetWithdrawAmount),
          ]),
          html.button([event.on_click(WithdrawMoney)], [
            element.text("Withdraw"),
          ]),
        ]),
      ])
    None -> element.text("")
  }
}

fn render_transaction_history(model: Model) -> element.Element(Msg) {
  let transaction_items =
    list.map(model.recent_transactions, fn(transaction) {
      html.li([], [
        element.text(
          transaction.transaction_type
          <> ": $"
          <> float.to_string(transaction.amount),
        ),
        element.text(
          " → Balance: $" <> float.to_string(transaction.new_balance),
        ),
      ])
    })

  html.div([attribute.class("transaction-history")], [
    html.h3([], [element.text("Recent Transactions")]),
    html.ul([], transaction_items),
  ])
}

// Effect functions for WebSocket communication
fn send_websocket_message_effect(
  socket: ws.WebSocket,
  message: json.Json,
) -> effect.Effect(Msg) {
  let message_string = json.to_string(message)
  ws.send(socket, message_string)
}

fn current_timestamp() -> Int {
  timestamp.system_time()
  |> timestamp.to_unix_seconds_and_nanoseconds
  |> pair.first
}

/// Main function to start the Lustre application
pub fn main() {
  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
  Nil
}
