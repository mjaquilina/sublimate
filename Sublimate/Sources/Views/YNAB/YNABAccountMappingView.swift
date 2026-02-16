import SwiftUI
import Combine
import GRDB

struct YNABAccountMappingView: View {
    let onComplete: () -> Void

    @StateObject private var viewModel = YNABAccountMappingViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack {
                if viewModel.isLoading {
                    ProgressView("Loading YNAB accounts...")
                } else if let error = viewModel.error {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.red)
                        Text("Error")
                            .font(.headline)
                        Text(error)
                            .foregroundColor(.secondary)
                        Button("Try Again") {
                            viewModel.loadAccounts()
                        }
                    }
                    .padding()
                } else {
                    Form {
                        Section {
                            Text("Map each YNAB account to a credit card in Sublimate")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        // Budget Selection (if multiple budgets)
                        if viewModel.budgets.count > 1 {
                            Section("Select Budget") {
                                Picker("Budget", selection: Binding(
                                    get: { viewModel.selectedBudgetId ?? "" },
                                    set: { newValue in
                                        viewModel.selectedBudgetId = newValue
                                        Task {
                                            try? await viewModel.loadAccountsForSelectedBudget()
                                        }
                                    }
                                )) {
                                    Text("Select a budget").tag("")
                                    ForEach(viewModel.budgets) { budget in
                                        Text(budget.name).tag(budget.id)
                                    }
                                }
                            }
                        }

                        // Show message if budget selected but no accounts
                        if viewModel.selectedBudgetId != nil && viewModel.ynabAccounts.isEmpty {
                            Section {
                                VStack(spacing: 16) {
                                    Image(systemName: "banknote")
                                        .font(.largeTitle)
                                        .foregroundColor(.secondary)
                                    Text("No YNAB Accounts Found")
                                        .font(.headline)
                                    Text("Make sure you have accounts in your selected YNAB budget")
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                            }
                        }

                        // Account Mappings (only show if budget is selected and accounts loaded)
                        if viewModel.selectedBudgetId != nil && !viewModel.ynabAccounts.isEmpty {
                            Section("Account Mappings") {
                                ForEach(viewModel.ynabAccounts, id: \.id) { account in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(account.name)
                                                .font(.headline)
                                            if let balance = account.balance {
                                                Text("Balance: \(balance.toCurrency())")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                        }

                                        Spacer()

                                        Picker("Card", selection: binding(for: account.id)) {
                                            Text("Skip").tag(nil as UUID?)
                                            ForEach(viewModel.cards) { card in
                                                Text(card.name).tag(card.id as UUID?)
                                            }
                                        }
                                        .frame(width: 200)
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        }
                    }
                    .formStyle(.grouped)
                }
            }
            .navigationTitle("Map YNAB Accounts")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        viewModel.saveMappings()
                        onComplete()
                    }
                    .disabled(viewModel.mappings.isEmpty)
                }
            }
            .onAppear {
                viewModel.loadAccounts()
            }
        }
        .frame(width: 600, height: 500)
    }

    private func binding(for accountId: String) -> Binding<UUID?> {
        Binding(
            get: { viewModel.mappings[accountId] },
            set: { newValue in
                if let newValue = newValue {
                    viewModel.mappings[accountId] = newValue
                } else {
                    viewModel.mappings.removeValue(forKey: accountId)
                }
            }
        )
    }
}

// Simplified YNAB Account model for mapping view
struct YNABAccountForMapping: Identifiable {
    let id: String
    let name: String
    let balance: Decimal?
}

@MainActor
class YNABAccountMappingViewModel: ObservableObject {
    @Published var ynabAccounts: [YNABAccountForMapping] = []
    @Published var cards: [Card] = []
    @Published var mappings: [String: UUID] = [:]  // YNAB account ID -> Card ID
    @Published var isLoading = false
    @Published var error: String?
    @Published var budgets: [YNABBudget] = []
    @Published var selectedBudgetId: String?

    private let ynabService = YNABService.shared

    func loadAccounts() {
        print("🔄 loadAccounts() called")
        isLoading = true
        error = nil

        Task {
            do {
                let db = try DatabaseManager.shared.database()

                // Load cards first
                cards = try await db.read { try Card.fetchAll($0) }
                print("✅ Loaded \(cards.count) cards")

                // Check if authenticated with YNAB
                guard ynabService.isAuthenticated() else {
                    print("❌ Not authenticated with YNAB")
                    error = "Not connected to YNAB. Please enter your API token in Settings first."
                    isLoading = false
                    return
                }
                print("✅ YNAB authenticated")

                // Fetch budgets
                budgets = try await ynabService.fetchBudgets()
                print("✅ Fetched \(budgets.count) budgets")

                if budgets.isEmpty {
                    error = "No YNAB budgets found"
                    isLoading = false
                    return
                }

                // Auto-select first budget if only one exists
                if budgets.count == 1 {
                    print("✅ Auto-selecting single budget: \(budgets[0].name)")
                    selectedBudgetId = budgets[0].id
                    try await loadAccountsForSelectedBudget()
                } else {
                    print("📋 Multiple budgets found, waiting for user selection")
                    isLoading = false
                }
            } catch {
                print("❌ Error in loadAccounts: \(error)")
                self.error = "Error: \(error.localizedDescription)"
                isLoading = false
            }
        }
    }

    func loadAccountsForSelectedBudget() async throws {
        guard let budgetId = selectedBudgetId else {
            error = "Please select a budget first"
            return
        }

        isLoading = true
        error = nil

        // Fetch accounts from YNAB
        let accounts = try await ynabService.fetchAccounts(budgetId: budgetId)

        // Convert to our simplified model
        ynabAccounts = accounts.map { account in
            YNABAccountForMapping(
                id: account.id,
                name: account.name,
                balance: Decimal(account.balance) / 1000  // Convert from milliunits
            )
        }

        // Load existing mappings from database
        let db = try DatabaseManager.shared.database()
        let existingMappings = try await db.read { try YNABAccountMapping.fetchAll($0) }

        // Populate mappings dict with existing values
        for mapping in existingMappings where mapping.ynabBudgetId == budgetId {
            mappings[mapping.ynabAccountId] = mapping.cardId
        }

        isLoading = false
        print("✅ Loaded \(ynabAccounts.count) YNAB accounts")
    }

    func saveMappings() {
        Task {
            do {
                guard let budgetId = selectedBudgetId else {
                    error = "No budget selected"
                    return
                }

                // Capture values before async closure
                let mappingsToSave = mappings
                let accounts = ynabAccounts

                let db = try DatabaseManager.shared.database()

                try await db.write { db in
                    // Clear existing mappings for this budget
                    try db.execute(
                        sql: "DELETE FROM ynab_account_mappings WHERE ynabBudgetId = ?",
                        arguments: [budgetId]
                    )

                    // Insert new mappings
                    for (ynabAccountId, cardId) in mappingsToSave {
                        let accountName = accounts.first(where: { $0.id == ynabAccountId })?.name ?? ""

                        let mapping = YNABAccountMapping(
                            id: UUID(),
                            ynabBudgetId: budgetId,
                            ynabAccountId: ynabAccountId,
                            ynabAccountName: accountName,
                            cardId: cardId,
                            lastImportDate: nil
                        )
                        try mapping.insert(db)
                    }
                }
            } catch {
                print("Error saving mappings: \(error)")
                self.error = "Failed to save mappings: \(error.localizedDescription)"
            }
        }
    }
}
