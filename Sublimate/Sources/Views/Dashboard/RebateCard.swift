import SwiftUI

/// Card displaying an available rebate
struct RebateCard: View {
    let rebate: Rebate
    let card: Card?

    private var expiresText: String? {
        guard let endDate = rebate.endDate else { return nil }
        let days = Date().daysBetween(endDate)
        if days < 0 {
            return "Expired"
        } else if days == 0 {
            return "Expires today"
        } else if days == 1 {
            return "Expires tomorrow"
        } else {
            return "Expires in \(days) days"
        }
    }

    private var isExpiringSoon: Bool {
        guard let endDate = rebate.endDate else { return false }
        return Date().daysBetween(endDate) < 7
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(rebate.vendor)
                    .font(.headline)

                if let card = card {
                    Text(card.name)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Text(rebateDescription)
                    .font(.subheadline)
                    .foregroundColor(.green)

                if let uses = rebate.usesRemaining {
                    Text("\(uses) uses remaining")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                if let expiresText = expiresText {
                    Text(expiresText)
                        .font(.caption)
                        .foregroundColor(isExpiringSoon ? .red : .secondary)
                }
            }
        }
        .padding()
        .cardBackground()
        .overlay(
            RoundedRectangle(cornerRadius: Constants.UI.cornerRadius)
                .stroke(isExpiringSoon ? Color.orange : Color.clear, lineWidth: 2)
        )
    }

    private var rebateDescription: String {
        switch rebate.rebateType {
        case .percentage:
            return "\(rebate.rebateValue.toPercentage(decimals: 0)) back"
        case .fixed:
            return "\(rebate.rebateValue.toCurrency()) credit"
        }
    }
}
