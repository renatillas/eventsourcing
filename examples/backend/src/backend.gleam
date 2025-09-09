import backend/services
import backend/websocket_server
import gleam/erlang/process
import gleam/io
import gleam/otp/static_supervisor
import gleam/result

pub fn main() {
  io.println(
    "🏦 Starting Real-time Banking Application with plain eventsourcing",
  )
  io.println("========================================================")

  case start_banking_system() {
    Ok(_) -> {
      io.println("✅ Banking system started successfully!")
      io.println("🌐 WebSocket server available at: ws://localhost:8080/ws")
      io.println("")
      io.println("Architecture:")
      io.println("- Command Processor: Handles banking operations")
      io.println("- WebSocket Service: Real-time client updates")
      io.println("")
      io.println("Press Ctrl+C to stop")

      // Keep the application running
      process.sleep_forever()
    }
    Error(error) -> {
      io.println("❌ Failed to start banking system: " <> error)
    }
  }
}

fn start_banking_system() -> Result(Nil, String) {
  // Create WebSocket broadcaster for real-time updates
  let websocket_broadcaster = process.new_subject()

  // Configure banking services
  let service_config =
    services.ServiceConfig(websocket_broadcaster: websocket_broadcaster)

  io.println("🔧 Starting WebSocket broadcaster first...")

  // Start WebSocket broadcaster first so it can be used by services
  use broadcaster_actor <- result.try(
    websocket_server.start_broadcaster_actor()
    |> result.map_error(fn(_) { "Failed to start WebSocket broadcaster" }),
  )

  io.println("✅ WebSocket broadcaster started")

  io.println("🔧 Starting banking services...")

  // Start banking services with broadcaster
  use #(command_eventstore, services_supervisor_spec) <- result.try(
    services.start_banking_services(service_config),
  )

  // Start services supervisor
  use _ <- result.try(
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.add(services_supervisor_spec)
    |> static_supervisor.start()
    |> result.map_error(fn(_) { "Failed to start services supervisor" }),
  )

  io.println("✅ Banking services started")

  // Start command processor with WebSocket broadcaster integration
  use command_processor <- result.try(
    services.start_command_processor(
      command_eventstore,
      broadcaster_actor,
    )
    |> result.map_error(fn(_) { "Failed to start command processor" }),
  )

  io.println("✅ Command processor started")

  // Start WebSocket server with the command processor
  use _websocket_server <- result.try(
    websocket_server.start_websocket_server_with_broadcaster(
      8080,
      command_processor,
      broadcaster_actor,
    )
    |> result.map_error(fn(_) { "Failed to start WebSocket server" }),
  )

  io.println("✅ WebSocket server started on port 8080")

  Ok(Nil)
}
