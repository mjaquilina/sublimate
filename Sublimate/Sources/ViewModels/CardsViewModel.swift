import Foundation
import SwiftUI
import GRDB
import Combine

@MainActor
class CardsViewModel: ObservableObject {
    @Published var cards: [Card] = []

    func loadCards() {
        Task {
            do {
                let db = try DatabaseManager.shared.database()
                cards = try await db.read { db in
                    try Card.all(db)
                }
            } catch {
                print("Error loading cards: \(error)")
            }
        }
    }

    func addCard(_ card: Card) {
        Task {
            do {
                let db = try DatabaseManager.shared.database()
                try await db.write { db in
                    var mutableCard = card
                    try mutableCard.insert(db)
                }
                loadCards()
            } catch {
                print("Error adding card: \(error)")
            }
        }
    }

    func deleteCard(_ card: Card) {
        Task {
            do {
                let db = try DatabaseManager.shared.database()
                try await db.write { db in
                    try Card.deleteOne(db, key: card.id)
                }
                loadCards()
            } catch {
                print("Error deleting card: \(error)")
            }
        }
    }
}
