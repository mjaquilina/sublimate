import Foundation
import SwiftUI
import GRDB
import Combine

@MainActor
class VendorsViewModel: ObservableObject {
    @Published var vendors: [Vendor] = []
    @Published var categories: [Category] = []

    func loadVendors() {
        Task {
            do {
                let db = try DatabaseManager.shared.database()
                vendors = try await db.read { db in
                    try Vendor
                        .order(Vendor.Columns.displayName)
                        .fetchAll(db)
                }
                categories = try await db.read { db in
                    try Category
                        .order(Category.Columns.name)
                        .fetchAll(db)
                }
            } catch {
                print("Error loading vendors: \(error)")
            }
        }
    }

    func addVendor(_ vendor: Vendor) {
        Task {
            do {
                print("🏪 VendorsViewModel.addVendor called with: \(vendor.displayName)")
                try DatabaseManager.shared.write { db in
                    try vendor.insert(db)
                }
                vendors.append(vendor)
                vendors.sort { $0.displayName < $1.displayName }
                print("🏪 Vendor added successfully. Total vendors: \(vendors.count)")
            } catch {
                print("❌ Error adding vendor: \(error)")
            }
        }
    }

    func updateVendor(_ vendor: Vendor) {
        Task {
            do {
                var updatedVendor = vendor
                updatedVendor.updatedAt = Date()

                try DatabaseManager.shared.write { db in
                    try updatedVendor.update(db)
                }

                if let index = vendors.firstIndex(where: { $0.id == vendor.id }) {
                    vendors[index] = updatedVendor
                }
                vendors.sort { $0.displayName < $1.displayName }
            } catch {
                print("Error updating vendor: \(error)")
            }
        }
    }

    func deleteVendor(_ vendor: Vendor) {
        Task {
            do {
                _ = try DatabaseManager.shared.write { db in
                    try vendor.delete(db)
                }
                vendors.removeAll { $0.id == vendor.id }
            } catch {
                print("Error deleting vendor: \(error)")
            }
        }
    }

    func getCategoryName(id: UUID?) -> String {
        guard let id = id else { return "None" }
        return categories.first(where: { $0.id == id })?.name ?? "Unknown"
    }
}
