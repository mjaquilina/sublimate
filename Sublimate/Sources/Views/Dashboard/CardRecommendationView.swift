import SwiftUI

/// Tool for looking up which card to use for a purchase
struct CardRecommendationView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @State private var searchText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Constants.UI.defaultPadding) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Enter category or vendor (e.g., \"groceries\")", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        viewModel.searchRecommendations(query: searchText)
                    }

                Button("Search") {
                    viewModel.searchRecommendations(query: searchText)
                }
                .buttonStyle(.borderedProminent)
            }

            if !viewModel.recommendations.isEmpty {
                VStack(alignment: .leading, spacing: Constants.UI.smallPadding) {
                    ForEach(viewModel.recommendations, id: \.card.id) { recommendation in
                        recommendationRow(recommendation)
                    }
                }
            } else if viewModel.hasSearched {
                Text("No recommendations found. Try a different search.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding()
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(Constants.UI.cornerRadius)
    }

    private func recommendationRow(_ recommendation: CardRecommendation) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(recommendation.card.name)
                    .font(.headline)

                if let ruleName = recommendation.earningRuleName {
                    Text(ruleName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if !recommendation.activeOffers.isEmpty {
                    Text("Active offers: \(recommendation.activeOffers.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundColor(.blue)
                }

                if !recommendation.availableRebates.isEmpty {
                    Text("Rebates: \(recommendation.availableRebates.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }

            Spacer()

            VStack(alignment: .trailing) {
                Text(recommendation.effectiveRate.toPercentage())
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.green)

                Text("effective rate")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(
            recommendation.rank == 0
                ? Color.green.opacity(0.1)
                : Color(.controlBackgroundColor)
        )
        .cornerRadius(Constants.UI.cornerRadius)
    }
}
