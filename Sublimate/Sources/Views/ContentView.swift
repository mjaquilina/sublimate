import SwiftUI

// MARK: - Focused Value for Navigation

struct NavigationSelectionKey: FocusedValueKey {
    typealias Value = Binding<ContentView.NavigationItem?>
}

extension FocusedValues {
    var navigationSelection: Binding<ContentView.NavigationItem?>? {
        get { self[NavigationSelectionKey.self] }
        set { self[NavigationSelectionKey.self] = newValue }
    }
}

/// Main container view with sidebar navigation
struct ContentView: View {
    @State private var selectedView: NavigationItem? = .dashboard
    @State private var databaseVersion = UUID() // Changes when database switches to force view refresh

    enum NavigationItem: String, CaseIterable, Identifiable {
        case dashboard = "Dashboard"
        case ynabImport = "YNAB Import"
        case cards = "Cards"
        case spendOffers = "Spend Offers"
        case rebates = "Rebates"
        case categories = "Categories"
        case vendors = "Vendors"
        case transactions = "Transactions"
        case points = "Points"
        case reports = "Reports"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .dashboard: return "chart.bar.fill"
            case .ynabImport: return "arrow.down.circle.fill"
            case .cards: return "creditcard.fill"
            case .spendOffers: return "tag.fill"
            case .rebates: return "gift.fill"
            case .categories: return "square.grid.2x2.fill"
            case .vendors: return "storefront.fill"
            case .transactions: return "list.bullet"
            case .points: return "star.fill"
            case .reports: return "doc.text.fill"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            // Sidebar
            List(NavigationItem.allCases, selection: $selectedView) { item in
                NavigationLink(value: item) {
                    Label(item.rawValue, systemImage: item.icon)
                }
            }
            .navigationTitle(Constants.appName)
        } detail: {
            // Detail view wrapped in NavigationStack
            // The key modifier resets the stack when selectedView changes
            NavigationStack {
                Group {
                    switch selectedView {
                    case .dashboard:
                        DashboardView()
                    case .ynabImport:
                        YNABImportView()
                    case .cards:
                        CardsListView()
                    case .spendOffers:
                        SpendOffersListView()
                    case .rebates:
                        RebatesListView()
                    case .categories:
                        CategoriesListView()
                    case .vendors:
                        VendorsListView()
                    case .transactions:
                        TransactionsListView()
                    case .points:
                        PointsView()
                    case .reports:
                        ReportsView()
                    case .none:
                        Text("Select a view")
                            .font(.title)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .id("\(selectedView?.rawValue ?? "none")-\(databaseVersion)") // Force NavigationStack to reset when selection or database changes
            .background(Color.appPageBackground)
        }
        .focusedSceneValue(\.navigationSelection, $selectedView)
        .onReceive(NotificationCenter.default.publisher(for: DatabaseManager.databaseDidSwitchNotification)) { _ in
            // Force all views to refresh by updating the database version
            databaseVersion = UUID()
        }
    }
}

// MARK: - Navigation Keyboard Shortcuts

struct NavigationCommands: Commands {
    @FocusedValue(\.navigationSelection) var selection

    var body: some Commands {
        CommandMenu("Navigation") {
            Button("Dashboard") { selection?.wrappedValue = .dashboard }
                .keyboardShortcut("1", modifiers: .command)
            Button("Cards") { selection?.wrappedValue = .cards }
                .keyboardShortcut("2", modifiers: .command)
            Button("Spend Offers") { selection?.wrappedValue = .spendOffers }
                .keyboardShortcut("3", modifiers: .command)
            Button("Rebates") { selection?.wrappedValue = .rebates }
                .keyboardShortcut("4", modifiers: .command)
            Button("Transactions") { selection?.wrappedValue = .transactions }
                .keyboardShortcut("5", modifiers: .command)
            Button("Points") { selection?.wrappedValue = .points }
                .keyboardShortcut("6", modifiers: .command)
            Button("Reports") { selection?.wrappedValue = .reports }
                .keyboardShortcut("7", modifiers: .command)
        }
    }
}
