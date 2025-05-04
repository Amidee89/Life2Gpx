//
//  SettingsView.swift
//  Life2Gpx
//
//  Created by Marco Carandente on 17.10.2024.
//

import SwiftUI

struct ManagementView: View {
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        NavigationView {
            List {
                NavigationLink(destination: ManagePlacesView()) {
                    Text("Manage places")
                }
                NavigationLink(destination: FindDuplicatesView()) {
                    Text("Find duplicate places")
                }
                NavigationLink(destination: ImportPlacesView()) {
                        Text("Import places")
                }
                .overlay(alignment: .trailing) {
                    
                }
                Text("Edit activity rules")
                Text("GPX Tidy up")
                NavigationLink(destination: SettingsView()) {
                    Text("Settings")
                }
                Text("Data import instructions")
            }
            .navigationTitle("Options")
            .navigationBarItems(trailing: Button("Done") {
                presentationMode.wrappedValue.dismiss()
            })
        }
    }
}

#Preview {
    ManagementView()
}
