import SwiftUI

struct EditVisitView: View {
    @Environment(\.dismiss) private var dismiss
    let timelineObject: TimelineObject
    var onSave: (String) -> Void
    
    @State private var placeName: String = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Place name", text: $placeName)
                }
            }
            .navigationTitle("Edit Visit")
            .navigationBarItems(
                leading: Button("Cancel") {
                    dismiss()
                },
                trailing: Button("Save") {
                    onSave(placeName)
                    dismiss()
                }
            )
        }
    }
} 