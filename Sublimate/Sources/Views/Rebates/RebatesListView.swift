import SwiftUI
import Combine
import GRDB

/// View displaying list of rebates grouped by status
struct RebatesListView: View {
    @StateObject private var viewModel = RebatesViewModel()
    @State private var showingAddRebate = false
    @State private var editingRebate: Rebate?
    @State private var rebateToDelete: Rebate?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Constants.UI.defaultPadding) {
                if !viewModel.activeRebates.isEmpty {
                    rebateSection(title: "Active", icon: "checkmark.circle.fill", rebates: viewModel.activeRebates)
                }

                if !viewModel.inactiveRebates.isEmpty {
                    rebateSection(title: "Used / Inactive", icon: "clock.arrow.circlepath", rebates: viewModel.inactiveRebates)
                }

                if viewModel.rebates.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "dollarsign.arrow.circlepath")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("No rebates")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("Add a rebate to start tracking vendor credits")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                }
            }
            .padding(Constants.UI.defaultPadding)
        }
        .navigationTitle("Rebates")
        .toolbar {
            Button(action: { showingAddRebate = true }) {
                Image(systemName: "plus")
            }
        }
        .sheet(isPresented: $showingAddRebate) {
            RebateFormView(rebate: nil, onSave: { newRebate in
                viewModel.addRebate(newRebate)
                showingAddRebate = false
            })
        }
        .sheet(item: $editingRebate) { rebate in
            RebateFormView(rebate: rebate, onSave: { updatedRebate in
                viewModel.updateRebate(updatedRebate)
                editingRebate = nil
            })
        }
        .alert("Delete Rebate?", isPresented: Binding(
            get: { rebateToDelete != nil },
            set: { if !$0 { rebateToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { rebateToDelete = nil }
            Button("Delete", role: .destructive) {
                if let rebate = rebateToDelete { viewModel.deleteRebate(rebate) }
            }
        } message: {
            Text("This will delete the \"\(rebateToDelete?.vendor ?? "")\" rebate. This action cannot be undone.")
        }
        .onAppear {
            viewModel.loadRebates()
        }
    }

    private func rebateSection(title: String, icon: String, rebates: [Rebate]) -> some View {
        VStack(alignment: .leading, spacing: Constants.UI.smallPadding) {
            HStack {
                Image(systemName: icon)
                Text(title)
                    .font(.title2)
                    .fontWeight(.semibold)
            }
            .padding(.top, Constants.UI.smallPadding)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280))], spacing: Constants.UI.defaultPadding) {
                ForEach(rebates) { rebate in
                    RebateListCard(rebate: rebate, card: viewModel.cardForRebate(rebate))
                        .contentShape(Rectangle())
                        .onTapGesture { editingRebate = rebate }
                        .contextMenu {
                            Button("Edit") { editingRebate = rebate }
                            Button("Delete", role: .destructive) { rebateToDelete = rebate }
                        }
                }
            }
        }
    }
}

// MARK: - Rebate Card

struct RebateListCard: View {
    let rebate: Rebate
    let card: Card?

    private var isExpired: Bool {
        if let endDate = rebate.endDate {
            return endDate < Date()
        }
        return false
    }

    private var isUsedUp: Bool {
        if let remaining = rebate.usesRemaining {
            return remaining <= 0
        }
        return false
    }

