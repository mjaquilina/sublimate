import SwiftUI
import Combine
import GRDB

/// View for managing points balances and redemptions
struct PointsView: View {
    @StateObject private var viewModel = PointsViewModel()
    @State private var selectedTab = 0
    @State private var showingAddRedemption = false
    @State private var adjustingBalance: BalanceDetail?

    var body: some View {
        VStack(spacing: 0) {
            Picker("View", selection: $selectedTab) {
                Text("Balances").tag(0)
                Text("Redemptions").tag(1)
                Text("History").tag(2)
            }
            .pickerStyle(.segmented)
            .padding()

            switch selectedTab {
            case 0:
                BalancesTab(viewModel: viewModel, adjustingBalance: $adjustingBalance)
            case 1:
                RedemptionsTab(viewModel: viewModel)
            case 2:
                HistoryTab(viewModel: viewModel)
            default:
                EmptyView()
            }
        }
        .navigationTitle("Points")
        .toolbar {
            if selectedTab == 1 {
                Button(action: { showingAddRedemption = true }) {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddRedemption) {
            PointRedemptionFormView(onSave: { redemption in
                viewModel.addRedemption(redemption)
                showingAddRedemption = false
            })
        }
        .sheet(item: $adjustingBalance) { detail in
            PointBalanceAdjustmentView(balanceDetail: detail, onSave: { newBalance in
                viewModel.adjustBalance(pointTypeId: detail.pointTypeId, newBalance: newBalance)
                adjustingBalance = nil
            })
        }
        .onAppear {
            viewModel.loadData()
        }
    }
}

// MARK: - Balances Tab

struct BalancesTab: View {
    @ObservedObject var viewModel: PointsViewModel
    @Binding var adjustingBalance: BalanceDetail?

    var body: some View {
        if viewModel.balanceDetails.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "creditcard")
                    .font(.largeTitle)
                    .foregroundColor(.secondary)
                Text("No point balances")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Text("Add a card with point types to track balances")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(viewModel.balanceDetails, id: \.id) { detail in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(detail.cardName)
                            .font(.headline)
                        Text(detail.pointTypeName)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("Cash Value: \(detail.cashValue.toCurrency())")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text(detail.balance.toFormattedString(decimals: 0))
                        .font(.title3)
                        .fontWeight(.bold)
                }
                .padding(.vertical, 4)
                .contextMenu {
                    Button("Adjust Balance") {
                        adjustingBalance = detail
                    }
                }
            }
        }
    }
}

// MARK: - Redemptions Tab

struct RedemptionsTab: View {
    @ObservedObject var viewModel: PointsViewModel
    @State private var redemptionToDelete: PointRedemption?

    var body: some View {
        if viewModel.redemptions.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.largeTitle)
                    .foregroundColor(.secondary)
                Text("No redemptions")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Text("Tap + to add a point redemption")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(viewModel.redemptions) { redemption in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(redemption.description)
                            .font(.headline)
                        HStack(spacing: 8) {
                            Text(redemption.date.toShortString())
                            Text("\u{2022}")
                            Text(viewModel.getPointTypeName(for: redemption.pointTypeId))
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                        HStack(spacing: 8) {
                            Text(redemption.redemptionType.rawValue
                                .replacingOccurrences(of: "_", with: " ").capitalized)
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(4)
                            if let cashValue = redemption.cashValue {
                                Text(cashValue.toCurrency())
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    Spacer()
                    Text("\(redemption.pointsRedeemed.toFormattedString(decimals: 0)) pts")
                        .fontWeight(.medium)
                }
                .padding(.vertical, 4)
                .contextMenu {
                    Button("Delete", role: .destructive) {
                        redemptionToDelete = redemption
                    }
                }
            }
            .alert("Delete Redemption?", isPresented: Binding(
                get: { redemptionToDelete != nil },
                set: { if !$0 { redemptionToDelete = nil } }
            )) {
                Button("Cancel", role: .cancel) { redemptionToDelete = nil }
                Button("Delete", role: .destructive) {
                    if let r = redemptionToDelete { viewModel.deleteRedemption(r) }
                }
            } message: {
                Text("This will delete this redemption and restore the points to the balance. This action cannot be undone.")
            }
        }
    }
}

