import SwiftUI
import GRDB

/// Form for creating/editing transactions with rewards preview
struct TransactionFormView: View {
    let transaction: Transaction?
    let onSave: (Transaction) -> Void

    @State private var selectedCard: Card?
    @State private var date = Date()
    @State private var vendor = ""
    @State private var selectedCategory: Category?
    @State private var amount = ""
    @State private var transactionType: TransactionType = .purchase
    @State private var rewardEligible = true
    @State private var onlineTransaction = false
    @State private var notes = ""

    @State private var cards: [Card] = []
    @State private var categories: [Category] = []
    @State private var vendors: [Vendor] = []
    @State private var showingRewardPreview = false
    @State private var rewardPreview: TransactionRewardPreview?
    @State private var showingVendorSuggestions = false

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Transaction Details") {
                    Picker("Card", selection: $selectedCard) {
                        Text("Select Card").tag(nil as Card?)
                        ForEach(cards) { card in
                            Text(card.name).tag(card as Card?)
                        }
                    }

                    DatePicker("Date", selection: $date, displayedComponents: .date)

                    VStack(alignment: .leading, spacing: 0) {
                        TextField("Vendor", text: $vendor)
                            .frame(minWidth: 300)
                            .help("Name of the merchant")
                            .onChange(of: vendor) { _, newValue in
                                showingVendorSuggestions = !newValue.isEmpty
                                checkVendorMatch(newValue)
                            }

                        if showingVendorSuggestions && !filteredVendors.isEmpty {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(filteredVendors.prefix(5)) { vendorMatch in
                                    Button(action: {
                                        selectVendor(vendorMatch)
                                    }) {
                                        HStack {
                                            Text(vendorMatch.displayName)
                                            Spacer()
                                            if let categoryId = vendorMatch.defaultCategoryId,
                                               let category = categories.first(where: { $0.id == categoryId }) {
                                                HStack(spacing: 4) {
                                                    if let icon = category.icon {
                                                        Image(systemName: icon)
                                                    }
                                                    Text(category.name)
                                                }
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            }
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 6)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .background(Color(nsColor: .controlBackgroundColor))
                                }
                            }
                            .background(Color(nsColor: .textBackgroundColor))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                            )
                            .padding(.top, 2)
                        }
                    }

                    Picker("Category", selection: $selectedCategory) {
                        Text("None").tag(nil as Category?)
                        ForEach(categories) { category in
                            HStack {
                                if let icon = category.icon {
                                    Image(systemName: icon)
                                }
                                Text(category.name)
                            }
                            .tag(category as Category?)
                        }
                    }

                    TextField("Amount", text: $amount)
                        .frame(minWidth: 300)
                        .help("Transaction amount (e.g., 123.45)")
                }

                Section("Type & Eligibility") {
                    Picker("Transaction Type", selection: $transactionType) {
                        Text("Purchase").tag(TransactionType.purchase)
                        Text("Refund").tag(TransactionType.refund)
                        Text("Payment").tag(TransactionType.payment)
                        Text("Statement Credit").tag(TransactionType.statementCredit)
                        Text("Fee").tag(TransactionType.fee)
                    }

                    Toggle("Eligible for Rewards", isOn: $rewardEligible)
                    Toggle("Online Transaction", isOn: $onlineTransaction)
                }

                Section {
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                        .frame(minWidth: 300)
                } header: {
                    Text("Notes")
                }
            }
            .formStyle(.grouped)
            .padding(20)
            .navigationTitle(transaction == nil ? "New Transaction" : "Edit Transaction")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveTransaction()
                    }
                    .disabled(!isValid)
                }
            }
            .sheet(isPresented: $showingRewardPreview) {
                if let preview = rewardPreview {
                    RewardPreviewView(preview: preview, onConfirm: {
                        finalizeTransaction(preview)
                    }, onCancel: {
                        showingRewardPreview = false
                    })
                }
            }
        }
        .frame(width: 550, height: 550)
        .onAppear {
            // Set non-dependent fields immediately
            if let transaction = transaction {
                date = transaction.date
                vendor = transaction.vendor
                amount = transaction.amount.toFormattedString()
                transactionType = transaction.transactionType
                rewardEligible = transaction.rewardEligible
                onlineTransaction = transaction.onlineTransaction
                notes = transaction.notes ?? ""
            }
            // Load data and set dependent fields (card, category) after loading
            loadData()
        }
    }

    private var isValid: Bool {
        selectedCard != nil && !vendor.isEmpty && !amount.isEmpty
    }

    private var filteredVendors: [Vendor] {
        guard !vendor.isEmpty else { return [] }
        let searchText = vendor.lowercased()
        return vendors.filter {
            $0.displayName.lowercased().contains(searchText) ||
            $0.name.contains(searchText)
        }
    }

    private func loadData() {
        Task {
            do {
                let db = try DatabaseManager.shared.database()
                cards = try await db.read { try Card.fetchAll($0) }
                categories = try await db.read { try Category.order(Category.Columns.name).fetchAll($0) }
                vendors = try await db.read { try Vendor.order(Vendor.Columns.displayName).fetchAll($0) }

                // Set selected card and category if editing
                if let transaction = transaction {
                    selectedCard = cards.first(where: { $0.id == transaction.cardId })
                    if let categoryName = transaction.merchantCategory {
                        selectedCategory = categories.first(where: { $0.name == categoryName })
                    }
                }
            } catch {
                print("Error loading form data: \(error)")
            }
        }
    }

    private func checkVendorMatch(_ text: String) {
        // Check if vendor already exists
        let normalizedText = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let matchingVendor = vendors.first(where: { $0.name == normalizedText }) {
            // Auto-select category if vendor has default
            if let categoryId = matchingVendor.defaultCategoryId {
                selectedCategory = categories.first(where: { $0.id == categoryId })
            }
            // Set online transaction based on vendor's default
            onlineTransaction = matchingVendor.defaultToOnlineTransaction
        }
    }

    private func selectVendor(_ selectedVendor: Vendor) {
        vendor = selectedVendor.displayName
        showingVendorSuggestions = false

        // Set default category if available
        if let categoryId = selectedVendor.defaultCategoryId {
            selectedCategory = categories.first(where: { $0.id == categoryId })
        }
        // Set online transaction based on vendor's default
        onlineTransaction = selectedVendor.defaultToOnlineTransaction
    }

    private func saveTransaction() {
        guard let card = selectedCard,
              let amountValue = Decimal.fromUserInput( amount) else {
            return
        }

        // Create vendor if it doesn't exist
        Task {
            let normalizedVendor = vendor.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if !vendors.contains(where: { $0.name == normalizedVendor }) {
                let newVendor = Vendor(
                    name: normalizedVendor,
                    displayName: vendor.trimmingCharacters(in: .whitespacesAndNewlines),
                    defaultCategoryId: selectedCategory?.id,
                    defaultToOnlineTransaction: onlineTransaction
                )
                do {
                    try DatabaseManager.shared.write { db in
                        try newVendor.insert(db)
                    }
                    vendors.append(newVendor)
                } catch {
                    print("Error creating vendor: \(error)")
                }
            }
        }

        let transaction = Transaction(
            id: self.transaction?.id ?? UUID(),
            cardId: card.id,
            date: date,
            vendor: vendor,
            merchantCategory: selectedCategory?.name,
            amount: amountValue,
            transactionType: transactionType,
            rewardEligible: rewardEligible,
            notes: notes.isEmpty ? nil : notes,
            ynabTransactionId: self.transaction?.ynabTransactionId,
            onlineTransaction: onlineTransaction
        )

        // If reward eligible, show preview
        if transaction.isEligibleForRewards {
            calculateRewards(for: transaction)
        } else {
            onSave(transaction)
            dismiss()
        }
    }

    private func calculateRewards(for transaction: Transaction) {
        Task {
            do {
                let db = try DatabaseManager.shared.database()
                let engine = RewardCalculationEngine(database: db)
                rewardPreview = try engine.calculateTransactionRewards(transaction)
                showingRewardPreview = true
            } catch {
                print("Error calculating rewards: \(error)")
                // Save without rewards on error
                onSave(transaction)
                dismiss()
            }
        }
    }

    private func finalizeTransaction(_ preview: TransactionRewardPreview) {
        Task {
            do {
                let db = try DatabaseManager.shared.database()
                let engine = RewardCalculationEngine(database: db)
                try engine.saveTransactionWithRewards(preview.transaction, preview: preview)
                onSave(preview.transaction)  // Notify parent to refresh
                showingRewardPreview = false
                dismiss()
            } catch {
                print("Error saving transaction: \(error)")
            }
        }
    }
}
