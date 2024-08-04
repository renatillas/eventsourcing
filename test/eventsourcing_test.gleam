import birdie
import decode
import eventsourcing
import eventsourcing/memory_store
import eventsourcing/postgres_store
import gleam/dynamic
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/option
import gleam/pgo
import gleam/result
import gleeunit
import gleeunit/should
import pprint

pub fn main() {
  gleeunit.main()
}

pub fn memory_store_execute_open_account_test() {
  let mem_store =
    memory_store.new(BankAccount(opened: False, balance: 0.0), handle, apply)
  let query = fn(
    aggregate_id: String,
    events: List(eventsourcing.EventEnvelop(BankAccountEvent)),
  ) {
    io.println(
      "Aggregate Bank Account with ID: "
      <> aggregate_id
      <> " commited "
      <> events |> list.length |> int.to_string
      <> " events.",
    )
  }
  let event_sourcing = eventsourcing.new(mem_store, [query])
  eventsourcing.execute(
    event_sourcing,
    "92085b42-032c-4d7a-84de-a86d67123858",
    OpenAccount("92085b42-032c-4d7a-84de-a86d67123858"),
  )
  |> should.be_ok
  |> should.equal(Nil)

  memory_store.load_aggregate_entity(
    mem_store.eventstore,
    "92085b42-032c-4d7a-84de-a86d67123858",
  )
  |> pprint.format
  |> birdie.snap(title: "memory store open account")
}

pub fn postgres_store_execute_open_account_test() {
  let postgres_store =
    postgres_store.new(
      pgo_config: pgo.Config(
        ..pgo.default_config(),
        host: "localhost",
        database: "postgres",
        pool_size: 15,
        password: option.Some("postgres"),
      ),
      emtpy_entity: BankAccount(opened: False, balance: 0.0),
      handle_command_function: handle,
      apply_function: apply,
      event_encoder: encode_event,
      event_decoder: decode_event,
      event_type: event_type(),
      event_version: "1",
      aggregate_type: aggregate_type(),
    )
  let event_sourcing = eventsourcing.new(postgres_store, [])
  eventsourcing.execute(
    event_sourcing,
    "92085b42-032c-4d7a-84de-a86d67123858",
    OpenAccount("92085b42-032c-4d7a-84de-a86d67123858"),
  )
  |> should.be_ok
  |> should.equal(Nil)

  postgres_store.load_aggregate(
    postgres_store.eventstore,
    "92085b42-032c-4d7a-84de-a86d67123858",
  ).aggregate.entity
  |> pprint.format
  |> birdie.snap(title: "memory store open account")
}

pub type BankAccount {
  BankAccount(opened: Bool, balance: Float)
}

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

pub fn event_type() {
  "BankAccountEvent"
}

pub fn encode_event(event: BankAccountEvent) -> String {
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

pub fn decode_event(
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

pub fn aggregate_type() -> String {
  "BankAccount"
}
