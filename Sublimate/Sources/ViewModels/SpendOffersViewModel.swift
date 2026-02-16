import Foundation
import SwiftUI
import GRDB
import Combine

@MainActor
class SpendOffersViewModel: ObservableObject {
    @Published var offers: [SpendOffer] = []
    @Published var cards: [UUID: Card] = [:]

    var activeOffers: [SpendOffer] {
        let now = Date()
        return offers.filter { $0.isActive && $0.startDate <= now && $0.endDate >= now }
            .sorted { $0.endDate < $1.endDate }
    }

    var futureOffers: [SpendOffer] {
        let now = Date()
        return offers.filter { $0.isActive && $0.startDate > now }
            .sorted { $0.startDate < $1.startDate }
    }

    var inactiveOffers: [SpendOffer] {
        let now = Date()
        return offers.filter { !$0.isActive || $0.endDate < now }
            .sorted { $0.endDate > $1.endDate }
    }

    func cardForOffer(_ offer: SpendOffer) -> Card? {
        cards[offer.cardId]
    }

    func loadOffers() {
        Task {
            do {
                let db = try DatabaseManager.shared.database()
                offers = try await db.read { db in
                    try SpendOffer
                        .order(SpendOffer.Columns.endDate.desc)
                        .fetchAll(db)
                }
                let allCards = try await db.read { try Card.fetchAll($0) }
                cards = Dictionary(uniqueKeysWithValues: allCards.map { ($0.id, $0) })
            } catch {
                print("Error loading offers: \(error)")
            }
        }
    }

    func addOffer(_ offer: SpendOffer) {
        Task {
            do {
                try await DatabaseManager.shared.write { db in
                    try offer.insert(db)
                }
                offers.append(offer)
            } catch {
                print("Error adding offer: \(error)")
            }
        }
    }

    func updateOffer(_ offer: SpendOffer) {
        Task {
            do {
                var updatedOffer = offer
                updatedOffer.updatedAt = Date()

                try await DatabaseManager.shared.write { db in
                    try updatedOffer.update(db)
                }

                if let index = offers.firstIndex(where: { $0.id == offer.id }) {
                    offers[index] = updatedOffer
                }
            } catch {
                print("Error updating offer: \(error)")
            }
        }
    }

    func deleteOffer(_ offer: SpendOffer) {
        Task {
            do {
                _ = try await DatabaseManager.shared.write { db in
                    try offer.delete(db)
                }
                offers.removeAll { $0.id == offer.id }
            } catch {
                print("Error deleting offer: \(error)")
            }
        }
    }
}
