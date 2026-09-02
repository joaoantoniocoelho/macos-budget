import Foundation
import SwiftUI

@MainActor
final class AppStore: ObservableObject {
    @Published var months: [BudgetMonth] = []
    @Published var selectedMonthID: Int64?
    @Published var incomes: [Income] = []
    @Published var expenses: [Expense] = []
    @Published var recurring: [RecurringExpense] = []
    @Published var investments: [Investment] = []
    @Published var errorMessage: String?

    let database: Database

    init(database: Database) {
        self.database = database
        reloadAll(selectLatest: true)
    }

    convenience init() {
        do { try self.init(database: Database()) }
        catch { fatalError("Falha ao iniciar banco: \(error.localizedDescription)") }
    }

    var selectedMonth: BudgetMonth? { months.first { $0.id == selectedMonthID } }

    var totals: DashboardTotals {
        var t = DashboardTotals()
        t.initialBalance = selectedMonth?.initialBalance ?? 0
        t.fixedExpected = incomes.filter(\.isFixed).reduce(0) { $0 + $1.amount }
        t.fixedReceived = incomes.filter { $0.isFixed && $0.status == .received }.reduce(0) { $0 + $1.amount }
        t.extrasReceived = incomes.filter { !$0.isFixed && $0.status == .received }.reduce(0) { $0 + $1.amount }
        t.recurringExpected = expenses.filter(\.isRecurring).reduce(0) { $0 + $1.amount }
        t.recurringPaid = expenses.filter { $0.isRecurring && [.paid,.prepaid].contains($0.status) }.reduce(0) { $0 + $1.amount }
        t.invoice = expenses.filter { $0.status == .invoice }.reduce(0) { $0 + $1.amount }
        t.pending = expenses.filter { $0.status == .pending }.reduce(0) { $0 + $1.amount }
        t.variable = expenses.filter { !$0.isRecurring }.reduce(0) { $0 + $1.amount }
        t.paidVariable = expenses.filter { !$0.isRecurring && [.paid,.prepaid].contains($0.status) }.reduce(0) { $0 + $1.amount }
        t.investmentsPlanned = investments.reduce(0) { $0 + $1.plannedAmount }
        t.investmentsActual = investments.filter { $0.status == .completed }.reduce(0) { $0 + $1.actualAmount }
        return t
    }

    func reloadAll(selectLatest: Bool = false) {
        perform {
            months = try database.months()
            if selectLatest || !months.contains(where: { $0.id == selectedMonthID }) { selectedMonthID = months.last?.id }
            recurring = try database.recurringExpenses()
            try reloadMonth()
        }
    }

    func reloadMonth() throws {
        guard let id = selectedMonthID else { incomes=[]; expenses=[]; investments=[]; return }
        incomes = try database.incomes(monthID: id)
        expenses = try database.expenses(monthID: id)
        investments = try database.investments(monthID: id)
    }

    private func refreshCurrentMonth() throws {
        months = try database.months()
        try reloadMonth()
    }

    func select(_ id: Int64) { selectedMonthID = id; perform { try reloadMonth() } }

    func createNextMonth() {
        perform {
            let base = months.last ?? BudgetMonth(id: 0, year: Calendar.current.component(.year, from: .now), month: Calendar.current.component(.month, from: .now), initialBalance: 0, currentBalance: 0, balanceDate: nil)
            let next = base.month == 12 ? (base.year + 1, 1) : (base.year, base.month + 1)
            selectedMonthID = try database.createMonth(year: next.0, month: next.1)
            months = try database.months(); try reloadMonth()
        }
    }

    func saveMonth(_ value: BudgetMonth) { perform { try database.updateMonth(value); reloadAll() } }
    func deleteCurrentMonth() {
        guard let id = selectedMonthID else { return }
        perform { try database.deleteMonth(id); reloadAll(selectLatest: true) }
    }
    func save(_ value: Income) { perform { try database.saveIncome(value); try refreshCurrentMonth() } }
    func delete(_ value: Income) { perform { try database.deleteIncome(value.id); try refreshCurrentMonth() } }
    func save(_ value: Expense) { perform { try database.saveExpense(value); try refreshCurrentMonth() } }
    func delete(_ value: Expense) { perform { try database.deleteExpense(value.id); try refreshCurrentMonth() } }
    func save(_ value: Investment) { perform { try database.saveInvestment(value); try refreshCurrentMonth() } }
    func delete(_ value: Investment) { perform { try database.deleteInvestment(value.id); try refreshCurrentMonth() } }
    func save(_ value: RecurringExpense, addToCurrentMonth: Bool = false) {
        perform {
            let recurringID = try database.saveRecurring(value)
            if addToCurrentMonth, let monthID = selectedMonthID {
                try database.instantiateRecurring(monthID: monthID)
                if var expense = try database.expenses(monthID: monthID).first(where: { $0.recurringID == recurringID }) {
                    expense.date = .now
                    expense.status = expense.paymentMethod == .card ? .invoice : .paid
                    try database.saveExpense(expense)
                }
            }
            recurring = try database.recurringExpenses()
            try refreshCurrentMonth()
        }
    }
    func delete(_ value: RecurringExpense) { perform { try database.deleteRecurring(value.id); recurring = try database.recurringExpenses() } }
    func syncRecurring() { guard let id=selectedMonthID else{return}; perform { try database.instantiateRecurring(monthID:id); try reloadMonth() } }
    func payInvoice() { guard let id=selectedMonthID else{return}; perform { try database.payInvoice(monthID:id); try refreshCurrentMonth() } }

    func exportBackup(to url: URL) {
        perform {
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            try FileManager.default.copyItem(at: database.url, to: url)
        }
    }
    func importBackup(from url: URL) { perform { try database.replaceDatabase(with: url); reloadAll(selectLatest: true) } }

    private func perform(_ action: () throws -> Void) {
        do { try action() } catch { errorMessage = error.localizedDescription }
    }
}
