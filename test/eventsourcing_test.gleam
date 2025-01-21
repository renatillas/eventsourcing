import birdie
import eventsourcing
import example_bank_account
import gleeunit
import gleeunit/should
import inmemory as memory_store
import pprint

pub fn main() {
  gleeunit.main()
}

pub fn execute_test() {
  let event_sourcing =
    eventsourcing.new(
      memory_store.new(),
      [],
      example_bank_account.handle,
      example_bank_account.apply,
      example_bank_account.UnopenedBankAccount,
    )
  eventsourcing.execute(
    event_sourcing,
    "92085b42-032c-4d7a-84de-a86d67123858",
    example_bank_account.OpenAccount("92085b42-032c-4d7a-84de-a86d67123858"),
  )
  |> pprint.format
  |> birdie.snap(title: "execute without metadata")
}

pub fn query_test() {
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
  let event_sourcing =
    eventsourcing.new(
      memory_store.new(),
      [query],
      example_bank_account.handle,
      example_bank_account.apply,
      example_bank_account.UnopenedBankAccount,
    )
  eventsourcing.execute(
    event_sourcing,
    "92085b42-032c-4d7a-84de-a86d67123858",
    example_bank_account.OpenAccount("92085b42-032c-4d7a-84de-a86d67123858"),
  )
  |> should.be_ok
  |> should.equal(Nil)
}

pub fn load_events_test() {
  let event_sourcing =
    eventsourcing.new(
      memory_store.new(),
      [],
      example_bank_account.handle,
      example_bank_account.apply,
      example_bank_account.UnopenedBankAccount,
    )
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

  eventsourcing.load_events(
    event_sourcing,
    "92085b42-032c-4d7a-84de-a86d67123858",
  )
  |> pprint.format
  |> birdie.snap(title: "load events")
}

pub fn load_events_with_metadata_test() {
  let event_sourcing =
    eventsourcing.new(
      memory_store.new(),
      [],
      example_bank_account.handle,
      example_bank_account.apply,
      example_bank_account.UnopenedBankAccount,
    )
  eventsourcing.execute_with_metadata(
    event_sourcing,
    "92085b42-032c-4d7a-84de-a86d67123858",
    example_bank_account.OpenAccount("92085b42-032c-4d7a-84de-a86d67123858"),
    [#("Hello", "World"), #("Fizz", "Buzz")],
  )
  |> should.be_ok
  |> should.equal(Nil)

  eventsourcing.load_events(
    event_sourcing,
    "92085b42-032c-4d7a-84de-a86d67123858",
  )
  |> pprint.format
  |> birdie.snap(title: "load events with metadata")
}

pub fn load_events_emtpy_aggregate_test() {
  let event_sourcing =
    eventsourcing.new(
      memory_store.new(),
      [],
      example_bank_account.handle,
      example_bank_account.apply,
      example_bank_account.UnopenedBankAccount,
    )
  eventsourcing.load_events(
    event_sourcing,
    "92085b42-032c-4d7a-84de-a86d67123858",
  )
  |> pprint.format
  |> birdie.snap(title: "load events empty aggregate")
}

pub fn load_aggregate_test() {
  let event_sourcing =
    eventsourcing.new(
      memory_store.new(),
      [],
      example_bank_account.handle,
      example_bank_account.apply,
      example_bank_account.UnopenedBankAccount,
    )
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

  eventsourcing.load_aggregate(
    event_sourcing,
    "92085b42-032c-4d7a-84de-a86d67123858",
  )
  |> pprint.format
  |> birdie.snap(title: "load aggregate entity")
}

pub fn load_emtpy_aggregate_test() {
  let event_sourcing =
    eventsourcing.new(
      memory_store.new(),
      [],
      example_bank_account.handle,
      example_bank_account.apply,
      example_bank_account.UnopenedBankAccount,
    )
  eventsourcing.load_aggregate(
    event_sourcing,
    "92085b42-032c-4d7a-84de-a86d67123858",
  )
  |> pprint.format
  |> birdie.snap(title: "load aggregate entity not found in the store")
}
