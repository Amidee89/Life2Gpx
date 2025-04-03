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
    @State private var visibleRegion: MKCoordinateRegion?
    @State private var isEditingPlace = false
    @State private var isCreatingPlace = false
    @State private var userLocation: CLLocationCoordinate2D?
    @State private var isMapLoaded = false

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
    
    var visiblePlaces: [Place] {
        let startTime = CFAbsoluteTimeGetCurrent()
        defer {
            let timeElapsed = CFAbsoluteTimeGetCurrent() - startTime
            print("Time to calculate visiblePlaces: \(timeElapsed * 1000) ms")
        }
        
        guard let region = visibleRegion else {
            // If no visible region yet, return places near user or a limited set
            if let userLocation = userLocation {
                // Return places within 10km of user location
                let filterStartTime = CFAbsoluteTimeGetCurrent()
                let nearbyPlaces = filteredPlaces.filter { place in
                    let placeLocation = CLLocation(latitude: place.coordinate.latitude, 
                                                  longitude: place.coordinate.longitude)
                    let userLoc = CLLocation(latitude: userLocation.latitude, 
                                            longitude: userLocation.longitude)
                    return placeLocation.distance(from: userLoc) <= 10000 // 10km radius
                }
                let filterTime = CFAbsoluteTimeGetCurrent() - filterStartTime
                print("Time to filter by distance: \(filterTime * 1000) ms")
                print("Loading \(nearbyPlaces.count) places within 10km of user location")
                return nearbyPlaces
            } else {
                // If no user location, return first 20 places or all if less than 20
                let limitedPlaces = Array(filteredPlaces.prefix(20))
                print("Loading \(limitedPlaces.count) places (limited to 20) due to no user location")
                return limitedPlaces
            }
        }
        
        // Calculate the visible region bounds with some padding
        let minLat = region.center.latitude - (region.span.latitudeDelta * 0.6)
        let maxLat = region.center.latitude + (region.span.latitudeDelta * 0.6)
        let minLon = region.center.longitude - (region.span.longitudeDelta * 0.6)
        let maxLon = region.center.longitude + (region.span.longitudeDelta * 0.6)
        
        // Filter places to only those within the visible region
        let filterStartTime = CFAbsoluteTimeGetCurrent()
        let visiblePlaces = filteredPlaces.filter { place in
            let lat = place.coordinate.latitude
            let lon = place.coordinate.longitude
            return lat >= minLat && lat <= maxLat && lon >= minLon && lon <= maxLon
        }
        let filterTime = CFAbsoluteTimeGetCurrent() - filterStartTime
        print("Time to filter by region: \(filterTime * 1000) ms")
        
        print("Loading \(visiblePlaces.count) places in visible map region")
        return visiblePlaces
    }

    var body: some View {
        NavigationView {
            VStack {
                Map(position: $cameraPosition, interactionModes: .all) {
                    // Only render annotations if map is loaded to prevent initial overload
                    if isMapLoaded {
                        ForEach(visiblePlaces) { place in
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
                    
                    // Add user location marker
                    if let userLocation = userLocation {
                        Marker("Current Location", coordinate: userLocation)
                            .tint(.blue)
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
                                    if let userLocation = userLocation {
                                        cameraPosition = .region(MKCoordinateRegion(
                                            center: userLocation,
                                            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                                        ))
                                    }
                                }
                            }
                    }
                    .padding(.trailing, 16)
                    .padding(.bottom, 16)
                    .allowsHitTesting(true)
                    .zIndex(1)
                }
                .onAppear {
                    print("Total places in viewModel: \(viewModel.places.count)")
                    viewModel.loadPlaces()
                    print("Places after loading: \(viewModel.places.count)")
                    
                    // Get user's current location
                    if let location = CLLocationManager().location?.coordinate {
                        userLocation = location
                        print("User location found: \(location.latitude), \(location.longitude)")
                        
                        // Set initial region to 3km around user (even smaller initial view)
                        let region = MKCoordinateRegion(
                            center: location,
                            latitudinalMeters: 3000, // Reduced from 5km to 3km
                            longitudinalMeters: 3000
                        )
                        cameraPosition = .region(region)
                        visibleRegion = region
                    } else if let firstPlace = filteredPlaces.first {
                        print("No user location, centering on first place")
                        setRegion(firstPlace.coordinate)
                    }
                }
                .mapStyle(.standard)
                .onMapCameraChange { context in
                    // Update visible region when map moves
                    visibleRegion = context.region
                    isMapLoaded = true
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
                    // Use user location if available, otherwise default
                    let defaultCoordinate = userLocation ?? CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
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
                    customIcon: nil,
                    elevation: nil
                ), isNewPlace: true)
                .onDisappear {
                    viewModel.loadPlaces()
                }
            }
        }
    }

    private func setRegion(_ coordinate: CLLocationCoordinate2D) {
        let region = MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )
        cameraPosition = .region(region)
        visibleRegion = region
    }


    private func placeDetails(place: Place) -> some View {
        VStack(alignment: .leading) {
            Text("Name: \(place.name)")
            if let streetAddress = place.streetAddress {
                Text("Address: \(streetAddress)")
            }
            Text("Radius: \(Int(place.radius)) meters")
            Text("Latitude: \(place.center.latitude), Longitude: \(place.center.longitude)")
            if let elevation = place.elevation {
                Text("Elevation: \(String(format: "%.1f", elevation)) meters")
            }
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
