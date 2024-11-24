//
//  FindDuplicatesView.swift
//  Life2Gpx
//
//  Created by Marco Carandente on 18.11.2024.
//

import SwiftUI
import MapKit

struct FindDuplicatesView: View {
    @State private var duplicatePairs: [(Place, Place)] = []
    @State private var selectedPair: (Place, Place)?
    @State private var cameraPosition: MapCameraPosition = .automatic

    var body: some View {
        NavigationView {
            VStack {
                if let selectedPair = selectedPair {
                    Map(position: $cameraPosition, interactionModes: .all) {
                        Annotation(selectedPair.0.name, coordinate: selectedPair.0.coordinate) {
                            ZStack {
                                Circle()
                                    .fill(Color.blue)
                                    .frame(width: 10, height: 10)
                            }
                        }
                        Annotation(selectedPair.1.name, coordinate: selectedPair.1.coordinate) {
                            ZStack {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 10, height: 10)
                            }
                        }
                    }
                    .frame(height: 300)
                }

                if !duplicatePairs.isEmpty {
                    List {
                        Section(header: Text("\(duplicatePairs.count) duplicates found")) {
                            ForEach(duplicatePairs, id: \.0.placeId) { (place1, place2) in
                                Button(action: {
                                    selectedPair = (place1, place2)
                                }) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(place1.name)
                                        Text(place2.name)
                                        Divider()
                                    }
                                }
                            }
                        }
                    }
                } else {
                    Text("No duplicates found.")
                        .foregroundColor(.gray)
                        .padding()
                }
            }
            .onAppear {
                duplicatePairs = PlaceManager.shared.findDuplicatePlaces()
            }
            .navigationTitle("Find Duplicates")
        }
    }
}

struct FindDuplicatesView_Previews: PreviewProvider {
    static var previews: some View {
        FindDuplicatesView()
    }
}
