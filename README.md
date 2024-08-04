# Eventsourcing

[![Package Version](https://img.shields.io/hexpm/v/eventsourcing)](https://hex.pm/packages/eventsourcing)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/eventsourcing/)

```sh
gleam add eventsourcing
```
```gleam
import eventsourcing
import eventsourcing/postgres_store

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
      case amount >. 0.0 {
        True -> Ok([CustomerDepositedCash(amount:, balance:)])
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

pub fn main() {
  let mem_store =
    memory_store.new(BankAccount(opened: False, balance: 0.0), handle, apply)
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
  let event_sourcing = eventsourcing.new(mem_store, [query])
  eventsourcing.execute(
    event_sourcing,
    "92085b42-032c-4d7a-84de-a86d67123858",
    OpenAccount("92085b42-032c-4d7a-84de-a86d67123858"),
  )
}
```

Further documentation can be found at <https://hexdocs.pm/eventsourcing>.

## Development

```sh
gleam run   # Run the project
gleam test  # Run the tests
```
