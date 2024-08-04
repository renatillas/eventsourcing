# eventsourcing

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

pub fn event_type() {
  "BankAccountEvent"
}

pub fn encode_event(event: BankAccountEvent) -> String {
  // ...
  todo
}

pub fn decode_event(
  string: String,
) -> Result(BankAccountEvent, List(dynamic.DecodeError)) {
  // ...
  todo
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

pub fn aggregate_type() -> String {
  "BankAccount"
}


pub fn main() {
  let postgres_store =
    postgres_store.new(
      pgo_config: pgo.Config(
        ..pgo.default_config(),
        host: "localhost",
        database: "postgres",
        pool_size: 15,
        password: option.Some("password"),
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
    DepositMoney(10.0),
  )
}
```

Further documentation can be found at <https://hexdocs.pm/eventsourcing>.

## Development

```sh
gleam run   # Run the project
gleam test  # Run the tests
```
