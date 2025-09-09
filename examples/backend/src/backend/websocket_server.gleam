import backend/banking
import backend/services
import eventsourcing
import gleam/dynamic/decode
import gleam/erlang/process
import gleam/float
import gleam/http/request
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/option
import gleam/result
import gleam/string
import mist
import mist/internal/websocket
import wisp
import wisp/wisp_mist

/// WebSocket client connection info
pub type WebSocketClient {
  WebSocketClient(
    id: String,
    connection: mist.WebsocketConnection,
    subscribed_accounts: List(String),
  )
}

/// WebSocket message types for client-server communication
pub type WebsocketClientMessage {
  // Client to Server
  ExecuteCommand(account_id: String, command: banking.Command)

  // Server to Client  
  EventNotification(account_id: String, events: List(banking.Event))
  AccountSnapshot(account_id: String, balance: Float, account_holder: String)
  ConnectionStatus(connected: Bool)
  CommandCompleted
  CommandFailed(reason: eventsourcing.EventSourcingError(banking.Error))
  CommandTimedout
}

/// Decoder for client commands
pub fn decode_websocket_message(
  account_id: String,
  json_string: String,
) -> Result(WebsocketClientMessage, json.DecodeError) {
  let message_decoder = {
    use message_type <- decode.field("type", decode.string)
    case message_type {
      "execute_command" -> {
        use aggregate_id <- decode.field("aggregate_id", decode.string)
        use command <- decode.field("command", decode_command(account_id))
        decode.success(ExecuteCommand(aggregate_id, command))
      }
      _ ->
        decode.failure(
          ExecuteCommand("unknown command type", banking.OpenAccount("", "")),
          "Unknown message type",
        )
    }
  }

  json.parse(json_string, message_decoder)
}

fn decode_command(account_id) -> decode.Decoder(banking.Command) {
  use command_type <- decode.field("type", decode.string)
  case command_type {
    "open_account" -> {
      use account_holder <- decode.field("account_holder", decode.string)
      decode.success(banking.OpenAccount(account_id, account_holder))
    }
    "deposit" -> {
      use amount <- decode.field(
        "amount",
        decode.one_of(decode.float, [
          {
            use decoded <- decode.then(decode.int)
            decode.success(int.to_float(decoded))
          },
        ]),
      )
      decode.success(banking.DepositMoney(amount))
    }
    "withdraw" -> {
      use amount <- decode.field(
        "amount",
        decode.one_of(decode.float, [
          {
            use decoded <- decode.then(decode.int)
            decode.success(int.to_float(decoded))
          },
        ]),
      )
      decode.success(banking.WithDrawMoney(amount))
    }
    "close_account" -> decode.success(banking.CloseAccount)
    _ -> decode.failure(banking.OpenAccount("", ""), "Unknown message type")
  }
}

