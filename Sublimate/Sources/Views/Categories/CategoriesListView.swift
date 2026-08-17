import SwiftUI

/// View displaying list of categories
struct CategoriesListView: View {
    @StateObject private var viewModel = CategoriesViewModel()
    @State private var showingAddCategory = false
    @State private var editingCategory: Category?

    var body: some View {
        List {
            ForEach(viewModel.categories) { category in
                CategoryRow(category: category)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        editingCategory = category
                    }
            }
            .onDelete(perform: deleteCategories)
        }
        .navigationTitle("Categories")
        .toolbar {
            Button(action: { showingAddCategory = true }) {
                Image(systemName: "plus")
            }
        }
        .sheet(isPresented: $showingAddCategory) {
            CategoryFormView(category: nil, onSave: { newCategory in
                viewModel.addCategory(newCategory)
                showingAddCategory = false
            })
        }
        .sheet(item: $editingCategory) { category in
            CategoryFormView(category: category, onSave: { updatedCategory in
                viewModel.updateCategory(updatedCategory)
                editingCategory = nil
            })
        }
        .onAppear {
            viewModel.loadCategories()
        }
    }

    private func deleteCategories(at offsets: IndexSet) {
        for index in offsets {
            viewModel.deleteCategory(viewModel.categories[index])
        }
    }
}

struct CategoryRow: View {
    let category: Category

    var body: some View {
        HStack(spacing: 12) {
            if let icon = category.icon {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(.accentColor)
                    .frame(width: 24, height: 24)
            }

            Text(category.name)
                .font(.body)

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Category Form
struct CategoryFormView: View {
    let category: Category?
    let onSave: (Category) -> Void

    @State private var name = ""
    @State private var selectedIcon: String?
    @Environment(\.dismiss) private var dismiss

    private var isValid: Bool {
        !name.isEmpty
    }

    // Common SF Symbols for categories
    private let availableIcons = [
        ("fork.knife", "Dining"),
        ("cart", "Shopping"),
        ("fuelpump", "Gas"),
        ("airplane", "Travel"),
        ("bag", "Retail"),
        ("theatermasks", "Entertainment"),
        ("bolt", "Utilities"),
        ("cross.case", "Healthcare"),
        ("car", "Transportation"),
        ("hammer", "Home"),
        ("laptopcomputer", "Electronics"),
        ("arrow.triangle.2.circlepath", "Subscriptions"),
        ("ellipsis.circle", "Other")
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Category Details") {
                    TextField("Category Name", text: $name)
                        .frame(minWidth: 300)
                        .help("e.g., Dining, Groceries, Gas")
                }

                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            // None option
                            iconOption(icon: nil, label: "None")

                            ForEach(availableIcons, id: \.0) { icon, label in
                                iconOption(icon: icon, label: label)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                } header: {
                    Text("Icon (Optional)")
                } footer: {
                    Text("Select an icon to help identify this category")
                        .font(.caption)
                }
            }
            .formStyle(.grouped)
            .padding(20)
            .navigationTitle(category == nil ? "New Category" : "Edit Category")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let newCategory = Category(
                            id: category?.id ?? UUID(),
                            name: name,
                            icon: selectedIcon
                        )
                        onSave(newCategory)
                    }
                    .disabled(!isValid)
                }
            }
        }
        .frame(width: 500, height: 400)
        .onAppear {
            if let category = category {
                name = category.name
                selectedIcon = category.icon
            }
        }
    }

    @ViewBuilder
    private func iconOption(icon: String?, label: String) -> some View {
        VStack(spacing: 4) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(selectedIcon == icon ? .white : .primary)
                    .frame(width: 44, height: 44)
                    .background(selectedIcon == icon ? Color.accentColor : Color.primary.opacity(0.08))
                    .cornerRadius(8)
            } else {
                Text("—")
                    .font(.title2)
                    .foregroundColor(selectedIcon == nil ? .white : .secondary)
                    .frame(width: 44, height: 44)
                    .background(selectedIcon == nil ? Color.accentColor : Color.primary.opacity(0.08))
                    .cornerRadius(8)
            }

            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .onTapGesture {
            selectedIcon = icon
        }
    }
}
