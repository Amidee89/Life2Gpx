import SwiftUI
import CoreLocation

struct PlaceSearchView: View {
    let coordinate: CLLocationCoordinate2D
    let selectedIds: [PlaceProvider: String]
    let onSelect: (PlaceSearchResult) -> Void
    let onDone: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedProvider: PlaceProvider?
    @State private var searchResults: [PlaceSearchResult] = []
    @State private var isSearching = false
    @State private var errorMessage: String?

    private var configuredProviders: [PlaceProvider] {
        PlaceSearchService.configuredProviders()
    }

    var body: some View {
        VStack(spacing: 0) {
            if configuredProviders.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "key.slash")
                        .font(.title)
                        .foregroundColor(.secondary)
                    Text("No providers configured")
                        .font(.headline)
                    Text("Add API keys in Options → API Keys")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button("Done") { onDone() }
                        .padding(.top, 8)
                }
                .padding()
            } else {
                providerSelector
                    .padding(.top, 8)

                Divider()
                    .padding(.top, 8)

                resultsArea
                    .frame(maxHeight: .infinity)

                Button("Done") { onDone() }
                    .buttonStyle(.borderless)
                    .foregroundColor(.blue)
                    .padding(.bottom, 8)
            }
        }
    }

    @ViewBuilder
    private var resultsArea: some View {
        if isSearching {
            ProgressView("Searching \(selectedProvider?.displayName ?? "")...")
                .padding()
        } else if let error = errorMessage {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title2)
                    .foregroundColor(.orange)
                Text(error)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
                HStack(spacing: 16) {
                    Button("Retry") { performSearch() }
                        .buttonStyle(.borderless)
                    Button("Copy Error") {
                        UIPasteboard.general.string = error
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.secondary)
                    .font(.caption)
                }
            }
            .padding()
        } else if searchResults.isEmpty && selectedProvider != nil {
            Text("No places found nearby")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding()
        } else {
            resultsList
        }
    }

    private var providerSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(configuredProviders) { provider in
                    Button {
                        selectedProvider = provider
                    } label: {
                        Image(provider.iconAssetName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 26, height: 26)
                            .offset(x: provider == .openStreetMap ? 0.85 : 0, y: provider == .openStreetMap ? 1 : 0)
                            .frame(width: 26, height: 26, alignment: .center)
                            .clipped()
                            .padding(7)
                            .background(
                                Circle()
                                    .fill(colorScheme == .dark
                                          ? Color(white: 0.88)
                                          : (selectedProvider == provider ? provider.color.opacity(0.15) : Color.white))
                            )
                            .overlay(
                                Circle()
                                    .stroke(selectedProvider == provider ? provider.color : Color.gray.opacity(0.3), lineWidth: selectedProvider == provider ? 2.5 : 1)
                            )
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
        .onAppear {
            if selectedProvider == nil {
                selectedProvider = configuredProviders.first
            }
        }
        .onChange(of: selectedProvider) { _ in
            performSearch()
        }
    }

    private var resultsList: some View {
        VStack(spacing: 0) {
            if let provider = selectedProvider {
                HStack {
                    Text(provider.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }

            List(searchResults) { result in
                Button {
                    onSelect(result)
                } label: {
                    HStack(spacing: 10) {
                        if isResultSelected(result) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.title3)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.name)
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(.primary)
                            if let address = result.address {
                                Text(address)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        Spacer()
                        let distance = coordinate.distance(to: result.coordinate)
                        Text(distance < 1000 ? String(format: "%.0f m", distance) : String(format: "%.1f km", distance / 1000))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    private func isResultSelected(_ result: PlaceSearchResult) -> Bool {
        guard let selectedId = selectedIds[result.provider] else { return false }
        return selectedId == result.id
    }

    private func performSearch() {
        guard let provider = selectedProvider else { return }
        isSearching = true
        errorMessage = nil
        searchResults = []

        Task {
            do {
                let results = try await PlaceSearchService.shared.search(near: coordinate, provider: provider)
                await MainActor.run {
                    searchResults = results
                    isSearching = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isSearching = false
                }
            }
        }
    }
}

#Preview {
    PlaceSearchView(
        coordinate: CLLocationCoordinate2D(latitude: 41.9028, longitude: 12.4964),
        selectedIds: [:],
        onSelect: { _ in },
        onDone: { }
    )
}
