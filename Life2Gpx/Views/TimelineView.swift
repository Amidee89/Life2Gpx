//
//  TimelineView.swift
//  Life2Gpx
//
//  Created by Marco Carandente on 25.4.2024.
//

import SwiftUI
import MapKit
import CoreGPX
import Foundation
import Photos
import UIKit

private enum TimelineDisplayItem: Identifiable {
    case single(TimelineObject)
    case groupHeader(id: UUID, items: [TimelineObject], isExpanded: Bool)
    case groupChild(TimelineObject)

    var id: String {
        switch self {
        case .single(let obj): return "s-\(obj.id.uuidString)"
        case .groupHeader(let id, _, _): return "g-\(id.uuidString)"
        case .groupChild(let obj): return "c-\(obj.id.uuidString)"
        }
    }
}

private struct TimelinePhoto: Identifiable, Sendable {
    let id: String
    let pixelWidth: Int
    let pixelHeight: Int

    var aspectRatio: CGFloat {
        CGFloat(max(pixelWidth, 1)) / CGFloat(max(pixelHeight, 1))
    }
}

private struct TimelinePhotoSheet: Identifiable {
    let id = UUID()
    let photos: [TimelinePhoto]
    let initialPhotoID: String?
    let closesOnDetailBack: Bool

    init(photos: [TimelinePhoto], initialPhotoID: String? = nil, closesOnDetailBack: Bool = false) {
        self.photos = photos
        self.initialPhotoID = initialPhotoID
        self.closesOnDetailBack = closesOnDetailBack
    }
}

enum TimelinePhotoLog {
    static let context = "TimelinePhotos"

    static func dateString(_ date: Date) -> String {
        dateFormatter.string(from: date)
    }

    static func intervalString(_ interval: DateInterval) -> String {
        "\(dateString(interval.start)) -> \(dateString(interval.end)) (\(Int(interval.duration))s)"
    }

    static func shortKey(_ key: String) -> String {
        String(key.prefix(18))
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss ZZZZZ"
        return formatter
    }()
}

extension PHAuthorizationStatus {
    var timelineLogDescription: String {
        switch self {
        case .notDetermined:
            return "notDetermined"
        case .restricted:
            return "restricted"
        case .denied:
            return "denied"
        case .authorized:
            return "authorized"
        case .limited:
            return "limited"
        @unknown default:
            return "unknown(\(rawValue))"
        }
    }
}

