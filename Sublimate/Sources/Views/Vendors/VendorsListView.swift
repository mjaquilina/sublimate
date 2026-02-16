import SwiftUI

struct VendorsListView: View {
    @StateObject private var viewModel = VendorsViewModel()
    @State private var showingAddVendor = false
    @State private var editingVendor: Vendor?

    var body: some View {
        List {
            ForEach(viewModel.vendors) { vendor in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(vendor.displayName)
                            .font(.headline)
                        if let categoryId = vendor.defaultCategoryId {
                            Text(viewModel.getCategoryName(id: categoryId))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    editingVendor = vendor
                }
            }
            .onDelete(perform: deleteVendors)
        }
        .navigationTitle("Vendors")
        .toolbar {
            Button(action: { showingAddVendor = true }) {
                Image(systemName: "plus")
            }
        }
        .sheet(isPresented: $showingAddVendor) {
            if viewModel.categories.isEmpty {
                ProgressView("Loading...")
                    .frame(width: 500, height: 400)
                    .onAppear {
                        viewModel.loadVendors()
                    }
            } else {
                VendorFormView(vendor: nil, categories: viewModel.categories, onSave: { newVendor in
                    viewModel.addVendor(newVendor)
                    showingAddVendor = false
                })
            }
        }
        .sheet(item: $editingVendor) { vendor in
            if viewModel.categories.isEmpty {
                ProgressView("Loading...")
                    .frame(width: 500, height: 400)
                    .onAppear {
                        viewModel.loadVendors()
                    }
            } else {
                VendorFormView(vendor: vendor, categories: viewModel.categories, onSave: { updatedVendor in
                    viewModel.updateVendor(updatedVendor)
                    editingVendor = nil
                })
            }
        }
        .onAppear {
            viewModel.loadVendors()
        }
    }

    private func deleteVendors(at offsets: IndexSet) {
        for index in offsets {
            viewModel.deleteVendor(viewModel.vendors[index])
        }
    }
}

struct VendorFormView: View {
    let vendor: Vendor?
    let categories: [Category]
    let onSave: (Vendor) -> Void

    @State private var displayName = ""
    @State private var selectedCategory: Category?
    @State private var defaultToOnlineTransaction = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Display Name", text: $displayName)
                        .frame(minWidth: 300)
                } header: {
                    Text("Vendor Details")
                }

                Section {
                    Picker("Default Category", selection: $selectedCategory) {
                        Text("None").tag(nil as Category?)
                        ForEach(categories) { category in
                            HStack {
                                if let icon = category.icon {
                                    Image(systemName: icon)
                                }
                                Text(category.name)
                            }
                            .tag(category as Category?)
                        }
                    }
                } header: {
                    Text("Category")
                } footer: {
                    Text("Automatically assign this category to transactions from this vendor")
                }

                Section {
                    Toggle("Default to Online Transaction", isOn: $defaultToOnlineTransaction)
                } header: {
                    Text("Transaction Type")
                } footer: {
                    Text("Transactions from this vendor will default to being marked as online")
                }
            }
            .formStyle(.grouped)
            .padding(20)
            .navigationTitle(vendor == nil ? "New Vendor" : "Edit Vendor")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveVendor()
                    }
                    .disabled(displayName.isEmpty)
                }
            }
        }
        .frame(width: 500, height: 400)
        .onAppear {
            print("🏪 VendorFormView appeared with \(categories.count) categories")
            if let vendor = vendor {
                displayName = vendor.displayName
                selectedCategory = categories.first(where: { $0.id == vendor.defaultCategoryId })
                defaultToOnlineTransaction = vendor.defaultToOnlineTransaction
            }
        }
    }

    private func saveVendor() {
        let normalizedName = displayName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        print("🏪 Saving vendor: '\(displayName)' (normalized: '\(normalizedName)')")
        print("🏪 Selected category: \(selectedCategory?.name ?? "None")")

        let newVendor = Vendor(
            id: vendor?.id ?? UUID(),
            name: normalizedName,
            displayName: displayName,
            defaultCategoryId: selectedCategory?.id,
            defaultToOnlineTransaction: defaultToOnlineTransaction,
            createdAt: vendor?.createdAt ?? Date(),
            updatedAt: Date()
        )

        print("🏪 Calling onSave with vendor: \(newVendor)")
        onSave(newVendor)
        dismiss()
    }
}
