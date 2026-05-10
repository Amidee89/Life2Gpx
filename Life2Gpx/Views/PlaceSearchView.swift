import SwiftUI
import CoreLocation

struct PlaceSearchView: View {
    let coordinate: CLLocationCoordinate2D
    let onSelect: (PlaceSearchResult) -> Void
    let onCancel: () -> Void

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
                    Button("Cancel") { onCancel() }
                        .padding(.top, 8)
                }
                .padding()
            } else {
                providerSelector
                    .padding(.horizontal)
                    .padding(.top, 8)

                Divider()
                    .padding(.top, 8)

                resultsArea
                    .frame(maxHeight: .infinity)

                Button("Cancel") { onCancel() }
                    .buttonStyle(.borderless)
                    .foregroundColor(.red)
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
        HStack(spacing: 12) {
            ForEach(configuredProviders) { provider in
                Button {
                    selectedProvider = provider
                } label: {
                    VStack(spacing: 4) {
                        ZStack {
                            Circle()
                                .fill(selectedProvider == provider ? provider.color : provider.color.opacity(0.3))
                            Text(provider.initial)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                        }
                        .frame(width: 40, height: 40)

                        Text(provider.displayName)
                            .font(.system(size: 9))
                            .foregroundColor(selectedProvider == provider ? .primary : .secondary)
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
            }
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
        List(searchResults) { result in
            Button {
                onSelect(result)
            } label: {
                HStack {
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
