import SwiftUI
import Combine
import GRDB

/// View displaying list of credit cards
struct CardsListView: View {
    @StateObject private var viewModel = CardsViewModel()
    @State private var showingAddCard = false
    @State private var cardToDelete: Card?

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 320, maximum: 400), spacing: 20)
            ], spacing: 20) {
                ForEach(viewModel.cards) { card in
                    NavigationLink(destination: CardDetailView(card: card)) {
                        CreditCardView(card: card)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            cardToDelete = card
                        } label: {
                            Label("Delete Card", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle("Cards")
        .toolbar {
            Button(action: { showingAddCard = true }) {
                Image(systemName: "plus")
            }
        }
        .sheet(isPresented: $showingAddCard) {
            CardFormView(card: nil, onSave: { newCard in
                viewModel.addCard(newCard)
                showingAddCard = false
            })
        }
        .alert("Delete Card?", isPresented: Binding(
            get: { cardToDelete != nil },
            set: { if !$0 { cardToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { cardToDelete = nil }
            Button("Delete", role: .destructive) {
                if let card = cardToDelete { viewModel.deleteCard(card) }
            }
        } message: {
            Text("This will delete \"\(cardToDelete?.name ?? "")\" and all associated data. This action cannot be undone.")
        }
        .onAppear {
            viewModel.loadCards()
        }
    }
}

// MARK: - Credit Card Visual Component
struct CreditCardView: View {
    let card: Card

    var body: some View {
        ZStack {
            // Card background with gradient
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: [cardColor(for: card), cardColor(for: card).opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)

            // Card content
            VStack(alignment: .leading, spacing: 0) {
                // Top section: Issuer and chip
                HStack {
                    Text(card.issuer.uppercased())
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white.opacity(0.9))

                    Spacer()

                    // EMV chip
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [Color.yellow.opacity(0.8), Color.orange.opacity(0.6)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 32, height: 24)
                        .overlay(
                            Grid(horizontalSpacing: 2, verticalSpacing: 2) {
                                GridRow {
                                    Circle().fill(Color.black.opacity(0.3)).frame(width: 3, height: 3)
                                    Circle().fill(Color.black.opacity(0.3)).frame(width: 3, height: 3)
                                    Circle().fill(Color.black.opacity(0.3)).frame(width: 3, height: 3)
                                }
                                GridRow {
                                    Circle().fill(Color.black.opacity(0.3)).frame(width: 3, height: 3)
                                    Circle().fill(Color.black.opacity(0.3)).frame(width: 3, height: 3)
                                    Circle().fill(Color.black.opacity(0.3)).frame(width: 3, height: 3)
                                }
                            }
                        )
                }

                Spacer()

                // Card number
                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { _ in
                        Text("••••")
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.medium)
                    }
                    Text(card.lastFour)
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)

                Spacer()
                    .frame(height: 8)

                // Card name
                Text(card.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
            }
            .padding(20)
        }
        .aspectRatio(1.586, contentMode: .fit) // Standard credit card aspect ratio
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }

    private func cardColor(for card: Card) -> Color {
        let issuer = card.issuer.lowercased()

        if issuer.contains("chase") {
            return Color.blue
        } else if issuer.contains("amex") || issuer.contains("american express") {
            return Color(red: 0.0, green: 0.4, blue: 0.6)
        } else if issuer.contains("capital one") {
            return Color(red: 0.8, green: 0.1, blue: 0.2)
        } else if issuer.contains("citi") {
            return Color(red: 0.0, green: 0.3, blue: 0.6)
        } else if issuer.contains("discover") {
            return Color.orange
        } else if issuer.contains("wells fargo") {
            return Color(red: 0.8, green: 0.0, blue: 0.0)
        } else if issuer.contains("bank of america") {
            return Color(red: 0.7, green: 0.0, blue: 0.1)
        } else {
            // Default: use hash of issuer string for consistent color
            let hash = abs(card.issuer.hashValue)
            let hue = Double(hash % 360) / 360.0
            return Color(hue: hue, saturation: 0.7, brightness: 0.6)
        }
    }
}

struct CardDetailView: View {
    let card: Card
    @StateObject private var viewModel = CardDetailViewModel()

    @State private var showingAddPointType = false
    @State private var editingPointType: PointType?
    @State private var showingAddEarningRule = false
    @State private var editingEarningRule: EarningRule?
    @State private var showingAddEarningCap = false
    @State private var editingEarningCap: EarningCap?
    @State private var showingEditCard = false
    @State private var editingOffer: SpendOffer?
    @State private var editingRebate: Rebate?
    @State private var showingDeleteConfirm = false
    @State private var deleteAction: (() -> Void)?
    @State private var deleteMessage = ""
    @State private var deleteTitle = ""

    var body: some View {
        ScrollView {
            VStack(spacing: Constants.UI.defaultPadding) {
                // Header
                HStack(spacing: Constants.UI.defaultPadding) {
                    CreditCardView(card: card)
                        .frame(width: 240)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(card.issuer)
                            .font(.title3)
                            .foregroundColor(.secondary)
                        Text("•••• \(card.lastFour)")
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.secondary)
                        if let notes = card.notes, !notes.isEmpty {
                            Text(notes)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(3)
                        }
                    }
                    Spacer()
                }
                .padding()
                .background(Color(.controlBackgroundColor))
                .cornerRadius(Constants.UI.cornerRadius)

                // Point Types
                sectionHeader("Point Types", icon: "star.fill") {
                    showingAddPointType = true
                }

                if viewModel.pointTypes.isEmpty {
                    emptyState("No point types yet", caption: "Add a point type to track rewards")
                } else {
                    ForEach(viewModel.pointTypes, id: \.id) { pointType in
                        let balance = viewModel.balances.first(where: { $0.pointTypeId == pointType.id })
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(pointType.name)
                                    .font(.headline)
                                Text("\(pointType.cashValuePerPoint.toFormattedString(decimals: 4)) per point")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if let balance = balance {
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("\(balance.balance.toFormattedString(decimals: 0))")
                                        .font(.title3)
                                        .fontWeight(.bold)
                                    Text("points")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding()
                        .background(Color(.controlBackgroundColor))
                        .cornerRadius(Constants.UI.cornerRadius)
                        .contentShape(Rectangle())
                        .onTapGesture { editingPointType = pointType }
                        .contextMenu {
                            Button("Edit") { editingPointType = pointType }
                            Button("Delete", role: .destructive) {
                                deleteTitle = "Delete Point Type?"
                                deleteMessage = "This will delete \"\(pointType.name)\" and its balance. This action cannot be undone."
                                deleteAction = { viewModel.deletePointType(pointType) }
                                showingDeleteConfirm = true
                            }
                        }
                    }
                }

                // Earning Rules
                sectionHeader("Earning Rules", icon: "arrow.up.right") {
                    showingAddEarningRule = true
                }

                if viewModel.earningRules.isEmpty {
                    emptyState("No earning rules yet", caption: "Add rules to define how you earn points")
                } else {
                    ForEach(viewModel.earningRules, id: \.id) { rule in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(rule.name)
                                    .font(.headline)
                                HStack(spacing: 6) {
                                    Text(rule.matchType.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                                        .font(.caption)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.blue.opacity(0.1))
                                        .foregroundColor(.blue)
                                        .cornerRadius(4)
                                    if !rule.matchValues.isEmpty {
                                        Text(rule.matchValues.joined(separator: ", "))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                            Spacer()
                            Text("\(rule.pointsPerDollar.toFormattedString())x")
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(.blue)
                        }
                        .padding()
                        .background(Color(.controlBackgroundColor))
                        .cornerRadius(Constants.UI.cornerRadius)
                        .contentShape(Rectangle())
                        .onTapGesture { editingEarningRule = rule }
                        .contextMenu {
                            Button("Edit") { editingEarningRule = rule }
                            Button("Delete", role: .destructive) {
                                deleteTitle = "Delete Earning Rule?"
                                deleteMessage = "This will delete \"\(rule.name)\" and remove it from any caps. This action cannot be undone."
                                deleteAction = { viewModel.deleteEarningRule(rule) }
                                showingDeleteConfirm = true
                            }
                        }
                    }
                }

                // Earning Caps
                sectionHeader("Earning Caps", icon: "gauge.with.dots.needle.33percent") {
                    showingAddEarningCap = true
                }

                if viewModel.earningCaps.isEmpty {
                    emptyState("No earning caps", caption: "Caps limit combined spending across earning rules")
                } else {
                    ForEach(viewModel.earningCaps, id: \.id) { cap in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(cap.name)
                                    .font(.headline)
                                Spacer()
                                Text("\(cap.progressPercentage.toFormattedString(decimals: 0))%")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(cap.progressPercentage >= 80 ? .red : .blue)
                            }

                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color.secondary.opacity(0.2))
                                        .frame(height: 4)
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(cap.progressPercentage >= 80 ? Color.red : Color.blue)
                                        .frame(
                                            width: geometry.size.width * CGFloat(truncating: min(cap.progressPercentage, 100) as NSDecimalNumber) / 100,
                                            height: 4
                                        )
                                }
                            }
                            .frame(height: 4)

                            HStack {
                                Text("\(cap.currentSpend.toCurrency()) / \(cap.maxSpend.toCurrency())")
                                    .font(.caption)
                                Spacer()
                                Text(cap.startDate.toShortString() + " - " + cap.endDate.toShortString())
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding()
                        .background(Color(.controlBackgroundColor))
                        .cornerRadius(Constants.UI.cornerRadius)
                        .contentShape(Rectangle())
                        .onTapGesture { editingEarningCap = cap }
                        .contextMenu {
                            Button("Edit") { editingEarningCap = cap }
                            Button("Delete", role: .destructive) {
                                deleteTitle = "Delete Earning Cap?"
                                deleteMessage = "This will delete \"\(cap.name)\" and its rule links. This action cannot be undone."
                                deleteAction = { viewModel.deleteEarningCap(cap) }
                                showingDeleteConfirm = true
                            }
                        }
                    }
                }

                // Spend Offers
                if !viewModel.spendOffers.isEmpty {
                    HStack {
                        Image(systemName: "tag.fill")
                        Text("Active Spend Offers")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Spacer()
                    }
                    .padding(.top, Constants.UI.smallPadding)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 280))], spacing: Constants.UI.defaultPadding) {
                        ForEach(viewModel.spendOffers) { offer in
                            SpendOfferCard(offer: offer, card: card)
                                .contentShape(Rectangle())
                                .onTapGesture { editingOffer = offer }
                                .contextMenu {
                                    Button("Edit") { editingOffer = offer }
                                    Button("Delete", role: .destructive) {
                                        deleteTitle = "Delete Spend Offer?"
                                        deleteMessage = "This will delete \"\(offer.name)\" and its progress data. This action cannot be undone."
                                        deleteAction = { viewModel.deleteOffer(offer) }
                                        showingDeleteConfirm = true
                                    }
                                }
                        }
                    }
                }

                // Rebates
                if !viewModel.rebates.isEmpty {
                    HStack {
                        Image(systemName: "dollarsign.arrow.circlepath")
                        Text("Active Rebates")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Spacer()
                    }
                    .padding(.top, Constants.UI.smallPadding)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 280))], spacing: Constants.UI.defaultPadding) {
                        ForEach(viewModel.rebates) { rebate in
                            RebateListCard(rebate: rebate, card: card)
                                .contentShape(Rectangle())
                                .onTapGesture { editingRebate = rebate }
                                .contextMenu {
                                    Button("Edit") { editingRebate = rebate }
                                    Button("Delete", role: .destructive) {
                                        deleteTitle = "Delete Rebate?"
                                        deleteMessage = "This will delete the \"\(rebate.vendor)\" rebate. This action cannot be undone."
                                        deleteAction = { viewModel.deleteRebate(rebate) }
                                        showingDeleteConfirm = true
                                    }
                                }
                        }
                    }
                }

                // Recent Transactions
                if !viewModel.recentTransactions.isEmpty {
                    HStack {
                        Image(systemName: "list.bullet.rectangle")
                        Text("Recent Transactions")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Spacer()
                    }
                    .padding(.top, Constants.UI.smallPadding)

                    VStack(spacing: 0) {
                        ForEach(viewModel.recentTransactions) { tx in
                            HStack {
                                Text(tx.date.toShortString())
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .frame(width: 80, alignment: .leading)
                                Text(tx.vendor)
                                    .font(.body)
                                    .lineLimit(1)
                                Spacer()
                                Text(tx.amount.toCurrency())
                                    .font(.body)
                                    .fontWeight(.medium)
                                    .foregroundColor(tx.transactionType == .refund ? .green : .primary)
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 8)

                            if tx.id != viewModel.recentTransactions.last?.id {
                                Divider()
                            }
                        }
                    }
                    .background(Color(.controlBackgroundColor))
                    .cornerRadius(Constants.UI.cornerRadius)
                }
            }
            .padding(Constants.UI.defaultPadding)
        }
        .navigationTitle(card.name)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    showingEditCard = true
                } label: {
                    Label("Edit Card", systemImage: "pencil")
                }
            }
        }
        .onAppear {
            viewModel.loadData(for: card)
        }
        .sheet(isPresented: $showingAddPointType) {
            PointTypeFormView(cardId: card.id, pointType: nil, onSave: { newPointType in
                viewModel.addPointType(newPointType)
                showingAddPointType = false
            })
        }
        .sheet(item: $editingPointType) { pointType in
            PointTypeFormView(cardId: card.id, pointType: pointType, onSave: { updatedPointType in
                viewModel.updatePointType(updatedPointType)
                editingPointType = nil
            })
        }
        .sheet(isPresented: $showingAddEarningRule) {
            EarningRuleFormView(cardId: card.id, pointTypes: viewModel.pointTypes, rule: nil, onSave: { newRule in
                viewModel.addEarningRule(newRule)
                showingAddEarningRule = false
            })
        }
        .sheet(item: $editingEarningRule) { rule in
            EarningRuleFormView(cardId: card.id, pointTypes: viewModel.pointTypes, rule: rule, onSave: { updatedRule in
                viewModel.updateEarningRule(updatedRule)
                editingEarningRule = nil
            })
        }
        .sheet(isPresented: $showingEditCard) {
            CardFormView(card: card, onSave: { updatedCard in
                viewModel.updateCard(updatedCard)
                showingEditCard = false
            })
        }
        .sheet(isPresented: $showingAddEarningCap) {
            EarningCapFormView(cardId: card.id, earningRules: viewModel.earningRules, cap: nil, onSave: { newCap in
                viewModel.addEarningCap(newCap)
                showingAddEarningCap = false
            })
        }
        .sheet(item: $editingEarningCap) { cap in
            EarningCapFormView(cardId: card.id, earningRules: viewModel.earningRules, cap: cap, onSave: { updatedCap in
                viewModel.updateEarningCap(updatedCap)
                editingEarningCap = nil
            })
        }
        .sheet(item: $editingOffer) { offer in
            SpendOfferFormView(offer: offer, onSave: { updatedOffer in
                viewModel.updateOffer(updatedOffer)
                editingOffer = nil
            })
        }
        .sheet(item: $editingRebate) { rebate in
            RebateFormView(rebate: rebate, onSave: { updatedRebate in
                viewModel.updateRebate(updatedRebate)
                editingRebate = nil
            })
        }
        .alert(deleteTitle, isPresented: $showingDeleteConfirm) {
            Button("Cancel", role: .cancel) { deleteAction = nil }
            Button("Delete", role: .destructive) { deleteAction?() }
        } message: {
            Text(deleteMessage)
        }
    }

    // MARK: - Section Header
    private func sectionHeader(_ title: String, icon: String, addAction: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: icon)
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)
            Spacer()
            Button(action: addAction) {
                Image(systemName: "plus.circle.fill")
            }
            .buttonStyle(.borderless)
        }
        .padding(.top, Constants.UI.smallPadding)
    }

    // MARK: - Empty State
    private func emptyState(_ message: String, caption: String) -> some View {
        VStack(spacing: 4) {
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text(caption)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.controlBackgroundColor).opacity(0.5))
        .cornerRadius(Constants.UI.cornerRadius)
    }
}

