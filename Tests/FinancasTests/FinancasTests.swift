import XCTest
@testable import Financas

final class FinancasTests: XCTestCase {
    func testSeedCreatesCategoriesWithoutFinancialData() throws {
        let database = try makeDatabase()
        XCTAssertTrue(try database.months().isEmpty)
        XCTAssertTrue(try database.recurringExpenses().isEmpty)
        let funds=try database.investmentFunds()
        XCTAssertEqual(funds.count,2)
        XCTAssertEqual(funds.reduce(0){$0+$1.currentBalance},10822.01,accuracy:0.001)
        XCTAssertEqual(try XCTUnwrap(funds.first(where:\.isEmergencyReserve)).currentBalance,8532.58,accuracy:0.001)
    }

    func testInvestmentMovementsUpdateFundAndAccountBalances() throws {
        let database=try makeDatabase()
        let monthID=try database.createMonth(year:2026,month:9,initialBalance:2000)
        let occam=try XCTUnwrap(database.investmentFunds().first(where:\.isEmergencyReserve))

        try database.saveInvestmentMovement(InvestmentMovement(id:0,monthID:monthID,fundID:occam.id,date:date(2026,9,6),kind:.contribution,amount:500,notes:"Aporte mensal"))
        XCTAssertEqual(try XCTUnwrap(database.months().first).currentBalance,1500,accuracy:0.001)
        XCTAssertEqual(try XCTUnwrap(database.investmentFunds().first(where:{$0.id == occam.id})).currentBalance,9032.58,accuracy:0.001)

        var movement=try XCTUnwrap(database.investmentMovements(monthID:monthID).first)
        movement.kind = .withdrawal
        movement.amount = 200
        try database.saveInvestmentMovement(movement)
        XCTAssertEqual(try XCTUnwrap(database.months().first).currentBalance,2200,accuracy:0.001)
        XCTAssertEqual(try XCTUnwrap(database.investmentFunds().first(where:{$0.id == occam.id})).currentBalance,8332.58,accuracy:0.001)

        try database.deleteInvestmentMovement(movement.id)
        XCTAssertEqual(try XCTUnwrap(database.months().first).currentBalance,2000,accuracy:0.001)
        XCTAssertEqual(try XCTUnwrap(database.investmentFunds().first(where:{$0.id == occam.id})).currentBalance,8532.58,accuracy:0.001)
    }

    func testInvestmentWithdrawalCannotExceedFundBalance() throws {
        let database=try makeDatabase()
        let monthID=try database.createMonth(year:2026,month:9,initialBalance:2000)
        let fund=try XCTUnwrap(database.investmentFunds().last)
        XCTAssertThrowsError(try database.saveInvestmentMovement(InvestmentMovement(id:0,monthID:monthID,fundID:fund.id,date:date(2026,9,6),kind:.withdrawal,amount:3000,notes:"")))
        XCTAssertEqual(try XCTUnwrap(database.months().first).currentBalance,2000,accuracy:0.001)
    }

    @MainActor
    func testNextSalaryUsesNearestPendingFixedIncome() throws {
        let database=try makeDatabase()
        let monthID=try database.createMonth(year:2026,month:9)
        try database.saveIncome(Income(id:0,monthID:monthID,date:nil,description:"Salário dia 15",category:"Salário",amount:5200,expectedDay:15,status:.pending,isFixed:true))
        try database.saveIncome(Income(id:0,monthID:monthID,date:nil,description:"Salário dia 30",category:"Salário",amount:3700,expectedDay:30,status:.pending,isFixed:true))
        let store=AppStore(database:database)
        let salary=try XCTUnwrap(store.nextSalary(referenceDate:date(2026,9,6)))
        XCTAssertEqual(salary.days,9)
        XCTAssertEqual(salary.amount,5200,accuracy:0.001)
    }