@MainActor
private final class TimelinePhotoStore: ObservableObject {
    @Published private var photosByKey: [String: [TimelinePhoto]] = [:]
    @Published private(set) var authorizationStatus: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)

    private var loadingKeys: Set<String> = []
    private var loadingImageKeys: Set<String> = []
    private var loadingFullImageIDs: Set<String> = []
    private var imageRequestStartedAt: [String: Date] = [:]
    private var authorizationRequestTask: Task<PHAuthorizationStatus, Never>?
    private let imageManager = PHCachingImageManager()
    private let thumbnailCache = NSCache<NSString, UIImage>()
    private let previewCache = NSCache<NSString, UIImage>()
    private let fullImageCache = NSCache<NSString, UIImage>()

    var canReadPhotos: Bool {
        authorizationStatus == .authorized || authorizationStatus == .limited
    }

    init() {
        thumbnailCache.countLimit = 220
        thumbnailCache.totalCostLimit = 64 * 1024 * 1024
        previewCache.countLimit = 80
        previewCache.totalCostLimit = 96 * 1024 * 1024
        fullImageCache.countLimit = 4
        fullImageCache.totalCostLimit = 160 * 1024 * 1024

        FileManagerUtil.logData(
            context: TimelinePhotoLog.context,
            content: "Photo store initialized. Initial authorization status: \(authorizationStatus.timelineLogDescription)",
            verbosity: 4
        )
    }

    func photos(for key: String) -> [TimelinePhoto] {
        photosByKey[key] ?? []
    }

    func hasLoadedPhotos(for key: String) -> Bool {
        photosByKey[key] != nil
    }

    func thumbnail(for photo: TimelinePhoto, displaySize: CGSize, contentMode: PHImageContentMode) -> UIImage? {
        thumbnailCache.object(forKey: imageCacheKey(for: photo, displaySize: displaySize, contentMode: contentMode) as NSString)
    }

    func previewImage(for photo: TimelinePhoto) -> UIImage? {
        previewCache.object(forKey: photo.id as NSString)
    }

    func fullImage(for photo: TimelinePhoto) -> UIImage? {
        fullImageCache.object(forKey: photo.id as NSString)
    }

    func clear() {
        let inFlightThumbnails = loadingImageKeys.count
        let inFlightFullImages = loadingFullImageIDs.count
        if inFlightThumbnails > 0 || inFlightFullImages > 0 {
            FileManagerUtil.logData(
                context: TimelinePhotoLog.context,
                content: "Clearing photo cache while \(inFlightThumbnails) thumbnail and \(inFlightFullImages) full-image requests are still in flight — those tasks may never complete and can accumulate under memory pressure.",
                verbosity: 2
            )
            ResourceDiagnostics.logMemory(
                context: TimelinePhotoLog.context,
                detail: "Photo cache clear with in-flight PhotoKit requests."
            )
        }

        FileManagerUtil.logData(
            context: TimelinePhotoLog.context,
            content: "Clearing photo cache. Cached intervals: \(photosByKey.count), loading intervals: \(loadingKeys.count), loading images: \(loadingImageKeys.count), loading full images: \(loadingFullImageIDs.count)",
            verbosity: 4
        )
        photosByKey.removeAll()
        loadingKeys.removeAll()
        loadingImageKeys.removeAll()
        loadingFullImageIDs.removeAll()
        imageRequestStartedAt.removeAll()
        thumbnailCache.removeAllObjects()
        previewCache.removeAllObjects()
        fullImageCache.removeAllObjects()
    }

    @discardableResult
    func loadThumbnail(for photo: TimelinePhoto, displaySize: CGSize, contentMode: PHImageContentMode, allowsNetworkAccess: Bool = true) async -> UIImage? {
        let cacheKey = imageCacheKey(for: photo, displaySize: displaySize, contentMode: contentMode)
        if let cachedImage = thumbnailCache.object(forKey: cacheKey as NSString) {
            return cachedImage
        }
        guard !loadingImageKeys.contains(cacheKey) else {
            FileManagerUtil.logData(
                context: TimelinePhotoLog.context,
                content: "Thumbnail load blocked for asset \(photo.id.prefix(12)): already in flight (\(loadingImageKeys.count) total). Repeated blocks suggest a hung PhotoKit callback.",
                verbosity: 2
            )
            return nil
        }

        loadingImageKeys.insert(cacheKey)
        imageRequestStartedAt[cacheKey] = Date()
        logInFlightImagePressureIfNeeded(trigger: "thumbnail started \(photo.id.prefix(12))")
        defer {
            loadingImageKeys.remove(cacheKey)
            imageRequestStartedAt.removeValue(forKey: cacheKey)
            logInFlightImagePressureIfNeeded(trigger: "thumbnail finished \(photo.id.prefix(12))")
        }

        let authorizationStatus = await requestAuthorizationIfNeeded()
        guard authorizationStatus == .authorized || authorizationStatus == .limited else {
            FileManagerUtil.logData(
                context: TimelinePhotoLog.context,
                content: "Cannot load thumbnail for asset \(photo.id.prefix(12)): authorization status is \(authorizationStatus.timelineLogDescription)",
                verbosity: 4
            )
            return nil
        }

        guard let asset = fetchAsset(localIdentifier: photo.id) else {
            FileManagerUtil.logData(
                context: TimelinePhotoLog.context,
                content: "Cannot load thumbnail for asset \(photo.id.prefix(12)): PHAsset not found.",
                verbosity: 4
            )
            return nil
        }

        let targetSize = pixelTargetSize(for: displaySize)
        FileManagerUtil.logData(
            context: TimelinePhotoLog.context,
            content: "Requesting visible thumbnail for asset \(photo.id.prefix(12)). Display: \(Int(displaySize.width))x\(Int(displaySize.height)), target: \(Int(targetSize.width))x\(Int(targetSize.height))",
            verbosity: 5
        )

        guard let image = await requestImage(for: asset, targetSize: targetSize, contentMode: contentMode, allowsNetworkAccess: allowsNetworkAccess) else {
            FileManagerUtil.logData(
                context: TimelinePhotoLog.context,
                content: "Visible thumbnail request returned nil for asset \(photo.id.prefix(12))",
                verbosity: 4
            )
            return nil
        }

        thumbnailCache.setObject(image, forKey: cacheKey as NSString, cost: image.memoryCost)
        previewCache.setObject(image, forKey: photo.id as NSString, cost: image.memoryCost)
        return image
    }

    @discardableResult
    func loadFullImage(for photo: TimelinePhoto) async -> UIImage? {
        if let cachedImage = fullImageCache.object(forKey: photo.id as NSString) {
            FileManagerUtil.logData(
                context: TimelinePhotoLog.context,
                content: "Skipping full image load for asset \(photo.id.prefix(12)): cache hit.",
                verbosity: 5
            )
            return cachedImage
        }
        guard !loadingFullImageIDs.contains(photo.id) else {
            FileManagerUtil.logData(
                context: TimelinePhotoLog.context,
                content: "Full image load blocked for asset \(photo.id.prefix(12)): already in flight (\(loadingFullImageIDs.count) total). Repeated blocks suggest a hung PhotoKit callback.",
                verbosity: 2
            )
            return nil
        }

        loadingFullImageIDs.insert(photo.id)
        imageRequestStartedAt["full:\(photo.id)"] = Date()
        defer {
            loadingFullImageIDs.remove(photo.id)
            imageRequestStartedAt.removeValue(forKey: "full:\(photo.id)")
            logInFlightImagePressureIfNeeded(trigger: "full image finished \(photo.id.prefix(12))")
        }

        let authorizationStatus = await requestAuthorizationIfNeeded()
        guard authorizationStatus == .authorized || authorizationStatus == .limited else {
            FileManagerUtil.logData(
                context: TimelinePhotoLog.context,
                content: "Cannot load full image for asset \(photo.id.prefix(12)): authorization status is \(authorizationStatus.timelineLogDescription)",
                verbosity: 4
            )
            return nil
        }

        guard let asset = fetchAsset(localIdentifier: photo.id) else {
            FileManagerUtil.logData(
                context: TimelinePhotoLog.context,
                content: "Cannot load full image for asset \(photo.id.prefix(12)): PHAsset not found.",
                verbosity: 4
            )
            return nil
        }

        FileManagerUtil.logData(
            context: TimelinePhotoLog.context,
            content: "Requesting full image for asset \(photo.id.prefix(12)), size \(asset.pixelWidth)x\(asset.pixelHeight)",
            verbosity: 4
        )

        if let image = await requestFullImage(for: asset) {
            fullImageCache.setObject(image, forKey: photo.id as NSString, cost: image.memoryCost)
            previewCache.setObject(image, forKey: photo.id as NSString, cost: image.memoryCost)
            FileManagerUtil.logData(
                context: TimelinePhotoLog.context,
                content: "Loaded full image for asset \(photo.id.prefix(12)). Returned size: \(Int(image.size.width))x\(Int(image.size.height))",
                verbosity: 4
            )
            return image
        } else {
            FileManagerUtil.logData(
                context: TimelinePhotoLog.context,
                content: "Full image request returned nil for asset \(photo.id.prefix(12))",
                verbosity: 4
            )
            return nil
        }
    }

    @discardableResult
    func requestAuthorizationIfNeeded() async -> PHAuthorizationStatus {
        let currentStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        authorizationStatus = currentStatus
        FileManagerUtil.logData(
            context: TimelinePhotoLog.context,
            content: "Authorization check. Current status: \(currentStatus.timelineLogDescription)",
            verbosity: 5
        )

        guard currentStatus == .notDetermined else {
            return currentStatus
        }

        if let authorizationRequestTask {
            FileManagerUtil.logData(
                context: TimelinePhotoLog.context,
                content: "Authorization request already in progress. Awaiting existing request.",
                verbosity: 5
            )
            let status = await authorizationRequestTask.value
            authorizationStatus = status
            FileManagerUtil.logData(
                context: TimelinePhotoLog.context,
                content: "Existing authorization request completed with status: \(status.timelineLogDescription)",
                verbosity: 4
            )
            return status
        }

        FileManagerUtil.logData(
            context: TimelinePhotoLog.context,
            content: "Requesting photo library authorization.",
            verbosity: 4
        )
        let requestTask = Task<PHAuthorizationStatus, Never> {
            await withCheckedContinuation { continuation in
                PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                    continuation.resume(returning: status)
                }
            }
        }
        authorizationRequestTask = requestTask

        let status = await requestTask.value
        authorizationRequestTask = nil
        authorizationStatus = status
        FileManagerUtil.logData(
            context: TimelinePhotoLog.context,
            content: "Photo library authorization response: \(status.timelineLogDescription)",
            verbosity: 4
        )
        return status
    }

    func loadPhotos(for key: String, interval: DateInterval) async {
        let shortKey = TimelinePhotoLog.shortKey(key)
        if let cachedPhotos = photosByKey[key] {
            FileManagerUtil.logData(
                context: TimelinePhotoLog.context,
                content: "Skipping load for \(shortKey): cache hit with \(cachedPhotos.count) photos. Interval: \(TimelinePhotoLog.intervalString(interval))",
                verbosity: 5
            )
            return
        }

        guard !loadingKeys.contains(key) else {
            FileManagerUtil.logData(
                context: TimelinePhotoLog.context,
                content: "Skipping load for \(shortKey): already loading. Interval: \(TimelinePhotoLog.intervalString(interval))",
                verbosity: 5
            )
            return
        }

        loadingKeys.insert(key)
        defer { loadingKeys.remove(key) }

        FileManagerUtil.logData(
            context: TimelinePhotoLog.context,
            content: "Loading photos for \(shortKey). Interval: \(TimelinePhotoLog.intervalString(interval))",
            verbosity: 4
        )
        let authorizationStatus = await requestAuthorizationIfNeeded()
        guard authorizationStatus == .authorized || authorizationStatus == .limited else {
            FileManagerUtil.logData(
                context: TimelinePhotoLog.context,
                content: "Cannot load photos for \(shortKey): authorization status is \(authorizationStatus.timelineLogDescription)",
                verbosity: 4
            )
            photosByKey[key] = []
            return
        }

        let photos = await fetchPhotoRecords(from: interval.start, to: interval.end)
        guard !photos.isEmpty else {
            FileManagerUtil.logData(
                context: TimelinePhotoLog.context,
                content: "No PhotoKit assets found for \(shortKey). Interval: \(TimelinePhotoLog.intervalString(interval))",
                verbosity: 4
            )
            photosByKey[key] = []
            return
        }

        photosByKey[key] = photos
        FileManagerUtil.logData(
            context: TimelinePhotoLog.context,
            content: "Finished loading photo metadata for \(shortKey). Records: \(photos.count)",
            verbosity: 4
        )
    }

    private func fetchPhotoRecords(from startDate: Date, to endDate: Date) async -> [TimelinePhoto] {
        await Task.detached(priority: .utility) {
            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
            options.predicate = NSPredicate(
                format: "mediaType == %d AND creationDate >= %@ AND creationDate < %@",
                PHAssetMediaType.image.rawValue,
                startDate as NSDate,
                endDate as NSDate
            )

            let result = PHAsset.fetchAssets(with: options)
            var photos: [TimelinePhoto] = []
            photos.reserveCapacity(result.count)
            result.enumerateObjects { asset, _, _ in
                photos.append(
                    TimelinePhoto(
                        id: asset.localIdentifier,
                        pixelWidth: asset.pixelWidth,
                        pixelHeight: asset.pixelHeight
                    )
                )
            }
            return photos
        }.value
    }

    private func fetchAsset(localIdentifier: String) -> PHAsset? {
        PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil).firstObject
    }

    private func imageCacheKey(for photo: TimelinePhoto, displaySize: CGSize, contentMode: PHImageContentMode) -> String {
        let scale = UIScreen.main.scale
        let widthBucket = Int(ceil(max(displaySize.width * scale, 1) / 32) * 32)
        let heightBucket = Int(ceil(max(displaySize.height * scale, 1) / 32) * 32)
        return "\(photo.id)-\(widthBucket)x\(heightBucket)-\(contentMode.rawValue)"
    }

    private func pixelTargetSize(for displaySize: CGSize) -> CGSize {
        let scale = UIScreen.main.scale
        return CGSize(
            width: max(1, displaySize.width * scale),
            height: max(1, displaySize.height * scale)
        )
    }

    private func logInFlightImagePressureIfNeeded(trigger: String) {
        let inFlightCount = loadingImageKeys.count + loadingFullImageIDs.count
        guard inFlightCount >= 8 else { return }

        let oldestAge = imageRequestStartedAt.values
            .map { Date().timeIntervalSince($0) }
            .max() ?? 0

        ResourceDiagnostics.logMemory(
            context: TimelinePhotoLog.context,
            detail: "High PhotoKit concurrency (\(inFlightCount) in flight, oldest ~\(Int(oldestAge))s) after \(trigger). Competing with MapKit for memory and I/O."
        )
    }

    private func scheduleHungImageRequestWarning(
        requestKind: String,
        assetID: String,
        isComplete: @escaping @Sendable () -> Bool,
        startedAt: Date
    ) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(15))
            guard !isComplete() else { return }

            let elapsed = Int(Date().timeIntervalSince(startedAt))
            ResourceDiagnostics.logMemory(
                context: TimelinePhotoLog.context,
                detail: "PhotoKit \(requestKind) request for asset \(assetID) has not completed after \(elapsed)s — continuation likely hung; further thumbnails/tiles may stop loading."
            )
        }
    }

    private func requestImage(for asset: PHAsset, targetSize: CGSize, contentMode: PHImageContentMode, allowsNetworkAccess: Bool) async -> UIImage? {
        FileManagerUtil.logData(
            context: TimelinePhotoLog.context,
            content: "Request image target for asset \(asset.localIdentifier.prefix(12)): \(Int(targetSize.width))x\(Int(targetSize.height)), contentMode: \(contentMode.rawValue)",
            verbosity: 5
        )

        return await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = allowsNetworkAccess

            nonisolated(unsafe) var didResume = false
            let startedAt = Date()
            let assetLabel = String(asset.localIdentifier.prefix(12))
            scheduleHungImageRequestWarning(
                requestKind: "thumbnail",
                assetID: assetLabel,
                isComplete: { didResume },
                startedAt: startedAt
            )

            imageManager.requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                guard !didResume else { return }

                let cancelled = info?[PHImageCancelledKey] as? Bool ?? false
                let hasError = info?[PHImageErrorKey] != nil
                let isDegraded = info?[PHImageResultIsDegradedKey] as? Bool ?? false
                if cancelled || hasError {
                    FileManagerUtil.logData(
                        context: TimelinePhotoLog.context,
                        content: "Image request failed for asset \(assetLabel). Cancelled: \(cancelled), error: \(String(describing: info?[PHImageErrorKey]))",
                        verbosity: 4
                    )
                    didResume = true
                    continuation.resume(returning: nil)
                    return
                }

                if image == nil, isDegraded {
                    FileManagerUtil.logData(
                        context: TimelinePhotoLog.context,
                        content: "PhotoKit returned nil degraded thumbnail for asset \(assetLabel) — waiting for final callback; if none arrives this request will hang.",
                        verbosity: 2
                    )
                    return
                }

                if let image {
                    FileManagerUtil.logData(
                        context: TimelinePhotoLog.context,
                        content: "Image request succeeded for asset \(assetLabel). Returned size: \(Int(image.size.width))x\(Int(image.size.height)), degraded: \(isDegraded)",
                        verbosity: 5
                    )
                    didResume = true
                    continuation.resume(returning: image)
                } else if !isDegraded {
                    didResume = true
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func requestFullImage(for asset: PHAsset) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .none
            options.isNetworkAccessAllowed = true

            nonisolated(unsafe) var didResume = false
            let startedAt = Date()
            let assetLabel = String(asset.localIdentifier.prefix(12))
            scheduleHungImageRequestWarning(
                requestKind: "full image",
                assetID: assetLabel,
                isComplete: { didResume },
                startedAt: startedAt
            )

            imageManager.requestImage(
                for: asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                guard !didResume else { return }

                let cancelled = info?[PHImageCancelledKey] as? Bool ?? false
                let hasError = info?[PHImageErrorKey] != nil
                let isDegraded = info?[PHImageResultIsDegradedKey] as? Bool ?? false

                if cancelled || hasError {
                    FileManagerUtil.logData(
                        context: TimelinePhotoLog.context,
                        content: "Full image request failed for asset \(assetLabel). Cancelled: \(cancelled), error: \(String(describing: info?[PHImageErrorKey]))",
                        verbosity: 4
                    )
                    didResume = true
                    continuation.resume(returning: nil)
                    return
                }

                if isDegraded {
                    FileManagerUtil.logData(
                        context: TimelinePhotoLog.context,
                        content: "PhotoKit returned degraded full-image preview for asset \(assetLabel) (hasImage=\(image != nil)) — waiting for high-quality callback; if none arrives this request will hang.",
                        verbosity: 2
                    )
                }

                if let image, !isDegraded {
                    didResume = true
                    continuation.resume(returning: image)
                } else if !isDegraded {
                    didResume = true
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

private extension UIImage {
    var memoryCost: Int {
        let pixelWidth = Int(size.width * scale)
        let pixelHeight = Int(size.height * scale)
        return max(1, pixelWidth * pixelHeight * 4)
    }
}

struct TimelineView: View {
    @Binding var timelineObjects: [TimelineObject]
    @Binding var selectedTimelineObjectID: UUID?
    @State private var editingTimelineObject: TimelineObject?
    @State private var showingEditSheet = false
    @State private var expandedGroupIDs: Set<UUID> = []
    @StateObject private var photoStore = TimelinePhotoStore()
    @State private var photoSheet: TimelinePhotoSheet?
    @AppStorage("timelinePictureDisplayMode") private var timelinePictureDisplayModeRaw: String = SettingsManager.shared.timelinePictureDisplayMode.rawValue

    var groupingMinutes: Double
    var onRefresh: () -> Void
    var onSelectItem: (TimelineObject) -> Void
    var onSelectGroup: (([TimelineObject]) -> Void)?
    var selectedDate: Date
    var onEditVisit: ((TimelineObject, Place?) -> Void)?
    var onRecenter: () -> Void

    private var displayItems: [TimelineDisplayItem] {
        guard groupingMinutes > 0 else {
            return timelineObjects.map { .single($0) }
        }

        var result: [TimelineDisplayItem] = []
        var pendingGroup: [TimelineObject] = []

        func flushGroup() {
            guard !pendingGroup.isEmpty else { return }
            if pendingGroup.count == 1 {
                result.append(.single(pendingGroup[0]))
            } else {
                let groupID = pendingGroup[0].id
                let isExpanded = expandedGroupIDs.contains(groupID)
                result.append(.groupHeader(id: groupID, items: pendingGroup, isExpanded: isExpanded))
                if isExpanded {
                    for item in pendingGroup {
                        result.append(.groupChild(item))
                    }
                }
            }
            pendingGroup = []
        }

        for item in timelineObjects {
            if item.durationInMinutes >= groupingMinutes {
                flushGroup()
                result.append(.single(item))
            } else {
                pendingGroup.append(item)
            }
        }
        flushGroup()

        return result
    }

    private var timelinePictureDisplayMode: TimelinePictureDisplayMode {
        TimelinePictureDisplayMode(rawValue: timelinePictureDisplayModeRaw) ?? .small
    }
    
    var body: some View {
        let photoIntervalsByObjectID = makePhotoIntervalsByObjectID()

        List(displayItems) { displayItem in
            switch displayItem {
            case .single(let item):
                itemRow(item: item, showEdit: true, photoInterval: photoIntervalsByObjectID[item.id])
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .alignmentGuide(.listRowSeparatorLeading) { d in d[.leading] }
                    .onTapGesture {
                        withAnimation { onSelectItem(item) }
                    }
                    .listRowBackground(item.id == selectedTimelineObjectID || item.selected ? Color.blue.opacity(0.3) : Color.clear)

            case .groupHeader(let groupID, let items, let isExpanded):
                groupHeaderRow(groupID: groupID, items: items, isExpanded: isExpanded)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .alignmentGuide(.listRowSeparatorLeading) { d in d[.leading] }
                    .onTapGesture {
                        withAnimation {
                            onSelectGroup?(items)
                        }
                    }
                    .listRowBackground(
                        items.contains(where: { $0.selected }) ? Color.blue.opacity(0.3) : Color.clear
                    )

            case .groupChild(let item):
                itemRow(item: item, showEdit: true, photoInterval: photoIntervalsByObjectID[item.id])
                    .padding(.leading, 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .alignmentGuide(.listRowSeparatorLeading) { d in d[.leading] }
                    .onTapGesture {
                        withAnimation { onSelectItem(item) }
                    }
                    .listRowBackground(item.id == selectedTimelineObjectID || item.selected ? Color.blue.opacity(0.3) : Color(.secondarySystemBackground))
            }
        }
        .refreshable {
            onRefresh()
        }
        .listStyle(PlainListStyle())
        .sheet(isPresented: $showingEditSheet, content: {
            if let timelineObject = editingTimelineObject {
                if timelineObject.type == .waypoint {
                    EditVisitView(
                        timelineObject: timelineObject,
                        fileDate: selectedDate,
                        onSave: { place in
                            onEditVisit?(timelineObject, place)
                        }
                    )
                } else {
                    EditTrackView(
                        timelineObject: timelineObject,
                        fileDate: selectedDate,
                        onSaveChanges: {
                            onRefresh()
                            onRecenter()
                        }
                    )
                }
            }
        })
        .fullScreenCover(item: $photoSheet) { sheet in
            TimelinePhotoViewer(
                photos: sheet.photos,
                initialPhotoID: sheet.initialPhotoID,
                closesOnDetailBack: sheet.closesOnDetailBack,
                photoStore: photoStore
            )
        }
        .onChange(of: showingEditSheet) { _, newValue in
            if !newValue {
                editingTimelineObject = nil
            }
        }
        .onChange(of: groupingMinutes) {
            expandedGroupIDs.removeAll()
        }
        .onChange(of: selectedDate) {
            FileManagerUtil.logData(
                context: TimelinePhotoLog.context,
                content: "Selected date changed to \(TimelinePhotoLog.dateString(selectedDate)). Clearing timeline photo cache.",
                verbosity: 4
            )
            photoStore.clear()
        }
        .onChange(of: timelineObjects.map { $0.id }) {
            FileManagerUtil.logData(
                context: TimelinePhotoLog.context,
                content: "Timeline object IDs changed. Object count: \(timelineObjects.count). Clearing timeline photo cache.",
                verbosity: 4
            )
            photoStore.clear()
        }
        .onChange(of: timelinePictureDisplayModeRaw) {
            FileManagerUtil.logData(
                context: TimelinePhotoLog.context,
                content: "Timeline picture display mode changed to \(timelinePictureDisplayModeRaw). Clearing timeline photo cache.",
                verbosity: 4
            )
            photoStore.clear()
        }
        .task(id: timelinePictureDisplayModeRaw) {
            FileManagerUtil.logData(
                context: TimelinePhotoLog.context,
                content: "Timeline photo task started. Mode: \(timelinePictureDisplayModeRaw), selectedDate: \(TimelinePhotoLog.dateString(selectedDate)), timelineObjects: \(timelineObjects.count), displayItems: \(displayItems.count)",
                verbosity: 4
            )
            if timelinePictureDisplayMode != .none {
                await photoStore.requestAuthorizationIfNeeded()
            } else {
                FileManagerUtil.logData(
                    context: TimelinePhotoLog.context,
                    content: "Timeline photo task skipped authorization because mode is none.",
                    verbosity: 4
                )
            }
        }
    }

    // MARK: - Item Row

    @ViewBuilder
    private func itemRow(item: TimelineObject, showEdit: Bool, photoInterval: DateInterval?) -> some View {
        let photoKey = photoInterval.map { photoCacheKey(for: item, interval: $0) }

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .trailing) {
                    if let startDate = item.startDate {
                        Text("\(formatDateToHoursMinutes(startDate))")
                            .bold()
                    }
                    Text(item.duration)
                }
                .frame(minWidth: 80, alignment: .trailing)

                HStack {
                    VStack(alignment: .center) {
                        if item.type == .waypoint {
                            PlaceIconView(icon: item.customIcon, fallbackColor: .gray)
                        } else {
                            switch item.trackType {
                            case "cycling":
                                Image(systemName: "figure.outdoor.cycle")
                                    .foregroundColor(trackTypeColorMapping[item.trackType ?? "cycling"])
                            case "walking":
                                Image(systemName: "figure.walk")
                                    .foregroundColor(trackTypeColorMapping[item.trackType ?? "walking"])
                            case "running":
                                Image(systemName: "figure.run")
                                    .foregroundColor(trackTypeColorMapping[item.trackType ?? "running"])
                            case "automotive":
                                Image(systemName: "car.fill")
                                    .foregroundColor(trackTypeColorMapping[item.trackType ?? "automotive"])
                            default:
                                Image(systemName: "arrow.down")
                                    .foregroundColor(trackTypeColorMapping[item.trackType ?? "unknown"])
                            }
                        }
                    }
                    .frame(width: 35, alignment: .center)
                }

                VStack(alignment: .leading) {
                    if item.type == .waypoint {
                        HStack(alignment: .center) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.name ?? "Unknown Place")
                                Group {
                                    if item.meters > 0 || item.steps > 0 || item.averageSpeed > 0 {
                                        HStack {
                                            if item.meters > 0 {
                                                if item.meters < 1000 {
                                                    Text("\(item.meters) m").font(.footnote)
                                                } else {
                                                    Text("\(item.meters/1000) km").font(.footnote)
                                                }
                                            }
                                            if item.steps > 0 {
                                                Text("\(item.steps) steps").font(.footnote)
                                            }
                                            if item.averageSpeed > 0 {
                                                Text("\(String(format: "%.1f", item.averageSpeed)) km/h").font(.footnote)
                                            }
                                        }
                                    } else {
                                        Color.clear.frame(height: 0)
                                    }
                                }
                            }
                        }
                    } else {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(item.trackType?.capitalized ?? "Movement")
                                if item.meters > 0 || item.steps > 0 || item.averageSpeed > 0 {
                                    HStack {
                                        if item.meters > 0 {
                                            if item.meters < 1000 {
                                                Text("\(item.meters) m").font(.footnote)
                                            } else {
                                                Text("\(item.meters/1000) km").font(.footnote)
                                            }
                                        }
                                        if item.steps > 0 {
                                            Text("\(item.steps) steps").font(.footnote)
                                        }
                                        if item.averageSpeed > 0 {
                                            Text("\(String(format: "%.1f", item.averageSpeed)) km/h").font(.footnote)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    if item.numberOfPoints == 1 {
                        Text("\(item.numberOfPoints) point").font(.footnote)
                    } else if item.numberOfPoints > 1 {
                        Text("\(item.numberOfPoints) points").font(.footnote)
                    }
                }

                Spacer()

                if timelinePictureDisplayMode == .small,
                   let photoInterval,
                   let photoKey {
                    TimelinePhotoAttachmentView(
                        photoStore: photoStore,
                        cacheKey: photoKey,
                        interval: photoInterval,
                        displayMode: .small,
                        onOpenPhoto: { photo in
                            photoSheet = TimelinePhotoSheet(
                                photos: photosForViewer(photo, cacheKey: photoKey),
                                initialPhotoID: photo.id,
                                closesOnDetailBack: true
                            )
                        },
                        onOpenAll: { photos in
                            photoSheet = TimelinePhotoSheet(photos: photos)
                        }
                    )
                }

                if showEdit {
                    editButton(for: item)
                }
            }

            if timelinePictureDisplayMode == .medium || timelinePictureDisplayMode == .large,
               let photoInterval,
               let photoKey {
                TimelinePhotoAttachmentView(
                    photoStore: photoStore,
                    cacheKey: photoKey,
                    interval: photoInterval,
                    displayMode: timelinePictureDisplayMode,
                    onOpenPhoto: { photo in
                        photoSheet = TimelinePhotoSheet(
                            photos: photosForViewer(photo, cacheKey: photoKey),
                            initialPhotoID: photo.id,
                            closesOnDetailBack: timelinePictureDisplayMode == .medium || timelinePictureDisplayMode == .large
                        )
                    },
                    onOpenAll: { photos in
                        photoSheet = TimelinePhotoSheet(photos: photos)
                    }
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func editButton(for item: TimelineObject) -> some View {
        if item.type == .waypoint && (item.id == selectedTimelineObjectID || item.name == nil || item.name == "Unknown Place" || item.name == "Unknown place") {
            Button(action: {
                editingTimelineObject = item
                onSelectItem(item)
                showingEditSheet = true
            }) {
                Image(systemName: "square.and.pencil")
                    .foregroundColor(item.id == selectedTimelineObjectID ? .black : .blue)
            }
            .buttonStyle(BorderlessButtonStyle())
            .contentShape(Rectangle())
        } else if item.type == .track && item.id == selectedTimelineObjectID {
            Button(action: {
                editingTimelineObject = item
                showingEditSheet = true
            }) {
                Image(systemName: "square.and.pencil")
                    .foregroundColor(.black)
            }
            .buttonStyle(BorderlessButtonStyle())
            .contentShape(Rectangle())
        }
    }

    // MARK: - Group Header Row

    @ViewBuilder
    private func groupHeaderRow(groupID: UUID, items: [TimelineObject], isExpanded: Bool) -> some View {
        HStack {
            VStack(alignment: .trailing) {
                if let startDate = items.first?.startDate {
                    Text("\(formatDateToHoursMinutes(startDate))")
                        .bold()
                }
                if let start = items.first?.startDate, let end = items.last?.endDate {
                    Text(calculateDuration(from: start, to: end))
                }
            }
            .frame(minWidth: 80, alignment: .trailing)

            HStack {
                Image(systemName: "rectangle.stack")
                    .foregroundColor(.secondary)
            }
            .frame(width: 35, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text(groupSummary(items))
                Text("\(items.count) items")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: {
                withAnimation {
                    if expandedGroupIDs.contains(groupID) {
                        expandedGroupIDs.remove(groupID)
                    } else {
                        expandedGroupIDs.insert(groupID)
                    }
                }
            }) {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .foregroundColor(.blue)
                    .padding(.trailing, 4)
            }
            .buttonStyle(BorderlessButtonStyle())
            .contentShape(Rectangle())
        }
    }

    // MARK: - Helpers

    private func makePhotoIntervalsByObjectID() -> [UUID: DateInterval] {
        let sortedObjects = timelineObjects.sorted {
            ($0.startDate ?? Date.distantPast) < ($1.startDate ?? Date.distantPast)
        }

        var intervalsByID: [UUID: DateInterval] = [:]
        intervalsByID.reserveCapacity(sortedObjects.count)

        for (index, item) in sortedObjects.enumerated() {
            guard let startDate = item.startDate else { continue }
            let nextStartDate = sortedObjects
                .dropFirst(index + 1)
                .compactMap(\.startDate)
                .first { $0 > startDate }
            let endDate = nextStartDate ?? item.endDate ?? endOfSelectedDay()
            guard endDate > startDate else { continue }

            intervalsByID[item.id] = DateInterval(start: startDate, end: endDate)
        }

        FileManagerUtil.logData(
            context: TimelinePhotoLog.context,
            content: "Computed photo intervals once for render. Timeline objects: \(timelineObjects.count), intervals: \(intervalsByID.count)",
            verbosity: 5
        )
        return intervalsByID
    }

    private func photoCacheKey(for item: TimelineObject, interval: DateInterval) -> String {
        let startTime = Int(interval.start.timeIntervalSince1970)
        let endTime = Int(interval.end.timeIntervalSince1970)
        return "\(item.id.uuidString)-\(startTime)-\(endTime)"
    }

    private func photosForViewer(_ selectedPhoto: TimelinePhoto, cacheKey: String) -> [TimelinePhoto] {
        let photos = photoStore.photos(for: cacheKey)
        return photos.isEmpty ? [selectedPhoto] : photos
    }

    private func endOfSelectedDay() -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: selectedDate)
        components.hour = 23
        components.minute = 59
        components.second = 59
        return Calendar.current.date(from: components) ?? selectedDate
    }

    private func groupSummary(_ items: [TimelineObject]) -> String {
        let tracks = items.filter { $0.type == .track }.count
        let stops = items.filter { $0.type == .waypoint }.count
        var parts: [String] = []
        if tracks > 0 {
            parts.append("\(tracks) track\(tracks == 1 ? "" : "s")")
        }
        if stops > 0 {
            parts.append("\(stops) stop\(stops == 1 ? "" : "s")")
        }
        return parts.joined(separator: " and ")
    }
}

private struct TimelinePhotoAttachmentView: View {
    @Environment(\.openURL) private var openURL

    @ObservedObject var photoStore: TimelinePhotoStore

    let cacheKey: String
    let interval: DateInterval
    let displayMode: TimelinePictureDisplayMode
    let onOpenPhoto: (TimelinePhoto) -> Void
    let onOpenAll: ([TimelinePhoto]) -> Void

    private let mediumPhotoSize: CGFloat = 56
    private let mediumPhotoSpacing: CGFloat = 6
    private let largePhotoSpacing: CGFloat = 8
    private let mediaIconLeadingOffset: CGFloat = 88

    private var photos: [TimelinePhoto] {
        photoStore.photos(for: cacheKey)
    }

    private var hasLoadedPhotos: Bool {
        photoStore.hasLoadedPhotos(for: cacheKey)
    }

    var body: some View {
        Group {
            if photoStore.authorizationStatus == .denied || photoStore.authorizationStatus == .restricted {
                permissionButton
            } else if photos.isEmpty && !hasLoadedPhotos {
                loadingAnchor
            } else {
                switch displayMode {
                case .none:
                    EmptyView()
                case .small:
                    smallThumbnail
                case .medium:
                    mediumStrip
                case .large:
                    largeStrip
                }
            }
        }
    }

    private var loadingAnchor: some View {
        Color.clear
            .frame(width: loadingAnchorSize.width, height: loadingAnchorSize.height)
            .task(id: cacheKey) {
                FileManagerUtil.logData(
                    context: TimelinePhotoLog.context,
                    content: "Photo attachment loading anchor mounted. Mode: \(displayMode.rawValue), key: \(TimelinePhotoLog.shortKey(cacheKey)), auth: \(photoStore.authorizationStatus.timelineLogDescription), interval: \(TimelinePhotoLog.intervalString(interval))",
                    verbosity: 4
                )
                await loadPhotos()
            }
    }

    private var loadingAnchorSize: CGSize {
        switch displayMode {
        case .small:
            return CGSize(width: 44, height: 44)
        case .medium, .large:
            return CGSize(width: 1, height: 1)
        case .none:
            return .zero
        }
    }

    private func loadPhotos() async {
        FileManagerUtil.logData(
            context: TimelinePhotoLog.context,
            content: "Photo attachment load started. Mode: \(displayMode.rawValue), key: \(TimelinePhotoLog.shortKey(cacheKey)), auth: \(photoStore.authorizationStatus.timelineLogDescription), interval: \(TimelinePhotoLog.intervalString(interval))",
            verbosity: 4
        )
        await photoStore.loadPhotos(for: cacheKey, interval: interval)
        FileManagerUtil.logData(
            context: TimelinePhotoLog.context,
            content: "Photo attachment load finished. Mode: \(displayMode.rawValue), key: \(TimelinePhotoLog.shortKey(cacheKey)), visible photos: \(photos.count), loaded: \(hasLoadedPhotos), auth: \(photoStore.authorizationStatus.timelineLogDescription)",
            verbosity: 4
        )
    }

    private var permissionButton: some View {
        Button(action: openPhotoSettings) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(.tertiarySystemFill))
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.black.opacity(0.12), lineWidth: 0.5)
                Image(systemName: "photo.badge.exclamationmark")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
            .frame(width: permissionButtonSize, height: permissionButtonSize)
        }
        .buttonStyle(BorderlessButtonStyle())
        .accessibilityLabel("Open photo permission settings")
        .task(id: cacheKey) {
            FileManagerUtil.logData(
                context: TimelinePhotoLog.context,
                content: "Photo permission button mounted. Mode: \(displayMode.rawValue), key: \(TimelinePhotoLog.shortKey(cacheKey)), auth: \(photoStore.authorizationStatus.timelineLogDescription)",
                verbosity: 4
            )
        }
    }

    private var permissionButtonSize: CGFloat {
        displayMode == .small ? 44 : 56
    }

    private func openPhotoSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            FileManagerUtil.logData(
                context: TimelinePhotoLog.context,
                content: "Could not build app settings URL for photo permissions.",
                verbosity: 4
            )
            return
        }
        FileManagerUtil.logData(
            context: TimelinePhotoLog.context,
            content: "Opening app settings from photo permission button.",
            verbosity: 4
        )
        openURL(url)
    }

    @ViewBuilder
    private var smallThumbnail: some View {
        if let photo = photos.first {
            Button(action: {
                onOpenPhoto(photo)
            }) {
                TimelineSquarePhoto(photo: photo, photoStore: photoStore, size: 44)
            }
            .buttonStyle(BorderlessButtonStyle())
            .accessibilityLabel("Show picture")
        }
    }

    @ViewBuilder
    private var mediumStrip: some View {
        if !photos.isEmpty {
            GeometryReader { proxy in
                mediumStripContent(width: proxy.size.width)
            }
            .frame(height: mediumPhotoSize)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func mediumStripContent(width: CGFloat) -> some View {
        let leadingPadding = mediaLeadingPadding(containerWidth: width, contentWidth: mediumContentWidth(count: photos.count))
        let slotCount = mediumSlotCount(for: width - leadingPadding)
        let showsMore = photos.count > slotCount
        let visiblePhotoCount = showsMore ? max(0, slotCount - 1) : min(photos.count, slotCount)

        return HStack(spacing: mediumPhotoSpacing) {
            ForEach(Array(photos.prefix(visiblePhotoCount))) { photo in
                Button(action: {
                    onOpenPhoto(photo)
                }) {
                    TimelineSquarePhoto(photo: photo, photoStore: photoStore, size: mediumPhotoSize)
                }
                .buttonStyle(BorderlessButtonStyle())
                .accessibilityLabel("Show picture")
            }

            if showsMore {
                Button(action: {
                    onOpenAll(photos)
                }) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color(.tertiarySystemFill))
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.black.opacity(0.12), lineWidth: 0.5)
                        Text("...")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .frame(width: mediumPhotoSize, height: mediumPhotoSize)
                }
                .buttonStyle(BorderlessButtonStyle())
                .accessibilityLabel("Show all pictures")
            }

            Spacer(minLength: 0)
        }
        .padding(.leading, leadingPadding)
    }

    private func mediumSlotCount(for width: CGFloat) -> Int {
        guard width > 0 else { return 1 }
        return max(1, Int((width + mediumPhotoSpacing) / (mediumPhotoSize + mediumPhotoSpacing)))
    }

    private func mediumContentWidth(count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        return CGFloat(count) * mediumPhotoSize + CGFloat(count - 1) * mediumPhotoSpacing
    }

    @ViewBuilder
    private var largeStrip: some View {
        if !photos.isEmpty {
            let height = max(72, UIScreen.main.bounds.height * 0.10)
            GeometryReader { proxy in
                let contentWidth = largeContentWidth(height: height)
                let leadingPadding = mediaLeadingPadding(containerWidth: proxy.size.width, contentWidth: contentWidth)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: largePhotoSpacing) {
                        ForEach(photos) { photo in
                            Button(action: {
                                onOpenPhoto(photo)
                            }) {
                                TimelineLargePhotoThumbnail(photo: photo, photoStore: photoStore, height: height)
                            }
                            .buttonStyle(BorderlessButtonStyle())
                            .accessibilityLabel("Show picture")
                        }
                    }
                    .padding(.leading, leadingPadding)
                    .padding(.vertical, 2)
                }
            }
            .frame(height: height + 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func largeContentWidth(height: CGFloat) -> CGFloat {
        let imageWidth = photos.reduce(CGFloat.zero) { partialResult, photo in
            partialResult + height * photo.aspectRatio
        }
        let spacingWidth = CGFloat(max(photos.count - 1, 0)) * largePhotoSpacing
        return imageWidth + spacingWidth
    }

    private func mediaLeadingPadding(containerWidth: CGFloat, contentWidth: CGFloat) -> CGFloat {
        let leadingOffset = min(mediaIconLeadingOffset, max(containerWidth, 0))
        let remainingWidthAfterIcon = max(containerWidth - leadingOffset, 0)
        return contentWidth >= remainingWidthAfterIcon ? 0 : leadingOffset
    }
}