pub fn encode_websocket_message(message: WebsocketClientMessage) -> String {
  case message {
    EventNotification(aggregate_id, events) ->
      json.object([
        #("type", json.string("event_notification")),
        #("aggregate_id", json.string(aggregate_id)),
        #("events", json.array(events, encode_event)),
      ])

    AccountSnapshot(account_id, balance, account_holder) ->
      json.object([
        #("type", json.string("account_snapshot")),
        #("balance", json.float(balance)),
        #("account_holder", json.string(account_holder)),
        #("account_id", json.string(account_id)),
      ])

    ConnectionStatus(connected) ->
      json.object([
        #("type", json.string("connection_status")),
        #("connected", json.bool(connected)),
      ])

    CommandCompleted ->
      json.object([#("type", json.string("command_completed"))])
    CommandFailed(reason) ->
      json.object([
        #("type", json.string("command_failed")),
        #("reason", json.string(string.inspect(reason))),
      ])
    CommandTimedout -> json.object([#("type", json.string("command_timedout"))])
    _ -> json.object([#("type", json.string("unknown"))])
  }
  |> json.to_string
}

fn encode_event(event: banking.Event) -> json.Json {
  case event {
    banking.AccountOpened(account_id, account_holder) ->
      json.object([
        #("type", json.string("account_opened")),
        #("account_id", json.string(account_id)),
        #("account_holder", json.string(account_holder)),
      ])

    banking.CustomerDepositedCash(amount, balance) ->
      json.object([
        #("type", json.string("deposit")),
        #("amount", json.float(amount)),
        #("balance", json.float(balance)),
      ])

    banking.CustomerWithdrewCash(amount, balance) ->
      json.object([
        #("type", json.string("withdrawal")),
        #("amount", json.float(amount)),
        #("balance", json.float(balance)),
      ])

    banking.AccountClosed ->
      json.object([#("type", json.string("account_closed"))])
  }
}

/// Start the WebSocket server with banking integration
pub fn start_websocket_server(
  port: Int,
  command_processor: process.Subject(
    eventsourcing.AggregateMessage(
      banking.BankAccount,
      banking.Command,
      banking.Event,
      banking.Error,
    ),
  ),
) -> Result(process.Subject(services.BroadcasterMsg), Nil) {
  // Start the WebSocket broadcaster actor
  use broadcaster_actor <- result.try(start_broadcaster_actor())

  // Note: We'll pass the broadcaster_actor back to be used directly by the command processor
  // instead of using a bridge process to avoid cross-process subject ownership issues

  // Start HTTP server with WebSocket upgrade capability
  let handler = fn(request) {
    case request.path_segments(request) {
      ["ws"] -> websocket_handler(request, command_processor, broadcaster_actor)
      _ ->
        wisp_mist.handler(fn(_) { wisp.not_found() }, wisp.random_string(64))(
          request,
        )
    }
  }

  let assert Ok(_server) =
    handler
    |> mist.new()
    |> mist.port(port)
    |> mist.start()

  io.println("WebSocket server started on port " <> int.to_string(port))
  Ok(broadcaster_actor)
}

/// Start the WebSocket server with an existing broadcaster
pub fn start_websocket_server_with_broadcaster(
  port: Int,
  command_processor: process.Subject(
    eventsourcing.AggregateMessage(
      banking.BankAccount,
      banking.Command,
      banking.Event,
      banking.Error,
    ),
  ),
  broadcaster_actor: process.Subject(services.BroadcasterMsg),
) -> Result(Nil, Nil) {
  // Start HTTP server with WebSocket upgrade capability
  let handler = fn(request) {
    case request.path_segments(request) {
      ["ws"] -> websocket_handler(request, command_processor, broadcaster_actor)
      _ ->
        wisp_mist.handler(fn(_) { wisp.not_found() }, wisp.random_string(64))(
          request,
        )
    }
  }

  let assert Ok(_server) =
    handler
    |> mist.new()
    |> mist.port(port)
    |> mist.start()

  io.println("WebSocket server started on port " <> int.to_string(port))
  Ok(Nil)
}

fn websocket_handler(
  request,
  eventsourcing: process.Subject(
    eventsourcing.AggregateMessage(
      banking.BankAccount,
      banking.Command,
      banking.Event,
      banking.Error,
    ),
  ),
  broadcaster_actor: process.Subject(services.BroadcasterMsg),
) {
  let assert Ok(query_params) = request.get_query(request)
  let client_id = case list.key_find(query_params, "client_id") {
    Ok(id) -> id
    Error(_) -> generate_client_id()
  }

  mist.websocket(
    request: request,
    on_init: fn(connection) {
      // Register client with broadcaster (we'll check for updates in the handler)
      process.send(
        broadcaster_actor,
        services.AddClient(client_id, process.new_subject()),
      )

      // Send connection confirmation
      let confirmation = encode_websocket_message(ConnectionStatus(True))
      let _ = mist.send_text_frame(connection, confirmation)

      #(#(client_id, 0), option.None)
      // Include a counter for polling
    },
    on_close: fn(state) {
      // Unregister client from broadcaster actor
      let #(client_id, _) = state
      process.send(broadcaster_actor, services.RemoveClient(client_id))
      Nil
    },
    handler: fn(
      state: #(String, Int),
      message: mist.WebsocketMessage(a),
      connection: websocket.WebsocketConnection,
    ) -> mist.Next(#(String, Int), a) {
      let #(client_id, poll_counter) = state

      // Poll for new AccountViews on every message
      let new_poll_counter = poll_counter + 1
      let should_poll = True

      case should_poll {
        True -> {
          // Request latest AccountViews from broadcaster
          let reply_subject = process.new_subject()
          process.send(
            broadcaster_actor,
            services.GetLatestAccountViews(reply_subject),
          )

          // Try to get the response quickly
          case process.receive(reply_subject, 100) {
            Ok(account_views) -> {
              // Filter out health-check accounts and send the rest as AccountSnapshots
              list.each(account_views, fn(account_view) {
                let snapshot_message =
                  encode_websocket_message(AccountSnapshot(
                    balance: account_view.balance,
                    account_holder: account_view.account_holder,
                    account_id: account_view.account_id,
                  ))
                let _ = mist.send_text_frame(connection, snapshot_message)
                Nil
              })
            }
            Error(_) -> {
              // Timeout or error, continue
              Nil
            }
          }
        }
      }
      case message {
        mist.Text(text) -> {
          case decode_websocket_message(client_id, text) {
            Ok(ExecuteCommand(aggregate_id, command)) -> {
              // Execute command (fire-and-forget)
              let response =
                eventsourcing.execute_with_response(
                  eventsourcing,
                  aggregate_id,
                  command,
                  [],
                )
              let response = process.receive(response, 5000)
              case response {
                Ok(Ok(_)) -> {
                  let confirmation = encode_websocket_message(CommandCompleted)
                  let assert Ok(Nil) =
                    mist.send_text_frame(connection, confirmation)

                  // Wait briefly for AccountView to propagate to broadcaster, then poll
                  process.sleep(50)
                  // 50ms delay to allow async propagation
                  let reply_subject = process.new_subject()
                  process.send(
                    broadcaster_actor,
                    services.GetLatestAccountViews(reply_subject),
                  )

                  case process.receive(reply_subject, 100) {
                    Ok(account_views) -> {
                      list.each(account_views, fn(account_view) {
                        let snapshot_message =
                          encode_websocket_message(AccountSnapshot(
                            account_id: account_view.account_id,
                            balance: account_view.balance,
                            account_holder: account_view.account_holder,
                          ))
                        let _ =
                          mist.send_text_frame(connection, snapshot_message)
                        Nil
                      })
                    }
                    Error(_) -> Nil
                  }

                  Nil
                }
                Ok(Error(reason)) -> {
                  // Command failed - send failure message
                  let failure_message =
                    encode_websocket_message(CommandFailed(reason))
                  let _ = mist.send_text_frame(connection, failure_message)
                  Nil
                }
                Error(_) -> {
                  // Timeout or other error
                  let failure_message =
                    encode_websocket_message(CommandTimedout)
                  let _ = mist.send_text_frame(connection, failure_message)
                  Nil
                }
              }
            }
            Ok(_) -> {
              Nil
            }
            Error(error) -> {
              io.println(
                "Failed to parse WebSocket message: " <> string.inspect(error),
              )
              Nil
            }
          }

          mist.continue(#(client_id, new_poll_counter))
        }
        mist.Binary(_) -> mist.continue(#(client_id, new_poll_counter))
        mist.Closed | mist.Shutdown -> {
          mist.continue(#(client_id, new_poll_counter))
        }
        mist.Custom(_) -> mist.continue(#(client_id, new_poll_counter))
      }
    },
  )
}

fn generate_client_id() -> String {
  // Generate a unique client ID
  "client_" <> int.to_string(erlang_system_time())
}

/// State for WebSocket broadcaster actor
pub type BroadcasterState {
  BroadcasterState(clients: List(#(String, mist.WebsocketConnection)))
}

/// Start the WebSocket broadcaster actor
pub fn start_broadcaster_actor() -> Result(
  process.Subject(services.BroadcasterMsg),
  Nil,
) {
  // Create a channel to get the subject from the spawned process
  let parent_subject = process.new_subject()

  let _ =
    process.spawn(fn() {
      // Create the subject within the spawned process
      let broadcaster_subject = process.new_subject()

      // Send the subject back to the parent
      process.send(parent_subject, broadcaster_subject)

      // Start the broadcaster loop
      websocket_broadcaster_process(broadcaster_subject, [], [])
    })

  // Wait for the subject from the spawned process
  case process.receive(parent_subject, 5000) {
    Ok(subject) -> Ok(subject)
    Error(_) -> Error(Nil)
  }
}

/// Simple process-based WebSocket broadcaster that stores AccountViews
fn websocket_broadcaster_process(
  broadcaster_subject: process.Subject(services.BroadcasterMsg),
  clients: List(#(String, process.Subject(services.WebSocketClientMsg))),
  account_views: List(banking.AccountView),
) -> Nil {
  case process.receive(broadcaster_subject, 1000) {
    Ok(message) -> {
      case message {
        services.AddClient(client_id, client_subject) -> {
          io.println("📥 Adding WebSocket client: " <> client_id)
          let new_clients = [#(client_id, client_subject), ..clients]
          websocket_broadcaster_process(
            broadcaster_subject,
            new_clients,
            account_views,
          )
        }

        services.RemoveClient(client_id) -> {
          io.println("📤 Removing WebSocket client: " <> client_id)
          let new_clients =
            list.filter(clients, fn(client) { client.0 != client_id })
          websocket_broadcaster_process(
            broadcaster_subject,
            new_clients,
            account_views,
          )
        }

        services.BroadcastAccountView(account_view) -> {
          io.println(
            "📤 Storing AccountView for: "
            <> " (balance: "
            <> float.to_string(account_view.balance)
            <> ")",
          )

          // Update account views list, preserving account holder name when updating
          let updated_views = case
            list.find(account_views, fn(view) {
              view.account_id == account_view.account_id
            })
          {
            Ok(_) ->
              list.map(account_views, fn(view) {
                case view.account_id == account_view.account_id {
                  True -> {
                    banking.AccountView(
                      account_id: account_view.account_id,
                      account_holder: account_view.account_holder,
                      balance: account_view.balance,
                      last_updated: account_view.last_updated,
                    )
                  }
                  False -> view
                }
              })
            Error(_) -> [account_view, ..account_views]
          }

          websocket_broadcaster_process(
            broadcaster_subject,
            clients,
            updated_views,
          )
        }

        services.GetLatestAccountViews(reply_to) -> {
          process.send(reply_to, account_views)
          websocket_broadcaster_process(
            broadcaster_subject,
            clients,
            account_views,
          )
        }

        services.Shutdown -> {
          io.println("📤 Shutting down WebSocket broadcaster")
          Nil
        }
      }
    }
    Error(_) -> {
      // Timeout, continue listening
      websocket_broadcaster_process(broadcaster_subject, clients, account_views)
    }
  }
}

@external(erlang, "erlang", "system_time")
fn erlang_system_time() -> Int
