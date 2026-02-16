import SwiftUI
import Combine
import GRDB

/// View displaying list of spend offers grouped by timeframe
struct SpendOffersListView: View {
    @StateObject private var viewModel = SpendOffersViewModel()
    @State private var showingAddOffer = false
    @State private var editingOffer: SpendOffer?
    @State private var offerToDelete: SpendOffer?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Constants.UI.defaultPadding) {
                if !viewModel.activeOffers.isEmpty {
                    offerSection(title: "Active", icon: "flame.fill", offers: viewModel.activeOffers)
                }

                if !viewModel.futureOffers.isEmpty {
                    offerSection(title: "Upcoming", icon: "calendar.badge.clock", offers: viewModel.futureOffers)
                }

                if !viewModel.inactiveOffers.isEmpty {
                    offerSection(title: "Expired / Inactive", icon: "clock.arrow.circlepath", offers: viewModel.inactiveOffers)
                }

                if viewModel.offers.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "tag")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("No spend offers")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("Add a spend offer to start tracking progress")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                }
            }
            .padding(Constants.UI.defaultPadding)
        }
        .navigationTitle("Spend Offers")
        .toolbar {
            Button(action: { showingAddOffer = true }) {
                Image(systemName: "plus")
            }
        }
        .sheet(isPresented: $showingAddOffer) {
            SpendOfferFormView(offer: nil, onSave: { newOffer in
                viewModel.addOffer(newOffer)
                showingAddOffer = false
            })
        }
        .sheet(item: $editingOffer) { offer in
            SpendOfferFormView(offer: offer, onSave: { updatedOffer in
                viewModel.updateOffer(updatedOffer)
                editingOffer = nil
            })
        }
        .alert("Delete Spend Offer?", isPresented: Binding(
            get: { offerToDelete != nil },
            set: { if !$0 { offerToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { offerToDelete = nil }
            Button("Delete", role: .destructive) {
                if let offer = offerToDelete { viewModel.deleteOffer(offer) }
            }
        } message: {
            Text("This will delete \"\(offerToDelete?.name ?? "")\" and its progress data. This action cannot be undone.")
        }
        .onAppear {
            viewModel.loadOffers()
        }
    }

    private func offerSection(title: String, icon: String, offers: [SpendOffer]) -> some View {
        VStack(alignment: .leading, spacing: Constants.UI.smallPadding) {
            HStack {
                Image(systemName: icon)
                Text(title)
                    .font(.title2)
                    .fontWeight(.semibold)
            }
            .padding(.top, Constants.UI.smallPadding)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300))], spacing: Constants.UI.defaultPadding) {
                ForEach(offers) { offer in
                    SpendOfferCard(offer: offer, card: viewModel.cardForOffer(offer))
                        .contentShape(Rectangle())
                        .onTapGesture { editingOffer = offer }
                        .contextMenu {
                            Button("Edit") { editingOffer = offer }
                            Button("Delete", role: .destructive) { offerToDelete = offer }
                        }
                }
            }
        }
    }
}

// MARK: - Spend Offer Card

struct SpendOfferCard: View {
    let offer: SpendOffer
    let card: Card?

    private var progressValue: Double {
        guard let progress = offer.progressPercentage() else { return 0 }
        return min(Double(truncating: progress as NSDecimalNumber) / 100.0, 1.0)
    }

    private var daysRemaining: Int {
        Date().daysBetween(offer.endDate)
    }

    private var isExpired: Bool {
        offer.endDate < Date()
    }

