import SwiftUI

struct AIInsightsView: View {
    @StateObject private var viewModel = AIInsightsViewModel()
    @State private var aiEnabled = UserDefaults.standard.bool(forKey: "aiInsightsEnabled")

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if !aiEnabled {
                    // AI Disabled Message
                    VStack(spacing: 12) {
                        Image(systemName: "sparkles.rectangle.stack")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)

                        Text("AI Insights Disabled")
                            .font(.title2)
                            .fontWeight(.semibold)

                        Text("Enable AI Insights in Settings to get personalized recommendations based on your spending patterns.")
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)

                        Button("Open Settings") {
                            // This would ideally open Settings, but for now just show a message
                            viewModel.showSettingsHint = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                } else {
                    // Header with refresh button
                    HStack {
                        VStack(alignment: .leading) {
                            Text("AI Insights")
                                .font(.title)
                                .fontWeight(.bold)
                            Text("Personalized recommendations based on your spending")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Button(action: { viewModel.refreshInsights() }) {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    }
                    .padding()

                    if viewModel.isLoading {
                        ProgressView("Generating insights...")
                            .frame(maxWidth: .infinity, maxHeight: 200)
                    } else if let error = viewModel.error {
                        ErrorCard(message: error)
                    } else if let insights = viewModel.insights {
                        // AI Briefing (if API enabled)
                        if viewModel.aiEnabled, let briefing = viewModel.aiBriefing {
                            AIBriefingCard(briefing: briefing)
                        }

                        // Missed Optimizations
                        if !insights.missedOptimizations.isEmpty {
                            InsightSection(
                                title: "Missed Optimizations",
                                icon: "exclamationmark.triangle",
                                color: .orange
                            ) {
                                ForEach(Array(insights.missedOptimizations.prefix(5).enumerated()), id: \.element.transaction.id) { _, opt in
                                    MissedOptimizationCard(optimization: opt)
                                }
                            }
                        }

                        // Pacing Alerts
                        if !insights.pacingAlerts.isEmpty {
                            InsightSection(
                                title: "Pacing Alerts",
                                icon: "gauge",
                                color: .red
                            ) {
                                ForEach(insights.pacingAlerts, id: \.offer.id) { alert in
                                    PacingAlertCard(alert: alert)
                                }
                            }
                        }

                        // Expiring Opportunities
                        if !insights.expiringOpportunities.isEmpty {
                            InsightSection(
                                title: "Expiring Soon",
                                icon: "clock.badge.exclamationmark",
                                color: .yellow
                            ) {
                                ForEach(insights.expiringOpportunities, id: \.id) { opp in
                                    ExpiringOpportunityCard(opportunity: opp)
                                }
                            }
                        }

                        // Spending Patterns
                        if !insights.spendingPatterns.isEmpty {
                            InsightSection(
                                title: "Spending Patterns",
                                icon: "chart.bar",
                                color: .blue
                            ) {
                                ForEach(Array(insights.spendingPatterns.enumerated()), id: \.element.category) { _, pattern in
                                    SpendingPatternCard(pattern: pattern)
                                }
                            }
                        }

                        if insights.missedOptimizations.isEmpty &&
                           insights.pacingAlerts.isEmpty &&
                           insights.expiringOpportunities.isEmpty &&
                           insights.spendingPatterns.isEmpty {
                            EmptyStateCard()
                        }
                    }
                }
            }
        }
        .navigationTitle("AI Insights")
        .onAppear {
            if aiEnabled {
                viewModel.refreshInsights()
            }
        }
        .alert("Settings", isPresented: $viewModel.showSettingsHint) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Go to Settings (in the sidebar) → AI Insights tab to enable this feature.")
        }
    }
}

// MARK: - Insight Cards

struct AIBriefingCard: View {
    let briefing: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundColor(.purple)
                Text("AI Summary")
                    .font(.headline)
                    .fontWeight(.semibold)
            }

            Text(briefing)
                .font(.body)
                .foregroundColor(.primary)
        }
        .padding()
        .background(Color.purple.opacity(0.1))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

