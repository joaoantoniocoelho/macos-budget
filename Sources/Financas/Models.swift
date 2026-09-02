import Foundation
import SwiftUI

private struct HideAmountsKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var hideAmounts: Bool {
        get { self[HideAmountsKey.self] }
        set { self[HideAmountsKey.self] = newValue }
    }
}

enum IncomeStatus: String, CaseIterable, Identifiable {
    case pending = "A receber"
    case received = "Recebido"
    var id: String { rawValue }
}

enum ExpenseStatus: String, CaseIterable, Identifiable {
    case pending = "Pendente"
    case invoice = "Na fatura"
    case paid = "Pago"
    case prepaid = "Pago antecipado"
    var id: String { rawValue }
}

enum InvestmentStatus: String, CaseIterable, Identifiable {
    case pending = "Pendente"
    case completed = "Realizado"
    var id: String { rawValue }
}

enum PaymentMethod: String, CaseIterable, Identifiable {
    case card = "Cartão"
    case pix = "Débito/PIX"
    case automatic = "Débito automático"
    case cash = "Dinheiro"
    var id: String { rawValue }
}

struct BudgetMonth: Identifiable, Hashable {
    let id: Int64
    var year: Int
    var month: Int
    var initialBalance: Double
    var currentBalance: Double
    var balanceDate: Date?

    var title: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.dateFormat = "LLLL yyyy"
        let date = Calendar.current.date(from: DateComponents(year: year, month: month)) ?? .now
        return formatter.string(from: date).capitalized
    }
}

struct Income: Identifiable {
    var id: Int64
    var monthID: Int64
    var date: Date?
    var description: String
    var category: String
    var amount: Double
    var expectedDay: Int?
    var status: IncomeStatus
    var isFixed: Bool
}

struct RecurringExpense: Identifiable {
    var id: Int64
    var description: String
    var category: String
    var amount: Double
    var dueDay: Int?
    var paymentMethod: PaymentMethod
    var notes: String
    var active: Bool
}

struct Expense: Identifiable {
    var id: Int64
    var monthID: Int64
    var recurringID: Int64?
    var date: Date?
    var description: String
    var category: String
    var amount: Double
    var paymentMethod: PaymentMethod
    var status: ExpenseStatus
    var competenceYear: Int?
    var competenceMonth: Int?
    var notes: String
    var isRecurring: Bool
    var includedInInitialBalance: Bool = false
}

struct Investment: Identifiable {
    var id: Int64
    var monthID: Int64
    var plannedDate: Date
    var plannedAmount: Double
    var actualAmount: Double
    var status: InvestmentStatus
}

struct DashboardTotals {
    var initialBalance = 0.0
    var fixedExpected = 0.0
    var fixedReceived = 0.0
    var extrasReceived = 0.0
    var recurringExpected = 0.0
    var recurringPaid = 0.0
    var invoice = 0.0
    var pending = 0.0
    var variable = 0.0
    var investmentsPlanned = 0.0
    var investmentsActual = 0.0

    var totalIncomeReceived: Double { fixedReceived + extrasReceived }
    var paidVariable: Double = 0.0
    var variableBudget: Double { fixedExpected - recurringExpected - investmentsPlanned }
}

enum AppFormat {
    static let currency: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = Locale(identifier: "pt_BR")
        return f
    }()

    static func money(_ value: Double, hidden: Bool = false) -> String {
        if hidden { return "R$ ••••" }
        return currency.string(from: NSNumber(value: value)) ?? "R$ 0,00"
    }

    static let date: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.dateStyle = .short
        return f
    }()
}