// MARK: - Card Detail ViewModel
@MainActor
class CardDetailViewModel: ObservableObject {
    @Published var pointTypes: [PointType] = []
    @Published var balances: [PointBalance] = []
    @Published var earningRules: [EarningRule] = []
    @Published var earningCaps: [EarningCap] = []
    @Published var spendOffers: [SpendOffer] = []
    @Published var rebates: [Rebate] = []
    @Published var recentTransactions: [Transaction] = []

    func loadData(for card: Card) {
        Task {
            do {
                let db = try DatabaseManager.shared.database()
                let cardId = card.id

                let allPointTypes = try await db.read { try PointType.fetchAll($0) }
                pointTypes = allPointTypes.filter { $0.cardId == cardId }

                let pointTypeIds = pointTypes.map { $0.id }
                let allBalances = try await db.read { try PointBalance.fetchAll($0) }
                balances = allBalances.filter { pointTypeIds.contains($0.pointTypeId) }

                let allRules = try await db.read { try EarningRule.fetchAll($0) }
                earningRules = allRules.filter { $0.cardId == cardId }

                earningCaps = try await db.read { db in
                    try EarningCap.capsForCard(db, cardId: cardId)
                }

                let allOffers = try await db.read { try SpendOffer.fetchAll($0) }
                let now = Date()
                spendOffers = allOffers.filter { $0.cardId == cardId && $0.isActive && $0.endDate >= now }

                let allRebates = try await db.read { try Rebate.fetchAll($0) }
                rebates = allRebates.filter { $0.cardId == cardId && $0.isActive }

                recentTransactions = try await db.read { db in
                    try Transaction.forCard(db, cardId: cardId, limit: 10)
                }
            } catch {
                print("Error loading card details: \(error)")
            }
        }
    }

