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
    @State private var isLoadingMore = false
    @State private var errorMessage: String?
    @State private var searchQuery: String = ""
    @State private var currentLimit: Int = 10
    @FocusState private var isSearchFocused: Bool

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

                searchBar
                    .padding(.horizontal)
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

    private var searchBar: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.subheadline)
                TextField("Search by name...", text: $searchQuery)
                    .font(.subheadline)
                    .textFieldStyle(.plain)
                    .focused($isSearchFocused)
                    .submitLabel(.search)
                    .onSubmit {
                        currentLimit = 10
                        performSearch()
                    }
                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                        currentLimit = 10
                        performSearch()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color(.systemGray6))
            .cornerRadius(10)
        }
    }

    @ViewBuilder
    private var resultsArea: some View {
        if isSearching && !isLoadingMore {
            VStack(spacing: 4) {
                ProgressView("Searching \(selectedProvider?.displayName ?? "")...")
                if !searchQuery.isEmpty {
                    Text("for \"\(searchQuery)\"")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
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
            currentLimit = 10
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
                    if !searchQuery.isEmpty {
                        Text("· \"\(searchQuery)\"")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text("\(searchResults.count) results")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }

            List {
                ForEach(searchResults) { result in
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

                if !searchResults.isEmpty {
                    Button {
                        loadMore()
                    } label: {
                        HStack {
                            Spacer()
                            if isLoadingMore {
                                ProgressView()
                                    .controlSize(.small)
                                    .padding(.trailing, 4)
                                Text("Loading...")
                                    .font(.subheadline)
                            } else {
                                Image(systemName: "arrow.down.circle")
                                Text("Search More")
                                    .font(.subheadline)
                            }
                            Spacer()
                        }
                        .foregroundColor(.blue)
                        .padding(.vertical, 4)
                    }
                    .disabled(isLoadingMore)
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

        let query = searchQuery.isEmpty ? nil : searchQuery
        let limit = currentLimit

        Task {
            do {
                let results = try await PlaceSearchService.shared.search(near: coordinate, provider: provider, query: query, limit: limit)
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

    private func loadMore() {
        guard let provider = selectedProvider, !isLoadingMore else { return }
        isLoadingMore = true
        let newLimit = currentLimit + 10

        let query = searchQuery.isEmpty ? nil : searchQuery

        Task {
            do {
                let results = try await PlaceSearchService.shared.search(near: coordinate, provider: provider, query: query, limit: newLimit)
                await MainActor.run {
                    currentLimit = newLimit
                    searchResults = results
                    isLoadingMore = false
                }
            } catch {
                await MainActor.run {
                    isLoadingMore = false
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
