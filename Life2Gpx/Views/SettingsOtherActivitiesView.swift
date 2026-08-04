import SwiftUI

struct OtherActivitiesView: View {
    @ObservedObject var preferencesManager = PreferencesManager.shared
    @State private var searchText = ""

    private var otherActivitiesCount: Int {
        preferencesManager.trackTypes.filter { type in
            type.category == .otherWorkouts &&
            (searchText.isEmpty ||
             type.name.localizedCaseInsensitiveContains(searchText) ||
             type.id.localizedCaseInsensitiveContains(searchText))
        }.count
    }

    var body: some View {
        List {
            Section(
                header: Text("Activities confined in a place (\(otherActivitiesCount))"),
                footer: Text("These activities usually take place in a fixed location (e.g. gym, court, home) and do not involve spatial movement across long distances.")
            ) {
                ForEach($preferencesManager.trackTypes) { $trackType in
                    if trackType.category == .otherWorkouts &&
                        (searchText.isEmpty ||
                         trackType.name.localizedCaseInsensitiveContains(searchText) ||
                         trackType.id.localizedCaseInsensitiveContains(searchText)) {
                        NavigationLink(destination: EditTrackTypeView(trackType: $trackType)) {
                            HStack {
                                PlaceIconView(icon: trackType.icon, fallbackColor: trackType.color)
                                    .frame(width: 30)
                                Text(trackType.name)
                                Spacer()
                                Text(trackType.id)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search confined activities")
        .navigationTitle("Other Activities")
    }
}

#Preview {
    NavigationView {
        OtherActivitiesView()
    }
}
