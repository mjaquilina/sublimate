import Foundation
import SwiftUI
import GRDB
import Combine

@MainActor
class RebatesViewModel: ObservableObject {
    @Published var rebates: [Rebate] = []
    @Published var cards: [UUID: Card] = [:]

    var activeRebates: [Rebate] {
        rebates.filter { $0.isActive && ($0.usesRemaining == nil || $0.usesRemaining! > 0) }
            .sorted { ($0.endDate ?? .distantFuture) < ($1.endDate ?? .distantFuture) }
    }

    var inactiveRebates: [Rebate] {
        rebates.filter { !$0.isActive || ($0.usesRemaining != nil && $0.usesRemaining! <= 0) }
            .sorted { ($0.endDate ?? .distantFuture) > ($1.endDate ?? .distantFuture) }
    }

    func cardForRebate(_ rebate: Rebate) -> Card? {
        cards[rebate.cardId]
    }

    func loadRebates() {
        Task {
            do {
                let db = try DatabaseManager.shared.database()
                rebates = try await db.read { db in
                    try Rebate
                        .order(Rebate.Columns.createdAt.desc)
                        .fetchAll(db)
                }
                let allCards = try await db.read { try Card.fetchAll($0) }
                cards = Dictionary(uniqueKeysWithValues: allCards.map { ($0.id, $0) })
            } catch {
                print("Error loading rebates: \(error)")
            }
        }
    }

    func addRebate(_ rebate: Rebate) {
        Task {
            do {
                try await DatabaseManager.shared.write { db in
                    try rebate.insert(db)
                }
                rebates.append(rebate)
            } catch {
                print("Error adding rebate: \(error)")
            }
        }
    }

    func updateRebate(_ rebate: Rebate) {
        Task {
            do {
                var updatedRebate = rebate
                updatedRebate.updatedAt = Date()

                try await DatabaseManager.shared.write { db in
                    try updatedRebate.update(db)
                }

                if let index = rebates.firstIndex(where: { $0.id == rebate.id }) {
                    rebates[index] = updatedRebate
                }
            } catch {
                print("Error updating rebate: \(error)")
            }
        }
    }

    func deleteRebate(_ rebate: Rebate) {
        Task {
            do {
                _ = try await DatabaseManager.shared.write { db in
                    try rebate.delete(db)
                }
                rebates.removeAll { $0.id == rebate.id }
            } catch {
                print("Error deleting rebate: \(error)")
            }
        }
    }
}
