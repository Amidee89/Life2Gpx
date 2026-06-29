//
//  PhotoViews.swift
//  Life2Gpx
//
//  Created by Antigravity on 2026-06-29.
//

import SwiftUI
import Photos
import UIKit

struct TimelinePhotoAttachmentView: View {
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

struct TimelineSquarePhoto: View {
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

struct TimelineLargePhotoThumbnail: View {
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

struct TimelinePhotoViewer: View {
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

struct TimelinePhotoGridCell: View {
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

struct TimelinePhotoDetailView: View {
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

struct TimelinePhotoCarousel: View {
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

struct TimelineZoomableImageView: UIViewRepresentable {
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

class ZoomableImageContainerView: UIView, UIScrollViewDelegate, UIGestureRecognizerDelegate {
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

struct TimelinePhotoActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Previews

#Preview("Square Photo") {
    let store = TimelinePhotoStore.preview
    let photo = TimelinePhoto(id: "dummy", pixelWidth: 100, pixelHeight: 100)
    TimelineSquarePhoto(photo: photo, photoStore: store, size: 56)
        .padding()
}

#Preview("Large Thumbnail") {
    let store = TimelinePhotoStore.preview
    let photo = TimelinePhoto(id: "dummy", pixelWidth: 150, pixelHeight: 100)
    TimelineLargePhotoThumbnail(photo: photo, photoStore: store, height: 100)
        .padding()
}

#Preview("Grid Cell") {
    let store = TimelinePhotoStore.preview
    let photo = TimelinePhoto(id: "dummy", pixelWidth: 100, pixelHeight: 100)
    TimelinePhotoGridCell(photo: photo, photoStore: store, action: {})
        .frame(width: 112, height: 112)
        .padding()
}

#Preview("Carousel") {
    let store = TimelinePhotoStore.preview
    let photo = TimelinePhoto(id: "dummy", pixelWidth: 100, pixelHeight: 100)
    TimelinePhotoCarousel(photos: [photo], selectedPhotoID: "dummy", photoStore: store, onSelectPhoto: { _ in })
}

#Preview("Detail View") {
    NavigationStack {
        let store = TimelinePhotoStore.preview
        let photo = TimelinePhoto(id: "dummy", pixelWidth: 100, pixelHeight: 100)
        TimelinePhotoDetailView(
            photos: [photo],
            initialPhotoID: "dummy",
            photoStore: store,
            onClose: {},
            leadingCloseTitle: "Back",
            trailingCloseTitle: "Done"
        )
    }
}

#Preview("Attachment View (Medium)") {
    let store = TimelinePhotoStore.preview
    TimelinePhotoAttachmentView(
        photoStore: store,
        cacheKey: "dummy_key",
        interval: DateInterval(start: Date(), duration: 60),
        displayMode: .medium,
        onOpenPhoto: { _ in },
        onOpenAll: { _ in }
    )
    .padding()
}

#Preview("Viewer (Grid)") {
    let store = TimelinePhotoStore.preview
    let photo = TimelinePhoto(id: "dummy", pixelWidth: 100, pixelHeight: 100)
    TimelinePhotoViewer(photos: [photo], initialPhotoID: nil, closesOnDetailBack: false, photoStore: store)
}

