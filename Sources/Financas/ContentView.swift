import SwiftUI
import Charts

enum AppSection: String, CaseIterable, Identifiable {
    case summary = "Resumo", expenses = "Gastos", outflows = "Saídas", incomes = "Entradas", investments = "Investimentos", settings = "Configurações"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .summary: "rectangle.grid.2x2"
        case .expenses: "creditcard"
        case .outflows: "arrow.up.circle"
        case .incomes: "arrow.down.circle"
        case .investments: "chart.line.uptrend.xyaxis"
        case .settings: "gear"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var store: AppStore
    @AppStorage("hideAmounts") private var hideAmounts = false
    @State private var section: AppSection? = .summary

    var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $section) { item in
                Label(item.rawValue, systemImage: item.icon).tag(item)
            }.navigationTitle("Finanças")
        } detail: {
            Group {
                switch section ?? .summary {
                case .summary: DashboardView()
                case .expenses: ExpensesView()
                case .outflows: ExpensesView(mode: .outflows)
                case .incomes: IncomesView()
                case .investments: InvestmentsView()
                case .settings: SettingsView()
                }
            }
            .toolbar { MonthToolbar() }
        }
        .environment(\.hideAmounts, hideAmounts)
        .alert("Não foi possível concluir", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage=nil } })) {
            Button("OK") { store.errorMessage=nil }
        } message: { Text(store.errorMessage ?? "Erro desconhecido") }
    }
}

struct MonthToolbar: View {
    @EnvironmentObject private var store: AppStore
    @AppStorage("hideAmounts") private var hideAmounts = false
    var body: some View {
        Button {
            hideAmounts.toggle()
        } label: {
            Label(hideAmounts ? "Mostrar valores" : "Ocultar valores", systemImage: hideAmounts ? "eye.slash" : "eye")
        }
        .help(hideAmounts ? "Mostrar valores" : "Ocultar valores")
        Picker("Mês", selection: Binding(get: { store.selectedMonthID ?? 0 }, set: store.select)) {
            ForEach(store.months) { Text($0.title).tag($0.id) }
        }.frame(width: 180)
        Button { store.createNextMonth() } label: { Label("Novo mês", systemImage: "plus") }
    }
}

struct EmptyMonthView: View {
    var body: some View { ContentUnavailableView("Nenhum mês", systemImage: "calendar", description: Text("Crie um mês para começar.")) }
}