private struct TimelineSquarePhoto: View {
    let photo: TimelinePhoto
    @ObservedObject var photoStore: TimelinePhotoStore
    let size: CGFloat

    @State private var loadedImage: UIImage?

    private var displaySize: CGSize {
        CGSize(width: size, height: size)
    }

    private var displayImage: UIImage? {
        loadedImage ?? photoStore.thumbnail(for: photo, displaySize: displaySize, contentMode: .aspectFill)
    }

    var body: some View {
        Group {
            if let image = displayImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color(.tertiarySystemFill)
                    .overlay {
                        Image(systemName: "photo")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
            }
        }
        .frame(width: size, height: size)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.black.opacity(0.12), lineWidth: 0.5)
        )
        .task(id: "\(photo.id)-\(Int(size))") {
            if loadedImage == nil {
                loadedImage = await photoStore.loadThumbnail(for: photo, displaySize: displaySize, contentMode: .aspectFill)
            }
        }
    }
}

private struct TimelineLargePhotoThumbnail: View {
    let photo: TimelinePhoto
    @ObservedObject var photoStore: TimelinePhotoStore
    let height: CGFloat

    @State private var loadedImage: UIImage?

    private var displaySize: CGSize {
        CGSize(width: height * photo.aspectRatio, height: height)
    }