struct MissedOptimizationCard: View {
    let optimization: MissedOptimization

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(optimization.transaction.vendor)
                    .font(.headline)
                Text(optimization.transaction.date.toShortString())
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack(spacing: 8) {
                    Text("Used: \(optimization.usedCard.name)")
                        .font(.caption)
                    Image(systemName: "arrow.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Should use: \(optimization.betterCard.name)")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }

            Spacer()

            VStack(alignment: .trailing) {
                Text("Missed")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(optimization.difference.toCurrency())
                    .font(.headline)
                    .foregroundColor(.orange)
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
    }
}

struct PacingAlertCard: View {
    let alert: PacingAlert

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(alert.offer.name)
                    .font(.headline)
                Spacer()
                Text(alert.card.name)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading) {
                    Text("Progress")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(alert.progressPercent.toFormattedString(decimals: 0))%")
                        .font(.body)
                        .fontWeight(.medium)
                }

                VStack(alignment: .leading) {
                    Text("Time Elapsed")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(alert.timeElapsedPercent.toFormattedString(decimals: 0))%")
                        .font(.body)
                        .fontWeight(.medium)
                }

                Spacer()

                if !alert.isOnTrack {
                    Label("Behind", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
    }
}

struct ExpiringOpportunityCard: View {
    let opportunity: ExpiringOpportunity

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(opportunity.name)
                    .font(.headline)
                Text("\(opportunity.card.name) • \(opportunity.type)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing) {
                Text("\(opportunity.daysRemaining) days")
                    .font(.headline)
                    .foregroundColor(opportunity.daysRemaining <= 7 ? .red : .orange)
                Text(opportunity.value)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
    }
}

struct CapWarningCard: View {
    let warning: CapWarning

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(warning.cap.name)
                    .font(.headline)
                Spacer()
                Text("\(warning.progressPercentage.toFormattedString(decimals: 0))%")
                    .font(.headline)
                    .foregroundColor(warning.progressPercentage >= 95 ? .red : .orange)
            }

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 8)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(warning.progressPercentage >= 95 ? Color.red : Color.orange)
                        .frame(width: geometry.size.width * CGFloat(truncating: min(warning.progressPercentage, 100) as NSDecimalNumber) / 100, height: 8)
                }
            }
            .frame(height: 8)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Remaining")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(warning.remainingSpend.toCurrency())
                        .font(.body)
                        .fontWeight(.medium)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("Days Left")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(warning.daysRemaining)")
                        .font(.body)
                        .fontWeight(.medium)
                }
            }

            if !warning.affectedRules.isEmpty {
                Text("Affects: \(warning.affectedRules.map { $0.name }.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(warning.progressPercentage >= 95 ? Color.red.opacity(0.3) : Color.orange.opacity(0.3), lineWidth: 2)
        )
    }
}

struct SpendingPatternCard: View {
    let pattern: SpendingPattern

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(pattern.category)
                .font(.headline)

            HStack {
                VStack(alignment: .leading) {
                    Text("Total Spend")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(pattern.totalSpend.toCurrency())
                        .font(.body)
                }

                Spacer()

                VStack(alignment: .leading) {
                    Text("Current Rate")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(pattern.currentAvgRate.toPercentage())
                        .font(.body)
                }

                Spacer()

                VStack(alignment: .leading) {
                    Text("Best Available")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(pattern.bestAvailableRate.toPercentage())
                        .font(.body)
                        .foregroundColor(.green)
                }
            }

            if pattern.potentialGain > 0 {
                HStack {
                    Text("Potential Gain:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(pattern.potentialGain.toCurrency())
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                }
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
    }
}

struct ErrorCard: View {
    let message: String

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle")
                .foregroundColor(.red)
            Text(message)
                .font(.body)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.red.opacity(0.1))
        .cornerRadius(8)
        .padding(.horizontal)
    }
}

struct EmptyStateCard: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 48))
                .foregroundColor(.green)

            Text("All Good!")
                .font(.title2)
                .fontWeight(.semibold)

            Text("No insights or alerts at this time. Keep using your cards optimally!")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }
}

// MARK: - Section Wrapper

struct InsightSection<Content: View>: View {
    let title: String
    let icon: String
    let color: Color
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                    .font(.title2)
                    .fontWeight(.semibold)
            }
            .padding(.horizontal)

            VStack(spacing: 8) {
                content
            }
            .padding(.horizontal)
        }
    }
}