// MARK: - History Tab

struct HistoryTab: View {
    @ObservedObject var viewModel: PointsViewModel
    @State private var selectedPointTypeFilter: UUID?

    private var filteredEntries: [HistoryEntry] {
        if let filter = selectedPointTypeFilter {
            return viewModel.historyEntries.filter { $0.pointTypeId == filter }
        }
        return viewModel.historyEntries
    }

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.pointTypeDisplays.count > 1 {
                Picker("Point Type", selection: $selectedPointTypeFilter) {
                    Text("All").tag(nil as UUID?)
                    ForEach(viewModel.pointTypeDisplays) { ptd in
                        Text(ptd.displayName).tag(ptd.id as UUID?)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }

            if filteredEntries.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No point history")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Earn or redeem points to see activity here")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredEntries) { entry in
                    historyRow(entry)
                }
            }
        }
    }

    private func historyRow(_ entry: HistoryEntry) -> some View {
        HStack {
            Image(systemName: iconForType(entry.entryType))
                .foregroundColor(colorForEntry(entry))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.description)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(entry.date.toShortString())
                    if selectedPointTypeFilter == nil {
                        Text("\u{2022}")
                        Text(viewModel.getPointTypeName(for: entry.pointTypeId))
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(pointsDisplayText(entry.points))
                    .fontWeight(.medium)
                    .foregroundColor(colorForEntry(entry))
                Text("Bal: \(entry.runningBalance.toFormattedString(decimals: 0))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func pointsDisplayText(_ points: Decimal) -> String {
        if points >= 0 {
            return "+\(points.toFormattedString(decimals: 0)) pts"
        } else {
            return "\(points.toFormattedString(decimals: 0)) pts"
        }
    }

    private func iconForType(_ type: HistoryEntry.HistoryEntryType) -> String {
        switch type {
        case .earned: return "arrow.down.circle.fill"
        case .redeemed: return "arrow.up.circle.fill"
        case .adjustment: return "slider.horizontal.3"
        }
    }

    private func colorForEntry(_ entry: HistoryEntry) -> Color {
        switch entry.entryType {
        case .earned: return .green
        case .redeemed: return .red
        case .adjustment: return entry.points >= 0 ? .green : .red
        }
    }
}

// MARK: - Point Redemption Form

struct PointRedemptionFormView: View {
    let onSave: (PointRedemption) -> Void

    @StateObject private var viewModel = PointRedemptionFormViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Point Type") {
                    Picker("Point Type", selection: $viewModel.selectedPointType) {
                        Text("Select...").tag(nil as PointTypeDisplay?)
                        ForEach(viewModel.pointTypeDisplays) { ptd in
                            Text(ptd.displayName).tag(ptd as PointTypeDisplay?)
                        }
                    }
                }

                Section("Redemption Details") {
                    DatePicker("Date", selection: $viewModel.date, displayedComponents: .date)

                    TextField("Points Redeemed", text: $viewModel.pointsRedeemed)
                        .frame(minWidth: 300)
                        .help("Number of points used in this redemption")

                    Picker("Redemption Type", selection: $viewModel.redemptionType) {
                        Text("Gift Card").tag(RedemptionType.giftCard)
                        Text("Travel").tag(RedemptionType.travel)
                        Text("Statement Credit").tag(RedemptionType.statementCredit)
                        Text("Merchandise").tag(RedemptionType.merchandise)
                        Text("Transfer").tag(RedemptionType.transfer)
                        Text("Other").tag(RedemptionType.other)
                    }

                    TextField("Cash Value (optional)", text: $viewModel.cashValue)
                        .frame(minWidth: 300)
                        .help("Dollar value received for this redemption")
                }

                Section("Description") {
                    TextField("Description", text: $viewModel.description)
                        .frame(minWidth: 300)
                        .help("Brief description of this redemption")
                }
            }
            .formStyle(.grouped)
            .padding(20)
            .navigationTitle("New Redemption")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let redemption = viewModel.createRedemption() {
                            onSave(redemption)
                        }
                    }
                    .disabled(!viewModel.isValid)
                }
            }
        }
        .frame(width: 500, height: 450)
    }
}

