# Finanças

MVP local para controle financeiro mensal no macOS. Não tem login, servidor, cloud ou sincronização.

## Stack e estrutura

- SwiftUI nativo (macOS 14+)
- SQLite 3 do sistema, acessado diretamente pela API C
- Swift Package Manager, sem pacotes externos
- `Models.swift`: tipos e regras de apresentação
- `Database.swift`: schema, consultas, categorias iniciais e backup
- `AppStore.swift`: estado da interface e cálculos do mês
- demais arquivos em `Sources/Financas`: telas SwiftUI

O modelo mantém meses, entradas, modelos de gastos recorrentes, lançamentos mensais e investimentos. Na interface, **Gastos** reúne somente despesas fixas e **Saídas** reúne compras e pagamentos pontuais. Gastos recorrentes ativos são instanciados ao criar um mês. Pagar a fatura apenas muda lançamentos de `Na fatura` para `Pago`; não cria uma despesa duplicada.

O saldo atual começa com o saldo informado e é conciliado automaticamente: entradas recebidas aumentam o saldo; gastos pagos e investimentos realizados reduzem o saldo. Pendências e compras ainda na fatura não movimentam a conta até o pagamento.

## Como rodar

Requer Xcode 16 ou superior. Na raiz do projeto:

```bash
swift run Financas
```

Também é possível abrir `Package.swift` no Xcode, selecionar o scheme **Financas** e executar com **⌘R**.

## Banco SQLite

O banco fica em:

```text
~/Library/Application Support/Financas/financas.sqlite
```

Na primeira execução, o app cria o schema e as categorias padrão, sem meses, saldos ou lançamentos. Em **Configurações** é possível mostrar o arquivo no Finder, exportar uma cópia e importar um backup.

O banco local e qualquer backup `.sqlite` ficam fora do repositório.

## Build

Para compilar em modo release:

```bash
swift build -c release
```

O executável fica em `.build/release/Financas`. Para gerar um `.app` local e colocá-lo em `dist/`, use:

```bash
./scripts/build-app.sh
```

O bundle resultante não é assinado para distribuição. Para compartilhar fora da sua máquina, configure assinatura e notarização no Xcode.
