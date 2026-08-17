import SwiftUI
import AppKit
import Combine

struct DatabaseSettingsView: View {
    @StateObject private var viewModel = DatabaseSettingsViewModel()
    @State private var showingCreateDialog = false
    @State private var newDatabaseName = ""
    @State private var showingError = false
    @State private var errorMessage = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Current Database
            VStack(alignment: .leading, spacing: 8) {
                Text("Current Database")
                    .font(.headline)

                if let path = viewModel.currentDatabasePath {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(URL(fileURLWithPath: path).lastPathComponent)
                                .font(.body)
                            Text(path)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Button("Show in Finder") {
                            NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
                        }
                    }
                    .padding()
                    .cardBackground(cornerRadius: 8)
                }
            }

            Divider()

            // Database Actions
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Button(action: { showingCreateDialog = true }) {
                        Label("Create New Database", systemImage: "plus.circle")
                    }

                    Button(action: { selectExistingDatabase() }) {
                        Label("Open Existing Database", systemImage: "folder")
                    }

                    Button(action: { viewModel.loadDatabaseFiles() }) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }

                Text("Database files must be in the app's container. The file picker will open in the correct location.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            // Available Databases
            VStack(alignment: .leading, spacing: 8) {
                Text("Available Databases")
                    .font(.headline)

                if viewModel.databaseFiles.isEmpty {
                    Text("No database files found")
                        .foregroundColor(.secondary)
                        .padding()
                } else {
                    List {
                        ForEach(viewModel.databaseFiles) { fileInfo in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(fileInfo.name)
                                            .font(.body)
                                        if fileInfo.isCurrent {
                                            Text("(Current)")
                                                .font(.caption)
                                                .foregroundColor(.blue)
                                        }
                                    }
                                    Text("\(fileInfo.formattedSize) • Modified \(fileInfo.modifiedDate.toShortString())")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                if !fileInfo.isCurrent {
                                    Button("Switch") {
                                        switchToDatabase(fileInfo)
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .frame(height: 200)
                }
            }
        }
        .padding()
        .onAppear {
            viewModel.loadDatabaseFiles()
        }
        .sheet(isPresented: $showingCreateDialog) {
            createDatabaseDialog
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    private var createDatabaseDialog: some View {
        VStack(spacing: 16) {
            Text("Create New Database")
                .font(.headline)

            TextField("Database Name", text: $newDatabaseName)
                .textFieldStyle(.roundedBorder)

            Text("The .db extension will be added automatically")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack {
                Button("Cancel") {
                    showingCreateDialog = false
                    newDatabaseName = ""
                }

                Button("Create") {
                    createNewDatabase()
                }
                .buttonStyle(.borderedProminent)
                .disabled(newDatabaseName.isEmpty)
            }
        }
        .padding()
        .frame(width: 400)
    }

    private func createNewDatabase() {
        do {
            let path = try DatabaseManager.shared.createNewDatabase(name: newDatabaseName)
            print("✅ Created new database at: \(path)")
            showingCreateDialog = false
            newDatabaseName = ""
            viewModel.loadDatabaseFiles()
        } catch DatabaseError.fileAlreadyExists {
            errorMessage = "A database with this name already exists"
            showingError = true
        } catch {
            errorMessage = "Failed to create database: \(error.localizedDescription)"
            showingError = true
        }
    }

    private func selectExistingDatabase() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.database]
        panel.message = "Select a database file"

        // Start in the app's database directory (Container/Application Support)
        if let databaseDir = try? DatabaseManager.shared.getDatabaseDirectory() {
            panel.directoryURL = databaseDir
        }

        if panel.runModal() == .OK, let url = panel.url {
            switchToDatabase(url.path)
        }
    }

    private func switchToDatabase(_ fileInfo: DatabaseFileInfo) {
        switchToDatabase(fileInfo.path)
    }

    private func switchToDatabase(_ path: String) {
        do {
            try DatabaseManager.shared.switchDatabase(to: path)
            print("✅ Switched to database: \(path)")

            // Refresh the database list to show the new current database
            viewModel.loadDatabaseFiles()
        } catch {
            errorMessage = "Failed to switch database: \(error.localizedDescription)"
            showingError = true
        }
    }
}

@MainActor
class DatabaseSettingsViewModel: ObservableObject {
    @Published var databaseFiles: [DatabaseFileInfo] = []
    @Published var currentDatabasePath: String?

    func loadDatabaseFiles() {
        do {
            databaseFiles = try DatabaseManager.shared.listDatabaseFiles()
            currentDatabasePath = DatabaseManager.shared.getCurrentDatabasePath()
        } catch {
            print("Error loading database files: \(error)")
        }
    }
}
