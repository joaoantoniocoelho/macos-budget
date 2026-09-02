import XCTest
@testable import Financas

final class FinancasTests: XCTestCase {
    func testSeedCreatesCategoriesWithoutFinancialData() throws {
        let database = try makeDatabase()
        XCTAssertTrue(try database.months().isEmpty)
        XCTAssertTrue(try database.recurringExpenses().isEmpty)
    }

    func testPayInvoiceMovesCardChargesToPaid() throws {
        let database = try makeDatabase()
        let monthID = try database.createMonth(year: 2026, month: 9)
        try database.saveExpense(Expense(id: 0, monthID: monthID, recurringID: nil, date: .now, description: "Compra", category: "Outros", amount: 80, paymentMethod: .card, status: .pending, competenceYear: nil, competenceMonth: nil, notes: "", isRecurring: false))
        XCTAssertEqual(try database.expenses(monthID: monthID).filter { $0.status == .invoice }.reduce(0) { $0 + $1.amount }, 80, accuracy: 0.001)
        try database.payInvoice(monthID: monthID)
        XCTAssertFalse(try database.expenses(monthID: monthID).contains { $0.status == .invoice })
        XCTAssertTrue(try database.expenses(monthID: monthID).contains { $0.description == "Compra" && $0.status == .paid })
    }

    func testNewMonthCopiesActiveRecurringExpenses() throws {
        let database = try makeDatabase()
        try database.saveRecurring(RecurringExpense(id: 0, description: "Aluguel", category: "Moradia", amount: 1000, dueDay: 5, paymentMethod: .pix, notes: "", active: true))
        try database.saveRecurring(RecurringExpense(id: 0, description: "Academia", category: "Lazer", amount: 120, dueDay: nil, paymentMethod: .card, notes: "", active: false))
        let id = try database.createMonth(year: 2026, month: 10)
        XCTAssertEqual(try database.expenses(monthID: id).filter(\.isRecurring).count, 1)
        XCTAssertEqual(try database.expenses(monthID: id).first?.description, "Aluguel")
        XCTAssertEqual(try database.expenses(monthID: id).first?.status, .pending)
    }

    func testCardRecurringExpenseStartsPending() throws {
        let database = try makeDatabase()
        try database.saveRecurring(RecurringExpense(id: 0, description: "Streaming", category: "Assinaturas", amount: 50, dueDay: 10, paymentMethod: .card, notes: "", active: true))
        try database.saveRecurring(RecurringExpense(id: 0, description: "Aluguel", category: "Moradia", amount: 1000, dueDay: 5, paymentMethod: .pix, notes: "", active: true))
        let monthID = try database.createMonth(year: 2026, month: 10)
        let streaming = try XCTUnwrap(database.expenses(monthID: monthID).first { $0.description == "Streaming" })
        let rent = try XCTUnwrap(database.expenses(monthID: monthID).first { $0.description == "Aluguel" })
        XCTAssertEqual(streaming.status, .pending)
        XCTAssertEqual(rent.status, .pending)
    }

    func testChangingPaymentToCardDoesNotForceInvoice() throws {
        let database = try makeDatabase()
        let monthID = try database.createMonth(year: 2026, month: 9, initialBalance: 2000)
        try database.saveRecurring(RecurringExpense(id: 0, description: "Internet", category: "Moradia", amount: 100, dueDay: 8, paymentMethod: .pix, notes: "", active: true))
        try database.instantiateRecurring(monthID: monthID)
        var expense = try XCTUnwrap(database.expenses(monthID: monthID).first { $0.description == "Internet" })
        expense.paymentMethod = .card
        try database.saveExpense(expense)
        XCTAssertEqual(try XCTUnwrap(database.expenses(monthID: monthID).first { $0.description == "Internet" }).status, .pending)
    }