    private var displayImage: UIImage? {
        loadedImage ?? photoStore.thumbnail(for: photo, displaySize: displaySize, contentMode: .aspectFit)
    }

    var body: some View {
        Group {
            if let image = displayImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Color(.tertiarySystemFill)
                    .overlay {
                        Image(systemName: "photo")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
            }
        }
        .frame(width: displaySize.width, height: displaySize.height)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.black.opacity(0.12), lineWidth: 0.5)
        )
        .task(id: "\(photo.id)-\(Int(displaySize.width))x\(Int(displaySize.height))") {
            if loadedImage == nil {
                loadedImage = await photoStore.loadThumbnail(for: photo, displaySize: displaySize, contentMode: .aspectFit)
            }
        }
    }
}

private struct TimelinePhotoViewer: View {
    @Environment(\.dismiss) private var dismiss

    let photos: [TimelinePhoto]
    let initialPhotoID: String?
    let closesOnDetailBack: Bool
    @ObservedObject var photoStore: TimelinePhotoStore

    @State private var selectedPhotoID: String?

    init(photos: [TimelinePhoto], initialPhotoID: String?, closesOnDetailBack: Bool, photoStore: TimelinePhotoStore) {
        self.photos = photos
        self.initialPhotoID = initialPhotoID
        self.closesOnDetailBack = closesOnDetailBack
        self.photoStore = photoStore
        _selectedPhotoID = State(initialValue: closesOnDetailBack ? (initialPhotoID ?? photos.first?.id) : initialPhotoID)
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 112), spacing: 10)]
    }

    var body: some View {
        NavigationStack {
            if let selectedPhotoID {
                if photos.contains(where: { $0.id == selectedPhotoID }) {
                    TimelinePhotoDetailView(
                        photos: photos,
                        initialPhotoID: selectedPhotoID,
                        photoStore: photoStore,
                        onClose: {
                            if closesOnDetailBack {
                                dismiss()
                            } else {
                                self.selectedPhotoID = nil
                            }
                        },
                        leadingCloseTitle: "Back",
                        trailingCloseTitle: closesOnDetailBack ? nil : "Done"
                    )
                } else {
                    ContentUnavailableView("Picture unavailable", systemImage: "photo")
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button("Back") {
                                    if closesOnDetailBack {
                                        dismiss()
                                    } else {
                                        self.selectedPhotoID = nil
                                    }
                                }
                            }
                        }
                }
            } else {
                gridNavigation
            }
        }
    }

    private var gridNavigation: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(photos) { photo in
                    TimelinePhotoGridCell(
                        photo: photo,
                        photoStore: photoStore,
                        action: {
                            selectedPhotoID = photo.id
                        }
                    )
                }
            }
            .padding()
        }
        .navigationTitle("Pictures")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    dismiss()
                }
            }
        }
    }
}

