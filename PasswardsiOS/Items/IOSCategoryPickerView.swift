import SwiftUI
import PasswardsCore

/// New-item type chooser: the 22 categories. Picking one pushes the editor for a
/// fresh item of that category; saving creates it and dismisses the whole sheet.
struct IOSCategoryPickerView: View {
    let vault: IOSVaultModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(PasswardsCore.Category.allCases, id: \.displayName) { category in
                    NavigationLink {
                        IOSItemEditorView(
                            vault: vault,
                            original: vault.newItem(category: category),
                            isNew: true,
                            showsCancel: false,
                            onClose: { dismiss() }
                        )
                    } label: {
                        HStack(spacing: 12) {
                            CategoryIcon(category: category, size: 32)
                            Text(category.displayName)
                        }
                    }
                }
            }
            .navigationTitle("Choose a Type")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .tint(Theme.accent)
    }
}