    private var isFuture: Bool {
        offer.startDate > Date()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Constants.UI.smallPadding) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(offer.name)
                        .font(.headline)
                    if let card = card {
                        Text(card.name)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    if isExpired {
                        Text("Expired")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.2))
                            .foregroundColor(.secondary)
                            .cornerRadius(4)
                    } else if isFuture {
                        Text("Starts \(offer.startDate.toShortString())")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("\(daysRemaining)d left")
                            .font(.caption)
                            .foregroundColor(daysRemaining < 7 ? .orange : .secondary)
                    }
                }
            }

            // Offer value description
            Text(offerDescription)
                .font(.subheadline)
                .foregroundColor(.blue)

            // Progress bar (only for active/expired, not future)
            if !isFuture {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: progressValue)
                        .tint(progressValue >= 1.0 ? .green : .blue)

                    HStack {
                        Text(progressDescription)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(Int(progressValue * 100))%")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                }
            }

            // Footer: match criteria + dates
            HStack {
                Text(matchDescription)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Spacer()
                if !offer.includeInOptimizations {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .help("Excluded from optimizations")
                }
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(Constants.UI.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: Constants.UI.cornerRadius)
                .stroke(progressValue >= 1.0 && !isExpired ? Color.green : Color.clear, lineWidth: 2)
        )
        .opacity(isExpired || !offer.isActive ? 0.7 : 1.0)
    }

    private var offerDescription: String {
        switch offer.offerType {
        case .percentageBack:
            let pct = offer.rewardPercentage?.toPercentage() ?? "0%"
            if let max = offer.maxRewardAmount {
                return "\(pct) back (up to \(max.toCurrency()))"
            }
            return "\(pct) back"
        case .flatBonusSpendThreshold:
            let bonus = offer.flatBonusAmount?.toCurrency() ?? "$0"
            let threshold = offer.spendThreshold?.toCurrency() ?? "$0"
            return "\(bonus) after spending \(threshold)"
        case .flatBonusTransactionCount:
            let bonus = offer.flatBonusAmount?.toCurrency() ?? "$0"
            let count = offer.countRequired ?? 0
            let minAmt = offer.transactionMinAmount
            if let min = minAmt {
                return "\(bonus) for \(count) transactions over \(min.toCurrency())"
            }
            return "\(bonus) for \(count) transactions"
        }
    }

    private var progressDescription: String {
        switch offer.offerType {
        case .percentageBack:
            if let max = offer.maxRewardAmount, let pct = offer.rewardPercentage, pct > 0 {
                let maxSpend = (max / pct) * 100
                return "\(offer.currentSpend.toCurrency()) / \(maxSpend.toCurrency())"
            }
            return "\(offer.currentSpend.toCurrency()) spent"
        case .flatBonusSpendThreshold:
            let threshold = offer.spendThreshold ?? 0
            return "\(offer.currentSpend.toCurrency()) / \(threshold.toCurrency())"
        case .flatBonusTransactionCount:
            let required = offer.countRequired ?? 0
            return "\(offer.currentCount) / \(required) transactions"
        }
    }

    private var matchDescription: String {
        switch offer.matchType {
        case .allSpend:
            return "All purchases"
        case .allOnline:
            return "All online purchases"
        case .vendor:
            return "Vendors: \(offer.matchValues.joined(separator: ", "))"
        case .category:
            return "Categories: \(offer.matchValues.joined(separator: ", "))"
        }
    }
}

// MARK: - Spend Offer Form
struct SpendOfferFormView: View {
    let offer: SpendOffer?
    let onSave: (SpendOffer) -> Void

    @StateObject private var viewModel: SpendOfferFormViewModel
    @Environment(\.dismiss) private var dismiss

    init(offer: SpendOffer?, onSave: @escaping (SpendOffer) -> Void) {
        self.offer = offer
        self.onSave = onSave
        _viewModel = StateObject(wrappedValue: SpendOfferFormViewModel(offer: offer))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Basic Information") {
                    TextField("Offer Name", text: $viewModel.name)
                        .frame(minWidth: 300)

                    Picker("Card", selection: $viewModel.selectedCard) {
                        Text("Select Card").tag(nil as Card?)
                        ForEach(viewModel.cards) { card in
                            Text(card.name).tag(card as Card?)
                        }
                    }
                    .onChange(of: viewModel.selectedCard) { _, _ in
                        Task { await viewModel.reloadPointTypes() }
                    }

                    DatePicker("Start Date", selection: $viewModel.startDate, displayedComponents: .date)
                    DatePicker("End Date", selection: $viewModel.endDate, displayedComponents: .date)
                }

