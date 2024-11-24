//
//  SettingsView.swift
//  Life2Gpx
//
//  Created by Marco Carandente on 17.10.2024.
//

import SwiftUI

struct SettingsView: View {
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
                Text("Edit activity rules")
                Text("GPX Tidy up")
                Text("Settings")
                Text("Data import instructions")
            }
            .navigationTitle("Options")
            .navigationBarItems(trailing: Button("Done") {
                presentationMode.wrappedValue.dismiss()
            })
        }
    }
}