private struct TimelinePhotoGridCell: View {
    let photo: TimelinePhoto
    @ObservedObject var photoStore: TimelinePhotoStore
    let action: () -> Void

    @State private var loadedImage: UIImage?

    var body: some View {
        Button(action: action) {
            GeometryReader { geometry in
                let displaySize = CGSize(width: geometry.size.width, height: geometry.size.height)
                let displayImage = loadedImage ?? photoStore.thumbnail(for: photo, displaySize: displaySize, contentMode: .aspectFill)

                Group {
                    if let image = displayImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Color(.tertiarySystemFill)
                            .overlay {
                                Image(systemName: "photo")
                                    .font(.title3)
                                    .foregroundColor(.secondary)
                            }
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.black.opacity(0.12), lineWidth: 0.5)
                )
                .task(id: "\(photo.id)-grid-\(Int(geometry.size.width))x\(Int(geometry.size.height))") {
                    if loadedImage == nil {
                        loadedImage = await photoStore.loadThumbnail(for: photo, displaySize: displaySize, contentMode: .aspectFill)
                    }
                }
            }
            .aspectRatio(1, contentMode: .fit)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open picture")
    }
}

private struct TimelinePhotoDetailView: View {
    let photos: [TimelinePhoto]
    let initialPhotoID: String
    @ObservedObject var photoStore: TimelinePhotoStore
    let onClose: () -> Void
    let leadingCloseTitle: String?
    let trailingCloseTitle: String?

