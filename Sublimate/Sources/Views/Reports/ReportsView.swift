import SwiftUI

/// View for generating and viewing reports
struct ReportsView: View {
    @StateObject private var viewModel = ReportsViewModel()
    @State private var selectedTab = 0
    @State private var dateRangePreset: DateRangePreset = .thisMonth

    enum DateRangePreset: String, CaseIterable {
        case thisMonth = "This Month"
        case lastMonth = "Last Month"
        case thisQuarter = "This Quarter"
        case thisYear = "This Year"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Date range picker
            HStack {
                Text("Date Range:")
                    .font(.headline)

                Picker("", selection: $dateRangePreset) {
                    ForEach(DateRangePreset.allCases, id: \.self) { preset in
                        Text(preset.rawValue).tag(preset)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 500)

                Spacer()

                Button(action: { viewModel.loadReports(for: dateRange) }) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }

                Button(action: { viewModel.exportToCSV() }) {
                    Label("Export CSV", systemImage: "square.and.arrow.up")
                }
            }
            .padding()
            .background(Color(.controlBackgroundColor))

            // Tab selector
            Picker("Report Type", selection: $selectedTab) {
                Text("Card Performance").tag(0)
                Text("Category Performance").tag(1)
                Text("Rewards Breakdown").tag(2)
            }
            .pickerStyle(.segmented)
            .padding()

            // Report content
            Group {
                switch selectedTab {
                case 0:
                    CardPerformanceReport(viewModel: viewModel)
                case 1:
                    CategoryPerformanceReport(viewModel: viewModel)
                case 2:
                    RewardsBreakdownReport(viewModel: viewModel)
                default:
                    CardPerformanceReport(viewModel: viewModel)
                }
            }
        }
        .navigationTitle("Reports")
        .onAppear {
            viewModel.loadReports(for: dateRange)
        }
        .onChange(of: dateRangePreset) { _, _ in
            viewModel.loadReports(for: dateRange)
        }
    }

    private var dateRange: (Date, Date) {
        let now = Date()
        switch dateRangePreset {
        case .thisMonth:
            return (now.startOfMonth(), now.endOfMonth())
        case .lastMonth:
            let lastMonth = Calendar.current.date(byAdding: .month, value: -1, to: now)!
            return (lastMonth.startOfMonth(), lastMonth.endOfMonth())
        case .thisQuarter:
            let quarter = (Calendar.current.component(.month, from: now) - 1) / 3
            let quarterStart = Calendar.current.date(from: DateComponents(year: Calendar.current.component(.year, from: now), month: quarter * 3 + 1, day: 1))!
            let quarterEnd = Calendar.current.date(byAdding: DateComponents(month: 3, day: -1), to: quarterStart)!
            return (quarterStart, quarterEnd)
        case .thisYear:
            let yearStart = Calendar.current.date(from: DateComponents(year: Calendar.current.component(.year, from: now), month: 1, day: 1))!
            let yearEnd = Calendar.current.date(from: DateComponents(year: Calendar.current.component(.year, from: now), month: 12, day: 31))!
            return (yearStart, yearEnd)
        }
    }
}

// MARK: - Card Performance Report
struct CardPerformanceReport: View {
    @ObservedObject var viewModel: ReportsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if viewModel.cardPerformance.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "creditcard")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("No data for selected period")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                } else {
                    Table(viewModel.cardPerformance) {
                        TableColumn("Card") { item in
                            Text(item.cardName)
                        }
                        TableColumn("Eligible Spend") { item in
                            Text(item.eligibleSpend.toCurrency())
                                .monospacedDigit()
                        }
                        .width(min: 100)
                        TableColumn("Points Value") { item in
                            Text(item.pointsValue.toCurrency())
                                .monospacedDigit()
                        }
                        .width(min: 100)
                        TableColumn("Spend Offers") { item in
                            Text(item.spendOfferValue.toCurrency())
                                .monospacedDigit()
                        }
                        .width(min: 100)
                        TableColumn("Rebates") { item in
                            Text(item.rebateValue.toCurrency())
                                .monospacedDigit()
                        }
                        .width(min: 80)
                        TableColumn("Total Rewards") { item in
                            Text(item.totalRewards.toCurrency())
                                .fontWeight(.bold)
                                .monospacedDigit()
                        }
                        .width(min: 120)
                        TableColumn("Effective Rate") { item in
                            Text(item.effectiveRate.toPercentage())
                                .foregroundColor(item.effectiveRate > 0 ? .green : .secondary)
                                .monospacedDigit()
                        }
                        .width(min: 100)
                    }
                    .frame(minHeight: 400)
                }
            }
            .padding()
        }
    }
}

// MARK: - Category Performance Report
struct CategoryPerformanceReport: View {
    @ObservedObject var viewModel: ReportsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if viewModel.categoryPerformance.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "folder")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("No data for selected period")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                } else {
                    Table(viewModel.categoryPerformance) {
                        TableColumn("Category") { item in
                            Text(item.categoryName)
                        }
                        TableColumn("Total Spend") { item in
                            Text(item.totalSpend.toCurrency())
                                .monospacedDigit()
                        }
                        .width(min: 120)
                        TableColumn("Total Rewards") { item in
                            Text(item.totalRewards.toCurrency())
                                .monospacedDigit()
                        }
                        .width(min: 120)
                        TableColumn("Effective Rate") { item in
                            Text(item.effectiveRate.toPercentage())
                                .foregroundColor(item.effectiveRate > 0 ? .green : .secondary)
                                .monospacedDigit()
                        }
                        .width(min: 100)
                        TableColumn("Best Card") { item in
                            Text(item.bestCard ?? "—")
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(minHeight: 400)
                }
            }
            .padding()
        }
    }
}

// MARK: - Rewards Breakdown Report
struct RewardsBreakdownReport: View {
    @ObservedObject var viewModel: ReportsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if viewModel.rewardsBreakdown == nil {
                    VStack(spacing: 8) {
                        Image(systemName: "chart.pie")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("No data for selected period")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                } else if let breakdown = viewModel.rewardsBreakdown {
                    // Summary cards
                    HStack(spacing: 16) {
                        summaryCard(title: "Total Rewards", value: breakdown.totalRewards.toCurrency(), color: .green)
                        summaryCard(title: "Points Value", value: breakdown.pointsValue.toCurrency(), color: .blue)
                        summaryCard(title: "Spend Offers", value: breakdown.spendOfferValue.toCurrency(), color: .orange)
                        summaryCard(title: "Rebates", value: breakdown.rebateValue.toCurrency(), color: .purple)
                    }

                    Divider()

                    // Points breakdown
                    if !breakdown.pointsByType.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Points Earned by Type")
                                .font(.headline)

                            ForEach(Array(breakdown.pointsByType.keys.sorted()), id: \.self) { typeName in
                                if let points = breakdown.pointsByType[typeName] {
                                    HStack {
                                        Text(typeName)
                                        Spacer()
                                        Text("\(points.toFormattedString(decimals: 0)) pts")
                                            .foregroundColor(.secondary)
                                            .monospacedDigit()
                                    }
                                }
                            }
                        }
                        .padding()
                        .background(Color(.controlBackgroundColor))
                        .cornerRadius(Constants.UI.cornerRadius)
                    }
                }
            }
            .padding()
        }
    }

    @ViewBuilder
    private func summaryCard(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(Constants.UI.cornerRadius)
    }
}
