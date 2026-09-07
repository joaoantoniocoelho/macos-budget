import SwiftUI

struct InvestmentsView: View {
    @EnvironmentObject private var store:AppStore
    @Environment(\.hideAmounts) private var hideAmounts
    @State private var editing:InvestmentMovement?
    private let columns=[GridItem(.adaptive(minimum:230),spacing:12)]

    var body:some View {
        if let month=store.selectedMonth {
            ScrollView {
                VStack(alignment:.leading,spacing:18) {
                    ScreenHeader("Investimentos",subtitle:"Acompanhe seus fundos, aportes e resgates") {
                        Button {
                            guard let fund=store.investmentFunds.first else { return }
                            editing=InvestmentMovement(id:0,monthID:month.id,fundID:fund.id,date:.now,kind:.contribution,amount:0,notes:"")
                        } label:{ Label("Nova movimentação",systemImage:"plus") }
                    }

                    LazyVGrid(columns:columns,spacing:12) {
                        MetricCard("Valor atual investido",store.totalInvested,"chart.line.uptrend.xyaxis",color:.green,size:.featured)
                        MetricCard("Meta do mês",store.totals.investmentsPlanned,"target",size:.featured)
                        MetricCard("Aportado no mês",store.totals.investmentsActual,"arrow.up.circle",color:.green,size:.featured)
                    }

                    EmergencyReserveCard(fund:store.emergencyReserve,fixedExpenses:store.monthlyFixedExpenseBaseline,months:store.emergencyReserveMonths)

                    GroupBox("Fundos e objetivos") {
                        LazyVGrid(columns:columns,spacing:12) {
                            ForEach(store.investmentFunds) { fund in FundCard(fund:fund) }
                        }.padding(6)
                    }

                    GroupBox("Movimentações de \(month.title)") {
                        if store.investmentMovements.isEmpty {
                            ContentUnavailableView("Nenhuma movimentação neste mês",systemImage:"arrow.left.arrow.right",description:Text("Registre um aporte ou resgate e escolha em qual fundo ele aconteceu."))
                                .frame(height:170)
                        } else {
                            VStack(spacing:0) {
                                ForEach(store.investmentMovements) { movement in
                                    InvestmentMovementRow(movement:movement,fundName:store.investmentFunds.first(where:{$0.id == movement.fundID})?.name ?? "Fundo") {
                                        editing=movement
                                    } delete:{ store.delete(movement) }
                                    if movement.id != store.investmentMovements.last?.id { Divider() }
                                }
                            }.padding(.horizontal,8)
                        }
                    }
                }.padding(24)
            }.sheet(item:$editing) { InvestmentMovementEditor(item:$0) }
        } else { EmptyMonthView() }
    }
}

private struct EmergencyReserveCard:View {
    @Environment(\.hideAmounts) private var hideAmounts
    let fund:InvestmentFund?
    let fixedExpenses:Double
    let months:Double
    var body:some View {
        GroupBox {
            HStack(spacing:18) {
                Image(systemName:"shield.checkered").font(.system(size:34)).foregroundStyle(.green)
                VStack(alignment:.leading,spacing:4) {
                    Text("Reserva de emergência").font(.headline)
                    Text(fund?.name ?? "Nenhum fundo definido").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment:.trailing,spacing:4) {
                    Text(fixedExpenses > 0 ? String(format:"%.1f meses",months) : "—").font(.title.bold()).monospacedDigit()
                    if let fund {
                        Text("\(AppFormat.money(fund.currentBalance,hidden:hideAmounts)) ÷ \(AppFormat.money(fixedExpenses,hidden:hideAmounts)) em gastos fixos mensais")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }.padding(10)
        }
    }
}

private struct FundCard:View {
    @Environment(\.hideAmounts) private var hideAmounts
    let fund:InvestmentFund
    var body:some View {
        VStack(alignment:.leading,spacing:10) {
            HStack(alignment:.top) {
                Image(systemName:fund.isEmergencyReserve ? "shield.fill" : (fund.countsAsInvestment ? "building.columns.fill" : "airplane.departure"))
                    .foregroundStyle(fund.isEmergencyReserve ? .green : .accentColor)
                Text(fund.name).font(.headline).lineLimit(2)
                Spacer()
            }
            Text(AppFormat.money(fund.currentBalance,hidden:hideAmounts)).font(.title2.bold()).monospacedDigit()
            Text(fund.isEmergencyReserve ? "Reserva de emergência" : (fund.countsAsInvestment ? "Fundo de investimento" : "Objetivo financeiro"))
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(14).frame(maxWidth:.infinity,minHeight:120,alignment:.leading)
        .background(.quaternary.opacity(0.45),in:RoundedRectangle(cornerRadius:12))
    }
}

private struct InvestmentMovementRow:View {
    @Environment(\.hideAmounts) private var hideAmounts
    let movement:InvestmentMovement
    let fundName:String
    let edit:()->Void
    let delete:()->Void
    var body:some View {
        HStack(spacing:12) {
            Image(systemName:movement.kind == .contribution ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                .font(.title2).foregroundStyle(movement.kind == .contribution ? .green : .orange)
            VStack(alignment:.leading,spacing:3) {
                Text(movement.kind.rawValue).fontWeight(.medium)
                Text("\(fundName) • \(AppFormat.date.string(from:movement.date))").font(.caption).foregroundStyle(.secondary)
                if !movement.notes.isEmpty { Text(movement.notes).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            Text("\(movement.kind == .contribution ? "+" : "−") \(AppFormat.money(movement.amount,hidden:hideAmounts))")
                .font(.headline).monospacedDigit()
            Menu {
                Button("Editar",action:edit)
                Button("Excluir",role:.destructive,action:delete)
            } label:{ Image(systemName:"ellipsis.circle") }
        }
        .padding(.vertical,12).contentShape(Rectangle()).onTapGesture(perform:edit)
    }
}

struct InvestmentMovementEditor:View {
    @EnvironmentObject private var store:AppStore
    @Environment(\.dismiss) private var dismiss
    @State var item:InvestmentMovement
    var body:some View {
        Form {
            Picker("Tipo",selection:$item.kind) {
                ForEach(InvestmentMovementKind.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)
            Picker("Fundo",selection:$item.fundID) {
                ForEach(store.investmentFunds) { Text($0.name).tag($0.id) }
            }
            DatePicker("Data",selection:$item.date,displayedComponents:.date)
            TextField("Valor",value:$item.amount,format:.number)
            TextField("Observação (opcional)",text:$item.notes)
            Text(item.kind == .contribution ? "O aporte será descontado do saldo atual da conta e somado ao fundo." : "O resgate será retirado do fundo e somado ao saldo atual da conta.")
                .font(.caption).foregroundStyle(.secondary)
            EditorButtons(saveEnabled:item.amount > 0 && store.investmentFunds.contains(where:{$0.id == item.fundID})) {
                store.save(item);dismiss()
            }
        }.padding().frame(width:460)
    }
}
