import birdie
import eventsourcing
import eventsourcing/memory_store
import example_bank_account
import gleeunit
import gleeunit/should
import pprint

pub fn main() {
  gleeunit.main()
}

pub fn execute_test() {
  let mem_store =
    memory_store.new(
      example_bank_account.UnopenedBankAccount,
      example_bank_account.handle,
      example_bank_account.apply,
    )
  let event_sourcing = eventsourcing.new(mem_store, [])
  eventsourcing.execute(
    event_sourcing,
    "92085b42-032c-4d7a-84de-a86d67123858",
    example_bank_account.OpenAccount("92085b42-032c-4d7a-84de-a86d67123858"),
  )
  |> pprint.format
  |> birdie.snap(title: "execute without metadata")
}

pub fn query_test() {
  let mem_store =
    memory_store.new(
      example_bank_account.UnopenedBankAccount,
      example_bank_account.handle,
      example_bank_account.apply,
    )
  let query = fn(
    aggregate_id: String,
    events: List(
      eventsourcing.EventEnvelop(example_bank_account.BankAccountEvent),
    ),
  ) {
    #(aggregate_id, events)
    |> pprint.format
    |> birdie.snap(title: "query event")
  }
  let event_sourcing = eventsourcing.new(mem_store, [query])
  eventsourcing.execute(
    event_sourcing,
    "92085b42-032c-4d7a-84de-a86d67123858",
    example_bank_account.OpenAccount("92085b42-032c-4d7a-84de-a86d67123858"),
  )
  |> should.be_ok
  |> should.equal(Nil)
}

pub fn load_events_test() {
  let mem_store =
    memory_store.new(
      example_bank_account.UnopenedBankAccount,
      example_bank_account.handle,
      example_bank_account.apply,
    )
  let event_sourcing = eventsourcing.new(mem_store, [])
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
  |> birdie.snap(title: "load events")
}

pub fn load_events_with_metadata_test() {
  let mem_store =
    memory_store.new(
      example_bank_account.UnopenedBankAccount,
      example_bank_account.handle,
      example_bank_account.apply,
    )
  let event_sourcing = eventsourcing.new(mem_store, [])
  eventsourcing.execute_with_metadata(
    event_sourcing,
    "92085b42-032c-4d7a-84de-a86d67123858",
    example_bank_account.OpenAccount("92085b42-032c-4d7a-84de-a86d67123858"),
    [#("Hello", "World"), #("Fizz", "Buzz")],
  )
  |> should.be_ok
  |> should.equal(Nil)

  memory_store.load_events(
    mem_store.eventstore,
    "92085b42-032c-4d7a-84de-a86d67123858",
  )
  |> pprint.format
  |> birdie.snap(title: "load events with metadata")
}

pub fn load_events_emtpy_aggregate_test() {
  let mem_store =
    memory_store.new(
      example_bank_account.UnopenedBankAccount,
      example_bank_account.handle,
      example_bank_account.apply,
    )
  memory_store.load_events(
    mem_store.eventstore,
    "92085b42-032c-4d7a-84de-a86d67123858",
  )
  |> pprint.format
  |> birdie.snap(title: "load events empty aggregate")
}

pub fn load_aggregate_entity_test() {
  let mem_store =
    memory_store.new(
      example_bank_account.UnopenedBankAccount,
      example_bank_account.handle,
      example_bank_account.apply,
    )
  let event_sourcing = eventsourcing.new(mem_store, [])
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
  |> birdie.snap(title: "load aggregate entity")
}

pub fn load_emtpy_aggregate_entity_test() {
  let mem_store =
    memory_store.new(
      example_bank_account.UnopenedBankAccount,
      example_bank_account.handle,
      example_bank_account.apply,
    )
  memory_store.load_aggregate_entity(
    mem_store.eventstore,
    "92085b42-032c-4d7a-84de-a86d67123858",
  )
  |> pprint.format
  |> birdie.snap(title: "load empty aggregate entity")
}