                Section("Offer Type") {
                    Picker("Type", selection: $viewModel.offerType) {
                        ForEach([OfferType.percentageBack, .flatBonusSpendThreshold, .flatBonusTransactionCount], id: \.self) { type in
                            Text(type.rawValue.replacingOccurrences(of: "_", with: " ").capitalized).tag(type)
                        }
                    }

                    // Conditional fields based on offer type
                    if viewModel.offerType == .percentageBack {
                        TextField("Reward Percentage", text: $viewModel.rewardPercentage)
                            .frame(minWidth: 300)
                            .help("e.g., 5 for 5% back")
                        TextField("Max Reward Amount", text: $viewModel.maxRewardAmount)
                            .frame(minWidth: 300)
                            .help("Maximum cashback cap")
                    } else if viewModel.offerType == .flatBonusSpendThreshold {
                        TextField("Bonus Amount", text: $viewModel.flatBonusAmount)
                            .frame(minWidth: 300)
                        TextField("Spend Threshold", text: $viewModel.spendThreshold)
                            .frame(minWidth: 300)
                    } else if viewModel.offerType == .flatBonusTransactionCount {
                        TextField("Bonus Amount", text: $viewModel.flatBonusAmount)
                            .frame(minWidth: 300)
                        TextField("Transaction Count Required", text: $viewModel.transactionCountRequired)
                            .frame(minWidth: 300)
                        TextField("Min Transaction Amount", text: $viewModel.transactionMinAmount)
                            .frame(minWidth: 300)
                    }
                }