    @MainActor
    func testFinancialGoalDoesNotCountAsInvestedValue() throws {
        let database=try makeDatabase()
        try database.execute("INSERT INTO investment_funds(name,opening_balance,is_emergency_reserve,counts_as_investment,active) VALUES('Viagem',8453,0,0,1)")
        let monthID=try database.createMonth(year:2026,month:9,initialBalance:1000)
        let travelID=try XCTUnwrap(database.investmentFunds().first(where:{$0.name == "Viagem"})?.id)
        try database.saveInvestmentMovement(InvestmentMovement(id:0,monthID:monthID,fundID:travelID,date:date(2026,9,7),kind:.contribution,amount:100,notes:""))
        let store=AppStore(database:database)
        XCTAssertEqual(store.investmentFunds.count,3)
        XCTAssertEqual(store.totalInvested,10822.01,accuracy:0.001)
        XCTAssertEqual(store.totals.investmentsActual,0,accuracy:0.001)
        XCTAssertEqual(store.investmentFunds.first(where:{$0.name == "Viagem"})?.countsAsInvestment,false)
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

    func testNewMonthCopiesOnlyFixedIncomes() throws {
        let database = try makeDatabase()
        let september = try database.createMonth(year: 2026, month: 9)
        try database.saveIncome(Income(id:0,monthID:september,date:nil,description:"Salário dia 15",category:"Salário",amount:5200,expectedDay:15,status:.received,isFixed:true))
        try database.saveIncome(Income(id:0,monthID:september,date:date(2026,9,30),description:"PLR",category:"PLR",amount:9500,expectedDay:nil,status:.pending,isFixed:false))
        let october = try database.createMonth(year: 2026, month: 10)
        let incomes = try database.incomes(monthID:october)
        XCTAssertEqual(incomes.count,1)
        XCTAssertEqual(incomes.first?.description,"Salário dia 15")
        XCTAssertEqual(incomes.first?.status,.pending)
        XCTAssertNil(incomes.first?.date)
    }

    func testNewMonthCopiesInvestmentPlanAsPending() throws {
        let database=try makeDatabase()
        let september=try database.createMonth(year:2026,month:9)
        try database.saveInvestment(Investment(id:0,monthID:september,plannedDate:date(2026,9,15),plannedAmount:1500,actualAmount:1500,status:.completed))
        try database.saveInvestment(Investment(id:0,monthID:september,plannedDate:date(2026,9,30),plannedAmount:1500,actualAmount:0,status:.pending))
        let october=try database.createMonth(year:2026,month:10)
        let plans=try database.investments(monthID:october)
        XCTAssertEqual(plans.count,2)
        XCTAssertEqual(plans.reduce(0){$0+$1.plannedAmount},3000,accuracy:0.001)
        XCTAssertTrue(plans.allSatisfy{$0.status == .pending && $0.actualAmount == 0})
        XCTAssertEqual(Calendar(identifier:.gregorian).component(.month,from:plans[0].plannedDate),10)
    }

    func testDeletingRecurringExpenseRemovesOnlyCurrentMonthAndDoesNotResync() throws {
        let database = try makeDatabase()
        try database.saveRecurring(RecurringExpense(id: 0, description: "Aluguel", category: "Moradia", amount: 1000, dueDay: nil, paymentMethod: .pix, notes: "", active: true))
        let september = try database.createMonth(year: 2026, month: 9)
        let expense = try XCTUnwrap(database.expenses(monthID: september).first)
        try database.deleteExpense(expense.id)
        XCTAssertTrue(try database.expenses(monthID: september).isEmpty)
        try database.instantiateRecurring(monthID: september)
        XCTAssertTrue(try database.expenses(monthID: september).isEmpty)
        let october = try database.createMonth(year: 2026, month: 10)
        XCTAssertEqual(try database.expenses(monthID: october).first?.description, "Aluguel")
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

    func testCardDueBeforeBalanceSnapshotStaysPending() throws {
        let today = date(2026, 9, 5)
        let database = try makeDatabase(today: today)
        try database.saveRecurring(RecurringExpense(id: 0, description: "Cartão antigo", category: "Assinaturas", amount: 90, dueDay: 2, paymentMethod: .card, notes: "", active: true))
        let monthID = try database.createMonth(year: 2026, month: 9, initialBalance: 1812.36, balanceDate: today)
        XCTAssertEqual(try database.expenses(monthID: monthID).first?.status, .pending)
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