    private var daysRemaining: Int? {
        guard let endDate = rebate.endDate else { return nil }
        return Date().daysBetween(endDate)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Constants.UI.smallPadding) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(rebate.vendor)
                        .font(.headline)
                    if let card = card {
                        Text(card.name)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    if isUsedUp {
                        Text("Used")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.2))
                            .foregroundColor(.secondary)
                            .cornerRadius(4)
                    } else if isExpired {
                        Text("Expired")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.2))
                            .foregroundColor(.secondary)
                            .cornerRadius(4)
                    } else if let days = daysRemaining {
                        Text("\(days)d left")
                            .font(.caption)
                            .foregroundColor(days < 7 ? .orange : .secondary)
                    }
                }
            }

            // Value description
            HStack {
                if rebate.rebateType == .percentage {
                    Text("\(rebate.rebateValue.toPercentage()) back")
                        .font(.subheadline)
                        .foregroundColor(.blue)
                } else {
                    Text("\(rebate.rebateValue.toCurrency()) credit")
                        .font(.subheadline)
                        .foregroundColor(.blue)
                }

                if let max = rebate.maxAmount {
                    Text("(max \(max.toCurrency()))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Footer: uses remaining + dates
            HStack {
                if let remaining = rebate.usesRemaining, let max = rebate.maxUses {
                    Text("\(remaining)/\(max) uses remaining")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else if rebate.maxUses == nil {
                    Text("Unlimited uses")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if let endDate = rebate.endDate {
                    Text("Exp \(endDate.toShortString())")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .cardBackground()
        .opacity(!rebate.isActive || isExpired || isUsedUp ? 0.7 : 1.0)
    }
}

// MARK: - Rebate Form
struct RebateFormView: View {
    let rebate: Rebate?
    let onSave: (Rebate) -> Void

    @StateObject private var viewModel: RebateFormViewModel
    @Environment(\.dismiss) private var dismiss

    init(rebate: Rebate?, onSave: @escaping (Rebate) -> Void) {
        self.rebate = rebate
        self.onSave = onSave
        _viewModel = StateObject(wrappedValue: RebateFormViewModel(rebate: rebate))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Basic Information") {
                    TextField("Vendor Name", text: $viewModel.vendor)
                        .frame(minWidth: 300)
                        .help("The merchant this rebate applies to")

                    Picker("Card", selection: $viewModel.selectedCard) {
                        Text("Select Card").tag(nil as Card?)
                        ForEach(viewModel.cards) { card in
                            Text(card.name).tag(card as Card?)
                        }
                    }
                }

                Section("Rebate Details") {
                    Picker("Rebate Type", selection: $viewModel.rebateType) {
                        Text("Percentage").tag(RebateType.percentage)
                        Text("Fixed Amount").tag(RebateType.fixed)
                    }

                    TextField(viewModel.rebateType == .percentage ? "Percentage" : "Fixed Amount",
                              text: $viewModel.rebateValue)
                        .frame(minWidth: 300)
                        .help(viewModel.rebateType == .percentage ? "e.g., 10 for 10% back" : "e.g., 25 for $25 credit")

                    TextField("Max Amount (optional)", text: $viewModel.maxAmount)
                        .frame(minWidth: 300)
                        .help("Maximum rebate per transaction")
                }

                Section("Usage Limits") {
                    TextField("Max Uses", text: $viewModel.maxUses)
                        .frame(minWidth: 300)
                        .help("Number of times this rebate can be used (default: 1, empty for unlimited)")

                    HStack {
                        DatePicker("Start Date", selection: $viewModel.startDate, displayedComponents: .date)
                            .disabled(viewModel.noStartDate)
                            .opacity(viewModel.noStartDate ? 0.5 : 1.0)
                        Toggle("No start date", isOn: $viewModel.noStartDate)
                    }

                    HStack {
                        DatePicker("Expiration Date", selection: $viewModel.endDate, displayedComponents: .date)
                            .disabled(viewModel.noExpirationDate)
                            .opacity(viewModel.noExpirationDate ? 0.5 : 1.0)
                        Toggle("No expiration", isOn: $viewModel.noExpirationDate)
                    }
                }

                Section {
                    Toggle("Active", isOn: $viewModel.isActive)
                }
            }
            .formStyle(.grouped)
            .padding(20)
            .navigationTitle(rebate == nil ? "New Rebate" : "Edit Rebate")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let newRebate = viewModel.createRebate(from: rebate) {
                            onSave(newRebate)
                        }
                    }
                    .disabled(!viewModel.isValid)
                }
            }
        }
        .frame(width: 500, height: 550)
    }
}

// MARK: - Rebate Form ViewModel
@MainActor
class RebateFormViewModel: ObservableObject {
    @Published var vendor = ""
    @Published var cards: [Card] = []
    @Published var selectedCard: Card?
    @Published var rebateType: RebateType = .percentage
    @Published var rebateValue = ""
    @Published var maxAmount = ""
    @Published var maxUses = "1"  // Default to 1
    @Published var noStartDate = true
    @Published var startDate = Date()
    @Published var noExpirationDate = false
    @Published var endDate = Calendar.current.date(byAdding: .month, value: 6, to: Date()) ?? Date()
    @Published var isActive = true

    private var pendingCardId: UUID?

    init(rebate: Rebate?) {
        // Set rebate data immediately (synchronously)
        if let rebate = rebate {
            self.vendor = rebate.vendor
            self.rebateType = rebate.rebateType
            self.rebateValue = rebate.rebateValue.toFormattedString()
            self.maxAmount = rebate.maxAmount?.toFormattedString() ?? ""
            self.maxUses = rebate.maxUses.map { String($0) } ?? ""
            self.noStartDate = rebate.startDate == nil
            self.startDate = rebate.startDate ?? Date()
            self.noExpirationDate = rebate.endDate == nil
            self.endDate = rebate.endDate ?? Calendar.current.date(byAdding: .month, value: 6, to: Date()) ?? Date()
            self.isActive = rebate.isActive

            // Store card ID to match up later when cards load
            self.pendingCardId = rebate.cardId
        }

        // Load async data (cards)
        Task {
            await loadData(rebate: rebate)
        }
    }

    var isValid: Bool {
        !vendor.isEmpty && selectedCard != nil && !rebateValue.isEmpty && Decimal.fromUserInput(rebateValue) != nil
    }

    func loadData(rebate: Rebate?) async {
        do {
            let db = try DatabaseManager.shared.database()
            cards = try await db.read { try Card.fetchAll($0) }

            // Set selected card using pending ID
            if let pendingCardId = pendingCardId {
                selectedCard = cards.first(where: { $0.id == pendingCardId })
            } else if let firstCard = cards.first {
                selectedCard = firstCard
            }
        } catch {
            print("Error loading form data: \(error)")
        }
    }

    func createRebate(from existing: Rebate?) -> Rebate? {
        guard let selectedCard = selectedCard,
              let value = Decimal.fromUserInput(rebateValue) else { return nil }

        return Rebate(
            id: existing?.id ?? UUID(),
            cardId: selectedCard.id,
            vendor: vendor,
            rebateType: rebateType,
            rebateValue: value,
            maxAmount: maxAmount.isEmpty ? nil : Decimal.fromUserInput(maxAmount),
            maxUses: maxUses.isEmpty ? nil : Int(maxUses),
            usesRemaining: existing?.usesRemaining ?? (maxUses.isEmpty ? nil : Int(maxUses)),
            startDate: noStartDate ? nil : startDate,
            endDate: noExpirationDate ? nil : endDate,
            isActive: isActive,
            createdAt: existing?.createdAt ?? Date()
        )
    }
}