    @State private var showingShareSheet = false
    @State private var selectedPhotoID: String
    @State private var loadedFullImagePhotoID: String?
    @State private var fullImage: UIImage?

    init(
        photos: [TimelinePhoto],
        initialPhotoID: String,
        photoStore: TimelinePhotoStore,
        onClose: @escaping () -> Void,
        leadingCloseTitle: String?,
        trailingCloseTitle: String?
    ) {
        self.photos = photos
        self.initialPhotoID = initialPhotoID
        self.photoStore = photoStore
        self.onClose = onClose
        self.leadingCloseTitle = leadingCloseTitle
        self.trailingCloseTitle = trailingCloseTitle
        _selectedPhotoID = State(initialValue: initialPhotoID)
    }

    private var currentPhoto: TimelinePhoto? {
        photos.first(where: { $0.id == selectedPhotoID }) ?? photos.first
    }

    private var currentPhotoIndex: Int? {
        guard let currentPhoto else { return nil }
        return photos.firstIndex(where: { $0.id == currentPhoto.id })
    }

    private var displayImage: UIImage? {
        guard let currentPhoto else { return nil }
        return (loadedFullImagePhotoID == currentPhoto.id ? fullImage : nil)
            ?? photoStore.fullImage(for: currentPhoto)
            ?? photoStore.previewImage(for: currentPhoto)
    }

