import Foundation
import SwiftUI
import Combine

@MainActor
class AIInsightsViewModel: ObservableObject {
    @Published var insights: LocalInsights?
    @Published var aiBriefing: String?
    @Published var isLoading = false
    @Published var error: String?
    @Published var showSettingsHint = false

    var aiEnabled: Bool {
        UserDefaults.standard.bool(forKey: "aiInsightsEnabled")
    }

    func refreshInsights() {
        isLoading = true
        error = nil

        Task {
            do {
                let db = try DatabaseManager.shared.database()
                let service = AIInsightsService(database: db)

                // Generate local insights
                let localInsights = try service.generateLocalInsights()
                insights = localInsights

                // Generate AI briefing if enabled and API key exists
                if aiEnabled, KeychainService.shared.getClaudeAPIKey() != nil {
                    do {
                        let briefing = try await service.generateInsightsBriefing(insights: localInsights)
                        aiBriefing = briefing
                    } catch {
                        // AI briefing failed, but local insights still work
                        print("Failed to generate AI briefing: \(error)")
                        aiBriefing = nil
                    }
                }

                isLoading = false
            } catch {
                self.error = error.localizedDescription
                isLoading = false
                print("Error generating insights: \(error)")
            }
        }
    }
}
