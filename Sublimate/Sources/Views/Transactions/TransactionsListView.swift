import SwiftUI
import GRDB

/// View displaying list of transactions in tabular form
struct TransactionsListView: View {
    @StateObject private var viewModel = TransactionsViewModel()
    @State private var showingAddTransaction = false
    @State private var editingTransaction: Transaction?
    @State private var linkingTransaction: Transaction?
    @State private var viewingTransaction: Transaction?
    @State private var selectedTransactionId: Transaction.ID?
    @State private var transactionToDelete: Transaction?

    var body: some View {
        Table(viewModel.filteredTransactions, selection: $selectedTransactionId) {
            TableColumn("Date") { tx in
                Text(tx.date.toShortString())
            }
            .width(min: 70, ideal: 80, max: 100)

            TableColumn("Vendor") { tx in
                Text(tx.vendor.isEmpty ? "—" : tx.vendor)
                    .lineLimit(1)
            }
            .width(min: 100, ideal: 180)

            TableColumn("Card") { tx in
                Text(viewModel.cardMap[tx.cardId] ?? "—")
                    .lineLimit(1)
                    .foregroundColor(.secondary)
            }
            .width(min: 80, ideal: 120, max: 160)

            TableColumn("Category") { tx in
                Text(tx.merchantCategory ?? "—")
                    .lineLimit(1)
                    .foregroundColor(.secondary)
            }
            .width(min: 70, ideal: 100, max: 140)

            TableColumn("Amount") { tx in
                Text(tx.amount.toCurrency())
                    .monospacedDigit()
            }
            .width(min: 70, ideal: 90, max: 110)

            TableColumn("Type") { tx in
                Text(tx.transactionType.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.caption)
            }
            .width(min: 60, ideal: 90, max: 110)

            TableColumn("% Earned") { tx in
                Text(viewModel.rewardPercentage(for: tx))
                    .monospacedDigit()
                    .foregroundColor(viewModel.rewardsByTransaction[tx.id] ?? 0 > 0 ? .green : .secondary)
            }
            .width(min: 55, ideal: 70, max: 90)
        }
        .contextMenu(forSelectionType: Transaction.ID.self) { selectedIds in
            if let id = selectedIds.first,
               let tx = viewModel.filteredTransactions.first(where: { $0.id == id }) {
                Button("View") { viewingTransaction = tx }
                Button("Modify") { editingTransaction = tx }
                if tx.transactionType == .statementCredit {
                    Divider()
                    Button("Link to Source...") { linkingTransaction = tx }
                }
                Divider()
                Button("Delete", role: .destructive) { transactionToDelete = tx }
            }
        } primaryAction: { selectedIds in
            if let id = selectedIds.first,
               let tx = viewModel.filteredTransactions.first(where: { $0.id == id }) {
                viewingTransaction = tx
            }
        }
        .navigationTitle("Transactions (\(viewModel.filteredTransactions.count))")
        .toolbar {
            ToolbarItemGroup {
                Picker("Card", selection: $viewModel.filterCardId) {
                    Text("All Cards").tag(nil as UUID?)
                    ForEach(viewModel.cards) { card in
                        Text(card.name).tag(card.id as UUID?)
                    }
                }
                .frame(width: 140)

                Picker("Vendor", selection: $viewModel.filterVendor) {
                    Text("All Vendors").tag(nil as String?)
                    ForEach(viewModel.vendorNames, id: \.self) { vendor in
                        Text(vendor).tag(vendor as String?)
                    }
                }
                .frame(width: 140)

                Picker("Category", selection: $viewModel.filterCategory) {
                    Text("All Categories").tag(nil as String?)
                    ForEach(viewModel.categoryNames, id: \.self) { category in
                        Text(category).tag(category as String?)
                    }
                }
                .frame(width: 140)

                Picker("Type", selection: $viewModel.filterType) {
                    Text("All Types").tag(nil as TransactionType?)
                    Text("Purchase").tag(TransactionType.purchase as TransactionType?)
                    Text("Refund").tag(TransactionType.refund as TransactionType?)
                    Text("Payment").tag(TransactionType.payment as TransactionType?)
                    Text("Credit").tag(TransactionType.statementCredit as TransactionType?)
                    Text("Fee").tag(TransactionType.fee as TransactionType?)
                }
                .frame(width: 110)

                if viewModel.hasActiveFilters {
                    Button(action: { viewModel.clearFilters() }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .help("Clear all filters")
                }

                Button(action: { showingAddTransaction = true }) {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddTransaction) {
            TransactionFormView(transaction: nil, onSave: { transaction in
                viewModel.addTransaction(transaction)
                showingAddTransaction = false
            })
        }
        .sheet(item: $editingTransaction) { transaction in
            TransactionFormView(transaction: transaction, onSave: { updatedTransaction in
                viewModel.updateTransaction(updatedTransaction)
                editingTransaction = nil
            })
        }
        .sheet(item: $linkingTransaction) { transaction in
            CreditLinkSheet(transaction: transaction, viewModel: viewModel)
        }
        .sheet(item: $viewingTransaction) { transaction in
            TransactionDetailView(transaction: transaction, onRewardUnlinked: {
                viewModel.loadTransactions()
            })
        }
        .alert("Delete Transaction?", isPresented: Binding(
            get: { transactionToDelete != nil },
            set: { if !$0 { transactionToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { transactionToDelete = nil }
            Button("Delete", role: .destructive) {
                if let tx = transactionToDelete { viewModel.deleteTransaction(tx) }
            }
        } message: {
            Text("This will delete this transaction and its associated rewards. This action cannot be undone.")
        }
        .onAppear {
            viewModel.loadTransactions()
        }
    }
}

// MARK: - Credit Link Sheet

struct CreditLinkSheet: View {
    let transaction: Transaction
    @ObservedObject var viewModel: TransactionsViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var sources: [CreditLinkSourceInfo] = []
    @State private var selectedSourceId: UUID?
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // Transaction summary
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(transaction.vendor.isEmpty ? "Statement Credit" : transaction.vendor)
                            .font(.headline)
                        Text("\(transaction.date.toShortString()) \u{2022} \(transaction.amount.toCurrency())")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal)

                if isLoading {
                    Spacer()
                    ProgressView("Loading sources...")
                    Spacer()
                } else if sources.isEmpty {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "tray")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("No matching sources found")
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                } else {
                    List {
                        Section("Select a source") {
                            Button(action: { selectedSourceId = nil }) {
                                HStack {
                                    Text("None")
                                    Spacer()
                                    if selectedSourceId == nil {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.blue)
                                    }
                                }
                            }
                            .buttonStyle(.plain)

                            ForEach(sources) { source in
                                Button(action: { selectedSourceId = source.id }) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(source.name)
                                            Text(source.type.replacingOccurrences(of: "_", with: " ").capitalized)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        if let amount = source.amount {
                                            Text(amount.toCurrency())
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        if selectedSourceId == source.id {
                                            Image(systemName: "checkmark")
                                                .foregroundColor(.blue)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Link Statement Credit")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let sourceType = sources.first(where: { $0.id == selectedSourceId })?.type
                        viewModel.linkCredit(
                            transactionId: transaction.id,
                            sourceId: selectedSourceId,
                            sourceType: sourceType
                        )
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 450, height: 400)
        .onAppear {
            // Pre-select existing link
            if let existingLink = viewModel.creditLinks[transaction.id] {
                selectedSourceId = existingLink.sourceId
            }
            Task {
                sources = await viewModel.loadAvailableSources(for: transaction)
                isLoading = false
            }
        }
    }
}

// MARK: - Transaction Detail View

/// Info about a spend offer this transaction contributed progress to
struct TransactionOfferProgress: Identifiable {
    let id: UUID
    let offer: SpendOffer
    let transactionContribution: Decimal  // amount or count this tx added
    let potentialEarnings: Decimal  // what the offer pays out if completed
    let progressDescription: String  // e.g. "$450 / $1,500" or "4 / 6 transactions"
    let progressPercent: Decimal
}

struct TransactionDetailView: View {
    let transaction: Transaction
    let onRewardUnlinked: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    @State private var rewards: [TransactionReward] = []
    @State private var creditLink: StatementCreditLink?
    @State private var offerProgress: [TransactionOfferProgress] = []
    @State private var isLoading = true
    @State private var rewardToUnlink: TransactionReward?
    @State private var showingUnlinkConfirm = false
    @State private var unlinkError: String?
    @State private var showingError = false

    init(transaction: Transaction, onRewardUnlinked: (() -> Void)? = nil) {
        self.transaction = transaction
        self.onRewardUnlinked = onRewardUnlinked
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                } else {
                    Form {
                        Section("Transaction") {
                            LabeledContent("Vendor", value: transaction.vendor.isEmpty ? "—" : transaction.vendor)
                            LabeledContent("Date", value: transaction.date.toShortString())
                            LabeledContent("Amount", value: transaction.amount.toCurrency())
                            LabeledContent("Type", value: transaction.transactionType.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                            if let category = transaction.merchantCategory {
                                LabeledContent("Category", value: category)
                            }
                            LabeledContent("Online", value: transaction.onlineTransaction ? "Yes" : "No")
                            if let notes = transaction.notes, !notes.isEmpty {
                                LabeledContent("Notes", value: notes)
                            }
                        }

                        if !rewards.isEmpty {
                            Section("Rewards Earned") {
                                ForEach(rewards) { reward in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(reward.description)
                                                .font(.body)
                                            Text(reward.rewardSourceType.replacingOccurrences(of: "_", with: " ").capitalized)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        VStack(alignment: .trailing, spacing: 2) {
                                            if let points = reward.pointsEarned {
                                                Text("\(points.toFormattedString()) pts")
                                                    .fontWeight(.medium)
                                            }
                                            Text(reward.cashValue.toCurrency())
                                                .font(.caption)
                                                .foregroundColor(.green)
                                        }
                                        Button(action: {
                                            rewardToUnlink = reward
                                            showingUnlinkConfirm = true
                                        }) {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundColor(.secondary)
                                        }
                                        .buttonStyle(.plain)
                                        .help("Unlink this reward")
                                    }
                                }

                                HStack {
                                    Text("Total Value")
                                        .fontWeight(.semibold)
                                    Spacer()
                                    Text(rewards.reduce(Decimal.zero) { $0 + $1.cashValue }.toCurrency())
                                        .fontWeight(.semibold)
                                        .foregroundColor(.green)
                                }
                            }
                        }

                        if !offerProgress.isEmpty {
                            Section("Offer Progress") {
                                ForEach(offerProgress) { progress in
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(progress.offer.name)
                                            .font(.body)
                                            .fontWeight(.medium)

                                        // Progress bar
                                        VStack(alignment: .leading, spacing: 2) {
                                            ProgressView(value: Double(truncating: min(progress.progressPercent, 100) as NSNumber) / 100.0)
                                                .tint(progress.progressPercent >= 100 ? .green : .blue)

                                            HStack {
                                                Text(progress.progressDescription)
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                                Spacer()
                                                let pct = min(progress.progressPercent, 100)
                                                Text("\(pct.toFormattedString())%")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                        }

                                        HStack {
                                            Text("This transaction:")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            Spacer()
                                            if progress.offer.offerType == .flatBonusTransactionCount {
                                                Text("+1 transaction")
                                                    .font(.caption)
                                                    .foregroundColor(.blue)
                                            } else {
                                                Text("+\(progress.transactionContribution.toCurrency())")
                                                    .font(.caption)
                                                    .foregroundColor(.blue)
                                            }
                                        }

                                        HStack {
                                            Text("Potential earnings:")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            Spacer()
                                            Text(progress.potentialEarnings.toCurrency())
                                                .font(.caption)
                                                .fontWeight(.medium)
                                                .foregroundColor(progress.progressPercent >= 100 ? .green : .orange)
                                        }
                                    }
                                }
                            }
                        }

                        if transaction.transactionType == .statementCredit {
                            if let link = creditLink {
                                Section("Linked Source") {
                                    LabeledContent("Source Type", value: link.sourceType.replacingOccurrences(of: "_", with: " ").capitalized)
                                    if let notes = link.notes, !notes.isEmpty {
                                        LabeledContent("Notes", value: notes)
                                    }
                                }
                            } else {
                                Section("Linked Source") {
                                    Text("Not linked to any source")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }

                        if rewards.isEmpty && offerProgress.isEmpty && transaction.transactionType != .statementCredit {
                            Section("Rewards") {
                                Text("No rewards for this transaction")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .formStyle(.grouped)
                }
            }
            .navigationTitle("Transaction Details")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(width: 500, height: 550)
        .onAppear { loadDetails() }
        .alert("Unlink Reward?", isPresented: $showingUnlinkConfirm) {
            Button("Cancel", role: .cancel) {
                rewardToUnlink = nil
            }
            Button("Unlink", role: .destructive) {
                if let reward = rewardToUnlink {
                    unlinkReward(reward)
                }
            }
        } message: {
            if let reward = rewardToUnlink {
                Text("This will remove the \(reward.rewardSourceType.replacingOccurrences(of: "_", with: " ")) reward (\(reward.cashValue.toCurrency())) from this transaction. This action cannot be undone.")
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(unlinkError ?? "An unknown error occurred")
        }
    }

    private func loadDetails() {
        Task {
            do {
                let db = try DatabaseManager.shared.database()
                let txId = transaction.id
                let tx = transaction
                rewards = try await db.read { db in
                    try TransactionReward.forTransaction(db, transactionId: txId)
                }
                if transaction.transactionType == .statementCredit {
                    creditLink = try await db.read { db in
                        try StatementCreditLink.forTransaction(db, transactionId: txId)
                    }
                }
                // Load matching spend offers this transaction contributed to
                if tx.isEligibleForRewards {
                    offerProgress = try await db.read { db in
                        let activeOffers = try SpendOffer.activeOffersForCard(db, cardId: tx.cardId, date: tx.date)
                        let matching = activeOffers.filter { $0.matches(vendor: tx.vendor, category: tx.merchantCategory, onlineTransaction: tx.onlineTransaction) }

                        return matching.compactMap { offer in
                            // Skip if transaction doesn't meet min amount for count offers
                            if offer.offerType == .flatBonusTransactionCount,
                               let minAmount = offer.transactionMinAmount,
                               abs(tx.amount) < minAmount {
                                return nil
                            }

                            let contribution = tx.amount
                            let potentialEarnings: Decimal
                            let progressDesc: String
                            let progressPct: Decimal

                            switch offer.offerType {
                            case .percentageBack:
                                if let pct = offer.rewardPercentage {
                                    potentialEarnings = offer.maxRewardAmount ?? (offer.currentSpend * pct / 100)
                                } else {
                                    potentialEarnings = 0
                                }
                                if let max = offer.maxRewardAmount, let pct = offer.rewardPercentage, pct > 0 {
                                    let maxSpend = (max / pct) * 100
                                    progressDesc = "\(offer.currentSpend.toCurrency()) / \(maxSpend.toCurrency())"
                                    progressPct = maxSpend > 0 ? (offer.currentSpend / maxSpend) * 100 : 0
                                } else {
                                    progressDesc = "\(offer.currentSpend.toCurrency()) spent"
                                    progressPct = 0
                                }

                            case .flatBonusSpendThreshold:
                                let bonus = offer.flatBonusAmount ?? 0
                                let threshold = offer.spendThreshold ?? 0
                                // Amortize: this transaction's share of the bonus
                                potentialEarnings = threshold > 0 ? tx.amount * (bonus / threshold) : 0
                                progressDesc = "\(offer.currentSpend.toCurrency()) / \(threshold.toCurrency())"
                                progressPct = threshold > 0 ? (offer.currentSpend / threshold) * 100 : 0

                            case .flatBonusTransactionCount:
                                let bonus = offer.flatBonusAmount ?? 0
                                let required = offer.countRequired ?? 0
                                // Amortize: each transaction's equal share of the bonus
                                potentialEarnings = required > 0 ? bonus / Decimal(required) : 0
                                progressDesc = "\(offer.currentCount) / \(required) transactions"
                                progressPct = required > 0 ? (Decimal(offer.currentCount) / Decimal(required)) * 100 : 0
                            }

                            return TransactionOfferProgress(
                                id: offer.id,
                                offer: offer,
                                transactionContribution: contribution,
                                potentialEarnings: potentialEarnings,
                                progressDescription: progressDesc,
                                progressPercent: progressPct
                            )
                        }
                    }
                }
            } catch {
                print("Error loading transaction details: \(error)")
            }
            isLoading = false
        }
    }

    private func unlinkReward(_ reward: TransactionReward) {
        Task {
            do {
                let viewModel = TransactionsViewModel()
                try await viewModel.unlinkReward(reward, from: transaction)

                // Reload details to reflect changes
                loadDetails()

                // Notify parent to refresh
                onRewardUnlinked?()

                // Clear the reward to unlink
                await MainActor.run {
                    rewardToUnlink = nil
                }
            } catch {
                await MainActor.run {
                    unlinkError = "Failed to unlink reward: \(error.localizedDescription)"
                    showingError = true
                    rewardToUnlink = nil
                }
            }
        }
    }
}
