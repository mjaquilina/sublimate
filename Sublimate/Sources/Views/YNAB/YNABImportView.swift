import SwiftUI
import Combine

/// View for importing transactions from YNAB
struct YNABImportView: View {
    @StateObject private var viewModel = YNABImportViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var showingImportConfirm = false

    var body: some View {
        NavigationStack {
            VStack {
                switch viewModel.importState {
                case .selectingAccounts:
                    accountSelectionView
                case .loadingTransactions:
                    loadingView
                case .reviewingTransactions(let transactions):
                    transactionReviewView(transactions: transactions)
                case .calculatingRewards:
                    calculatingView
                case .linkingCredits(let credits):
                    creditLinkingView(credits: credits)
                case .completed(let imported):
                    completedView(imported: imported)
                case .error(let message):
                    errorView(message: message)
                }
            }
            .navigationTitle("Import from YNAB")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 800, height: 600)
        .onAppear {
            viewModel.loadMappings()
        }
    }

    // MARK: - Account Selection
    private var accountSelectionView: some View {
        VStack(spacing: 20) {
            Text("Select YNAB accounts to import from:")
                .font(.headline)

            if viewModel.accountMappings.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    Text("No YNAB accounts mapped")
                        .font(.headline)
                    Text("Go to Settings → YNAB to map your accounts to cards")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
            } else {
                List(viewModel.accountMappings, selection: $viewModel.selectedMappings) { mapping in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(mapping.ynabAccountName)
                                .font(.headline)
                            Text(viewModel.getCardName(for: mapping.cardId))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if let lastImport = mapping.lastImportDate {
                            Text("Last: \(lastImport.toShortString())")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                DatePicker("Import since:", selection: $viewModel.importSinceDate, displayedComponents: .date)
                    .padding(.horizontal)

                Button("Load Transactions") {
                    viewModel.loadTransactions()
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.selectedMappings.isEmpty)
            }
        }
        .padding()
    }

    // MARK: - Loading
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading transactions from YNAB...")
                .font(.headline)
        }
    }

    // MARK: - Transaction Review
    private func transactionReviewView(transactions: [ImportableTransaction]) -> some View {
        let selectedCount = transactions.filter { $0.isSelected }.count

        return VStack(spacing: 0) {
            HStack {
                // Master checkbox for select/deselect all
                Toggle("", isOn: Binding(
                    get: { selectedCount == transactions.count && !transactions.isEmpty },
                    set: { newValue in
                        transactions.forEach { $0.isSelected = newValue }
                    }
                ))
                .labelsHidden()
                .toggleStyle(.checkbox)
                .frame(width: 20)

                Text("\(selectedCount) of \(transactions.count) transactions selected")
                    .font(.headline)

                Spacer()
                Button("Import Selected") {
                    showingImportConfirm = true
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedCount == 0)
                .alert("Import Transactions?", isPresented: $showingImportConfirm) {
                    Button("Cancel", role: .cancel) { }
                    Button("Import") { viewModel.importTransactions() }
                } message: {
                    Text("This will import \(selectedCount) transactions and calculate rewards for each.")
                }
            }
            .padding()
            .background(Color(.controlBackgroundColor))

            // Column headers
            HStack(spacing: 12) {
                Text("")
                    .frame(width: 20)
                Text("Date")
                    .frame(width: 80, alignment: .leading)
                Text("Vendor")
                    .frame(width: 200, alignment: .leading)
                Text("Category")
                    .frame(width: 120, alignment: .leading)
                Text("Amount")
                    .frame(width: 80, alignment: .trailing)
                Text("Type")
                    .frame(width: 100, alignment: .leading)
                Text("Online")
                    .frame(width: 50, alignment: .center)
                Text("Card")
                    .frame(width: 80, alignment: .leading)
            }
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.vertical, 4)
            .padding(.horizontal, 12)

            Divider()

            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(transactions) { tx in
                        TransactionReviewRow(
                            transaction: tx,
                            vendors: viewModel.vendors,
                            categories: viewModel.categories,
                            cardName: viewModel.getCardName(for: tx.cardId)
                        )
                    }
                }
            }
        }
    }

    // MARK: - Calculating Rewards
    private var calculatingView: some View {
        VStack(spacing: 20) {
            if viewModel.importProgress.total > 0 {
                ProgressView(value: Double(viewModel.importProgress.current),
                             total: Double(viewModel.importProgress.total))
                    .frame(width: 300)
                Text("Processing \(viewModel.importProgress.current) of \(viewModel.importProgress.total) transactions...")
                    .font(.headline)
            } else {
                ProgressView()
                    .scaleEffect(1.5)
                Text("Calculating rewards...")
                    .font(.headline)
            }
            Text("This may take a moment")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Credit Linking
    private func creditLinkingView(credits: [Transaction]) -> some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Link Statement Credits")
                        .font(.headline)
                    Text("\(credits.count) statement credits found")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Skip All") {
                    viewModel.skipCreditLinking(importedCount: credits.count)
                }
                Button("Done") {
                    viewModel.skipCreditLinking(importedCount: credits.count)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(Color(.controlBackgroundColor))

            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(credits) { credit in
                        CreditLinkRow(
                            transaction: credit,
                            viewModel: viewModel
                        )
                    }
                }
                .padding()
            }
        }
    }

    // MARK: - Completed
    private func completedView(imported: Int) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.green)

            Text("Successfully imported \(imported) transactions")
                .font(.headline)

            Button("Done") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Error
    private func errorView(message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.red)

            Text("Import Failed")
                .font(.headline)

            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button("Try Again") {
                viewModel.reset()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

// MARK: - Credit Link Row
struct CreditLinkRow: View {
    let transaction: Transaction
    @ObservedObject var viewModel: YNABImportViewModel
    @State private var sources: [CreditLinkSource] = []
    @State private var selectedSourceId: UUID?
    @State private var isLoading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(transaction.vendor)
                        .font(.headline)
                    HStack(spacing: 8) {
                        Text(transaction.date.toShortString())
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(transaction.amount.toCurrency())
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.green)
                    }
                }

                Spacer()

                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Picker("Link to", selection: $selectedSourceId) {
                        Text("None (Other)").tag(nil as UUID?)
                        ForEach(sources) { source in
                            HStack {
                                Text(source.name)
                                if let amount = source.amount {
                                    Text("(\(amount.toCurrency()))")
                                        .foregroundColor(.secondary)
                                }
                            }
                            .tag(source.id as UUID?)
                        }
                    }
                    .frame(width: 300)
                    .onChange(of: selectedSourceId) { _, newValue in
                        let sourceType = sources.first(where: { $0.id == newValue })?.type
                        viewModel.linkCredit(
                            transactionId: transaction.id,
                            sourceId: newValue,
                            sourceType: sourceType
                        )
                    }
                }
            }

            if let selectedId = selectedSourceId,
               let source = sources.first(where: { $0.id == selectedId }) {
                HStack(spacing: 4) {
                    Image(systemName: "link")
                        .font(.caption)
                        .foregroundColor(.blue)
                    Text("Linked to \(source.type.replacingOccurrences(of: "_", with: " "))")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
        .onAppear {
            loadSources()
        }
    }

    private func loadSources() {
        Task {
            do {
                sources = try await viewModel.loadAvailableSources(for: transaction)
                isLoading = false

                // Auto-select if only one exact match by amount
                if let exactMatch = sources.first(where: {
                    $0.amount != nil && abs($0.amount! - abs(transaction.amount)) < 0.01
                }), sources.filter({ $0.amount != nil && abs($0.amount! - abs(transaction.amount)) < 0.01 }).count == 1 {
                    selectedSourceId = exactMatch.id
                }
            } catch {
                print("Error loading sources: \(error)")
                isLoading = false
            }
        }
    }
}

