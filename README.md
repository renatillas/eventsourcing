# Eventsourcing

[![Package Version](https://img.shields.io/hexpm/v/eventsourcing)](https://hex.pm/packages/eventsourcing)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/eventsourcing/)

```sh
gleam add eventsourcing
```
```gleam
import eventsourcing
import eventsourcing/memory_store

import gleam/result

pub const bank_account_event_type = "BankAccountEvent"
pub const bank_account_type = "BankAccount"

pub type BankAccount {
  BankAccount(balance: Float)
  UnopenedBankAccount
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


pub type BankAccountError {
  CantDepositNegativeAmount
  CantOperateOnUnopenedAccount
  CantWithdrawMoreThanCurrentBalance
}

pub fn handle(
  bank_account: BankAccount,
  command: BankAccountCommand,
) -> Result(List(BankAccountEvent), BankAccountError) {
  case bank_account, command {
    UnopenedBankAccount, OpenAccount(account_id) ->
      Ok([AccountOpened(account_id)])
    BankAccount(balance), DepositMoney(amount) -> {
      let balance = balance +. amount
      case amount >. 0.0 {
        True -> Ok([CustomerDepositedCash(amount:, balance:)])
        False -> Error(CantDepositNegativeAmount)
      }
    }
    BankAccount(balance), WithDrawMoney(amount) -> {
      let balance = balance -. amount
      case amount >. 0.0 && balance >. 0.0 {
        True -> Ok([CustomerWithdrewCash(amount:, balance:)])
        False -> Error(CantWithdrawMoreThanCurrentBalance)
      }
    }
    _, _ -> Error(CantOperateOnUnopenedAccount)
  }
}

pub fn apply(bank_account: BankAccount, event: BankAccountEvent) {
  case bank_account, event {
    UnopenedBankAccount, AccountOpened(_) -> BankAccount(0.0)
    BankAccount(_), CustomerDepositedCash(_, balance) -> BankAccount(balance:)
    BankAccount(_), CustomerWithdrewCash(_, balance) -> BankAccount(balance:)
    _, _ -> panic
  }
}

pub fn main() {
  let mem_store =
    memory_store.new(UnopenedBankAccount, handle, apply)
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