    func addPointType(_ pointType: PointType) {
        Task {
            do {
                try DatabaseManager.shared.write { db in
                    try pointType.insert(db)
                    let balance = PointBalance(pointTypeId: pointType.id, balance: 0)
                    try balance.insert(db)
                }
                pointTypes.append(pointType)
            } catch {
                print("Error adding point type: \(error)")
            }
        }
    }

    func addEarningRule(_ rule: EarningRule) {
        Task {
            do {
                try DatabaseManager.shared.write { db in
                    try rule.insert(db)
                }
                earningRules.append(rule)
            } catch {
                print("Error adding earning rule: \(error)")
            }
        }
    }

    func updatePointType(_ pointType: PointType) {
        Task {
            do {
                var updatedPointType = pointType
                updatedPointType.updatedAt = Date()

                try DatabaseManager.shared.write { db in
                    try updatedPointType.update(db)
                }

                if let index = pointTypes.firstIndex(where: { $0.id == pointType.id }) {
                    pointTypes[index] = updatedPointType
                }
            } catch {
                print("Error updating point type: \(error)")
            }
        }
    }

    func updateEarningRule(_ rule: EarningRule) {
        Task {
            do {
                var updatedRule = rule
                updatedRule.updatedAt = Date()

                try DatabaseManager.shared.write { db in
                    try updatedRule.update(db)
                }

                if let index = earningRules.firstIndex(where: { $0.id == rule.id }) {
                    earningRules[index] = updatedRule
                }
            } catch {
                print("Error updating earning rule: \(error)")
            }
        }
    }

