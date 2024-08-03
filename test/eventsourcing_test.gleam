import birdie
import eventsourcing
import eventsourcing/memory_store
import gleeunit
import pprint

pub fn main() {
  gleeunit.main()
}

// gleeunit test functions end in `_test`
pub fn execute_test() {
  let mem_store =
    memory_store.new(BankAccount(opened: False, balance: 0.0), handle, apply)
  let event_sourcing = eventsourcing.new(mem_store, [])
  eventsourcing.execute(event_sourcing, "1", DepositMoney(2.0))
  eventsourcing.execute(event_sourcing, "1", DepositMoney(3.0))
  eventsourcing.execute(event_sourcing, "1", DepositMoney(5.0))

  memory_store.load_aggregate(mem_store.eventstore, "1").aggregate.entity
  |> pprint.format
  |> birdie.snap(title: "execute")
}

pub type BankAccount {
  BankAccount(opened: Bool, balance: Float)
}

pub type BankAccountCommand {
  OpenAccount(account_id: String)
  DepositMoney(amount: Float)
  WithDrawMoney(amount: Float)
  WriteCheck(check_number: String, amount: Float)
}

pub type BankAccountEvent {
  AccountOpened(account_id: String)
  CustomerDepositedCash(amount: Float, balance: Float)
  CustomerWithdrewCash(amount: Float, balance: Float)
  CustomerWroteCheck(check_number: String, amount: Float, balance: Float)
}

pub fn handle(
  bank_account: BankAccount,
  command: BankAccountCommand,
) -> Result(List(BankAccountEvent), Nil) {
  case command {
    DepositMoney(amount) -> {
      let balance = bank_account.balance +. amount
      case amount >. 0.0 {
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
