import birdie
import eventsourcing
import eventsourcing/memory_store
import example_bank_account
import gleam/int
import gleam/io
import gleam/list
import gleeunit
import gleeunit/should
import pprint

pub fn main() {
  gleeunit.main()
}

pub fn memory_store_execute_test() {
  let mem_store =
    memory_store.new(
      example_bank_account.BankAccount(opened: False, balance: 0.0),
      example_bank_account.handle,
      example_bank_account.apply,
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
  let event_sourcing = eventsourcing.new(mem_store, [query])
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

  memory_store.load_aggregate_entity(
    mem_store.eventstore,
    "92085b42-032c-4d7a-84de-a86d67123858",
  )
  |> pprint.format
  |> birdie.snap(title: "memory store")
}

pub fn memory_store_load_events_test() {
  let mem_store =
    memory_store.new(
      example_bank_account.BankAccount(opened: False, balance: 0.0),
      example_bank_account.handle,
      example_bank_account.apply,
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
  let event_sourcing = eventsourcing.new(mem_store, [query])
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

  memory_store.load_events(
    mem_store.eventstore,
    "92085b42-032c-4d7a-84de-a86d67123858",
  )
  |> pprint.format
  |> birdie.snap(title: "memory store load events")
}