    func updateCard(_ card: Card) {
        Task {
            do {
                var updatedCard = card
                updatedCard.updatedAt = Date()

                try DatabaseManager.shared.write { db in
                    try updatedCard.update(db)
                }
            } catch {
                print("Error updating card: \(error)")
            }
        }
    }

    func addEarningCap(_ cap: EarningCap) {
        earningCaps.append(cap)
    }

    func updateEarningCap(_ cap: EarningCap) {
        if let index = earningCaps.firstIndex(where: { $0.id == cap.id }) {
            earningCaps[index] = cap
        }
    }

    func deletePointType(_ pointType: PointType) {
        Task {
            do {
                let pointTypeId = pointType.id
                try DatabaseManager.shared.write { db in
                    // Delete associated balance first
                    if let balance = try PointBalance.findByPointType(db, pointTypeId: pointTypeId) {
                        try balance.delete(db)
                    }
                    try pointType.delete(db)
                }
                pointTypes.removeAll { $0.id == pointTypeId }
                balances.removeAll { $0.pointTypeId == pointTypeId }
            } catch {
                print("Error deleting point type: \(error)")
            }
        }
    }

    func deleteEarningRule(_ rule: EarningRule) {
        Task {
            do {
                let ruleId = rule.id
                try DatabaseManager.shared.write { db in
                    // Delete junction table entries
                    try db.execute(
                        sql: "DELETE FROM earning_rule_caps WHERE earningRuleId = ?",
                        arguments: [ruleId]
                    )
                    try rule.delete(db)
                }
                earningRules.removeAll { $0.id == ruleId }
            } catch {
                print("Error deleting earning rule: \(error)")
            }
        }
    }

