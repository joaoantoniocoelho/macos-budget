import SwiftUI

struct ExpensesView: View {
    enum Mode: Equatable { case fixed, outflows }
    @EnvironmentObject private var store: AppStore
    @Environment(\.hideAmounts) private var hideAmounts
    @State private var editing: Expense?
    @State private var editingRecurring: RecurringExpense?
    @State private var filter: ExpenseFilter = .all
    @State private var confirmInvoice = false
    var mode:Mode = .fixed

    private struct ExpenseGroup: Identifiable {
        let category:String
        let items:[Expense]
        var id:String { category }
        var total:Double { items.reduce(0) { $0 + $1.amount } }
    }

    enum ExpenseFilter: String, CaseIterable, Identifiable { case all="Todos", invoice="Na fatura", pending="Pendentes", paid="Pagos"; var id:String{rawValue} }
    private var modeExpenses:[Expense] { store.expenses.filter { mode == .fixed ? $0.isRecurring : !$0.isRecurring } }
    var filtered: [Expense] {
        switch filter { case .all:return modeExpenses; case .invoice:return modeExpenses.filter{$0.status == .invoice}; case .pending:return modeExpenses.filter{$0.status == .pending}; case .paid:return modeExpenses.filter{[.paid,.prepaid].contains($0.status)} }
    }
    private var groups:[ExpenseGroup] {
        Dictionary(grouping:filtered,by:\.category)
            .map { ExpenseGroup(category:$0.key,items:$0.value.sorted { $0.description.localizedCaseInsensitiveCompare($1.description) == .orderedAscending }) }
            .sorted { $0.category.localizedCaseInsensitiveCompare($1.category) == .orderedAscending }
    }

    var body: some View {
        if let month = store.selectedMonth {
            VStack(spacing:0) {
                ScreenHeader(mode == .fixed ? "Gastos fixos" : "Saídas", subtitle:mode == .fixed ? "Despesas recorrentes agrupadas por categoria" : "Gastos pontuais agrupados por categoria") {
                    Picker("Filtro",selection:$filter){ForEach(ExpenseFilter.allCases){Text($0.rawValue).tag($0)}}.pickerStyle(.segmented).frame(width:430)
                    if mode == .fixed {
                        Button { editingRecurring=RecurringExpense(id:0,description:"",category:"Outros",amount:0,dueDay:nil,paymentMethod:.pix,notes:"",active:true) } label:{Label("Novo gasto fixo",systemImage:"plus")}
                    } else {
                        Button { editing = Expense(id:0,monthID:month.id,recurringID:nil,date:.now,description:"",category:"Outros",amount:0,paymentMethod:.pix,status:.pending,competenceYear:nil,competenceMonth:nil,notes:"",isRecurring:false) } label:{Label("Nova saída",systemImage:"plus")}
                    }
                }
                HStack {
                    Label(mode == .fixed ? "Total fixo: \(AppFormat.money(modeExpenses.reduce(0) { $0 + $1.amount }, hidden: hideAmounts))" : "Total de saídas: \(AppFormat.money(modeExpenses.reduce(0) { $0 + $1.amount }, hidden: hideAmounts))",systemImage:"sum")
                    Label("Fatura atual: \(AppFormat.money(store.totals.invoice, hidden: hideAmounts))",systemImage:"creditcard")
                    Label("Pago antecipadamente: \(AppFormat.money(modeExpenses.filter { $0.status == .prepaid }.reduce(0) { $0 + $1.amount }, hidden: hideAmounts))",systemImage:"checkmark.circle")
                    Spacer()
                    Button("Marcar fatura como paga") { confirmInvoice=true }.disabled(store.totals.invoice == 0)
                    if mode == .fixed { Button("Sincronizar recorrentes") { store.syncRecurring() }.help("Inclui recorrências ativas que ainda não existem neste mês") }
                }.padding(.horizontal,24).padding(.bottom,12)
                List {
                    ForEach(groups) { group in
                        Section {
                            ForEach(group.items) { expenseRow($0, showCategory:false) }
                        } header: {
                            HStack { Text(group.category);Spacer();Text(AppFormat.money(group.total, hidden: hideAmounts)).monospacedDigit() }
                        }
                    }
                }
            }
            .sheet(item:$editing){ExpenseEditor(item:$0)}
            .sheet(item:$editingRecurring){RecurringEditor(item:$0,addToCurrentMonth:true)}
            .confirmationDialog("Quitar a fatura?",isPresented:$confirmInvoice,titleVisibility:.visible){Button("Marcar lançamentos como pagos"){store.payInvoice()};Button("Cancelar",role:.cancel){}} message:{Text("Todos os gastos em “Na fatura” passarão para “Pago”. Nenhuma nova despesa será criada.")}
        } else { EmptyMonthView() }
    }
    private func expenseRow(_ item:Expense,showCategory:Bool)->some View {
        HStack {
            Image(systemName:item.isRecurring ? "repeat" : "cart").foregroundStyle(.secondary).frame(width:22)
            VStack(alignment:.leading){Text(item.description).fontWeight(.medium);Text("\(showCategory ? item.category + " • " : "")\(item.paymentMethod.rawValue)\(competence(item))\(item.includedInInitialBalance ? " • já incluído no saldo inicial" : "")").font(.caption).foregroundStyle(.secondary)}
            Spacer(); Text(AppFormat.money(item.amount, hidden: hideAmounts)).monospacedDigit(); StatusBadge(item.status.rawValue,positive:[.paid,.prepaid].contains(item.status))
            Menu {
                ForEach(ExpenseStatus.allCases) { status in Button(status.rawValue) { var copy=item;copy.status=status;store.save(copy) } }
                if [.paid,.prepaid].contains(item.status) && !item.includedInInitialBalance { Button("Já estava no saldo inicial") { var copy=item;copy.includedInInitialBalance=true;store.save(copy) } }
                Divider();Button("Editar"){editing=item};Button("Excluir",role:.destructive){store.delete(item)}
            } label:{Image(systemName:"ellipsis.circle")}
        }.contentShape(Rectangle()).onTapGesture{editing=item}
    }
    private func competence(_ item:Expense)->String { guard let y=item.competenceYear,let m=item.competenceMonth else{return ""};return " • competência \(String(format:"%02d",m))/\(y)" }
}

