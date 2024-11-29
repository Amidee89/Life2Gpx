//
//  ManagePlaceView.swift
//  Life2Gpx
//
//  Created by Marco Carandente on 18.11.2024.
//

import SwiftUI
import MapKit

struct ManagePlacesView: View {
    @StateObject private var viewModel: ManagePlacesViewModel
    @State private var searchText = ""
    @State private var selectedPlace: Place?
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var region = MKCoordinateRegion()
    @State private var isEditingPlace = false

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

                List {
                    ForEach(filteredPlaces) { place in
                        HStack {
                            VStack(alignment: .leading) {
                                Text("\(place.name)")
                                if let streetAddress = place.streetAddress {
                                    Text("Address: \(streetAddress)")
                                }
                                Text("Radius: \(Int(place.radius)) meters")
                            }
                            .onTapGesture {
                                selectedPlace = place
                                //111000 meters per degree approx
                                let radiusInDegrees = (place.radius * 2.2) / 111000 
                                let minimumSpan = 10.0 / 111000 
                                let span = max(radiusInDegrees, minimumSpan)
                                
                                cameraPosition = .region(MKCoordinateRegion(
                                    center: place.coordinate,
                                    span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)
                                ))
                            }
                            Spacer()

                            if selectedPlace == place {
                                Button(action: {
                                    isEditingPlace = true
                                }) {
                                    Image(systemName: "pencil")
                                        .foregroundColor(.blue)
                                }
                                .padding(.trailing)
                                .zIndex(10) // Ensure button is above other elements
                            }
                        }
                        .padding()
                        .background(
                            selectedPlace == place
                                ? Color.blue.opacity(0.2)
                                : Color.clear
                        )

                        .cornerRadius(8)
               
                        .overlay(
                            selectedPlace == place ? Color.clear : Color.clear
                        )
                    }
                }
                .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search Places")
            }
            .navigationTitle("Places")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $isEditingPlace) {
                if let selectedPlace = selectedPlace {
                    EditPlaceView(place: selectedPlace)
                        .onDisappear {
                            // Reload data when EditPlaceView disappears
                            viewModel.loadPlaces()
                        }
                }
            }
        }
    }

    private func setRegion(_ coordinate: CLLocationCoordinate2D) {
        region = MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )
    }


    private func placeDetails(place: Place) -> some View {
        VStack(alignment: .leading) {
            Text("Name: \(place.name)")
            if let streetAddress = place.streetAddress {
                Text("Address: \(streetAddress)")
            }
            Text("Radius: \(Int(place.radius)) meters")
            Text("Latitude: \(place.center.latitude), Longitude: \(place.center.longitude)")
            HStack {
                Spacer()
                Button("Edit") {
                    selectedPlace = place
                    isEditingPlace = true
                }
                .padding(.top, 8)
            }
        }
        .padding(.vertical, 4)
    }
}

struct ManagePlacesView_Previews: PreviewProvider {
    static var previews: some View {
        ManagePlacesView(viewModel: ManagePlacesViewModel.preview)
    }
}
