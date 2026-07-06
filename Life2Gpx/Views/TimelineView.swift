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
import os
import AVFoundation

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

private func timelinePhotoKitInfoSummary(_ info: [AnyHashable: Any]?) -> String {
    guard let info else { return "info=nil" }

    let cancelled = info[PHImageCancelledKey] as? Bool ?? false
    let degraded = info[PHImageResultIsDegradedKey] as? Bool ?? false
    let inCloud = info[PHImageResultIsInCloudKey] as? Bool ?? false
    let errorDescription = (info[PHImageErrorKey] as? Error)?.localizedDescription ?? "nil"
    return "cancelled=\(cancelled) degraded=\(degraded) inCloud=\(inCloud) error=\(errorDescription)"
}

@MainActor
final class TimelinePhotoStore: ObservableObject {
    @Published private var photosByKey: [String: [TimelinePhoto]] = [:]
    @Published private(set) var authorizationStatus: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)

    private var loadingKeys: Set<String> = []
    private var loadingImageKeys: Set<String> = []
    private var loadingFullImageIDs: Set<String> = []
    private var imageRequestStartedAt: [String: Date] = [:]
    private var inFlightRequestIDs: [String: PHImageRequestID] = [:]
    private var authorizationRequestTask: Task<PHAuthorizationStatus, Never>?
    private let imageManager = PHCachingImageManager()
    private let thumbnailCache = NSCache<NSString, UIImage>()
    private let previewCache = NSCache<NSString, UIImage>()
    private let fullImageCache = NSCache<NSString, UIImage>()

    private static let requestTimeoutSeconds: UInt64 = 10

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
        let inFlightRequests = inFlightRequestIDs.count

        if inFlightRequests > 0 {
            FileManagerUtil.logData(
                context: TimelinePhotoLog.context,
                content: "Cancelling \(inFlightRequests) in-flight PhotoKit requests (\(inFlightThumbnails) thumbnails, \(inFlightFullImages) full images) during cache clear.",
                verbosity: 2
            )
            ResourceDiagnostics.logMemory(
                context: TimelinePhotoLog.context,
                detail: "Photo cache clear — cancelling \(inFlightRequests) in-flight PhotoKit requests."
            )
            for (_, requestID) in inFlightRequestIDs {
                imageManager.cancelImageRequest(requestID)
            }
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
        inFlightRequestIDs.removeAll()
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
            inFlightRequestIDs.removeValue(forKey: cacheKey)
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

        let signpostID = diagnosticsSignposter.makeSignpostID()
        let signpostState = diagnosticsSignposter.beginInterval("PhotoKit thumbnail", id: signpostID, "\(photo.id.prefix(12))")
        let image = await requestImage(for: asset, targetSize: targetSize, contentMode: contentMode, allowsNetworkAccess: allowsNetworkAccess, cacheKey: cacheKey)
        diagnosticsSignposter.endInterval("PhotoKit thumbnail", signpostState)

        guard let image else {
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
            inFlightRequestIDs.removeValue(forKey: "full:\(photo.id)")
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

        let signpostID = diagnosticsSignposter.makeSignpostID()
        let signpostState = diagnosticsSignposter.beginInterval("PhotoKit fullImage", id: signpostID, "\(photo.id.prefix(12))")
        let image = await requestFullImage(for: asset)
        diagnosticsSignposter.endInterval("PhotoKit fullImage", signpostState)

        if let image {
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

    func loadVideoAsset(for photo: TimelinePhoto) async -> AVPlayerItem? {
        guard let asset = fetchAsset(localIdentifier: photo.id) else {
            FileManagerUtil.logData(
                context: TimelinePhotoLog.context,
                content: "Cannot load video for asset \(photo.id.prefix(12)): PHAsset not found.",
                verbosity: 4
            )
            return nil
        }
        
        FileManagerUtil.logData(
            context: TimelinePhotoLog.context,
            content: "Requesting AVPlayerItem for asset \(photo.id.prefix(12)), network={\(NetworkDiagnostics.shared.snapshot())}",
            verbosity: 4
        )
        
        return await withCheckedContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat
            options.progressHandler = { progress, error, _, info in
                let errorDescription = error?.localizedDescription ?? "nil"
                FileManagerUtil.logData(
                    context: TimelinePhotoLog.context,
                    content: "PhotoKit video network progress for asset \(photo.id.prefix(12)): \(Int(progress * 100))%, error=\(errorDescription), \(timelinePhotoKitInfoSummary(info)), network={\(NetworkDiagnostics.shared.snapshot())}",
                    verbosity: error == nil ? 5 : 4
                )
            }
            
            nonisolated(unsafe) var didResume = false
            
            imageManager.requestPlayerItem(forVideo: asset, options: options) { playerItem, info in
                guard !didResume else { return }
                didResume = true
                if let error = info?[PHImageErrorKey] as? Error {
                    FileManagerUtil.logData(
                        context: TimelinePhotoLog.context,
                        content: "Video request failed for asset \(photo.id.prefix(12)): \(error.localizedDescription), \(timelinePhotoKitInfoSummary(info)), network={\(NetworkDiagnostics.shared.snapshot())}",
                        verbosity: 4
                    )
                }
                FileManagerUtil.logData(
                    context: TimelinePhotoLog.context,
                    content: "Video request completed for asset \(photo.id.prefix(12)). playerItem=\(playerItem != nil), \(timelinePhotoKitInfoSummary(info))",
                    verbosity: 5
                )
                continuation.resume(returning: playerItem)
            }
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
                format: "(mediaType == %d OR mediaType == %d) AND creationDate >= %@ AND creationDate < %@",
                PHAssetMediaType.image.rawValue,
                PHAssetMediaType.video.rawValue,
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
                        pixelHeight: asset.pixelHeight,
                        isVideo: asset.mediaType == .video,
                        duration: asset.duration
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


    private func requestImage(for asset: PHAsset, targetSize: CGSize, contentMode: PHImageContentMode, allowsNetworkAccess: Bool, cacheKey: String) async -> UIImage? {
        FileManagerUtil.logData(
            context: TimelinePhotoLog.context,
            content: "Request image target for asset \(asset.localIdentifier.prefix(12)): \(Int(targetSize.width))x\(Int(targetSize.height)), contentMode: \(contentMode.rawValue), allowsNetworkAccess=\(allowsNetworkAccess), network={\(NetworkDiagnostics.shared.snapshot())}",
            verbosity: 5
        )

        let assetLabel = String(asset.localIdentifier.prefix(12))

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let options = PHImageRequestOptions()
                options.deliveryMode = .opportunistic
                options.resizeMode = .fast
                options.isNetworkAccessAllowed = allowsNetworkAccess
                options.progressHandler = { progress, error, _, info in
                    let errorDescription = error?.localizedDescription ?? "nil"
                    FileManagerUtil.logData(
                        context: TimelinePhotoLog.context,
                        content: "PhotoKit thumbnail network progress for asset \(assetLabel): \(Int(progress * 100))%, error=\(errorDescription), \(timelinePhotoKitInfoSummary(info)), network={\(NetworkDiagnostics.shared.snapshot())}",
                        verbosity: error == nil ? 5 : 4
                    )
                }

                nonisolated(unsafe) var didResume = false
                let startedAt = Date()

                let requestID = imageManager.requestImage(
                    for: asset,
                    targetSize: targetSize,
                    contentMode: .aspectFit,
                    options: options
                ) { image, info in
                    guard !didResume else { return }

                    let cancelled = info?[PHImageCancelledKey] as? Bool ?? false
                    let hasError = info?[PHImageErrorKey] != nil
                    let isDegraded = info?[PHImageResultIsDegradedKey] as? Bool ?? false
                    let isInCloud = info?[PHImageResultIsInCloudKey] as? Bool ?? false
                    if isInCloud {
                        FileManagerUtil.logData(
                            context: TimelinePhotoLog.context,
                            content: "PhotoKit thumbnail callback indicates asset \(assetLabel) is iCloud-backed. \(timelinePhotoKitInfoSummary(info)), network={\(NetworkDiagnostics.shared.snapshot())}",
                            verbosity: 5
                        )
                    }
                    if cancelled || hasError {
                        FileManagerUtil.logData(
                            context: TimelinePhotoLog.context,
                            content: "Image request failed for asset \(assetLabel). \(timelinePhotoKitInfoSummary(info)), network={\(NetworkDiagnostics.shared.snapshot())}",
                            verbosity: 4
                        )
                        didResume = true
                        continuation.resume(returning: nil)
                        return
                    }

                    if image == nil, isDegraded {
                        FileManagerUtil.logData(
                            context: TimelinePhotoLog.context,
                            content: "PhotoKit returned nil degraded thumbnail for asset \(assetLabel) — waiting for final callback; if none arrives timeout will cancel after \(Self.requestTimeoutSeconds)s.",
                            verbosity: 2
                        )
                        return
                    }

                    if let image {
                        let elapsed = Int(Date().timeIntervalSince(startedAt))
                        FileManagerUtil.logData(
                            context: TimelinePhotoLog.context,
                            content: "Image request succeeded for asset \(assetLabel). Returned size: \(Int(image.size.width))x\(Int(image.size.height)), degraded: \(isDegraded), elapsed: \(elapsed)s, \(timelinePhotoKitInfoSummary(info))",
                            verbosity: 5
                        )
                        didResume = true
                        continuation.resume(returning: image)
                    } else if !isDegraded {
                        didResume = true
                        continuation.resume(returning: nil)
                    }
                }

                Task { @MainActor in
                    self.inFlightRequestIDs[cacheKey] = requestID
                }

                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: Self.requestTimeoutSeconds * 1_000_000_000)
                    guard !didResume else { return }
                    didResume = true
                    self.imageManager.cancelImageRequest(requestID)
                    self.inFlightRequestIDs.removeValue(forKey: cacheKey)
                    FileManagerUtil.logData(
                        context: TimelinePhotoLog.context,
                        content: "⚠️ PhotoKit thumbnail request TIMED OUT after \(Self.requestTimeoutSeconds)s for asset \(assetLabel). Request cancelled to unblock further loads.",
                        verbosity: 2
                    )
                    ResourceDiagnostics.logMemory(
                        context: TimelinePhotoLog.context,
                        detail: "PhotoKit thumbnail timeout for \(assetLabel) after \(Self.requestTimeoutSeconds)s."
                    )
                    continuation.resume(returning: nil)
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                if let requestID = self?.inFlightRequestIDs.removeValue(forKey: cacheKey) {
                    self?.imageManager.cancelImageRequest(requestID)
                }
            }
        }
    }

    private func requestFullImage(for asset: PHAsset) async -> UIImage? {
        let assetLabel = String(asset.localIdentifier.prefix(12))
        let fullCacheKey = "full:\(asset.localIdentifier)"

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let options = PHImageRequestOptions()
                options.deliveryMode = .highQualityFormat
                options.resizeMode = .none
                options.isNetworkAccessAllowed = true
                options.progressHandler = { progress, error, _, info in
                    let errorDescription = error?.localizedDescription ?? "nil"
                    FileManagerUtil.logData(
                        context: TimelinePhotoLog.context,
                        content: "PhotoKit full-image network progress for asset \(assetLabel): \(Int(progress * 100))%, error=\(errorDescription), \(timelinePhotoKitInfoSummary(info)), network={\(NetworkDiagnostics.shared.snapshot())}",
                        verbosity: error == nil ? 5 : 4
                    )
                }

                nonisolated(unsafe) var didResume = false
                let startedAt = Date()

                let requestID = imageManager.requestImage(
                    for: asset,
                    targetSize: PHImageManagerMaximumSize,
                    contentMode: .aspectFit,
                    options: options
                ) { image, info in
                    guard !didResume else { return }

                    let cancelled = info?[PHImageCancelledKey] as? Bool ?? false
                    let hasError = info?[PHImageErrorKey] != nil
                    let isDegraded = info?[PHImageResultIsDegradedKey] as? Bool ?? false
                    let isInCloud = info?[PHImageResultIsInCloudKey] as? Bool ?? false

                    if isInCloud {
                        FileManagerUtil.logData(
                            context: TimelinePhotoLog.context,
                            content: "PhotoKit full-image callback indicates asset \(assetLabel) is iCloud-backed. \(timelinePhotoKitInfoSummary(info)), network={\(NetworkDiagnostics.shared.snapshot())}",
                            verbosity: 5
                        )
                    }

                    if cancelled || hasError {
                        FileManagerUtil.logData(
                            context: TimelinePhotoLog.context,
                            content: "Full image request failed for asset \(assetLabel). \(timelinePhotoKitInfoSummary(info)), network={\(NetworkDiagnostics.shared.snapshot())}",
                            verbosity: 4
                        )
                        didResume = true
                        continuation.resume(returning: nil)
                        return
                    }

                    if isDegraded {
                        FileManagerUtil.logData(
                            context: TimelinePhotoLog.context,
                            content: "PhotoKit returned degraded full-image preview for asset \(assetLabel) (hasImage=\(image != nil)) - waiting for high-quality callback; timeout after \(Self.requestTimeoutSeconds)s. \(timelinePhotoKitInfoSummary(info))",
                            verbosity: 2
                        )
                    }

                    if let image, !isDegraded {
                        let elapsed = Int(Date().timeIntervalSince(startedAt))
                        FileManagerUtil.logData(
                            context: TimelinePhotoLog.context,
                            content: "Full image loaded for asset \(assetLabel), elapsed: \(elapsed)s, \(timelinePhotoKitInfoSummary(info))",
                            verbosity: 4
                        )
                        didResume = true
                        continuation.resume(returning: image)
                    } else if !isDegraded {
                        didResume = true
                        continuation.resume(returning: nil)
                    }
                }

                Task { @MainActor in
                    self.inFlightRequestIDs[fullCacheKey] = requestID
                }

                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: Self.requestTimeoutSeconds * 1_000_000_000)
                    guard !didResume else { return }
                    didResume = true
                    self.imageManager.cancelImageRequest(requestID)
                    self.inFlightRequestIDs.removeValue(forKey: fullCacheKey)
                    FileManagerUtil.logData(
                        context: TimelinePhotoLog.context,
                        content: "⚠️ PhotoKit full-image request TIMED OUT after \(Self.requestTimeoutSeconds)s for asset \(assetLabel). Request cancelled to unblock further loads.",
                        verbosity: 2
                    )
                    ResourceDiagnostics.logMemory(
                        context: TimelinePhotoLog.context,
                        detail: "PhotoKit full-image timeout for \(assetLabel) after \(Self.requestTimeoutSeconds)s."
                    )
                    continuation.resume(returning: nil)
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                if let requestID = self?.inFlightRequestIDs.removeValue(forKey: fullCacheKey) {
                    self?.imageManager.cancelImageRequest(requestID)
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
    @Binding var scrollPositions: [String: String]
    @State private var activeScrollID: String? = nil
    @State private var scrolledDateKey: String? = nil
    @State private var pendingScrollTarget: String? = nil
    @State private var visibleIDs: Set<String> = []
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
    var onEditVisit: ((TimelineObject, Place?, Bool) -> Void)?
    var onRecenter: () -> Void
    var isEditMode: Bool = false
    @Binding var selectedEditItems: Set<UUID>

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
                let groupUUID = pendingGroup[0].id
                let stableGroupID = pendingGroup[0].stableId
                let isExpanded = expandedGroupIDs.contains(groupUUID)
                result.append(.groupHeader(id: stableGroupID, uuid: groupUUID, items: pendingGroup, isExpanded: isExpanded))
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

    private var selectedDayKey: String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: selectedDate)
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }

    private var displayedObjectsDayKey: String? {
        guard let firstWithDate = timelineObjects.first(where: { $0.startDate != nil }),
              let startDate = firstWithDate.startDate else {
            return nil
        }
        let components = Calendar.current.dateComponents([.year, .month, .day], from: startDate)
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }
    
    private func updateActiveScrollID() {
        if let topVisibleItem = displayItems.first(where: { visibleIDs.contains($0.id) }) {
            let topId = topVisibleItem.id
            if activeScrollID != topId {
                FileManagerUtil.logData(context: "TimelineScroll", content: "[updateActiveScrollID] Top visible item ID determined to be: \(topId)", verbosity: 4)
                activeScrollID = topId
            }
        }
    }

    private func applyScrollPositionForCurrentDay() {
        let key = selectedDayKey
        let displayedKey = displayedObjectsDayKey
        
        FileManagerUtil.logData(context: "TimelineScroll", content: "[applyScrollPosition] Starting scroll restoration. selectedDate key: \(key), displayed items key: \(displayedKey ?? "nil"), saved positions count: \(scrollPositions.count)", verbosity: 4)
        
        if timelineObjects.isEmpty {
            FileManagerUtil.logData(context: "TimelineScroll", content: "[applyScrollPosition] Timeline is empty. Resetting activeScrollID to nil.", verbosity: 4)
            activeScrollID = nil
            scrolledDateKey = key
            return
        }
        
        // We only restore/set scroll position if the displayed objects actually match the selected day.
        guard let displayedKey = displayedKey, displayedKey == key else {
            FileManagerUtil.logData(context: "TimelineScroll", content: "[applyScrollPosition] Displayed items key (\(displayedKey ?? "nil")) does not match selectedDate key (\(key)). Delaying scroll restoration.", verbosity: 4)
            return
        }
        
        let targetId: String?
        if let savedId = scrollPositions[key], displayItems.contains(where: { $0.id == savedId }) {
            FileManagerUtil.logData(context: "TimelineScroll", content: "[applyScrollPosition] Restoring saved scroll position: \(savedId) for day: \(key)", verbosity: 4)
            targetId = savedId
        } else if let firstId = displayItems.first?.id {
            FileManagerUtil.logData(context: "TimelineScroll", content: "[applyScrollPosition] No saved position or saved ID not found. Scrolling to first item: \(firstId) for day: \(key)", verbosity: 4)
            targetId = firstId
            scrollPositions[key] = firstId
        } else {
            FileManagerUtil.logData(context: "TimelineScroll", content: "[applyScrollPosition] List is empty. Resetting activeScrollID to nil.", verbosity: 4)
            targetId = nil
        }
        
        scrolledDateKey = key
        
        if let targetId = targetId {
            FileManagerUtil.logData(context: "TimelineScroll", content: "[applyScrollPosition] Setting pendingScrollTarget: \(targetId) for day: \(key)", verbosity: 4)
            pendingScrollTarget = targetId
        }
    }
    
    var body: some View {
        let photoIntervalsByObjectID = makePhotoIntervalsByObjectID()

        ScrollViewReader { proxy in
        List(displayItems) { displayItem in
            switch displayItem {
            case .single(let item):
                HStack(spacing: 0) {
                    if isEditMode {
                        editModeSelectionCircle(for: item)
                    }
                    itemRow(item: item, showEdit: !isEditMode, photoInterval: photoIntervalsByObjectID[item.id])
                }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .alignmentGuide(.listRowSeparatorLeading) { d in d[.leading] }
                    .onTapGesture {
                        if isEditMode {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                toggleEditSelection(for: item)
                            }
                        } else {
                            withAnimation { onSelectItem(item) }
                        }
                    }
                    .listRowBackground(
                        isEditMode
                            ? (selectedEditItems.contains(item.id) ? Color.blue.opacity(0.15) : Color.clear)
                            : (item.id == selectedTimelineObjectID || item.selected ? Color.blue.opacity(0.3) : Color.clear)
                    )
                    .id(displayItem.id)
                    .onAppear {
                        visibleIDs.insert(displayItem.id)
                        updateActiveScrollID()
                    }
                    .onDisappear {
                        visibleIDs.remove(displayItem.id)
                        updateActiveScrollID()
                    }

            case .groupHeader(_, let groupUUID, let items, let isExpanded):
                HStack(spacing: 0) {
                    if isEditMode {
                        // In edit mode, allow selecting all items in the group
                        editModeGroupSelectionCircle(for: items)
                    }
                    groupHeaderRow(groupID: groupUUID, items: items, isExpanded: isExpanded)
                }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .alignmentGuide(.listRowSeparatorLeading) { d in d[.leading] }
                    .onTapGesture {
                        if isEditMode {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                let allSelected = items.allSatisfy { selectedEditItems.contains($0.id) }
                                for item in items {
                                    if allSelected {
                                        selectedEditItems.remove(item.id)
                                    } else {
                                        selectedEditItems.insert(item.id)
                                    }
                                }
                            }
                        } else {
                            withAnimation {
                                onSelectGroup?(items)
                            }
                        }
                    }
                    .listRowBackground(
                        isEditMode
                            ? (items.contains(where: { selectedEditItems.contains($0.id) }) ? Color.blue.opacity(0.15) : Color.clear)
                            : (items.contains(where: { $0.selected }) ? Color.blue.opacity(0.3) : Color.clear)
                    )
                    .id(displayItem.id)
                    .onAppear {
                        visibleIDs.insert(displayItem.id)
                        updateActiveScrollID()
                    }
                    .onDisappear {
                        visibleIDs.remove(displayItem.id)
                        updateActiveScrollID()
                    }

            case .groupChild(let item):
                HStack(spacing: 0) {
                    if isEditMode {
                        editModeSelectionCircle(for: item)
                    }
                    itemRow(item: item, showEdit: !isEditMode, photoInterval: photoIntervalsByObjectID[item.id])
                }
                    .padding(.leading, 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .alignmentGuide(.listRowSeparatorLeading) { d in d[.leading] }
                    .onTapGesture {
                        if isEditMode {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                toggleEditSelection(for: item)
                            }
                        } else {
                            withAnimation { onSelectItem(item) }
                        }
                    }
                    .listRowBackground(
                        isEditMode
                            ? (selectedEditItems.contains(item.id) ? Color.blue.opacity(0.15) : Color(.secondarySystemBackground))
                            : (item.id == selectedTimelineObjectID || item.selected ? Color.blue.opacity(0.3) : Color(.secondarySystemBackground))
                    )
                    .id(displayItem.id)
                    .onAppear {
                        visibleIDs.insert(displayItem.id)
                        updateActiveScrollID()
                    }
                    .onDisappear {
                        visibleIDs.remove(displayItem.id)
                        updateActiveScrollID()
                    }
            }
        }
        .refreshable {
            onRefresh()
        }
        .listStyle(PlainListStyle())
        .onAppear {
            FileManagerUtil.logData(context: "TimelineScroll", content: "[onAppear] TimelineView appeared. selectedDate: \(selectedDate)", verbosity: 4)
            applyScrollPositionForCurrentDay()
        }
        .onChange(of: selectedDate) { oldDate, newDate in
            FileManagerUtil.logData(context: "TimelineScroll", content: "[onChange selectedDate] selectedDate changed from \(oldDate) to \(newDate). Locking scroll updates.", verbosity: 4)
            scrolledDateKey = nil // Lock scroll updates during transition
            visibleIDs.removeAll() // Clear visible IDs
            activeScrollID = nil // Reset activeScrollID
        }
        .onChange(of: timelineObjects.map { $0.id }) { oldIds, newIds in
            FileManagerUtil.logData(context: "TimelineScroll", content: "[onChange timelineObjects] IDs changed. Old count: \(oldIds.count), New count: \(newIds.count). Restoring scroll position.", verbosity: 4)
            applyScrollPositionForCurrentDay()
        }
        .onChange(of: activeScrollID) { oldId, newId in
            let key = selectedDayKey
            let displayedKey = displayedObjectsDayKey
            
            FileManagerUtil.logData(context: "TimelineScroll", content: "[onChange activeScrollID] activeScrollID changed from \(oldId ?? "nil") to \(newId ?? "nil"). scrolledDateKey: \(scrolledDateKey ?? "nil"), selectedDayKey: \(key), displayedKey: \(displayedKey ?? "nil")", verbosity: 5)
            
            // Only save if scroll-tracking is unlocked and matches the currently displayed day
            guard let displayedKey = displayedKey,
                  scrolledDateKey == key,
                  displayedKey == key else {
                FileManagerUtil.logData(context: "TimelineScroll", content: "[onChange activeScrollID] Ignored scroll update (scrolledDateKey mismatch or still transitioning)", verbosity: 4)
                return
            }
            
            if let newId = newId {
                if displayItems.contains(where: { $0.id == newId }) {
                    FileManagerUtil.logData(context: "TimelineScroll", content: "[onChange activeScrollID] Saving scroll position: \(newId) under key: \(key)", verbosity: 4)
                    scrollPositions[key] = newId
                } else {
                    FileManagerUtil.logData(context: "TimelineScroll", content: "[onChange activeScrollID] Ignored scroll update because ID \(newId) is not in current displayItems", verbosity: 4)
                }
            }
        }
        .onChange(of: pendingScrollTarget) { _, targetId in
            // This onChange runs inside the ScrollViewReader closure where proxy is guaranteed valid.
            if let targetId = targetId {
                FileManagerUtil.logData(context: "TimelineScroll", content: "[pendingScrollTarget] Calling proxy.scrollTo: \(targetId)", verbosity: 4)
                proxy.scrollTo(targetId, anchor: .top)
                pendingScrollTarget = nil
            }
        }
        .onChange(of: selectedTimelineObjectID) { _, newId in
            guard let newId = newId else { return }
            if let displayItem = displayItems.first(where: { item in
                switch item {
                case .single(let obj):
                    return obj.id == newId
                case .groupHeader(_, _, let items, _):
                    return items.contains(where: { $0.id == newId })
                case .groupChild(let obj):
                    return obj.id == newId
                }
            }) {
                FileManagerUtil.logData(context: "TimelineScroll", content: "[selectedTimelineObjectID] Scrolling to display item: \(displayItem.id) for selected object: \(newId)", verbosity: 4)
                withAnimation {
                    proxy.scrollTo(displayItem.id, anchor: .center)
                }
            }
        }
        } // end ScrollViewReader
        .sheet(isPresented: $showingEditSheet, content: {
            if let timelineObject = editingTimelineObject {
                if timelineObject.type == .waypoint {
                    EditVisitView(
                        timelineObject: timelineObject,
                        fileDate: selectedDate,
                        onSave: { place, wasUnknown in
                            onEditVisit?(timelineObject, place, wasUnknown)
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
                photoStore: photoStore
            )
        }
        .onChange(of: showingEditSheet) { _, newValue in
            if !newValue {
                editingTimelineObject = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .loadTodayData)) { _ in
            showingEditSheet = false
            photoSheet = nil
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
                            PlaceIconView(icon: PreferencesManager.shared.icon(for: item.trackType), fallbackColor: PreferencesManager.shared.color(for: item.trackType))
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
                                initialPhotoID: photo.id
                            )
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
                            initialPhotoID: photo.id
                        )
                    }
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .task(id: photoKey) {
            if let photoKey = photoKey, let photoInterval = photoInterval, timelinePictureDisplayMode != .none {
                await photoStore.loadPhotos(for: photoKey, interval: photoInterval)
            }
        }
    }

    @ViewBuilder
    private func editButton(for item: TimelineObject) -> some View {
        if item.type == .waypoint && (item.id == selectedTimelineObjectID || item.isUnknownPlace) {
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

    // MARK: - Edit Mode Helpers

    @ViewBuilder
    private func editModeSelectionCircle(for item: TimelineObject) -> some View {
        let isSelected = selectedEditItems.contains(item.id)
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.title3)
            .foregroundColor(isSelected ? .blue : .gray)
            .padding(.trailing, 8)
    }

    @ViewBuilder
    private func editModeGroupSelectionCircle(for items: [TimelineObject]) -> some View {
        let allSelected = items.allSatisfy { selectedEditItems.contains($0.id) }
        let someSelected = !allSelected && items.contains(where: { selectedEditItems.contains($0.id) })
        Image(systemName: allSelected ? "checkmark.circle.fill" : (someSelected ? "minus.circle.fill" : "circle"))
            .font(.title3)
            .foregroundColor(allSelected ? .blue : (someSelected ? .blue.opacity(0.5) : .gray))
            .padding(.trailing, 8)
    }

    private func toggleEditSelection(for item: TimelineObject) {
        if selectedEditItems.contains(item.id) {
            selectedEditItems.remove(item.id)
        } else {
            selectedEditItems.insert(item.id)
        }
    }
}

#if DEBUG
extension TimelinePhotoStore {
    func setPreviewPhotos(_ photos: [TimelinePhoto], for key: String) {
        self.photosByKey[key] = photos
    }
    
    func setPreviewThumbnail(_ image: UIImage, for photo: TimelinePhoto, displaySize: CGSize, contentMode: PHImageContentMode) {
        let key = imageCacheKey(for: photo, displaySize: displaySize, contentMode: contentMode)
        thumbnailCache.setObject(image, forKey: key as NSString)
    }
    
    func setPreviewFullImage(_ image: UIImage, for photo: TimelinePhoto) {
        fullImageCache.setObject(image, forKey: photo.id as NSString)
        previewCache.setObject(image, forKey: photo.id as NSString)
    }

    static var preview: TimelinePhotoStore {
        let store = TimelinePhotoStore()
        let dummyPhoto = TimelinePhoto(id: "dummy", pixelWidth: 100, pixelHeight: 100)
        store.setPreviewPhotos([dummyPhoto], for: "dummy_key")
        
        let rect = CGRect(origin: .zero, size: CGSize(width: 200, height: 200))
        UIGraphicsBeginImageContext(rect.size)
        let context = UIGraphicsGetCurrentContext()
        context?.setFillColor(UIColor.systemTeal.cgColor)
        context?.fill(rect)
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        if let image {
            store.setPreviewThumbnail(image, for: dummyPhoto, displaySize: CGSize(width: 44, height: 44), contentMode: .aspectFill)
            store.setPreviewThumbnail(image, for: dummyPhoto, displaySize: CGSize(width: 56, height: 56), contentMode: .aspectFill)
            store.setPreviewThumbnail(image, for: dummyPhoto, displaySize: CGSize(width: 62, height: 62), contentMode: .aspectFill)
            store.setPreviewThumbnail(image, for: dummyPhoto, displaySize: CGSize(width: 150, height: 100), contentMode: .aspectFit)
            store.setPreviewFullImage(image, for: dummyPhoto)
        }
        return store
    }
}
#endif