struct DashboardView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.hideAmounts) private var hideAmounts
    @State private var editingBalance = false
    @State private var hoveredCategory:String?
    private let detailColumns = [GridItem(.adaptive(minimum: 180), spacing: 12)]

    private struct CategorySpending: Identifiable {
        let category:String
        let items:[Expense]
        var total:Double { items.reduce(0) { $0 + $1.amount } }
        var id:String { category }
    }

    private var spendingByCategory:[CategorySpending] {
        let spent = store.expenses.filter { [.paid,.prepaid,.invoice].contains($0.status) }
        return Dictionary(grouping:spent,by:\.category)
            .map { CategorySpending(category:$0.key,items:$0.value.sorted { $0.amount > $1.amount }) }
            .sorted { $0.total > $1.total }
    }

    private var totalCategorySpending:Double { spendingByCategory.reduce(0) { $0 + $1.total } }

    var body: some View {
        if let month = store.selectedMonth {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(month.title).font(.largeTitle.bold())
                            Text("Saldo inicial \(AppFormat.money(month.initialBalance, hidden: hideAmounts))").foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Editar saldos") { editingBalance=true }
                    }
                    HStack(alignment: .top, spacing: 12) {
                        MetricCard("Saldo atual", month.currentBalance, "wallet.bifold", color: month.currentBalance >= 0 ? .green : .red, size: .featured)
                        MetricCard("Pendentes", store.totals.pending, "clock", color: .orange, size: .featured)
                        MetricCard("Na fatura", store.totals.invoice, "creditcard", color: .orange, size: .featured)
                        MetricCard("Disponível", store.totals.variableBudget, "leaf", color: store.totals.variableBudget >= 0 ? .green : .red, size: .featured, caption: "Salário previsto − recorrentes previstos − meta de investimento. Não é o saldo da conta.")
                    }
                    LazyVGrid(columns: detailColumns, spacing: 12) {
                        MetricCard("Salário previsto", store.totals.fixedExpected, "calendar")
                        MetricCard("Salário recebido", store.totals.fixedReceived, "checkmark.circle")
                        MetricCard("Recorrentes previstos", store.totals.recurringExpected, "repeat")
                        MetricCard("Recorrentes pagos", store.totals.recurringPaid, "checkmark.seal")
                        MetricCard("Investimentos planejados", store.totals.investmentsPlanned, "target")
                        MetricCard("Investimentos realizados", store.totals.investmentsActual, "chart.line.uptrend.xyaxis")
                        MetricCard("Saídas pontuais", store.totals.variable, "cart")
                    }
                    GroupBox("Gastos por categoria") {
                        if spendingByCategory.isEmpty {
                            ContentUnavailableView("Nenhum gasto realizado", systemImage:"chart.pie", description:Text("Gastos pagos ou na fatura aparecerão aqui."))
                                .frame(height:220)
                        } else {
                            VStack(alignment:.leading,spacing:8) {
                                Text("Pagos, pagos antecipadamente e na fatura • Total \(AppFormat.money(totalCategorySpending, hidden: hideAmounts))")
                                    .font(.caption).foregroundStyle(.secondary)
                                HStack(spacing:20) {
                                    Chart(spendingByCategory) { item in
                                        SectorMark(
                                            angle:.value("Valor",item.total),
                                            innerRadius:.ratio(0.48),
                                            outerRadius:.ratio(hoveredCategory == item.category ? 1 : 0.94),
                                            angularInset:1.5
                                        )
                                        .cornerRadius(3)
                                        .foregroundStyle(by:.value("Categoria",item.category))
                                        .opacity(hoveredCategory == nil || hoveredCategory == item.category ? 1 : 0.48)
                                        .annotation(position:.overlay) {
                                            if item.total / totalCategorySpending >= 0.08 {
                                                Text("\(Int((item.total / totalCategorySpending * 100).rounded()))%")
                                                    .font(.caption.bold()).foregroundStyle(.white)
                                            }
                                        }
                                    }
                                    .chartLegend(position:.trailing,alignment:.center,spacing:8)
                                    .chartOverlay { proxy in
                                        GeometryReader { geometry in
                                            Rectangle().fill(.clear).contentShape(Rectangle())
                                                .onContinuousHover { phase in
                                                    switch phase {
                                                    case .active(let location):
                                                        guard let anchor=proxy.plotFrame else { hoveredCategory=nil;return }
                                                        let frame=geometry[anchor]
                                                        let point=CGPoint(x:location.x-frame.minX,y:location.y-frame.minY)
                                                        let center=CGPoint(x:frame.width/2,y:frame.height/2)
                                                        let distance=hypot(point.x-center.x,point.y-center.y)
                                                        let radius=min(frame.width,frame.height)/2
                                                        guard distance >= radius*0.42 && distance <= radius*1.05,
                                                              let value:Double=proxy.value(atAngle:proxy.angle(at:point)) else { hoveredCategory=nil;return }
                                                        hoveredCategory=category(at:value)
                                                    case .ended: hoveredCategory=nil
                                                    }
                                                }
                                        }
                                    }
                                    .frame(minWidth:420,minHeight:300)
                                    GroupBox {
                                        if let selected=spendingByCategory.first(where:{$0.category == hoveredCategory}) {
                                            VStack(alignment:.leading,spacing:7) {
                                                HStack { Text(selected.category).font(.headline);Spacer();Text(AppFormat.money(selected.total, hidden: hideAmounts)).font(.headline).monospacedDigit() }
                                                Text("\(Int((selected.total/totalCategorySpending*100).rounded()))% do total").font(.caption).foregroundStyle(.secondary)
                                                Divider()
                                                ScrollView {
                                                    VStack(spacing:6) {
                                                        ForEach(selected.items) { expense in
                                                            HStack { VStack(alignment:.leading){Text(expense.description);Text(expense.status.rawValue).font(.caption).foregroundStyle(.secondary)};Spacer();Text(AppFormat.money(expense.amount, hidden: hideAmounts)).monospacedDigit() }
                                                        }
                                                    }
                                                }
                                            }
                                        } else {
                                            ContentUnavailableView("Passe o mouse sobre uma fatia",systemImage:"cursorarrow.motionlines",description:Text("Veja os lançamentos que compõem cada categoria."))
                                        }
                                    }.frame(width:310,height:260)
                                }
                            }.padding(8)
                        }
                    }
                    GroupBox("Orçamento para gastos variáveis") {
                        HStack {
                            CalculationItem("Renda prevista", store.totals.fixedExpected)
                            Image(systemName: "minus")
                            CalculationItem("Gastos previstos", store.totals.recurringExpected)
                            Image(systemName: "minus")
                            CalculationItem("Meta de investimento", store.totals.investmentsPlanned)
                            Image(systemName: "equal")
                            CalculationItem("Disponível", store.totals.variableBudget, emphasized: true)
                        }.padding(8)
                    }
                }.padding(24)
            }.sheet(isPresented: $editingBalance) { MonthEditor(month: month) }
        } else { EmptyMonthView() }
    }

    private func category(at angleValue:Double)->String? {
        var accumulated=0.0
        for item in spendingByCategory {
            accumulated += item.total
            if angleValue <= accumulated { return item.category }
        }
        return spendingByCategory.last?.category
    }
}