    func testPendingCardRecurringStaysPendingOnReopen() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("test.sqlite")
        let database = try Database(url: url, today: date(2026, 9, 2))
        try database.saveRecurring(RecurringExpense(id: 0, description: "Streaming", category: "Assinaturas", amount: 50, dueDay: 10, paymentMethod: .card, notes: "", active: true))
        let monthID = try database.createMonth(year: 2026, month: 10)
        XCTAssertEqual(try XCTUnwrap(database.expenses(monthID: monthID).first).status, .pending)
        let reopened = try Database(url: url, today: date(2026, 9, 2))
        XCTAssertEqual(try XCTUnwrap(reopened.expenses(monthID: monthID).first).status, .pending)
    }

    func testImportRejectsUnrelatedSQLiteFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let database = try Database(url: directory.appendingPathComponent("current.sqlite"), today: date(2026, 9, 2))
        let unrelated = directory.appendingPathComponent("unrelated.sqlite")
        FileManager.default.createFile(atPath: unrelated.path, contents: Data("not sqlite".utf8))
        XCTAssertThrowsError(try database.replaceDatabase(with: unrelated))
        XCTAssertTrue(try database.months().isEmpty)
    }

    func testBalanceUpdatesWithCompletedTransactions() throws {
        let database = try makeDatabase()
        let monthID = try database.createMonth(year: 2026, month: 9, initialBalance: 2000)
        XCTAssertEqual(try XCTUnwrap(database.months().first).currentBalance, 2000, accuracy: 0.001)

        try database.saveIncome(Income(id: 0, monthID: monthID, date: nil, description: "Salário", category: "Salário", amount: 500, expectedDay: 15, status: .pending, isFixed: true))
        var income = try XCTUnwrap(database.incomes(monthID: monthID).first)
        income.status = .received
        try database.saveIncome(income)
        XCTAssertEqual(try XCTUnwrap(database.months().first).currentBalance, 2500, accuracy: 0.001)

        try database.saveExpense(Expense(id: 0, monthID: monthID, recurringID: nil, date: .now, description: "Aluguel", category: "Moradia", amount: 400, paymentMethod: .pix, status: .pending, competenceYear: nil, competenceMonth: nil, notes: "", isRecurring: false))
        var expense = try XCTUnwrap(database.expenses(monthID: monthID).first { $0.description == "Aluguel" })
        XCTAssertEqual(try XCTUnwrap(database.months().first).currentBalance, 2100, accuracy: 0.001)

        expense.status = .pending
        try database.saveExpense(expense)
        XCTAssertEqual(try XCTUnwrap(database.months().first).currentBalance, 2500, accuracy: 0.001)

        try database.saveInvestment(Investment(id: 0, monthID: monthID, plannedDate: .now, plannedAmount: 300, actualAmount: 0, status: .pending))
        var investment = try XCTUnwrap(database.investments(monthID: monthID).first)
        investment.status = .completed
        investment.actualAmount = 300
        try database.saveInvestment(investment)
        XCTAssertEqual(try XCTUnwrap(database.months().first).currentBalance, 2200, accuracy: 0.001)
    }

    func testNewVariableExpenseUsesPaymentMethodAutomatically() throws {
        let database = try makeDatabase()
        let monthID = try database.createMonth(year: 2026, month: 9, initialBalance: 2000)

        try database.saveExpense(Expense(id: 0, monthID: monthID, recurringID: nil, date: .now, description: "Janta", category: "Alimentação fora", amount: 100, paymentMethod: .pix, status: .pending, competenceYear: nil, competenceMonth: nil, notes: "", isRecurring: false))
        let dinner = try XCTUnwrap(database.expenses(monthID: monthID).first { $0.description == "Janta" })
        XCTAssertEqual(dinner.status, .paid)
        XCTAssertEqual(try XCTUnwrap(database.months().first).currentBalance, 1900, accuracy: 0.001)

        var historicalDinner = dinner
        historicalDinner.includedInInitialBalance = true
        try database.saveExpense(historicalDinner)
        XCTAssertEqual(try XCTUnwrap(database.months().first).currentBalance, 2000, accuracy: 0.001)

        try database.saveExpense(Expense(id: 0, monthID: monthID, recurringID: nil, date: .now, description: "Cinema", category: "Lazer", amount: 50, paymentMethod: .card, status: .pending, competenceYear: nil, competenceMonth: nil, notes: "", isRecurring: false))
        let cinema = try XCTUnwrap(database.expenses(monthID: monthID).first { $0.description == "Cinema" })
        XCTAssertEqual(cinema.status, .invoice)
        XCTAssertEqual(try XCTUnwrap(database.months().first).currentBalance, 2000, accuracy: 0.001)
    }

    func testCardRecurringMovesToInvoiceOnDueDay() throws {
        let today = date(2026, 9, 15)
        let database = try makeDatabase(today: today)
        try database.saveRecurring(RecurringExpense(id: 0, description: "Streaming", category: "Assinaturas", amount: 50, dueDay: 15, paymentMethod: .card, notes: "", active: true))
        try database.saveRecurring(RecurringExpense(id: 0, description: "Depois", category: "Assinaturas", amount: 20, dueDay: 20, paymentMethod: .card, notes: "", active: true))
        try database.saveRecurring(RecurringExpense(id: 0, description: "Aluguel", category: "Moradia", amount: 1000, dueDay: 15, paymentMethod: .pix, notes: "", active: true))
        try database.saveRecurring(RecurringExpense(id: 0, description: "Sem dia", category: "Assinaturas", amount: 10, dueDay: nil, paymentMethod: .card, notes: "", active: true))
        let monthID = try database.createMonth(year: 2026, month: 9, initialBalance: 2000)
        XCTAssertEqual(try XCTUnwrap(database.expenses(monthID: monthID).first { $0.description == "Streaming" }).status, .invoice)
        XCTAssertEqual(try XCTUnwrap(database.expenses(monthID: monthID).first { $0.description == "Depois" }).status, .pending)
        XCTAssertEqual(try XCTUnwrap(database.expenses(monthID: monthID).first { $0.description == "Aluguel" }).status, .pending)
        XCTAssertEqual(try XCTUnwrap(database.expenses(monthID: monthID).first { $0.description == "Sem dia" }).status, .pending)
        XCTAssertEqual(try XCTUnwrap(database.months().first).currentBalance, 2000, accuracy: 0.001)
    }

    func testCardRecurringStaysPendingBeforeDueDay() throws {
        let database = try makeDatabase(today: date(2026, 9, 2))
        try database.saveRecurring(RecurringExpense(id: 0, description: "Streaming", category: "Assinaturas", amount: 50, dueDay: 15, paymentMethod: .card, notes: "", active: true))
        let monthID = try database.createMonth(year: 2026, month: 9)
        XCTAssertEqual(try XCTUnwrap(database.expenses(monthID: monthID).first).status, .pending)
    }

    func testCardRecurringMovesToInvoiceWhenAppReopensOnDueDay() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("test.sqlite")
        let before = try Database(url: url, today: date(2026, 9, 2))
        try before.saveRecurring(RecurringExpense(id: 0, description: "Streaming", category: "Assinaturas", amount: 50, dueDay: 15, paymentMethod: .card, notes: "", active: true))
        let monthID = try before.createMonth(year: 2026, month: 9)
        XCTAssertEqual(try XCTUnwrap(before.expenses(monthID: monthID).first).status, .pending)
        let after = try Database(url: url, today: date(2026, 9, 15))
        XCTAssertEqual(try XCTUnwrap(after.expenses(monthID: monthID).first).status, .invoice)
    }

    func testPaidCardRecurringIsNotMovedToInvoiceOnDueDay() throws {
        let database = try makeDatabase(today: date(2026, 9, 15))
        try database.saveRecurring(RecurringExpense(id: 0, description: "Streaming", category: "Assinaturas", amount: 120, dueDay: 15, paymentMethod: .card, notes: "", active: true))
        let monthID = try database.createMonth(year: 2026, month: 9)
        var expense = try XCTUnwrap(database.expenses(monthID: monthID).first)
        expense.status = .paid
        expense.includedInInitialBalance = true
        try database.saveExpense(expense)
        try database.applyDueCardInvoices(on: date(2026, 9, 15))
        XCTAssertEqual(try XCTUnwrap(database.expenses(monthID: monthID).first).status, .paid)
    }

    func testHiddenMoneyDoesNotRevealAmount() {
        XCTAssertEqual(AppFormat.money(1999.5, hidden: true), "R$ ••••")
        XCTAssertNotEqual(AppFormat.money(1999.5, hidden: false), "R$ ••••")
    }

    private func makeDatabase(today: Date = FinancasTests.testToday) throws -> Database {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return try Database(url: directory.appendingPathComponent("test.sqlite"), today: today)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day))!
    }

    private static let testToday = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 9, day: 2))!
}
