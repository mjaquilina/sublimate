import Foundation
import SwiftUI
import GRDB
import Combine

@MainActor
class CategoriesViewModel: ObservableObject {
    @Published var categories: [Category] = []

    func loadCategories() {
        Task {
            do {
                let db = try DatabaseManager.shared.database()
                categories = try await db.read { db in
                    try Category
                        .order(Category.Columns.name)
                        .fetchAll(db)
                }
            } catch {
                print("Error loading categories: \(error)")
            }
        }
    }

    func addCategory(_ category: Category) {
        Task {
            do {
                try DatabaseManager.shared.write { db in
                    try category.insert(db)
                }
                categories.append(category)
                categories.sort { $0.name < $1.name }
            } catch {
                print("Error adding category: \(error)")
            }
        }
    }

    func updateCategory(_ category: Category) {
        Task {
            do {
                var updatedCategory = category
                updatedCategory.updatedAt = Date()

                try DatabaseManager.shared.write { db in
                    try updatedCategory.update(db)
                }

                if let index = categories.firstIndex(where: { $0.id == category.id }) {
                    categories[index] = updatedCategory
                    categories.sort { $0.name < $1.name }
                }
            } catch {
                print("Error updating category: \(error)")
            }
        }
    }

    func deleteCategory(_ category: Category) {
        Task {
            do {
                _ = try DatabaseManager.shared.write { db in
                    try category.delete(db)
                }
                categories.removeAll { $0.id == category.id }
            } catch {
                print("Error deleting category: \(error)")
            }
        }
    }
}
