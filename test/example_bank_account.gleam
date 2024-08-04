import decode
import gleam/dynamic
import gleam/json
import gleam/result

pub type BankAccount {
  BankAccount(opened: Bool, balance: Float)
}

pub const bank_account_type = "BankAccount"

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

pub const bank_account_event_type = "BankAccountEvent"

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