                Section("Match Criteria") {
                    Picker("Match Type", selection: $viewModel.matchType) {
                        ForEach([MatchType.allSpend, .allOnline, .category, .vendor], id: \.self) { type in
                            Text(type.rawValue.replacingOccurrences(of: "_", with: " ").capitalized).tag(type)
                        }
                    }
                    .onChange(of: viewModel.matchType) { _, _ in
                        viewModel.matchValues = ""
                        viewModel.showingSuggestions = false
                    }

                    if viewModel.matchType != .allSpend && viewModel.matchType != .allOnline && viewModel.matchType == .category {
                        VStack(alignment: .leading, spacing: 0) {
                            TextField("Categories (comma-separated)", text: $viewModel.matchValues)
                                .frame(minWidth: 300)
                                .help("Type to search categories")
                                .onChange(of: viewModel.matchValues) { _, newValue in
                                    viewModel.showingSuggestions = !newValue.isEmpty
                                }

                            if viewModel.showingSuggestions && !viewModel.filteredCategories.isEmpty {
                                VStack(alignment: .leading, spacing: 0) {
                                    ForEach(viewModel.filteredCategories.prefix(5)) { category in
                                        Button(action: {
                                            viewModel.addCategory(category.name)
                                        }) {
                                            HStack {
                                                if let icon = category.icon {
                                                    Image(systemName: icon)
                                                }
                                                Text(category.name)
                                                Spacer()
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
                    } else if viewModel.matchType == .vendor {
                        VStack(alignment: .leading, spacing: 0) {
                            TextField("Vendors (comma-separated)", text: $viewModel.matchValues)
                                .frame(minWidth: 300)
                                .help("Type to search vendors")
                                .onChange(of: viewModel.matchValues) { _, newValue in
                                    viewModel.showingSuggestions = !newValue.isEmpty
                                }

                            if viewModel.showingSuggestions && !viewModel.filteredVendors.isEmpty {
                                VStack(alignment: .leading, spacing: 0) {
                                    ForEach(viewModel.filteredVendors.prefix(5)) { vendor in
                                        Button(action: {
                                            viewModel.addVendor(vendor.displayName)
                                        }) {
                                            HStack {
                                                Text(vendor.displayName)
                                                Spacer()
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
                    }
                }

                Section("Reward Details") {
                    if !viewModel.pointTypes.isEmpty {
                        Picker("Reward Type", selection: $viewModel.rewardIsPoints) {
                            Text("Cash Back").tag(false)
                            Text("Points").tag(true)
                        }

                        if viewModel.rewardIsPoints {
                            Picker("Point Type", selection: $viewModel.selectedPointType) {
                                Text("Select Point Type").tag(nil as PointType?)
                                ForEach(viewModel.pointTypes) { pt in
                                    Text(pt.name).tag(pt as PointType?)
                                }
                            }
                        }
                    }
                }

                Section {
                    Toggle("Active", isOn: $viewModel.isActive)
                    Toggle("Include in Optimizations", isOn: $viewModel.includeInOptimizations)
                        .help("When enabled, this offer's value is factored into card recommendations and missed optimization alerts")
                }
            }
            .formStyle(.grouped)
            .padding(20)
            .navigationTitle(offer == nil ? "New Spend Offer" : "Edit Spend Offer")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let newOffer = viewModel.createOffer(from: offer) {
                            onSave(newOffer)
                        }
                    }
                    .disabled(!viewModel.isValid)
                }
            }
        }
        .frame(width: 550, height: 650)
    }
}

// MARK: - Spend Offer Form ViewModel
@MainActor
class SpendOfferFormViewModel: ObservableObject {
    @Published var name = ""
    @Published var cards: [Card] = []
    @Published var selectedCard: Card?
    @Published var startDate = Date()
    @Published var endDate = Calendar.current.date(byAdding: .month, value: 3, to: Date()) ?? Date()
    @Published var offerType: OfferType = .percentageBack
    @Published var matchType: MatchType = .allSpend
    @Published var matchValues = ""
    @Published var rewardPercentage = ""
    @Published var maxRewardAmount = ""
    @Published var flatBonusAmount = ""
    @Published var spendThreshold = ""
    @Published var transactionCountRequired = ""
    @Published var transactionMinAmount = ""
    @Published var pointTypes: [PointType] = []
    @Published var selectedPointType: PointType?
    @Published var rewardIsPoints = false
    @Published var isActive = true
    @Published var includeInOptimizations = true
    @Published var categories: [Category] = []
    @Published var vendors: [Vendor] = []
    @Published var showingSuggestions = false

    private var pendingCardId: UUID?
    private var pendingPointTypeId: UUID?

    init(offer: SpendOffer?) {
        if let offer = offer {
            self.name = offer.name
            self.startDate = offer.startDate
            self.endDate = offer.endDate
            self.offerType = offer.offerType
            self.matchType = offer.matchType
            self.matchValues = offer.matchValues.joined(separator: ", ")
            self.rewardPercentage = offer.rewardPercentage?.toFormattedString() ?? ""
            self.maxRewardAmount = offer.maxRewardAmount?.toFormattedString() ?? ""
            self.flatBonusAmount = offer.flatBonusAmount?.toFormattedString() ?? ""
            self.spendThreshold = offer.spendThreshold?.toFormattedString() ?? ""
            self.transactionCountRequired = offer.countRequired.map { String($0) } ?? ""
            self.transactionMinAmount = offer.transactionMinAmount?.toFormattedString() ?? ""
            self.isActive = offer.isActive
            self.includeInOptimizations = offer.includeInOptimizations

            self.pendingCardId = offer.cardId
            self.pendingPointTypeId = offer.pointTypeId

            if offer.pointTypeId != nil {
                self.rewardIsPoints = true
            }
        }

        Task {
            await loadData(offer: offer)
        }
    }

    var isValid: Bool {
        guard !name.isEmpty, selectedCard != nil else { return false }

        switch offerType {
        case .percentageBack:
            return !rewardPercentage.isEmpty && Decimal.fromUserInput( rewardPercentage) != nil
        case .flatBonusSpendThreshold:
            return !flatBonusAmount.isEmpty && !spendThreshold.isEmpty
        case .flatBonusTransactionCount:
            return !flatBonusAmount.isEmpty && !transactionCountRequired.isEmpty
        }
    }

    var filteredCategories: [Category] {
        guard !matchValues.isEmpty else { return [] }

        // Get the last item being typed (after the last comma)
        let components = matchValues.split(separator: ",")
        guard let lastComponent = components.last else { return [] }

        let searchText = lastComponent.trimmingCharacters(in: .whitespaces).lowercased()
        guard !searchText.isEmpty else { return categories }

        return categories.filter { $0.name.lowercased().contains(searchText) }
    }

    var filteredVendors: [Vendor] {
        guard !matchValues.isEmpty else { return [] }

        // Get the last item being typed (after the last comma)
        let components = matchValues.split(separator: ",")
        guard let lastComponent = components.last else { return [] }

        let searchText = lastComponent.trimmingCharacters(in: .whitespaces).lowercased()
        guard !searchText.isEmpty else { return vendors }

        return vendors.filter {
            $0.displayName.lowercased().contains(searchText) ||
            $0.name.contains(searchText)
        }
    }

    func addCategory(_ categoryName: String) {
        // Replace the last component with the selected category
        var components = matchValues.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        if components.isEmpty {
            matchValues = categoryName
        } else {
            components[components.count - 1] = categoryName
            matchValues = components.joined(separator: ", ")
        }
        showingSuggestions = false
    }

    func addVendor(_ vendorName: String) {
        // Replace the last component with the selected vendor
        var components = matchValues.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        if components.isEmpty {
            matchValues = vendorName
        } else {
            components[components.count - 1] = vendorName
            matchValues = components.joined(separator: ", ")
        }
        showingSuggestions = false
    }

    func loadData(offer: SpendOffer?) async {
        do {
            let db = try DatabaseManager.shared.database()
            cards = try await db.read { try Card.fetchAll($0) }
            categories = try await db.read { try Category.order(Category.Columns.name).fetchAll($0) }
            vendors = try await db.read { try Vendor.order(Vendor.Columns.displayName).fetchAll($0) }

            if let pendingCardId = pendingCardId {
                selectedCard = cards.first(where: { $0.id == pendingCardId })
            } else if let firstCard = cards.first {
                selectedCard = firstCard
            }

            // Load point types for the selected card
            await reloadPointTypes()

            // If editing and has a pointTypeId, find the selected one
            if let pendingPointTypeId = pendingPointTypeId {
                selectedPointType = pointTypes.first(where: { $0.id == pendingPointTypeId })
            }
        } catch {
            print("Error loading form data: \(error)")
        }
    }

    func reloadPointTypes() async {
        guard let card = selectedCard else {
            pointTypes = []
            selectedPointType = nil
            return
        }
        do {
            let cardId = card.id
            let db = try DatabaseManager.shared.database()
            let allPointTypes = try await db.read { try PointType.fetchAll($0) }
            pointTypes = allPointTypes.filter { $0.cardId == cardId }
            // Clear selection if the current point type doesn't belong to the new card
            if let selected = selectedPointType, !pointTypes.contains(where: { $0.id == selected.id }) {
                selectedPointType = nil
            }
        } catch {
            print("Error loading point types: \(error)")
        }
    }

    func createOffer(from existing: SpendOffer?) -> SpendOffer? {
        guard let selectedCard = selectedCard else { return nil }

        let matchValuesArray = (matchType == .allSpend || matchType == .allOnline) ? [] : matchValues.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }

        return SpendOffer(
            id: existing?.id ?? UUID(),
            cardId: selectedCard.id,
            name: name,
            offerType: offerType,
            matchType: matchType,
            matchValues: matchValuesArray,
            rewardPercentage: offerType == .percentageBack ? Decimal.fromUserInput(rewardPercentage) : nil,
            maxRewardAmount: offerType == .percentageBack ? Decimal.fromUserInput(maxRewardAmount) : nil,
            flatBonusAmount: offerType != .percentageBack ? Decimal.fromUserInput(flatBonusAmount) : nil,
            spendThreshold: offerType == .flatBonusSpendThreshold ? Decimal.fromUserInput(spendThreshold) : nil,
            countRequired: offerType == .flatBonusTransactionCount ? Int(transactionCountRequired) : nil,
            transactionMinAmount: offerType == .flatBonusTransactionCount ? Decimal.fromUserInput(transactionMinAmount) : nil,
            pointTypeId: rewardIsPoints ? selectedPointType?.id : nil,
            startDate: startDate,
            endDate: endDate,
            currentSpend: existing?.currentSpend ?? 0,
            currentCount: existing?.currentCount ?? 0,
            isActive: isActive,
            includeInOptimizations: includeInOptimizations,
            createdAt: existing?.createdAt ?? Date()
        )
    }
}
