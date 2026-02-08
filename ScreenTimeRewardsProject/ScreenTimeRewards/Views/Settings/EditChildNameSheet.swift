import SwiftUI

/// Sheet for editing the child's display name
struct EditChildNameSheet: View {
    @Environment(\.dismiss) private var dismiss

    let currentName: String
    var onSave: (String) -> Void

    @State private var newName: String = ""

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Child's Name", text: $newName)
                        .autocorrectionDisabled()
                } header: {
                    Text("Display Name")
                } footer: {
                    Text("This name will be shown on the parent's dashboard")
                }
            }
            .navigationTitle("Edit Name")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmedName.isEmpty {
                            onSave(trimmedName)
                        }
                        dismiss()
                    }
                    .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                newName = currentName
            }
        }
    }
}
