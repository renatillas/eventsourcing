import eventsourcing
import eventsourcing/memory_store

/// Command
pub type BankAccountCommand {
  OpenAccount(account_id: String)
  DepositMoney(amount: Float)
  WithDrawMoney(amount: Float)
  WriteCheck(check_number: String, amount: Float)
}

/// Event
pub type BankAccountEvent {
  AccountOpened(account_id: String)
  CustomerDepositedCash(amount: Float, balance: Float)
  CustomerWithdrewCash(amount: Float, balance: Float)
  CustomerWroteCheck(check_number: String, amount: Float, balance: Float)
}

pub fn event_type(event: BankAccountEvent) -> String {
  case event {
    AccountOpened(_) -> "AccountOpened"
    CustomerDepositedCash(_, _) -> "CustomerDepositedCash"
    CustomerWithdrewCash(_, _) -> "CustomerWithdrewCash"
    CustomerWroteCheck(_, _, _) -> "CustomerWroteCheck"
  }
}

pub type BankAccount {
  BankAccount(opened: Bool, balance: Float)
}

pub fn handle(
  bank_account: BankAccount,
  command: BankAccountCommand,
) -> Result(List(BankAccountEvent), Nil) {
  case command {
    DepositMoney(amount) -> {
      let balance = bank_account.balance +. amount
      case balance >=. 0.0 {
        True -> Ok([CustomerDepositedCash(amount:, balance:)])
        False -> Error(Nil)
      }
    }
    _ -> Ok([])
  }
}

pub fn apply(bank_account: BankAccount, event: BankAccountEvent) {
  case event {
    AccountOpened(_) -> BankAccount(..bank_account, opened: True)
    CustomerDepositedCash(_, balance) -> BankAccount(..bank_account, balance:)
    CustomerWithdrewCash(_, balance) -> BankAccount(..bank_account, balance:)
    CustomerWroteCheck(_, _, balance) -> BankAccount(..bank_account, balance:)
  }
}

pub fn aggregate_type(_: BankAccount) -> String {
  "BankAccount"
}

pub fn main() {
  let mem_store =
    memory_store.new(BankAccount(opened: False, balance: 0.0), handle, apply)
  let event_sourcing = eventsourcing.new(mem_store, [])
  let assert Ok(Nil) =
    eventsourcing.execute(event_sourcing, "1", DepositMoney(2.0))
  let assert Ok(Nil) =
    eventsourcing.execute(event_sourcing, "1", DepositMoney(3.0))
  let assert Ok(Nil) =
    eventsourcing.execute(event_sourcing, "1", DepositMoney(5.0))
  Ok(Nil)
}