    private var canShareFullImage: Bool {
        guard let currentPhoto else { return false }
        return (loadedFullImagePhotoID == currentPhoto.id && fullImage != nil) || photoStore.fullImage(for: currentPhoto) != nil
    }

    private var canShowPreviousPhoto: Bool {
        guard let currentPhotoIndex else { return false }
        return currentPhotoIndex > 0
    }

    private var canShowNextPhoto: Bool {
        guard let currentPhotoIndex else { return false }
        return currentPhotoIndex < photos.index(before: photos.endIndex)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let displayImage {
                TimelineZoomableImageView(
                    image: displayImage,
                    onDismissRequest: onClose,
                    onShowPreviousPhoto: canShowPreviousPhoto ? showPreviousPhoto : nil,
                    onShowNextPhoto: canShowNextPhoto ? showNextPhoto : nil
                )
                .ignoresSafeArea()
            }

            if displayImage == nil || !canShareFullImage {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            if let currentPhoto {
                TimelinePhotoCarousel(
                    photos: photos,
                    selectedPhotoID: currentPhoto.id,
                    photoStore: photoStore,
                    onSelectPhoto: { photo in
                        selectedPhotoID = photo.id
                    }
                )
                .padding(.bottom, 8)
            }
        }
        .navigationTitle("Picture")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let leadingCloseTitle {
                ToolbarItem(placement: .topBarLeading) {
                    Button(leadingCloseTitle) {
                        onClose()
                    }
                }
            }

            ToolbarItemGroup(placement: .topBarTrailing) {
                Button(action: {
                    showingShareSheet = true
                }) {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(!canShareFullImage)
                .accessibilityLabel("Share picture")

                if let trailingCloseTitle {
                    Button(trailingCloseTitle) {
                        onClose()
                    }
                }
            }
        }
        .task(id: selectedPhotoID) {
            guard let currentPhoto else { return }
            let photoID = currentPhoto.id

            if let cachedImage = photoStore.fullImage(for: currentPhoto) {
                loadedFullImagePhotoID = photoID
                fullImage = cachedImage
                return
            }

            loadedFullImagePhotoID = photoID
            fullImage = nil

            let loadedImage = await photoStore.loadFullImage(for: currentPhoto)
            guard selectedPhotoID == photoID else { return }

            loadedFullImagePhotoID = photoID
            fullImage = loadedImage
        }
        .sheet(isPresented: $showingShareSheet) {
            if let currentPhoto,
               let image = (loadedFullImagePhotoID == currentPhoto.id ? fullImage : nil) ?? photoStore.fullImage(for: currentPhoto) {
                TimelinePhotoActivityView(items: [image])
            }
        }
    }

