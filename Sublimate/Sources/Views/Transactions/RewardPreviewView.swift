import SwiftUI

/// Preview of rewards before saving transaction
struct RewardPreviewView: View {
    let preview: TransactionRewardPreview
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Constants.UI.defaultPadding) {
                    // Transaction Summary
                    transactionSummary

                    // Earning Rule Reward
                    if let earning = preview.earningRuleReward {
                        earningRuleSection(earning)
                    }

                    // Spend Offer Rewards
                    if preview.spendOfferRewards.contains(where: { $0.cashValue > 0 }) {
                        spendOffersSection
                    }

                    // Spend Offer Progress (no reward yet)
                    if preview.spendOfferRewards.contains(where: { $0.cashValue == 0 }) {
                        spendOfferProgressSection
                    }

                    // Rebate Rewards
                    if !preview.rebateRewards.isEmpty {
                        rebatesSection
                    }

                    // Totals
                    totalsSection

                    // Point Balance Changes
                    if !preview.pointBalanceChanges.isEmpty {
                        balanceChangesSection
                    }
                }
                .padding()
            }
            .navigationTitle("Reward Preview")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirm", action: onConfirm)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private var transactionSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Transaction")
                .font(.headline)

            Group {
                HStack {
                    Text("Vendor:")
                    Spacer()
                    Text(preview.transaction.vendor)
                }
                HStack {
                    Text("Amount:")
                    Spacer()
                    Text(preview.transaction.amount.toCurrency())
                        .fontWeight(.bold)
                }
                if let category = preview.transaction.merchantCategory {
                    HStack {
                        Text("Category:")
                        Spacer()
                        Text(category)
                    }
                }
            }
            .font(.subheadline)
        }
        .padding()
        .cardBackground()
    }

    private func earningRuleSection(_ earning: EarningRuleReward) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Earning Rule")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text(earning.rule.name)
                    .font(.subheadline)
                    .fontWeight(.medium)

                if let points = earning.pointsEarned {
                    Text("\(points.toFormattedString()) points")
                        .font(.caption)
                }

                Text(earning.cashValue.toCurrency())
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.green)
            }
        }
        .padding()
        .background(Color.green.opacity(0.1))
        .cornerRadius(Constants.UI.cornerRadius)
    }

    private var spendOffersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Spend Offers")
                .font(.headline)

            ForEach(Array(preview.spendOfferRewards.filter { $0.cashValue > 0 }.enumerated()), id: \.offset) { _, reward in
                VStack(alignment: .leading, spacing: 4) {
                    Text(reward.offer.name)
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Text(reward.progressUpdate)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(reward.cashValue.toCurrency())
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.blue)

                        if reward.offer.offerType == .percentageBack,
                           let percentage = reward.offer.rewardPercentage {
                            Text("(\(percentage.toPercentage()) back)")
                                .font(.subheadline)
                                .foregroundColor(.blue.opacity(0.8))
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .cornerRadius(Constants.UI.cornerRadius)
    }

    private var spendOfferProgressSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Offer Progress")
                .font(.headline)

            ForEach(Array(preview.spendOfferRewards.filter { $0.cashValue == 0 }.enumerated()), id: \.offset) { _, reward in
                VStack(alignment: .leading, spacing: 4) {
                    Text(reward.offer.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(reward.progressUpdate)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .cardBackground()
    }

    private var rebatesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Rebates")
                .font(.headline)

            ForEach(Array(preview.rebateRewards.enumerated()), id: \.offset) { _, reward in
                VStack(alignment: .leading, spacing: 4) {
                    Text(reward.rebate.vendor)
                        .font(.subheadline)
                        .fontWeight(.medium)

                    if let usesAfter = reward.usesRemainingAfter {
                        Text("\(usesAfter) uses remaining after")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Text(reward.cashValue.toCurrency())
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.orange)
                }
            }
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(Constants.UI.cornerRadius)
    }

    private var totalsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Total Rewards")
                .font(.headline)

            if preview.totalPointsValue > 0 {
                HStack {
                    Text("Points Value:")
                    Spacer()
                    Text(preview.totalPointsValue.toCurrency())
                }
            }

            if preview.totalSpendOfferValue > 0 {
                HStack {
                    Text("Spend Offers:")
                    Spacer()
                    Text(preview.totalSpendOfferValue.toCurrency())
                }
            }

            if preview.totalRebateValue > 0 {
                HStack {
                    Text("Rebates:")
                    Spacer()
                    Text(preview.totalRebateValue.toCurrency())
                }
            }

            Divider()

            HStack {
                Text("Total:")
                    .fontWeight(.bold)
                Spacer()
                Text(preview.totalRewardValue.toCurrency())
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.green)
            }
        }
        .padding()
        .cardBackground()
    }

    private var balanceChangesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Point Balance Changes")
                .font(.headline)

            ForEach(Array(preview.pointBalanceChanges.keys), id: \.self) { pointTypeId in
                if let change = preview.pointBalanceChanges[pointTypeId] {
                    HStack {
                        Text("Point Type")  // TODO: Look up actual name
                        Spacer()
                        Text("+\(change.toFormattedString())")
                            .foregroundColor(.green)
                    }
                }
            }
        }
        .padding()
        .cardBackground()
    }
}