struct MetricCard: View {
    enum Size { case compact, featured }
    @Environment(\.hideAmounts) private var hideAmounts
    let title: String; let value: Double; let icon: String; let color: Color; let size: Size; let caption: String?
    init(_ title: String, _ value: Double, _ icon: String, color: Color = .accentColor, size: Size = .compact, caption: String? = nil) {
        self.title=title; self.value=value; self.icon=icon; self.color=color; self.size=size; self.caption=caption
    }
    var body: some View {
        GroupBox {
            HStack(alignment: size == .featured ? .top : .center) {
                Image(systemName:icon).foregroundStyle(color).font(size == .featured ? .largeTitle : .title2)
                VStack(alignment:.leading, spacing: size == .featured ? 6 : 2) {
                    Text(title).font(size == .featured ? .subheadline : .caption).foregroundStyle(.secondary)
                    Text(AppFormat.money(value, hidden: hideAmounts)).font(size == .featured ? .title.bold() : .title3.bold()).monospacedDigit()
                    if let caption {
                        Text(caption).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer()
            }
            .padding(.vertical, size == .featured ? 10 : 5)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
    }
}

struct CalculationItem: View {
    @Environment(\.hideAmounts) private var hideAmounts
    let title:String; let value:Double; var emphasized=false
    init(_ title:String,_ value:Double,emphasized:Bool=false){self.title=title;self.value=value;self.emphasized=emphasized}
    var body: some View { VStack(alignment:.leading){Text(title).font(.caption).foregroundStyle(.secondary);Text(AppFormat.money(value, hidden: hideAmounts)).font(emphasized ? .headline.bold() : .headline)}.frame(maxWidth:.infinity,alignment:.leading) }
}

struct MonthEditor: View {
    @EnvironmentObject private var store:AppStore; @Environment(\.dismiss) private var dismiss
    @State var month:BudgetMonth
    var body:some View { Form { TextField("Saldo inicial",value:$month.initialBalance,format:.number);TextField("Saldo atual",value:$month.currentBalance,format:.number);Text("O saldo atual é atualizado ao receber entradas, pagar gastos ou realizar investimentos. Edite-o apenas para conciliar com a conta.").font(.caption).foregroundStyle(.secondary); Toggle("Informar data",isOn:Binding(get:{month.balanceDate != nil},set:{month.balanceDate = $0 ? .now:nil})); if month.balanceDate != nil { DatePicker("Data do saldo",selection:Binding(get:{month.balanceDate ?? .now},set:{month.balanceDate=$0}),displayedComponents:.date) }; HStack{Spacer();Button("Cancelar"){dismiss()};Button("Salvar"){store.saveMonth(month);dismiss()}.keyboardShortcut(.defaultAction)} }.padding().frame(width:420) }
}
