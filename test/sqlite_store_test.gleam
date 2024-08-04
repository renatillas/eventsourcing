import birdie
import eventsourcing
import eventsourcing/sqlite_store
import example_bank_account
import gleam/int
import gleam/io
import gleam/list
import gleeunit
import gleeunit/should
import pprint
import sqlight

pub fn main() {
  gleeunit.main()
}

pub fn sqlite_store_test() {
  let assert Ok(db) = sqlight.open(":memory:")
  let sqlite_store =
    sqlite_store.new(
      sqlight_connection: db,
      empty_entity: example_bank_account.BankAccount(
        opened: False,
        balance: 0.0,
      ),
      handle_command_function: example_bank_account.handle,
      apply_function: example_bank_account.apply,
      event_encoder: example_bank_account.event_encoder,
      event_decoder: example_bank_account.event_decoder,
      event_type: example_bank_account.bank_account_event_type,
      event_version: "1.0",
      aggregate_type: example_bank_account.bank_account_type,
    )
  let query = fn(
    aggregate_id: String,
    events: List(
      eventsourcing.EventEnvelop(example_bank_account.BankAccountEvent),
    ),
  ) {
    io.println_error(
      "Aggregate Bank Account with ID: "
      <> aggregate_id
      <> " commited "
      <> events |> list.length |> int.to_string
      <> " events.",
    )
  }
  sqlite_store.create_event_table(sqlite_store.eventstore)
  |> should.be_ok

  let event_sourcing = eventsourcing.new(sqlite_store, [query])

  eventsourcing.execute(
    event_sourcing,
    "92085b42-032c-4d7a-84de-a86d67123858",
    example_bank_account.OpenAccount("92085b42-032c-4d7a-84de-a86d67123858"),
  )
  |> should.be_ok
  |> should.equal(Nil)

  eventsourcing.execute(
    event_sourcing,
    "92085b42-032c-4d7a-84de-a86d67123858",
    example_bank_account.DepositMoney(10.0),
  )
  |> should.be_ok
  |> should.equal(Nil)

  eventsourcing.execute(
    event_sourcing,
    "92085b42-032c-4d7a-84de-a86d67123858",
    example_bank_account.WithDrawMoney(5.99),
  )
  |> should.be_ok
  |> should.equal(Nil)

  sqlite_store.load_aggregate_entity(
    sqlite_store.eventstore,
    "92085b42-032c-4d7a-84de-a86d67123858",
  )
  |> pprint.format
  |> birdie.snap(title: "sqlite store")
}

pub fn sqlite_store_load_events_test() {
  let assert Ok(db) = sqlight.open(":memory:")
  let sqlite_store =
    sqlite_store.new(
      sqlight_connection: db,
      empty_entity: example_bank_account.BankAccount(
        opened: False,
        balance: 0.0,
      ),
      handle_command_function: example_bank_account.handle,
      apply_function: example_bank_account.apply,
      event_encoder: example_bank_account.event_encoder,
      event_decoder: example_bank_account.event_decoder,
      event_type: example_bank_account.bank_account_event_type,
      event_version: "1.0",
      aggregate_type: example_bank_account.bank_account_type,
    )
  let query = fn(
    aggregate_id: String,
    events: List(
      eventsourcing.EventEnvelop(example_bank_account.BankAccountEvent),
    ),
  ) {
    io.println_error(
      "Aggregate Bank Account with ID: "
      <> aggregate_id
      <> " commited "
      <> events |> list.length |> int.to_string
      <> " events.",
    )
  }
  sqlite_store.create_event_table(sqlite_store.eventstore)
  |> should.be_ok

  let event_sourcing = eventsourcing.new(sqlite_store, [query])

  eventsourcing.execute(
    event_sourcing,
    "92085b42-032c-4d7a-84de-a86d67123858",
    example_bank_account.OpenAccount("92085b42-032c-4d7a-84de-a86d67123858"),
  )
  |> should.be_ok
  |> should.equal(Nil)

  eventsourcing.execute(
    event_sourcing,
    "92085b42-032c-4d7a-84de-a86d67123858",
    example_bank_account.DepositMoney(10.0),
  )
  |> should.be_ok
  |> should.equal(Nil)

  eventsourcing.execute(
    event_sourcing,
    "92085b42-032c-4d7a-84de-a86d67123858",
    example_bank_account.WithDrawMoney(5.99),
  )
  |> should.be_ok
  |> should.equal(Nil)

  sqlite_store.load_events(
    sqlite_store.eventstore,
    "92085b42-032c-4d7a-84de-a86d67123858",
  )
  |> should.be_ok
  |> pprint.format
  |> birdie.snap(title: "sqlite store load events")
}
