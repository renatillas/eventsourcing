import gleam/dynamic/decode
import gleam/erlang/atom

/// Bank account aggregate state
pub type BankAccount {
  BankAccount(balance: Float, account_holder: String)
  UnopenedBankAccount
}

/// Commands that can be sent to a bank account
pub type Command {
  OpenAccount(account_id: String, account_holder: String)
  DepositMoney(amount: Float)
  WithDrawMoney(amount: Float)
  CloseAccount
}

/// Events that occur in the banking domain
pub type Event {
  AccountOpened(account_id: String, account_holder: String)
  CustomerDepositedCash(amount: Float, balance: Float)
  CustomerWithdrewCash(amount: Float, balance: Float)
  AccountClosed
}

/// Errors that can occur during command processing
pub type Error {
  CantDepositNegativeAmount
  CantWithdrawNegativeAmount
  CantOperateOnUnopenedAccount
  CantWithdrawMoreThanCurrentBalance
  AccountAlreadyClosed
}

/// Bank account view model for real-time projections
pub type AccountView {
  AccountView(
    account_id: String,
    account_holder: String,
    balance: Float,
    last_updated: Int,
  )
}

/// Business logic for handling banking commands
pub fn handle(
  bank_account: BankAccount,
  command: Command,
) -> Result(List(Event), Error) {
  case bank_account, command {
    UnopenedBankAccount, OpenAccount(account_id, account_holder) ->
      Ok([AccountOpened(account_id, account_holder)])

    BankAccount(balance, _), DepositMoney(amount) -> {
      case amount >. 0.0 {
        True -> {
          let new_balance = balance +. amount
          Ok([CustomerDepositedCash(amount, new_balance)])
        }
        False -> Error(CantDepositNegativeAmount)
      }
    }

    BankAccount(balance, _), WithDrawMoney(amount) -> {
      case amount >. 0.0 && balance >=. amount {
        True -> {
          let new_balance = balance -. amount
          Ok([CustomerWithdrewCash(amount, new_balance)])
        }
        False ->
          case amount <=. 0.0 {
            True -> Error(CantWithdrawNegativeAmount)
            False -> Error(CantWithdrawMoreThanCurrentBalance)
          }
      }
    }

    BankAccount(_, _), CloseAccount -> Ok([AccountClosed])

    _, _ -> Error(CantOperateOnUnopenedAccount)
  }
}

/// Apply events to update account state
pub fn apply(bank_account: BankAccount, event: Event) -> BankAccount {
  case bank_account, event {
    UnopenedBankAccount, AccountOpened(_, account_holder) ->
      BankAccount(0.0, account_holder)

    BankAccount(_, account_holder), CustomerDepositedCash(_, new_balance) ->
      BankAccount(new_balance, account_holder)

    BankAccount(_, account_holder), CustomerWithdrewCash(_, new_balance) ->
      BankAccount(new_balance, account_holder)

    BankAccount(_, _), AccountClosed -> UnopenedBankAccount

    _, _ -> bank_account
  }
}

/// Event decoder for Gleam native format (used by eventsourcing_glyn)
pub fn event_decoder_gleam() -> decode.Decoder(Event) {
  use tag <- decode.field(0, atom.decoder())
  case atom.to_string(tag) {
    "account_opened" -> {
      use account_id <- decode.field(1, decode.string)
      use account_holder <- decode.field(2, decode.string)
      decode.success(AccountOpened(account_id, account_holder))
    }
    "customer_deposited_cash" -> {
      use amount <- decode.field(1, decode.float)
      use balance <- decode.field(2, decode.float)
      decode.success(CustomerDepositedCash(amount, balance))
    }
    "customer_withdrew_cash" -> {
      use amount <- decode.field(1, decode.float)
      use balance <- decode.field(2, decode.float)
      decode.success(CustomerWithdrewCash(amount, balance))
    }
    "account_closed" -> decode.success(AccountClosed)
    _ -> decode.failure(AccountClosed, "Unknown event type")
  }
}