// MARK: - Transaction Review Row
struct TransactionReviewRow: View {
    @ObservedObject var transaction: ImportableTransaction
    let vendors: [Vendor]
    let categories: [Category]
    let cardName: String

    var body: some View {
        HStack(spacing: 12) {
            // Checkbox for selective import
            Toggle("", isOn: $transaction.isSelected)
                .labelsHidden()
                .toggleStyle(.checkbox)
                .frame(width: 20)

            // Date
            Text(transaction.date.toShortString())
                .frame(width: 80, alignment: .leading)
                .font(.caption)

            // Vendor Picker
            VStack(alignment: .leading, spacing: 2) {
                Picker("", selection: Binding(
                    get: {
                        // Use special "none" UUID for no vendor, nil UUID for create new
                        if transaction.vendor.isEmpty {
                            return UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
                        }
                        return transaction.selectedVendor?.id ?? UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!
                    },
                    set: { (newId: UUID) in
                        // Check if it's the special "none" UUID (no vendor)
                        if newId.uuidString == "00000000-0000-0000-0000-000000000000" {
                            transaction.selectedVendor = nil
                            transaction.vendor = ""
                            transaction.selectedCategory = nil
                            transaction.category = nil
                        }
                        // Check if it's the special "create new" UUID
                        else if newId.uuidString == "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF" {
                            transaction.selectedVendor = nil
                            transaction.vendor = transaction.originalVendorName
                        }
                        // Otherwise find the vendor
                        else if let vendor = vendors.first(where: { $0.id == newId }) {
                            transaction.selectedVendor = vendor
                            transaction.vendor = vendor.displayName
                            // Update category to vendor's default
                            if let categoryId = vendor.defaultCategoryId {
                                transaction.selectedCategory = categories.first(where: { $0.id == categoryId })
                                transaction.category = transaction.selectedCategory?.name
                            }
                            // Set online transaction based on vendor's default
                            transaction.onlineTransaction = vendor.defaultToOnlineTransaction
                        }
                    }
                )) {
                    Text("None").tag(UUID(uuidString: "00000000-0000-0000-0000-000000000000")!)
                    Text("Create: \(transaction.originalVendorName)").tag(UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!)
                    ForEach(vendors) { vendor in
                        Text(vendor.displayName).tag(vendor.id)
                    }
                }
                .labelsHidden()
                .frame(width: 200)
            }

            // Category Picker
            Picker("", selection: Binding(
                get: {
                    // Use special "none" UUID for no category
                    if transaction.selectedCategory == nil && transaction.category == nil {
                        return UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
                    }
                    return transaction.selectedCategory?.id ?? UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
                },
                set: { newId in
                    // Check if it's the special "none" UUID
                    if newId.uuidString == "00000000-0000-0000-0000-000000000001" {
                        transaction.selectedCategory = nil
                        transaction.category = nil
                    } else if let category = categories.first(where: { $0.id == newId }) {
                        transaction.selectedCategory = category
                        transaction.category = category.name
                    }
                }
            )) {
                Text("None").tag(UUID(uuidString: "00000000-0000-0000-0000-000000000001")! as UUID)
                ForEach(categories) { category in
                    Text(category.name).tag(category.id)
                }
            }
            .labelsHidden()
            .frame(width: 120)

            // Amount
            Text(transaction.amount.toCurrency())
                .monospacedDigit()
                .frame(width: 80, alignment: .trailing)
                .font(.caption)

            // Type Picker
            Picker("", selection: $transaction.type) {
                Text("Purchase").tag(TransactionType.purchase)
                Text("Refund").tag(TransactionType.refund)
                Text("Payment").tag(TransactionType.payment)
                Text("Credit").tag(TransactionType.statementCredit)
                Text("Fee").tag(TransactionType.fee)
            }
            .labelsHidden()
            .frame(width: 100)

            // Online Toggle
            Toggle("", isOn: $transaction.onlineTransaction)
                .labelsHidden()
                .toggleStyle(.checkbox)
                .frame(width: 50)

            // Card
            Text(cardName)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(Color(.controlBackgroundColor))
    }
}

/// Represents a transaction ready to import
class ImportableTransaction: Identifiable, ObservableObject {
    let id: String
    let date: Date
    @Published var vendor: String
    @Published var selectedVendor: Vendor?
    @Published var category: String?
    @Published var selectedCategory: Category?
    let amount: Decimal
    @Published var type: TransactionType
    @Published var onlineTransaction: Bool
    let cardId: UUID
    let ynabTransactionId: String
    let originalVendorName: String  // Keep original YNAB payee name
    @Published var isSelected: Bool = true  // For selective import

    init(id: String, date: Date, vendor: String, category: String?, amount: Decimal,
         type: TransactionType, cardId: UUID, ynabTransactionId: String, onlineTransaction: Bool = false) {
        self.id = id
        self.date = date
        self.vendor = vendor
        self.originalVendorName = vendor
        self.category = category
        self.amount = amount
        self.type = type
        self.cardId = cardId
        self.ynabTransactionId = ynabTransactionId
        self.onlineTransaction = onlineTransaction
    }
}