// MARK: - Point Redemption Form ViewModel

@MainActor
class PointRedemptionFormViewModel: ObservableObject {
    @Published var pointTypeDisplays: [PointTypeDisplay] = []
    @Published var selectedPointType: PointTypeDisplay?
    @Published var date = Date()
    @Published var pointsRedeemed = ""
    @Published var redemptionType: RedemptionType = .statementCredit
    @Published var cashValue = ""
    @Published var description = ""

    init() {
        Task { await loadData() }
    }

    var isValid: Bool {
        selectedPointType != nil
            && !pointsRedeemed.isEmpty
            && Decimal.fromUserInput(pointsRedeemed) != nil
            && !description.isEmpty
    }

    func loadData() async {
        do {
            let db = try DatabaseManager.shared.database()
            let pointTypes = try await db.read { try PointType.fetchAll($0) }
            let cards = try await db.read { try Card.fetchAll($0) }

            pointTypeDisplays = pointTypes.compactMap { pt in
                guard let card = cards.first(where: { $0.id == pt.cardId }) else { return nil }
                return PointTypeDisplay(id: pt.id, name: pt.name, cardName: card.name)
            }
        } catch {
            print("Error loading form data: \(error)")
        }
    }

    func createRedemption() -> PointRedemption? {
        guard let ptDisplay = selectedPointType,
              let pts = Decimal.fromUserInput(pointsRedeemed) else { return nil }

        return PointRedemption(
            pointTypeId: ptDisplay.id,
            date: date,
            pointsRedeemed: pts,
            redemptionType: redemptionType,
            cashValue: cashValue.isEmpty ? nil : Decimal.fromUserInput(cashValue),
            description: description
        )
    }
}

// MARK: - Balance Adjustment View

struct PointBalanceAdjustmentView: View {
    let balanceDetail: BalanceDetail
    let onSave: (Decimal) -> Void

    @State private var newBalanceText = ""
    @Environment(\.dismiss) private var dismiss

    private var newBalance: Decimal? {
        Decimal.fromUserInput(newBalanceText)
    }

    private var difference: Decimal? {
        guard let nb = newBalance else { return nil }
        return nb - balanceDetail.balance
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Current Balance") {
                    HStack {
                        Text(balanceDetail.pointTypeName)
                        Spacer()
                        Text(balanceDetail.balance.toFormattedString(decimals: 0))
                            .fontWeight(.bold)
                    }
                    Text(balanceDetail.cardName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section("New Balance") {
                    TextField("Enter correct balance", text: $newBalanceText)
                        .frame(minWidth: 300)
                        .help("Enter the balance shown by your card vendor")
                }

                if let diff = difference {
                    Section("Adjustment") {
                        HStack {
                            Text("Difference")
                            Spacer()
                            Text(diff >= 0
                                ? "+\(diff.toFormattedString(decimals: 0))"
                                : "\(diff.toFormattedString(decimals: 0))")
                                .foregroundColor(diff >= 0 ? .green : .red)
                                .fontWeight(.medium)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .padding(20)
            .navigationTitle("Adjust Balance")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let nb = newBalance {
                            onSave(nb)
                        }
                    }
                    .disabled(newBalance == nil)
                }
            }
        }
        .frame(width: 400, height: 300)
    }
}
