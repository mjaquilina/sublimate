import SwiftUI

/// Main dashboard showing active offers, rebates, and recommendations
struct DashboardView: View {
    @StateObject private var viewModel = DashboardViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Constants.UI.defaultPadding) {
                // Summary Headers
                HStack(spacing: Constants.UI.defaultPadding) {
                    summaryCard(
                        title: "This Month",
                        rewards: viewModel.totalRewardsThisMonth,
                        spend: viewModel.totalSpendThisMonth,
                        rate: viewModel.effectiveRate
                    )
                    summaryCard(
                        title: "Last Month",
                        rewards: viewModel.totalRewardsLastMonth,
                        spend: viewModel.totalSpendLastMonth,
                        rate: viewModel.effectiveRateLastMonth
                    )
                }

                // Active Spend Offers
                if !viewModel.activeOffers.isEmpty {
                    sectionHeader(title: "Active Spend Offers", icon: "tag.fill")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300))], spacing: Constants.UI.defaultPadding) {
                        ForEach(viewModel.activeOffers) { offer in
                            ActiveOfferCard(offer: offer, card: viewModel.cardForOffer(offer))
                        }
                    }
                }

                // Available Rebates
                if !viewModel.activeRebates.isEmpty {
                    sectionHeader(title: "Available Rebates", icon: "gift.fill")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300))], spacing: Constants.UI.defaultPadding) {
                        ForEach(viewModel.activeRebates) { rebate in
                            RebateCard(rebate: rebate, card: viewModel.cardForRebate(rebate))
                        }
                    }
                }

                // Insights
                if let insights = viewModel.insights {
                    // Cap Warnings
                    if !insights.capWarnings.isEmpty {
                        sectionHeader(title: "Earning Cap Alerts", icon: "exclamationmark.octagon")
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 300))], spacing: Constants.UI.defaultPadding) {
                            ForEach(insights.capWarnings, id: \.cap.id) { warning in
                                CapWarningCard(warning: warning)
                            }
                        }
                    }

                    // Expiring Opportunities
                    if !insights.expiringOpportunities.isEmpty {
                        sectionHeader(title: "Expiring Soon", icon: "clock.badge.exclamationmark")
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 300))], spacing: Constants.UI.defaultPadding) {
                            ForEach(insights.expiringOpportunities.prefix(3), id: \.id) { opp in
                                ExpiringOpportunityCard(opportunity: opp)
                            }
                        }
                    }

                    // Missed Optimizations
                    if !insights.missedOptimizations.isEmpty {
                        sectionHeader(title: "Recent Missed Optimizations", icon: "exclamationmark.triangle")
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 300))], spacing: Constants.UI.defaultPadding) {
                            ForEach(Array(insights.missedOptimizations.prefix(3).enumerated()), id: \.element.transaction.id) { _, opt in
                                MissedOptimizationCard(optimization: opt)
                            }
                        }
                    }
                }

            }
            .padding(Constants.UI.defaultPadding)
        }
        .navigationTitle("Dashboard")
        .toolbar {
            Button(action: { viewModel.loadData() }) {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        }
        .onAppear {
            viewModel.loadData()
        }
        .refreshable {
            viewModel.loadData()
        }
    }

    private func summaryCard(title: String, rewards: Decimal, spend: Decimal, rate: Decimal) -> some View {
        VStack(alignment: .leading, spacing: Constants.UI.smallPadding) {
            Text(title)
                .font(.headline)

            HStack(spacing: Constants.UI.largePadding) {
                VStack(alignment: .leading) {
                    Text("Total Rewards")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(rewards.toCurrency())
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                }

                VStack(alignment: .leading) {
                    Text("Total Spend")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(spend.toCurrency())
                        .font(.title)
                        .fontWeight(.bold)
                }

                VStack(alignment: .leading) {
                    Text("Effective Rate")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(rate.toPercentage())
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    private func sectionHeader(title: String, icon: String) -> some View {
        HStack {
            Image(systemName: icon)
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)
        }
        .padding(.top, Constants.UI.smallPadding)
    }

}

#Preview {
    DashboardView()
}
