import birdie
import decode
import eventsourcing
import eventsourcing/sqlite_store
import gleam/dynamic
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/result
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
      empty_entity: BankAccount(opened: False, balance: 0.0),
      handle_command_function: handle,
      apply_function: apply,
      event_encoder: event_encoder,
      event_decoder: event_decoder,
      event_type: bank_account_event_type,
      event_version: "1.0",
      aggregate_type: bank_account_type,
    )
  let query = fn(
    aggregate_id: String,
    events: List(eventsourcing.EventEnvelop(BankAccountEvent)),
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
    OpenAccount("92085b42-032c-4d7a-84de-a86d67123858"),
  )
  |> should.be_ok
  |> should.equal(Nil)

  eventsourcing.execute(
    event_sourcing,
    "92085b42-032c-4d7a-84de-a86d67123858",
    DepositMoney(10.0),
  )
  |> should.be_ok
  |> should.equal(Nil)

  eventsourcing.execute(
    event_sourcing,
    "92085b42-032c-4d7a-84de-a86d67123858",
    WithDrawMoney(5.99),
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

pub type BankAccount {
  BankAccount(opened: Bool, balance: Float)
}

const bank_account_type = "BankAccount"

pub type BankAccountCommand {
  OpenAccount(account_id: String)
  DepositMoney(amount: Float)
  WithDrawMoney(amount: Float)
}

pub type BankAccountEvent {
  AccountOpened(account_id: String)
  CustomerDepositedCash(amount: Float, balance: Float)
  CustomerWithdrewCash(amount: Float, balance: Float)
}

const bank_account_event_type = "BankAccountEvent"

pub fn handle(
  bank_account: BankAccount,
  command: BankAccountCommand,
) -> Result(List(BankAccountEvent), Nil) {
  case command {
    OpenAccount(account_id) -> Ok([AccountOpened(account_id)])
    DepositMoney(amount) -> {
      let balance = bank_account.balance +. amount
      case amount >. 0.0 {
        True -> Ok([CustomerDepositedCash(amount:, balance:)])
        False -> Error(Nil)
      }
    }
    WithDrawMoney(amount) -> {
      let balance = bank_account.balance -. amount
      case amount >. 0.0 && balance >. 0.0 {
        True -> Ok([CustomerWithdrewCash(amount:, balance:)])
        False -> Error(Nil)
      }
    }
  }
}

pub fn apply(bank_account: BankAccount, event: BankAccountEvent) {
  case event {
    AccountOpened(_) -> BankAccount(..bank_account, opened: True)
    CustomerDepositedCash(_, balance) -> BankAccount(..bank_account, balance:)
    CustomerWithdrewCash(_, balance) -> BankAccount(..bank_account, balance:)
  }
}

pub fn event_encoder(event: BankAccountEvent) -> String {
  case event {
    AccountOpened(account_id) ->
      json.object([
        #("event-type", json.string("account-opened")),
        #("account-id", json.string(account_id)),
      ])
    CustomerDepositedCash(amount, balance) ->
      json.object([
        #("event-type", json.string("customer-deposited-cash")),
        #("amount", json.float(amount)),
        #("balance", json.float(balance)),
      ])
    CustomerWithdrewCash(amount, balance) ->
      json.object([
        #("event-type", json.string("customer-withdrew-cash")),
        #("amount", json.float(amount)),
        #("balance", json.float(balance)),
      ])
  }
  |> json.to_string
}

pub fn event_decoder(
  string: String,
) -> Result(BankAccountEvent, List(dynamic.DecodeError)) {
  let account_opened_decoder =
    decode.into({
      use account_id <- decode.parameter
      AccountOpened(account_id)
    })
    |> decode.field("account-id", decode.string)

  let customer_deposited_cash =
    decode.into({
      use amount <- decode.parameter
      use balance <- decode.parameter
      CustomerDepositedCash(amount, balance)
    })
    |> decode.field("amount", decode.float)
    |> decode.field("balance", decode.float)

  let customer_withdrew_cash =
    decode.into({
      use amount <- decode.parameter
      use balance <- decode.parameter
      CustomerWithdrewCash(amount, balance)
    })
    |> decode.field("amount", decode.float)
    |> decode.field("balance", decode.float)

  let decoder =
    decode.at(["event-type"], decode.string)
    |> decode.then(fn(event_type) {
      case event_type {
        "account-opened" -> account_opened_decoder
        "customer-deposited-cash" -> customer_deposited_cash
        "customer-withdrew-cash" -> customer_withdrew_cash
        _ -> decode.fail("event-type")
      }
    })
  json.decode(from: string, using: decode.from(decoder, _))
  |> result.map_error(fn(_) { [] })
}