struct ExpenseEditor: View {
    @EnvironmentObject private var store:AppStore; @Environment(\.dismiss) private var dismiss
    @State var item:Expense; @State private var hasCompetence:Bool
    private let categories=["Moradia","Carro","Saúde","Educação","Assinaturas","SaaS / Projetos","Alimentação fora","Lazer","Compras","Transporte/Uber","Pets","Presentes","Viagens","Outros"]
    init(item:Expense){_item=State(initialValue:item);_hasCompetence=State(initialValue:item.competenceMonth != nil)}
    var body:some View {
        Form {
            TextField("Descrição",text:$item.description)
            TextField("Valor",value:$item.amount,format:.number)
            Picker("Categoria",selection:$item.category){ForEach(categories,id:\.self){Text($0)}}
            Picker("Pagamento",selection:$item.paymentMethod){ForEach(PaymentMethod.allCases){Text($0.rawValue).tag($0)}}
            if item.id == 0 && !item.isRecurring {
                LabeledContent("Status automático") { Text(item.paymentMethod == .card ? ExpenseStatus.invoice.rawValue : ExpenseStatus.paid.rawValue).foregroundStyle(.secondary) }
            } else {
                Picker("Status",selection:$item.status){ForEach(ExpenseStatus.allCases){Text($0.rawValue).tag($0)}}
            }
            Toggle("Informar data",isOn:Binding(get:{item.date != nil},set:{item.date=$0 ? .now:nil}))
            if item.date != nil { DatePicker("Data",selection:Binding(get:{item.date ?? .now},set:{item.date=$0}),displayedComponents:.date) }
            Toggle("Informar competência",isOn:$hasCompetence)
            if hasCompetence { HStack { TextField("Mês",value:$item.competenceMonth,format:.number);TextField("Ano",value:$item.competenceYear,format:.number) } }
            Toggle("Já estava incluído no saldo inicial",isOn:$item.includedInInitialBalance)
            Text("Ative para pagamentos anteriores ao saldo informado. O lançamento mantém o status, mas não será descontado novamente.").font(.caption).foregroundStyle(.secondary)
            TextField("Observação",text:$item.notes,axis:.vertical).lineLimit(2...4)
            EditorButtons(saveEnabled:!item.description.isEmpty && item.amount >= 0){if !hasCompetence{item.competenceMonth=nil;item.competenceYear=nil};store.save(item);dismiss()}
        }.padding().frame(width:450).navigationTitle(item.id == 0 ? "Nova saída" : "Editar lançamento")
    }
}
