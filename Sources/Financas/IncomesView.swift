import SwiftUI

struct IncomesView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.hideAmounts) private var hideAmounts
    @State private var editing: Income?
    var extrasOnly = false

    var body: some View {
        if let month = store.selectedMonth {
            VStack(spacing: 0) {
                ScreenHeader(extrasOnly ? "Entradas extras" : "Entradas", subtitle: extrasOnly ? "Bônus, freelas, reembolsos e outras rendas" : "Fixas e extras recebidas no mês") {
                    Button { editing = Income(id: 0, monthID: month.id, date: .now, description: "", category: "Outros", amount: 0, expectedDay: nil, status: .pending, isFixed: false) } label: { Label("Nova entrada", systemImage: "plus") }
                }
                List {
                    if !extrasOnly { Section("Entradas fixas") { ForEach(store.incomes.filter(\.isFixed)) { row($0) } } }
                    Section("Entradas extras") { ForEach(store.incomes.filter { !$0.isFixed }) { row($0) } }
                }
            }
            .sheet(item: $editing) { IncomeEditor(item: $0) }
        } else { EmptyMonthView() }
    }

    private func row(_ item: Income) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(item.description).fontWeight(.medium)
                Text(item.isFixed ? "Previsto dia \(item.expectedDay.map(String.init) ?? "—")" : "\(item.category) • \(item.date.map(AppFormat.date.string) ?? "Sem data")").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(AppFormat.money(item.amount, hidden: hideAmounts)).monospacedDigit()
            StatusBadge(item.status.rawValue, positive: item.status == .received)
            Menu { if item.status != .received { Button("Marcar como recebido") { var copy=item;copy.status = .received;if copy.date == nil { copy.date = .now };store.save(copy) } }; Button("Editar") { editing=item }; Button("Excluir", role:.destructive) { store.delete(item) } } label: { Image(systemName:"ellipsis.circle") }
        }.contentShape(Rectangle()).onTapGesture { editing=item }
    }
}

struct IncomeEditor: View {
    @EnvironmentObject private var store: AppStore; @Environment(\.dismiss) private var dismiss
    @State var item: Income
    private let categories = ["PLR","Bônus","Freela","Presente","Reembolso","Venda","Outros"]

    var body: some View {
        Form {
            Toggle("Entrada fixa", isOn: $item.isFixed)
            TextField("Descrição", text: $item.description)
            TextField("Valor", value: $item.amount, format: .number)
            if item.isFixed { TextField("Dia esperado", value: $item.expectedDay, format: .number) }
            else {
                DatePicker("Data", selection: Binding(get:{item.date ?? .now},set:{item.date=$0}), displayedComponents:.date)
                Picker("Categoria", selection:$item.category) { ForEach(categories,id:\.self){Text($0)} }
            }
            Picker("Status", selection:$item.status) { ForEach(IncomeStatus.allCases){Text($0.rawValue).tag($0)} }
            EditorButtons(saveEnabled: !item.description.isEmpty && item.amount >= 0) { store.save(item); dismiss() }
        }.padding().frame(width:420).navigationTitle(item.id == 0 ? "Nova entrada" : "Editar entrada")
    }
}

struct ScreenHeader<Actions: View>: View {
    let title:String; let subtitle:String; @ViewBuilder let actions:Actions
    init(_ title:String,subtitle:String,@ViewBuilder actions:()->Actions){self.title=title;self.subtitle=subtitle;self.actions=actions()}
    var body:some View { HStack { VStack(alignment:.leading){Text(title).font(.largeTitle.bold());Text(subtitle).foregroundStyle(.secondary)};Spacer();actions }.padding(24) }
}

struct EditorButtons: View {
    @Environment(\.dismiss) private var dismiss
    let saveEnabled:Bool; let save:()->Void
    var body:some View { HStack { Spacer();Button("Cancelar"){dismiss()};Button("Salvar",action:save).keyboardShortcut(.defaultAction).disabled(!saveEnabled) }.padding(.top,8) }
}

struct StatusBadge: View {
    let text:String; let positive:Bool
    init(_ text:String,positive:Bool=false){self.text=text;self.positive=positive}
    var body:some View { Text(text).font(.caption).padding(.horizontal,8).padding(.vertical,4).background((positive ? Color.green : Color.orange).opacity(0.14),in:Capsule()).foregroundStyle(positive ? .green : .orange).frame(width:110) }
}
