import SwiftUI

@main
struct FinancasApp: App {
    @StateObject private var store = AppStore()
    @AppStorage("hideAmounts") private var hideAmounts = false

    var body: some Scene {
        WindowGroup("Finanças") {
            ContentView().environmentObject(store).environment(\.hideAmounts, hideAmounts).frame(minWidth: 960, minHeight: 620)
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Novo mês") { store.createNextMonth() }.keyboardShortcut("n")
            }
            CommandGroup(after: .toolbar) {
                Button(hideAmounts ? "Mostrar valores" : "Ocultar valores") { hideAmounts.toggle() }
                    .keyboardShortcut("h", modifiers: [.command, .shift])
            }
        }
    }
}