    func deleteEarningCap(_ cap: EarningCap) {
        Task {
            do {
                let capId = cap.id
                try DatabaseManager.shared.write { db in
                    try db.execute(
                        sql: "DELETE FROM earning_rule_caps WHERE earningCapId = ?",
                        arguments: [capId]
                    )
                    try cap.delete(db)
                }
                earningCaps.removeAll { $0.id == capId }
            } catch {
                print("Error deleting earning cap: \(error)")
            }
        }
    }

    func updateOffer(_ offer: SpendOffer) {
        Task {
            do {
                var updated = offer
                updated.updatedAt = Date()
                try DatabaseManager.shared.write { db in
                    try updated.update(db)
                }
                if let index = spendOffers.firstIndex(where: { $0.id == offer.id }) {
                    spendOffers[index] = updated
                }
            } catch {
                print("Error updating offer: \(error)")
            }
        }
    }

    func deleteOffer(_ offer: SpendOffer) {
        Task {
            do {
                _ = try DatabaseManager.shared.write { db in
                    try offer.delete(db)
                }
                spendOffers.removeAll { $0.id == offer.id }
            } catch {
                print("Error deleting offer: \(error)")
            }
        }
    }

    func updateRebate(_ rebate: Rebate) {
        Task {
            do {
                var updated = rebate
                updated.updatedAt = Date()
                try DatabaseManager.shared.write { db in
                    try updated.update(db)
                }
                if let index = rebates.firstIndex(where: { $0.id == rebate.id }) {
                    rebates[index] = updated
                }
            } catch {
                print("Error updating rebate: \(error)")
            }
        }
    }

