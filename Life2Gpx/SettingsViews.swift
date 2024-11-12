//
//  SettingsView.swift
//  Life2Gpx
//
//  Created by Marco Carandente on 17.10.2024.
//
import Foundation
import SwiftUI
import MapKit

struct SettingsView: View {
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        NavigationView {
            List {
                NavigationLink(destination: ManagePlacesView()) {
                    Text("Manage places")
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

struct ManagePlacesView: View {
    @StateObject private var viewModel: ManagePlacesViewModel
    @State private var searchText = ""
    @State private var selectedPlace: Place?
    @State private var selectedPair: (Place, Place)?
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var region = MKCoordinateRegion()
    @State private var duplicatePairs: [(Place, Place)] = []

    // Public initializer to allow external setup
    init(viewModel: ManagePlacesViewModel = ManagePlacesViewModel()) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }
    
    var filteredPlaces: [Place] {
        if searchText.isEmpty {
            return viewModel.places
        } else {
            return viewModel.places.filter { place in
                place.name.localizedCaseInsensitiveContains(searchText) ||
                (place.streetAddress?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
    }
    
    var body: some View {
        NavigationView {
            VStack {
                if let selectedPair = selectedPair {
                    // Map view showing both places in the selected pair with distinct colors
                    Map(position: $cameraPosition, interactionModes: .all) {
                        // First place marker in the pair
                        Annotation(selectedPair.0.name, coordinate: selectedPair.0.coordinate) {
                            ZStack {
                                Circle()
                                    .fill(Color.blue)
                                    .frame(width: 10, height: 10)
                            }
                        }
                        // Second place marker in the pair
                        Annotation(selectedPair.1.name, coordinate: selectedPair.1.coordinate) {
                            ZStack {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 10, height: 10)
                            }
                        }
                        // Circle representing the radius for both places
                        MapCircle(center: selectedPair.0.coordinate, radius: selectedPair.0.radius)
                            .stroke(Color.blue.opacity(1), lineWidth: 2)
                            .foregroundStyle(Color.blue.opacity(0.5))
                        MapCircle(center: selectedPair.1.coordinate, radius: selectedPair.1.radius)
                            .stroke(Color.green.opacity(1), lineWidth: 2)
                            .foregroundStyle(Color.green.opacity(0.5))
                    }
                    .frame(height: 300)
                    .onAppear {
                        // Adjust camera to center between the two places
                        setRegion(for: selectedPair)
                    }
                } else if let selectedPlace = selectedPlace {
                    Map(position: $cameraPosition, interactionModes: .all) {
                        // Single place marker in the normal map view
                        Annotation(selectedPlace.name, coordinate: selectedPlace.coordinate) {
                            ZStack {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 10, height: 10)
                            }
                        }
                        MapCircle(center: selectedPlace.coordinate, radius: selectedPlace.radius)
                            .stroke(Color.red.opacity(1), lineWidth: 2)
                            .foregroundStyle(Color.orange.opacity(0.5))
                    }
                    .frame(height: 300)
                    .onAppear {
                        setRegion(selectedPlace.coordinate)
                    }
                }
                Group {
                    if !duplicatePairs.isEmpty {
                        // Header showing duplicate count and the list of duplicate pairs
                        List {
                            Section(header: Text("\(duplicatePairs.count) duplicates found")) {
                                ForEach(duplicatePairs, id: \.0.placeId) { (place1, place2) in
                                    Button(action: {
                                        selectedPair = (place1, place2)
                                        setRegion(for: (place1, place2))
                                        cameraPosition = .region(MKCoordinateRegion(
                                            center: place1.coordinate,
                                            span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)))
                                    }) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            placeDetails(place: place1)
                                            placeDetails(place: place2)
                                            Divider()
                                        }
                                    }
                                }
                            }
                        }
                        .navigationBarItems(trailing: Button("Done") {
                            duplicatePairs.removeAll()
                            selectedPair = nil
                        })
                    } else {
                        List {
                            ForEach(filteredPlaces) { place in
                                Button(action: {
                                    selectedPlace = place
                                    setRegion(place.coordinate)
                                    cameraPosition = .region(MKCoordinateRegion(
                                        center: place.coordinate,
                                        span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                                    ))
                                }) {
                                    VStack(alignment: .leading) {
                                        Text(place.name)
                                            .font(.headline)
                                        Text("Radius: \(Int(place.radius)) meters")
                                            .font(.subheadline)
                                        Text("Latitude: \(place.center.latitude), Longitude: \(place.center.longitude)")
                                            .font(.footnote)
                                        Text("ID: \(place.placeId)")
                                            .font(.footnote)
                                        if let streetAddress = place.streetAddress {
                                            Text("Address: \(streetAddress)")
                                                .font(.footnote)
                                        }
                                        if let secondsFromGMT = place.secondsFromGMT {
                                            Text("Seconds from GMT: \(secondsFromGMT)")
                                                .font(.footnote)
                                        }
                                        if let lastSaved = place.lastSaved {
                                            Text("Last Saved: \(lastSaved)")
                                                .font(.footnote)
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        }
                        .navigationBarItems(trailing: Button("Duplicates") {
                            duplicatePairs = PlaceManager.shared.findDuplicatePlaces()
                        })
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
                .navigationTitle("Places")
                .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search Places")
            }
        }.navigationViewStyle(StackNavigationViewStyle())
    }
    
    private func setRegion(for pair: (Place, Place)) {
        let coordinateSpan = MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        let averageLatitude = (pair.0.coordinate.latitude + pair.1.coordinate.latitude) / 2
        let averageLongitude = (pair.0.coordinate.longitude + pair.1.coordinate.longitude) / 2
        region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: averageLatitude, longitude: averageLongitude),
            span: coordinateSpan
        )
    }

    private func setRegion(_ coordinate: CLLocationCoordinate2D) {
        region = MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )
    }

    // Helper function to show place details
    private func placeDetails(place: Place) -> some View {
        VStack(alignment: .leading) {
            Text("Name: \(place.name)")
            Text("Radius: \(Int(place.radius)) meters")
            Text("Latitude: \(place.center.latitude), Longitude: \(place.center.longitude)")
            Text("ID: \(place.placeId)")
            if let streetAddress = place.streetAddress {
                Text("Address: \(streetAddress)")
            }
            if let secondsFromGMT = place.secondsFromGMT {
                Text("Seconds from GMT: \(secondsFromGMT)")
            }
            if let lastSaved = place.lastSaved {
                Text("Last Saved: \(lastSaved)")
            }
        }
        .font(.footnote)
    }
}


struct ManagePlacesView_Previews: PreviewProvider {
    static var previews: some View {
        ManagePlacesView(viewModel: ManagePlacesViewModel.preview)
    }
}
