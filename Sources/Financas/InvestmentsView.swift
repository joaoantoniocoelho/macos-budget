import SwiftUI

struct InvestmentsView: View {
    @EnvironmentObject private var store:AppStore
    @Environment(\.hideAmounts) private var hideAmounts
    @State private var editing:Investment?
    var body:some View {
        if let month=store.selectedMonth {
            VStack(spacing:0){
                ScreenHeader("Investimentos",subtitle:"Aportes reduzem o disponível, mas não são gastos") { Button{editing=Investment(id:0,monthID:month.id,plannedDate:.now,plannedAmount:0,actualAmount:0,status:.pending)}label:{Label("Novo aporte",systemImage:"plus")} }
                HStack { MetricCard("Meta do mês",store.totals.investmentsPlanned,"target");MetricCard("Realizado",store.totals.investmentsActual,"checkmark.circle",color:.green) }.padding(.horizontal,24).padding(.bottom,12)
                List(store.investments){item in HStack{VStack(alignment:.leading){Text("Aporte planejado").fontWeight(.medium);Text(AppFormat.date.string(from:item.plannedDate)).font(.caption).foregroundStyle(.secondary)};Spacer();VStack(alignment:.trailing){Text(AppFormat.money(item.plannedAmount, hidden: hideAmounts));if item.status == .completed{Text("Realizado: \(AppFormat.money(item.actualAmount, hidden: hideAmounts))").font(.caption)}};StatusBadge(item.status.rawValue,positive:item.status == .completed);Menu{Button("Editar"){editing=item};Button("Marcar realizado"){var copy=item;copy.status = .completed;if copy.actualAmount == 0{copy.actualAmount=copy.plannedAmount};store.save(copy)};Button("Excluir",role:.destructive){store.delete(item)}}label:{Image(systemName:"ellipsis.circle")}}.contentShape(Rectangle()).onTapGesture{editing=item}}
            }.sheet(item:$editing){InvestmentEditor(item:$0)}
        } else {EmptyMonthView()}
    }
}

struct InvestmentEditor:View {
    @EnvironmentObject private var store:AppStore;@Environment(\.dismiss) private var dismiss;@State var item:Investment
    var body:some View{Form{DatePicker("Data planejada",selection:$item.plannedDate,displayedComponents:.date);TextField("Valor planejado",value:$item.plannedAmount,format:.number);Picker("Status",selection:$item.status){ForEach(InvestmentStatus.allCases){Text($0.rawValue).tag($0)}};if item.status == .completed{TextField("Valor realizado",value:$item.actualAmount,format:.number)};EditorButtons(saveEnabled:item.plannedAmount >= 0){if item.status == .completed && item.actualAmount == 0{item.actualAmount=item.plannedAmount};store.save(item);dismiss()}}.padding().frame(width:410)}
}