    func deleteRebate(_ rebate: Rebate) {
        Task {
            do {
                _ = try DatabaseManager.shared.write { db in
                    try rebate.delete(db)
                }
                rebates.removeAll { $0.id == rebate.id }
            } catch {
                print("Error deleting rebate: \(error)")
            }
        }
    }
}

// MARK: - Point Type Form
struct PointTypeFormView: View {
    let cardId: UUID
    let pointType: PointType?
    let onSave: (PointType) -> Void

    @State private var name = ""
    @State private var cashValuePerPoint = "0.01"
    @Environment(\.dismiss) private var dismiss

    private var isValid: Bool {
        !name.isEmpty && !cashValuePerPoint.isEmpty && Decimal.fromUserInput( cashValuePerPoint) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Point Type Name", text: $name)
                        .frame(minWidth: 300)

                    TextField("Cash Value Per Point", text: $cashValuePerPoint)
                        .frame(minWidth: 300)
                } footer: {
                    Text("Enter the cash value of one point. For example, 0.01 means each point is worth 1 cent.")
                        .font(.caption)
                }
            }
            .formStyle(.grouped)
            .padding(20)
            .navigationTitle(pointType == nil ? "New Point Type" : "Edit Point Type")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let cashValue = Decimal.fromUserInput( cashValuePerPoint) else { return }
                        let newPointType = PointType(
                            id: pointType?.id ?? UUID(),
                            cardId: cardId,
                            name: name,
                            cashValuePerPoint: cashValue
                        )
                        onSave(newPointType)
                    }
                    .disabled(!isValid)
                }
            }
        }
        .frame(width: 450, height: 300)
        .onAppear {
            if let pointType = pointType {
                name = pointType.name
                cashValuePerPoint = pointType.cashValuePerPoint.toFormattedString(decimals: 4)
            }
        }
    }
}

// MARK: - Earning Rule Form
struct EarningRuleFormView: View {
    let cardId: UUID
    let pointTypes: [PointType]
    let rule: EarningRule?
    let onSave: (EarningRule) -> Void

    @State private var name = ""
    @State private var selectedPointType: PointType?
    @State private var matchType: MatchType = .allSpend
    @State private var matchValues = ""
    @State private var pointsPerDollar = "1"
    @State private var isActive = true

    @Environment(\.dismiss) private var dismiss

    private var isValid: Bool {
        guard !name.isEmpty, selectedPointType != nil, !pointsPerDollar.isEmpty else { return false }
        guard Decimal.fromUserInput( pointsPerDollar) != nil else { return false }
        if matchType != .allSpend && matchValues.isEmpty { return false }
        return true
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Rule Details") {
                    TextField("Rule Name", text: $name)
                        .frame(minWidth: 300)

                    Picker("Point Type", selection: $selectedPointType) {
                        Text("Select Point Type").tag(nil as PointType?)
                        ForEach(pointTypes) { pt in
                            Text(pt.name).tag(pt as PointType?)
                        }
                    }

                    TextField("Points Per Dollar", text: $pointsPerDollar)
                        .frame(minWidth: 300)
                }

