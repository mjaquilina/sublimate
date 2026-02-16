import SwiftUI

/// App settings view
struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @State private var ynabToken = ""
    @State private var showingImport = false
    @State private var showingAccountMapping = false
    @State private var selectedTab = 1  // 0 = YNAB, 1 = Database

    var body: some View {
        TabView(selection: $selectedTab) {
            // YNAB Integration Tab
            Form {
                Section {
                    SecureField("YNAB API Token", text: $ynabToken)
                        .frame(minWidth: 300)

                    HStack {
                        Button("Connect to YNAB") {
                            viewModel.testYNABConnection(token: ynabToken)
                        }
                        .disabled(ynabToken.isEmpty)

                        if let status = viewModel.ynabConnectionStatus {
                            Text(status)
                                .font(.caption)
                                .foregroundColor(viewModel.ynabConnected ? .green : .red)
                        }
                    }
                } header: {
                    Text("API Configuration")
                } footer: {
                    Text("Get your API token from YNAB Developer Settings")
                        .font(.caption)
                }

                Section {
                    if viewModel.ynabConnected {
                        if !viewModel.accountMappings.isEmpty {
                            List {
                                ForEach(viewModel.accountMappings) { mapping in
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
                                            Text(lastImport.toShortString())
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                            }
                            .frame(height: 150)
                        }

                        HStack {
                            Button("Manage Account Mappings") {
                                showingAccountMapping = true
                            }

                            if !viewModel.accountMappings.isEmpty {
                                Button("Import Transactions") {
                                    showingImport = true
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                    } else {
                        Text("Connect to YNAB first")
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Account Mappings")
                }
            }
            .formStyle(.grouped)
            .padding(20)
            .tabItem {
                Label("YNAB", systemImage: "link")
            }
            .tag(0)
            .sheet(isPresented: $showingImport) {
                YNABImportView()
            }
            .sheet(isPresented: $showingAccountMapping) {
                YNABAccountMappingView(onComplete: {
                    showingAccountMapping = false
                    viewModel.loadAccountMappings()
                })
            }

            // Data Tab
            ScrollView {
                VStack(spacing: 20) {
                    DatabaseSettingsView()

                    Divider()

                    // Data Export Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Data Export")
                            .font(.headline)

                        Button(action: { viewModel.exportData() }) {
                            Label("Export All Data to CSV", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.bordered)

                        Text("Export all your credit card and rewards data to CSV format.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()

                    Divider()

                    // Maintenance Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Maintenance")
                            .font(.headline)

                        Button(action: { viewModel.recalculatePointBalances() }) {
                            Label("Recalculate Point Balances", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .buttonStyle(.bordered)

                        Text("Recalculate all point balances from transactions and redemptions. Use this if balances seem incorrect.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Divider()

                        Button(action: { viewModel.repairOfferProgress() }) {
                            Label("Repair Offer Progress", systemImage: "wrench.and.screwdriver")
                        }
                        .buttonStyle(.bordered)

                        Text("Recalculate spend offer progress (currentSpend / currentCount) from all transactions. Use this if offer progress seems incorrect.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()

                    Divider()

                    // Sample Data
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Sample Data")
                            .font(.headline)

                        Button(action: { viewModel.showingGenerateSampleDataConfirm = true }) {
                            Label("Generate Sample Data", systemImage: "wand.and.stars")
                        }
                        .buttonStyle(.bordered)

                        Text("Populate the database with realistic sample cards, transactions, offers, and rebates for testing.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()

                    Divider()

                    // Danger Zone
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Danger Zone")
                            .font(.headline)
                            .foregroundColor(.red)

                        Button(action: { viewModel.showingDeleteTransactionsConfirm = true }) {
                            Label("Delete All Transactions", systemImage: "trash")
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)

                        Text("Permanently delete all transactions and their rewards. Point balances will be reset to 0. This cannot be undone.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                }
            }
            .tabItem {
                Label("Database", systemImage: "externaldrive")
            }
            .tag(1)
        }
        .frame(width: 650, height: 550)
        .onChange(of: selectedTab) { _, newTab in
            // Only load YNAB token when switching to YNAB tab
            if newTab == 0 && ynabToken.isEmpty {
                if let savedToken = KeychainService.shared.getYNABToken() {
                    ynabToken = savedToken
                }
                viewModel.loadAccountMappings()
            }
        }
        .alert("Delete All Transactions?", isPresented: $viewModel.showingDeleteTransactionsConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                viewModel.deleteAllTransactions()
            }
        } message: {
            Text("This will permanently delete all transactions and their associated rewards. Spend offer progress and rebate usage will be reset. This action cannot be undone.")
        }
        .alert("Generate Sample Data?", isPresented: $viewModel.showingGenerateSampleDataConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Generate") {
                viewModel.generateSampleData()
            }
        } message: {
            Text("This will create sample cards, transactions, offers, and rebates. Existing data will not be affected.")
        }
    }
}
