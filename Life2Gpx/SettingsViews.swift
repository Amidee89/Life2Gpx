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
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var region = MKCoordinateRegion()
    
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
                    if let selectedPlace = selectedPlace {
                       Map(position: $cameraPosition, interactionModes: .all) {
                           // Marker for the selected place
                           Annotation(selectedPlace.name, coordinate: selectedPlace.coordinate) {
                               ZStack {
                                   Circle()
                                       .fill(Color.red)
                                       .frame(width: 10, height: 10)
                               }
                           }
                           // Circle to represent the radius
                           MapCircle(center: selectedPlace.coordinate, radius: selectedPlace.radius)
                               .stroke(Color.red.opacity(1), lineWidth: 2)
                               .foregroundStyle(Color.orange.opacity(0.5))
                           
                       }
                       .onAppear {
                           setRegion(selectedPlace.coordinate)
                       }
                       .onChange(of: selectedPlace) {
                           let coordinate = selectedPlace.coordinate
                           setRegion(coordinate)
                       }
                       .frame(height: 300)
                    }
                    List {
                        ForEach(filteredPlaces) { place in
                            // Make the row tappable
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
                    .navigationTitle("Places")
                    .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search Places")
                }
            }
        }
    
    private func setRegion(_ coordinate: CLLocationCoordinate2D) {
        region = MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )
    }
}

struct ManagePlacesView_Previews: PreviewProvider {
    static var previews: some View {
        ManagePlacesView(viewModel: ManagePlacesViewModel.preview)
    }
}