                Section {
                    Picker("Apply To", selection: $matchType) {
                        Text("All Spending").tag(MatchType.allSpend)
                        Text("Specific Categories").tag(MatchType.category)
                        Text("Specific Vendors").tag(MatchType.vendor)
                    }

                    if matchType != .allSpend {
                        TextField(
                            matchType == .category ? "Categories" : "Vendors",
                            text: $matchValues,
                            axis: .vertical
                        )
                        .lineLimit(2...4)
                        .frame(minWidth: 300)
                    }
                } header: {
                    Text("Match Criteria")
                } footer: {
                    if matchType != .allSpend {
                        Text("Enter multiple values separated by commas (e.g., Dining, Groceries, Gas)")
                            .font(.caption)
                    }
                }

                Section {
                    Toggle("Active", isOn: $isActive)
                }
            }
            .formStyle(.grouped)
            .padding(20)
            .navigationTitle(rule == nil ? "New Earning Rule" : "Edit Earning Rule")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let selectedPointType = selectedPointType,
                              let points = Decimal.fromUserInput( pointsPerDollar) else { return }

                        let valuesArray = matchType == .allSpend ? [] : matchValues.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }

                        let newRule = EarningRule(
                            id: rule?.id ?? UUID(),
                            cardId: cardId,
                            pointTypeId: selectedPointType.id,
                            name: name,
                            matchType: matchType,
                            matchValues: valuesArray,
                            pointsPerDollar: points,
                            isActive: isActive
                        )
                        onSave(newRule)
                    }
                    .disabled(!isValid)
                }
            }
        }
        .frame(width: 500, height: 450)
        .onAppear {
            if let rule = rule {
                name = rule.name
                selectedPointType = pointTypes.first(where: { $0.id == rule.pointTypeId })
                matchType = rule.matchType
                matchValues = rule.matchValues.joined(separator: ", ")
                pointsPerDollar = rule.pointsPerDollar.toFormattedString()
                isActive = rule.isActive
            } else if let firstPointType = pointTypes.first {
                selectedPointType = firstPointType
            }
        }
    }
}

struct CardFormView: View {
    let card: Card?
    let onSave: (Card) -> Void

    @State private var name = ""
    @State private var issuer = ""
    @State private var lastFour = ""
    @State private var notes = ""

    @Environment(\.dismiss) private var dismiss

    private var isValid: Bool {
        !name.isEmpty && !issuer.isEmpty && !lastFour.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Card Details") {
                    TextField("Card Name", text: $name)
                        .frame(minWidth: 300)
                        .help("e.g., Chase Sapphire Reserve, Amex Gold")

                    TextField("Issuer", text: $issuer)
                        .frame(minWidth: 300)
                        .help("e.g., Chase, American Express, Capital One")

                    TextField("Last Four Digits", text: $lastFour)
                        .frame(minWidth: 300)
                        .help("Last 4 digits of card number")

                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                        .frame(minWidth: 300)
                }
            }
            .formStyle(.grouped)
            .padding(20)
            .navigationTitle(card == nil ? "New Card" : "Edit Card")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let newCard = Card(
                            id: card?.id ?? UUID(),
                            name: name,
                            issuer: issuer,
                            lastFour: lastFour,
                            notes: notes.isEmpty ? nil : notes
                        )
                        onSave(newCard)
                    }
                    .disabled(!isValid)
                }
            }
        }
        .frame(width: 450, height: 350)
        .onAppear {
            if let card = card {
                name = card.name
                issuer = card.issuer
                lastFour = card.lastFour
                notes = card.notes ?? ""
            }
        }
    }
}

// MARK: - Earning Cap Form
struct EarningCapFormView: View {
    let cardId: UUID
    let earningRules: [EarningRule]
    let cap: EarningCap?
    let onSave: (EarningCap) -> Void

    @State private var name = ""
    @State private var maxSpend = ""
    @State private var startDate = Date()
    @State private var endDate = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
    @State private var selectedRuleIds: Set<UUID> = []

