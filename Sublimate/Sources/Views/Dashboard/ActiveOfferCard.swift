import SwiftUI

/// Card displaying an active spend offer with progress
struct ActiveOfferCard: View {
    let offer: SpendOffer
    let card: Card?

    private var progressValue: Double {
        guard let progress = offer.progressPercentage() else { return 0 }
        return min(Double(truncating: progress as NSDecimalNumber) / 100.0, 1.0)
    }

    private var daysRemaining: Int {
        Date().daysBetween(offer.endDate)
    }

    private var isBehind: Bool {
        guard let progressPercent = offer.progressPercentage() else { return false }

        let now = Date()
        let totalDuration = offer.endDate.timeIntervalSince(offer.startDate)
        let elapsed = now.timeIntervalSince(offer.startDate)
        let timeElapsedPercent = (Decimal(elapsed) / Decimal(totalDuration)) * 100

        let isOnTrack = progressPercent >= timeElapsedPercent

        // Behind if more than 10% behind pace
        return !isOnTrack && (timeElapsedPercent - progressPercent) > 10
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Constants.UI.smallPadding) {
            // Header
            HStack {
                VStack(alignment: .leading) {
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
                    if isBehind {
                        Label("Behind", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    Text("\(daysRemaining) days")
                        .font(.caption)
                        .foregroundColor(daysRemaining < 7 ? .orange : .secondary)
                }
            }

            // Progress bar
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

            // Match criteria
            Text(matchDescription)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(Constants.UI.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: Constants.UI.cornerRadius)
                .stroke(progressValue >= 1.0 ? Color.green : Color.clear, lineWidth: 2)
        )
    }

    private var progressDescription: String {
        switch offer.offerType {
        case .percentageBack:
            if let max = offer.maxRewardAmount, let percentage = offer.rewardPercentage {
                let maxSpend = (max / percentage) * 100
                return "\(offer.currentSpend.toCurrency()) / \(maxSpend.toCurrency())"
            }
            return "Total: \(offer.currentSpend.toCurrency())"

        case .flatBonusSpendThreshold:
            if let threshold = offer.spendThreshold {
                return "\(offer.currentSpend.toCurrency()) / \(threshold.toCurrency())"
            }
            return ""

        case .flatBonusTransactionCount:
            if let required = offer.countRequired {
                return "\(offer.currentCount) / \(required) transactions"
            }
            return ""
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
