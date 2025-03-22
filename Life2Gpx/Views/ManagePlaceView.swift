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
    @State private var isCreatingPlace = false
    @State private var userLocation: CLLocationCoordinate2D?

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
                Map(position: $cameraPosition, interactionModes: .all) {
                    ForEach(filteredPlaces) { place in
                        Annotation(place.name, coordinate: place.coordinate) {
                            ZStack {
                                Circle()
                                    .fill(selectedPlace == place ? Color.purple : Color.red)
                                    .frame(width: 10, height: 10)
                            }
                        }
                        MapCircle(center: place.coordinate, radius: place.radius)
                            .stroke(selectedPlace == place ? Color.purple.opacity(1) : Color.red.opacity(1), lineWidth: 2)
                            .foregroundStyle(selectedPlace == place ? Color.purple.opacity(0.5) : Color.orange.opacity(0.5))
                    }
                }
                .frame(height: 300)
                .overlay(alignment: .bottomTrailing) {
                    VStack(spacing: 10) {
                        Image(systemName: "location")
                            .font(.title)
                            .padding()
                            .background(Color.white)
                            .foregroundColor(.blue)
                            .clipShape(Circle())
                            .shadow(radius: 3)
                            .scaleEffect(0.8)
                            .contentShape(Circle())
                            .onTapGesture {
                                withAnimation {
                                    cameraPosition = .userLocation(followsHeading: false, fallback: .region(region))
                                }
                            }
                    }
                    .padding(.trailing, 16)
                    .padding(.bottom, 16)
                    .allowsHitTesting(true)
                    .zIndex(1)
                }
                .onAppear {
                    if let firstPlace = filteredPlaces.first {
                        setRegion(firstPlace.coordinate)
                    }
                    viewModel.loadPlaces()
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
            .toolbar {
                Button(action: {
                    // Directly set the coordinate and show the sheet
                    let defaultCoordinate = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
                    userLocation = defaultCoordinate
                    isCreatingPlace = true
                }) {
                    Image(systemName: "plus")
                }
            }
            .sheet(isPresented: $isEditingPlace) {
                if let selectedPlace {
                    EditPlaceView(place: selectedPlace)
                        .onDisappear {
                            viewModel.loadPlaces()
                            
                            if !viewModel.places.contains(where: { $0.placeId == selectedPlace.placeId }) {
                                self.selectedPlace = nil
                            }
                        }
                    
                }
            }
            .sheet(isPresented: $isCreatingPlace) {
                EditPlaceView(place: Place(
                    placeId: UUID().uuidString,
                    name: "",
                    center: Center(latitude: userLocation?.latitude ?? 37.7749, 
                                  longitude: userLocation?.longitude ?? -122.4194),
                    radius: 40,
                    streetAddress: nil,
                    secondsFromGMT: TimeZone.current.secondsFromGMT(),
                    lastSaved: ISO8601DateFormatter().string(from: Date()),
                    facebookPlaceId: nil,
                    mapboxPlaceId: nil,
                    foursquareVenueId: nil,
                    foursquareCategoryId: nil,
                    previousIds: nil,
                    lastVisited: nil,
                    isFavorite: nil,
                    customIcon: nil
                ), isNewPlace: true)
                .onDisappear {
                    viewModel.loadPlaces()
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