    private func showPreviousPhoto() {
        guard let currentPhotoIndex, currentPhotoIndex > 0 else { return }
        selectedPhotoID = photos[currentPhotoIndex - 1].id
    }

    private func showNextPhoto() {
        guard let currentPhotoIndex, currentPhotoIndex < photos.index(before: photos.endIndex) else { return }
        selectedPhotoID = photos[currentPhotoIndex + 1].id
    }
}

private struct TimelinePhotoCarousel: View {
    let photos: [TimelinePhoto]
    let selectedPhotoID: String
    @ObservedObject var photoStore: TimelinePhotoStore
    let onSelectPhoto: (TimelinePhoto) -> Void

    private let thumbnailSize: CGFloat = 62
    private let thumbnailSpacing: CGFloat = 10
    private let topPadding: CGFloat = 10
    private let bottomPadding: CGFloat = 12
    private let horizontalPadding: CGFloat = 14

    private var carouselHeight: CGFloat {
        thumbnailSize + topPadding + bottomPadding
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: thumbnailSpacing) {
                    ForEach(photos) { photo in
                        let isSelected = photo.id == selectedPhotoID

                        Button(action: {
                            onSelectPhoto(photo)
                        }) {
                            TimelineSquarePhoto(photo: photo, photoStore: photoStore, size: thumbnailSize)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .stroke(isSelected ? Color.white : Color.white.opacity(0.18), lineWidth: isSelected ? 2 : 1)
                                )
                                .opacity(isSelected ? 1 : 0.76)
                        }
                        .buttonStyle(.plain)
                        .id(photo.id)
                        .accessibilityLabel("Show picture")
                    }
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.top, topPadding)
                .padding(.bottom, bottomPadding)
            }
            .frame(height: carouselHeight, alignment: .bottom)
            .background(
                Color.black.opacity(0.82)
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(Color.white.opacity(0.12))
                            .frame(height: 0.5)
                    }
            )
            .onAppear {
                proxy.scrollTo(selectedPhotoID, anchor: .center)
            }
            .onChange(of: selectedPhotoID) { _, newValue in
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: carouselHeight, alignment: .bottom)
    }
}

private struct TimelineZoomableImageView: UIViewRepresentable {
    let image: UIImage
    let onDismissRequest: () -> Void
    let onShowPreviousPhoto: (() -> Void)?
    let onShowNextPhoto: (() -> Void)?

    func makeUIView(context: Context) -> ZoomableImageContainerView {
        let view = ZoomableImageContainerView()
        view.onDismissRequest = onDismissRequest
        view.onShowPreviousPhoto = onShowPreviousPhoto
        view.onShowNextPhoto = onShowNextPhoto
        return view
    }

    func updateUIView(_ uiView: ZoomableImageContainerView, context: Context) {
        uiView.onDismissRequest = onDismissRequest
        uiView.onShowPreviousPhoto = onShowPreviousPhoto
        uiView.onShowNextPhoto = onShowNextPhoto
        uiView.setImage(image)
    }
}

private final class ZoomableImageContainerView: UIView, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private var currentImage: UIImage?
    private var needsZoomReset = true
    private var lastBoundsSize: CGSize = .zero

    var onDismissRequest: (() -> Void)?
    var onShowPreviousPhoto: (() -> Void)?
    var onShowNextPhoto: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    func setImage(_ image: UIImage) {
        if currentImage !== image {
            currentImage = image
            imageView.image = image
            needsZoomReset = true
        }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scrollView.frame = bounds

        if needsZoomReset || bounds.size != lastBoundsSize {
            resetZoom()
            needsZoomReset = false
            lastBoundsSize = bounds.size
        } else {
            centerImage()
        }
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerImage()
    }

    private func configure() {
        backgroundColor = .black
        scrollView.backgroundColor = .black
        scrollView.delegate = self
        scrollView.bouncesZoom = true
        scrollView.showsHorizontalScrollIndicator = true
        scrollView.showsVerticalScrollIndicator = true
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 8

        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true

        scrollView.addSubview(imageView)
        addSubview(scrollView)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        let swipeDown = UISwipeGestureRecognizer(target: self, action: #selector(handleDismissSwipe(_:)))
        swipeDown.direction = .down
        swipeDown.delegate = self
        scrollView.addGestureRecognizer(swipeDown)

        let swipeRight = UISwipeGestureRecognizer(target: self, action: #selector(handlePhotoSwipe(_:)))
        swipeRight.direction = .right
        swipeRight.delegate = self
        scrollView.addGestureRecognizer(swipeRight)

        let swipeLeft = UISwipeGestureRecognizer(target: self, action: #selector(handlePhotoSwipe(_:)))
        swipeLeft.direction = .left
        swipeLeft.delegate = self
        scrollView.addGestureRecognizer(swipeLeft)

        scrollView.panGestureRecognizer.require(toFail: swipeDown)
        scrollView.panGestureRecognizer.require(toFail: swipeRight)
        scrollView.panGestureRecognizer.require(toFail: swipeLeft)
    }

    private func resetZoom() {
        guard let image = currentImage, bounds.width > 0, bounds.height > 0 else { return }

        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else { return }

        let widthScale = bounds.width / imageSize.width
        let heightScale = bounds.height / imageSize.height
        let fitScale = min(widthScale, heightScale)
        let fittedSize = CGSize(width: imageSize.width * fitScale, height: imageSize.height * fitScale)
        let pixelScale = max(imageSize.width / max(fittedSize.width, 1), imageSize.height / max(fittedSize.height, 1))

        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = max(4, min(12, pixelScale))
        scrollView.zoomScale = 1
        imageView.frame = CGRect(origin: .zero, size: fittedSize)
        scrollView.contentSize = fittedSize
        centerImage()
    }

    private func centerImage() {
        let boundsSize = scrollView.bounds.size
        var frame = imageView.frame
        frame.origin.x = max((boundsSize.width - frame.width) / 2, 0)
        frame.origin.y = max((boundsSize.height - frame.height) / 2, 0)
        imageView.frame = frame
    }

    @objc private func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
        if scrollView.zoomScale > scrollView.minimumZoomScale + 0.01 {
            scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            return
        }

        let targetScale = min(scrollView.maximumZoomScale, max(3, scrollView.minimumZoomScale * 3))
        let tapPoint = recognizer.location(in: imageView)
        let zoomSize = CGSize(
            width: scrollView.bounds.width / targetScale,
            height: scrollView.bounds.height / targetScale
        )
        let zoomOrigin = CGPoint(
            x: tapPoint.x - zoomSize.width / 2,
            y: tapPoint.y - zoomSize.height / 2
        )
        scrollView.zoom(to: CGRect(origin: zoomOrigin, size: zoomSize), animated: true)
    }

    @objc private func handleDismissSwipe(_ recognizer: UISwipeGestureRecognizer) {
        onDismissRequest?()
    }

    @objc private func handlePhotoSwipe(_ recognizer: UISwipeGestureRecognizer) {
        switch recognizer.direction {
        case .right:
            onShowPreviousPhoto?()
        case .left:
            onShowNextPhoto?()
        default:
            break
        }
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if let swipeGesture = gestureRecognizer as? UISwipeGestureRecognizer {
            guard scrollView.zoomScale <= scrollView.minimumZoomScale + 0.01 else { return false }

            switch swipeGesture.direction {
            case .down:
                return onDismissRequest != nil
            case .right:
                return onShowPreviousPhoto != nil
            case .left:
                return onShowNextPhoto != nil
            default:
                return true
            }
        }
        return true
    }
}

private struct TimelinePhotoActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