    @Environment(\.dismiss) private var dismiss

    private var isValid: Bool {
        guard !name.isEmpty, !maxSpend.isEmpty else { return false }
        guard Decimal.fromUserInput( maxSpend) != nil else { return false }
        guard endDate > startDate else { return false }
        guard !selectedRuleIds.isEmpty else { return false }
        return true
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Cap Details") {
                    TextField("Name", text: $name)
                        .frame(minWidth: 300)
                        .help("e.g., Gas + Groceries Cap")

                    TextField("Max Spend", text: $maxSpend)
                        .frame(minWidth: 300)
                        .help("Maximum combined spend across selected rules")

                    DatePicker("Start Date", selection: $startDate, displayedComponents: .date)

                    DatePicker("End Date", selection: $endDate, displayedComponents: .date)
                }

                Section {
                    if earningRules.isEmpty {
                        Text("No earning rules available. Create earning rules first.")
                            .foregroundColor(.secondary)
                            .italic()
                    } else {
                        ForEach(earningRules) { rule in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(rule.name)
                                        .font(.body)
                                    HStack(spacing: 8) {
                                        Text(rule.matchType.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        if !rule.matchValues.isEmpty {
                                            Text(rule.matchValues.joined(separator: ", "))
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }

                                Spacer()

                                Toggle("", isOn: Binding(
                                    get: { selectedRuleIds.contains(rule.id) },
                                    set: { isSelected in
                                        if isSelected {
                                            selectedRuleIds.insert(rule.id)
                                        } else {
                                            selectedRuleIds.remove(rule.id)
                                        }
                                    }
                                ))
                                .labelsHidden()
                            }
                        }
                    }
                } header: {
                    Text("Earning Rules")
                } footer: {
                    Text("Select which earning rules count toward this cap. All selected rules will share the spend limit.")
                        .font(.caption)
                }
            }
            .formStyle(.grouped)
            .padding(20)
            .navigationTitle(cap == nil ? "New Earning Cap" : "Edit Earning Cap")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let maxSpendDecimal = Decimal.fromUserInput(maxSpend) else { return }

                        let capName = name
                        let capStartDate = startDate
                        let capEndDate = endDate
                        let ruleIds = selectedRuleIds

                        Task {
                            do {
                                let db = try DatabaseManager.shared.database()

                                let capToSave = try await db.write { db -> EarningCap in
                                    let capToSave: EarningCap

                                    if let existingCap = cap {
                                        var updated = existingCap
                                        updated.name = capName
                                        updated.maxSpend = maxSpendDecimal
                                        updated.startDate = capStartDate
                                        updated.endDate = capEndDate
                                        updated.updatedAt = Date()
                                        try updated.update(db)
                                        capToSave = updated
                                    } else {
                                        let newCap = EarningCap(
                                            id: UUID(),
                                            name: capName,
                                            maxSpend: maxSpendDecimal,
                                            currentSpend: 0,
                                            startDate: capStartDate,
                                            endDate: capEndDate
                                        )
                                        try newCap.insert(db)
                                        capToSave = newCap
                                    }

                                    try db.execute(
                                        sql: "DELETE FROM earning_rule_caps WHERE earningCapId = ?",
                                        arguments: [capToSave.id]
                                    )

                                    for ruleId in ruleIds {
                                        let link = EarningRuleCap(
                                            earningRuleId: ruleId,
                                            earningCapId: capToSave.id
                                        )
                                        try link.insert(db)
                                    }

                                    return capToSave
                                }

                                onSave(capToSave)
                                dismiss()
                            } catch {
                                print("Error saving earning cap: \(error)")
                            }
                        }
                    }
                    .disabled(!isValid)
                }
            }
        }
        .frame(width: 500, height: 550)
        .onAppear {
            if let cap = cap {
                name = cap.name
                maxSpend = cap.maxSpend.toFormattedString(decimals: 2)
                startDate = cap.startDate
                endDate = cap.endDate

                // Load linked rules
                Task {
                    do {
                        let db = try DatabaseManager.shared.database()
                        let linkedRules = try await db.read { db in
                            try EarningRuleCap.rulesForCap(db, capId: cap.id)
                        }
                        selectedRuleIds = Set(linkedRules.map { $0.id })
                    } catch {
                        print("Error loading linked rules: \(error)")
                    }
                }
            }
        }
    }
}
