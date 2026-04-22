//
//  HomeView.swift
//  CaptureMobile

import SwiftUI
import Combine
import PostHog

// MARK: - Image Cache (Memory + Disk)

final class ImageCache {
    static let shared = ImageCache()
    private let memoryCache = NSCache<NSString, UIImage>()
    private let session: URLSession

    private init() {
        memoryCache.countLimit = 100
        memoryCache.totalCostLimit = 50 * 1024 * 1024

        let diskCache = URLCache(
            memoryCapacity: 30 * 1024 * 1024,
            diskCapacity: 200 * 1024 * 1024
        )
        let config = URLSessionConfiguration.default
        config.urlCache = diskCache
        config.requestCachePolicy = .returnCacheDataElseLoad
        session = URLSession(configuration: config)
    }

    func image(for url: URL) -> UIImage? {
        memoryCache.object(forKey: url.absoluteString as NSString)
    }

    func store(_ image: UIImage, for url: URL) {
        memoryCache.setObject(image, forKey: url.absoluteString as NSString)
    }

    func data(from url: URL) async throws -> Data {
        let (data, _) = try await session.data(from: url)
        return data
    }
}

struct CachedAsyncImage<Placeholder: View>: View {
    let url: URL?
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var image: UIImage?
    @State private var isLoading = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                placeholder()
                    .onAppear { loadImage() }
            }
        }
    }

    private func loadImage() {
        guard let url, !isLoading else { return }

        if let cached = ImageCache.shared.image(for: url) {
            self.image = cached
            return
        }

        isLoading = true
        Task {
            do {
                let data = try await ImageCache.shared.data(from: url)
                if let uiImage = UIImage(data: data) {
                    ImageCache.shared.store(uiImage, for: url)
                    await MainActor.run { self.image = uiImage }
                }
            } catch {
                print("Image load failed: \(error)")
            }
            await MainActor.run { isLoading = false }
        }
    }
}

// MARK: - Relative Time Text

struct RelativeTimeText: View {
    let date: Date
    @State private var text: String = ""
    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        Text(text)
            .font(CaptureFont.monoSm)
            .foregroundStyle(CaptureColors.textHint)
            .onAppear { text = timeAgo(from: date) }
            .onReceive(timer) { _ in text = timeAgo(from: date) }
    }

    private func timeAgo(from date: Date) -> String {
        let seconds = Date().timeIntervalSince(date)
        if seconds < 60 { return "Just now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m ago" }
        if seconds < 86400 { return "\(Int(seconds / 3600))h ago" }
        if seconds < 604_800 { return "\(Int(seconds / 86400))d ago" }
        return "\(Int(seconds / 604_800))w ago"
    }
}

// MARK: - Home View

struct HomeView: View {
    @ObservedObject var captureHistory = CaptureHistoryManager.shared
    @ObservedObject var processingState = CaptureProcessingState.shared
    @State private var selectedCategory: String = "all"

    private let categories = ["all", "restaurant", "event", "movie", "book", "clothing", "note", "other"]

    var body: some View {
        NavigationStack {
            ZStack {
                CaptureColors.bg.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: CaptureSpacing.lg) {
                        headerView
                        categoryChip

                        if processingState.isProcessing && !processingState.hasPendingFailure {
                            processingCard
                        }

                        if captureHistory.captures.isEmpty && !processingState.isProcessing && !captureHistory.isLoading {
                            emptyState
                        }

                        if processingState.hasPendingFailure {
                            failedCard
                        }

                        capturesList
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 100)
                }
            }
            .navigationBarHidden(true)
            .onAppear {
                processingState.checkForFailure()
                Task { await captureHistory.loadCaptures(category: selectedCategory) }
            }
            .preferredColorScheme(.light)
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Text("Your Captures")
                .font(CaptureFont.display)
                .foregroundStyle(CaptureColors.text)
                .tracking(-0.5)
            Spacer()
        }
        .padding(.horizontal, CaptureSpacing.screenHorizontalFeature)
    }

    // MARK: - Category Chip (Dropdown Menu)

    private var categoryChip: some View {
        HStack {
            Menu {
                ForEach(categories, id: \.self) { cat in
                    Button {
                        selectedCategory = cat
                        Task { await captureHistory.loadCaptures(category: cat) }
                    } label: {
                        HStack {
                            Text(categoryDisplayName(cat))
                            if selectedCategory == cat {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 12))
                    Text(categoryDisplayName(selectedCategory))
                        .font(CaptureFont.caption)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10))
                }
                .foregroundStyle(CaptureColors.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(CaptureColors.primaryMuted, in: RoundedRectangle(cornerRadius: CaptureRadius.md))
                .overlay(RoundedRectangle(cornerRadius: CaptureRadius.md).stroke(CaptureColors.primary.opacity(0.10)))
            }
            Spacer()
        }
        .padding(.horizontal, CaptureSpacing.screenHorizontalFeature)
    }

    private func categoryDisplayName(_ cat: String) -> String {
        cat == "all" ? "All" : cat.capitalized + "s"
    }

    // MARK: - Processing Card

    private var processingCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(CaptureColors.surface).frame(width: 32, height: 32)
                ProgressView().scaleEffect(0.8).tint(CaptureColors.primary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Analyzing capture...")
                    .font(CaptureFont.title)
                    .foregroundStyle(CaptureColors.text)
                Text("Extracting data")
                    .font(CaptureFont.bodySm)
                    .foregroundStyle(CaptureColors.textSecondary)
            }
            Spacer()
        }
        .padding(CaptureSpacing.base)
        .background(CaptureColors.card, in: RoundedRectangle(cornerRadius: CaptureRadius.lg))
        .overlay(RoundedRectangle(cornerRadius: CaptureRadius.lg).stroke(CaptureColors.border))
        .captureShadow(.card)
        .padding(.horizontal, CaptureSpacing.screenHorizontalFeature)
    }

    // MARK: - Failed Card

    private var failedCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16)).foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(CaptureColors.warning, in: RoundedRectangle(cornerRadius: CaptureRadius.md))
            VStack(alignment: .leading, spacing: 2) {
                Text("Capture failed")
                    .font(CaptureFont.title)
                    .foregroundStyle(CaptureColors.text)
                Text("Please try again")
                    .font(CaptureFont.bodySm)
                    .foregroundStyle(CaptureColors.textSecondary)
            }
            Spacer()
            Button { processingState.clearFailure() } label: {
                Image(systemName: "xmark").font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CaptureColors.textTertiary).padding(8)
            }.buttonStyle(.plain)
        }
        .padding(CaptureSpacing.base)
        .background(CaptureColors.warningMuted, in: RoundedRectangle(cornerRadius: CaptureRadius.lg))
        .overlay(RoundedRectangle(cornerRadius: CaptureRadius.lg).stroke(CaptureColors.warning.opacity(0.15)))
        .padding(.horizontal, CaptureSpacing.screenHorizontalFeature)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: CaptureSpacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: CaptureRadius.xl)
                    .fill(CaptureColors.text.opacity(0.06))
                    .frame(width: 56, height: 56)
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 24))
                    .foregroundStyle(CaptureColors.textTertiary)
            }
            Text("No captures yet")
                .font(CaptureFont.heading)
                .foregroundStyle(CaptureColors.textSecondary)
            Text("Take a screenshot, photo, or write a note to get started.")
                .font(CaptureFont.bodySm)
                .foregroundStyle(CaptureColors.textTertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, CaptureSpacing.xxxl)
        .padding(.horizontal, CaptureSpacing.screenHorizontalFeature)
    }

    // MARK: - Captures List

    private var capturesList: some View {
        LazyVStack(spacing: CaptureSpacing.cardGap) {
            ForEach(captureHistory.captures, id: \.id) { capture in
                NavigationLink(value: capture.id) {
                    CaptureCardView(capture: capture)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, CaptureSpacing.screenHorizontalFeature)
        .navigationDestination(for: String.self) { captureID in
            if let capture = captureHistory.captures.first(where: { $0.id == captureID }) {
                CaptureDetailView(capture: capture)
            }
        }
    }
}

// MARK: - Capture Card

struct CaptureCardView: View {
    let capture: Capture

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                categoryPillSmall
                Spacer()
                RelativeTimeText(date: capture.timeCaptured)
            }

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(capture.title)
                        .font(CaptureFont.title)
                        .foregroundStyle(CaptureColors.text)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)

                    if !capture.tags.isEmpty {
                        TagChipsRow(tags: capture.tags)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let urlStr = capture.imageUrl, let url = URL(string: urlStr) {
                    CachedAsyncImage(url: url) {
                        ZStack {
                            CaptureColors.surface
                            Image(systemName: capture.categoryIcon)
                                .font(.system(size: 16))
                                .foregroundStyle(CaptureColors.textTertiary)
                        }
                    }
                    .frame(width: 46, height: 46)
                    .clipShape(RoundedRectangle(cornerRadius: CaptureRadius.md))
                }
            }
        }
        .padding(CaptureSpacing.cardPadding)
        .background(CaptureColors.card, in: RoundedRectangle(cornerRadius: CaptureRadius.lg))
        .overlay(RoundedRectangle(cornerRadius: CaptureRadius.lg).stroke(CaptureColors.border, lineWidth: 0.5))
        .captureShadow(.card)
    }

    private var categoryPillSmall: some View {
        HStack(spacing: 5) {
            Image(systemName: capture.categoryIcon)
                .font(.system(size: 9, weight: .semibold))
            Text(capture.categoryLabel.uppercased())
                .font(CaptureFont.monoSection)
                .tracking(0.8)
        }
        .foregroundStyle(CaptureColors.primary)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(CaptureColors.primaryMuted, in: Capsule())
    }
}

// MARK: - Capture Detail View

struct CaptureDetailView: View {
    let capture: Capture
    @ObservedObject var captureHistory = CaptureHistoryManager.shared
    @State private var showFullscreenImage = false
    @State private var showDeleteConfirm = false
    @State private var editedContent: String = ""
    @State private var isSavingContent = false
    @State private var showReanalyzingBanner = false
    @State private var showDetailsSheet = false
    @FocusState private var isEditorFocused: Bool
    @Environment(\.dismiss) private var dismiss

    private var isNote: Bool {
        capture.captureMethod == "note" || capture.category == "note"
    }

    private var originalContent: String {
        capture.content
            ?? (capture.extractedData["content"] as? String)
            ?? ""
    }

    private var contentHasChanged: Bool {
        editedContent != originalContent
    }

    var body: some View {
        Group {
            if isNote {
                noteLayout
            } else {
                standardLayout
            }
        }
        .background(CaptureColors.bg)
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.light)
        .onAppear { editedContent = originalContent }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showDeleteConfirm = true } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(CaptureColors.danger)
                }
            }
        }
        .fullScreenCover(isPresented: $showFullscreenImage) {
            FullscreenImageView(url: URL(string: capture.imageUrl ?? ""))
        }
        .sheet(isPresented: $showDetailsSheet) {
            CaptureDetailsSheet(capture: capture)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .alert("Delete Capture", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task {
                    await captureHistory.deleteCapture(id: capture.id)
                    dismiss()
                }
            }
        } message: {
            Text("Are you sure you want to delete this capture? This cannot be undone.")
        }
    }

    // MARK: - Note Layout (new-note canvas style)

    private var noteLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: CaptureSpacing.sm) {
                pillRow

                Text(capture.title)
                    .font(CaptureFont.display)
                    .foregroundStyle(CaptureColors.text)
                    .tracking(-0.5)
            }
            .padding(.top, CaptureSpacing.base)
            .padding(.horizontal, CaptureSpacing.xl)

            if showReanalyzingBanner {
                reanalyzingBanner
                    .padding(.top, CaptureSpacing.md)
                    .padding(.horizontal, CaptureSpacing.xl)
            }

            noteEditor
                .padding(.top, CaptureSpacing.md)
                .padding(.horizontal, CaptureSpacing.screenHorizontalFeature)
        }
        .onTapGesture { isEditorFocused = true }
    }

    private var noteEditor: some View {
        TextEditor(text: $editedContent)
            .font(CaptureFont.heading)
            .foregroundStyle(CaptureColors.text)
            .scrollContentBackground(.hidden)
            .focused($isEditorFocused)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    if contentHasChanged {
                        noteEditorSaveBar
                    }
                }
            }
    }

    private var noteEditorSaveBar: some View {
        HStack(spacing: 0) {
            Button {
                isEditorFocused = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(CaptureColors.textSecondary)
                    .frame(width: 44)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.plain)

            Button {
                saveContent()
                isEditorFocused = false
            } label: {
                HStack(spacing: 6) {
                    if isSavingContent {
                        ProgressView().scaleEffect(0.7).tint(.white)
                    } else {
                        Text("Save").font(.system(size: 15, weight: .bold))
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(CaptureColors.primary, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isSavingContent)
        }
    }

    // MARK: - Standard Layout (non-note captures)

    private var standardLayout: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: CaptureSpacing.lg) {
                if let urlStr = capture.imageUrl, let url = URL(string: urlStr) {
                    CachedAsyncImage(url: url) {
                        ZStack {
                            CaptureColors.surface
                            Image(systemName: capture.categoryIcon)
                                .font(.system(size: 40)).foregroundStyle(CaptureColors.textTertiary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: CaptureRadius.xl))
                    .onTapGesture { showFullscreenImage = true }
                }

                VStack(alignment: .leading, spacing: CaptureSpacing.sm) {
                    pillRow

                    Text(capture.title)
                        .font(CaptureFont.headingLg)
                        .foregroundStyle(CaptureColors.text)
                }
            }
            .padding(CaptureSpacing.screenHorizontalFeature)
            .padding(.bottom, CaptureSpacing.xxxl)
        }
    }

    // MARK: - Pills

    private var pillRow: some View {
        HStack(spacing: CaptureSpacing.sm) {
            categoryPill
            Spacer(minLength: CaptureSpacing.sm)
            detailsPill
        }
    }

    private var categoryPill: some View {
        HStack(spacing: 6) {
            Image(systemName: capture.categoryIcon)
                .font(.system(size: 10, weight: .semibold))
            Text(capture.categoryLabel.uppercased())
                .font(CaptureFont.monoSection)
                .tracking(0.8)
        }
        .foregroundStyle(CaptureColors.primary)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(CaptureColors.primaryMuted, in: Capsule())
    }

    private var detailsPill: some View {
        Button {
            showDetailsSheet = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.system(size: 11, weight: .semibold))
                Text("SEE DETAILS")
                    .font(CaptureFont.monoSection)
                    .tracking(0.8)
            }
            .foregroundStyle(CaptureColors.primary)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(CaptureColors.primaryMuted, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Shared helpers

    private var reanalyzingBanner: some View {
        HStack(spacing: 10) {
            ProgressView().scaleEffect(0.7).tint(CaptureColors.primary)
            Text("Re-analyzing capture...")
                .font(CaptureFont.bodySm)
                .fontWeight(.medium)
                .foregroundStyle(CaptureColors.textSecondary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(CaptureColors.surface, in: RoundedRectangle(cornerRadius: CaptureRadius.lg))
    }

    private func saveContent() {
        guard let userID = AppleAuthManager.shared.getUserID() else { return }
        guard contentHasChanged else { return }
        isSavingContent = true
        Task {
            let success = await APIService.shared.updateCaptureContent(
                captureID: capture.id, userID: userID, content: editedContent
            )
            await MainActor.run {
                isSavingContent = false
                if success {
                    showReanalyzingBanner = true
                    Task {
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        await captureHistory.loadCaptures()
                        await MainActor.run { showReanalyzingBanner = false }
                    }
                }
            }
        }
    }

}

// MARK: - Capture Details Sheet

struct CaptureDetailsSheet: View {
    let capture: Capture
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: CaptureSpacing.lg) {
                    infoSection

                    if !extractedPairs.isEmpty {
                        extractedSection
                    }
                }
                .padding(CaptureSpacing.screenHorizontalFeature)
                .padding(.top, CaptureSpacing.sm)
                .padding(.bottom, CaptureSpacing.xxxl)
            }
            .background(CaptureColors.bg)
            .navigationTitle("Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(CaptureColors.primary)
                }
            }
        }
    }

    // MARK: - Static Capture Columns

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: CaptureSpacing.sm) {
            detailRow(label: "Category", value: capture.categoryLabel)
            separator
            detailRow(label: "Source", value: capture.methodLabel)
            separator
            detailRow(label: "Captured", value: capturedDateString)
            if !capture.tags.isEmpty {
                separator
                tagsRow
            }
        }
        .padding(CaptureSpacing.base)
        .background(CaptureColors.card, in: RoundedRectangle(cornerRadius: CaptureRadius.lg))
        .overlay(RoundedRectangle(cornerRadius: CaptureRadius.lg).stroke(CaptureColors.border, lineWidth: 0.5))
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(CaptureFont.bodySm)
                .foregroundStyle(CaptureColors.textTertiary)
            Spacer()
            Text(value)
                .font(CaptureFont.bodySm)
                .fontWeight(.medium)
                .foregroundStyle(CaptureColors.text)
                .multilineTextAlignment(.trailing)
        }
    }

    private var tagsRow: some View {
        HStack(alignment: .top, spacing: CaptureSpacing.sm) {
            Text("Tags")
                .font(CaptureFont.bodySm)
                .foregroundStyle(CaptureColors.textTertiary)
            Spacer(minLength: 0)
            HStack(spacing: CaptureSpacing.tagGap) {
                ForEach(capture.tags, id: \.self) { tag in
                    Text(tag)
                        .font(CaptureFont.monoXs)
                        .foregroundStyle(CaptureColors.textTertiary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(CaptureColors.text.opacity(0.03), in: RoundedRectangle(cornerRadius: CaptureRadius.sm))
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var separator: some View {
        Rectangle()
            .fill(CaptureColors.border)
            .frame(height: 1)
    }

    // MARK: - AI-Extracted

    private var extractedSection: some View {
        VStack(alignment: .leading, spacing: CaptureSpacing.sm) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12))
                Text("EXTRACTED")
                    .font(CaptureFont.monoSection)
                    .tracking(0.8)
            }
            .foregroundStyle(CaptureColors.primary)

            VStack(alignment: .leading, spacing: CaptureSpacing.sm) {
                ForEach(Array(extractedPairs.enumerated()), id: \.element.key) { index, pair in
                    detailRow(label: pair.key.replacingOccurrences(of: "_", with: " ").capitalized, value: pair.value)
                    if index < extractedPairs.count - 1 {
                        separator
                    }
                }
            }
            .padding(CaptureSpacing.base)
            .background(CaptureColors.primaryMuted, in: RoundedRectangle(cornerRadius: CaptureRadius.lg))
            .overlay(RoundedRectangle(cornerRadius: CaptureRadius.lg).stroke(CaptureColors.primary.opacity(0.08)))
        }
    }

    private var extractedPairs: [(key: String, value: String)] {
        capture.extractedData.compactMap { key, value in
            if key == "tags" || key == "content" { return nil }
            let str = "\(value)"
            guard !str.isEmpty, str != "<null>" else { return nil }
            return (key: key, value: str)
        }
        .sorted { $0.key < $1.key }
    }

    private var capturedDateString: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "EEEE, MMM d · h:mm a"
        return fmt.string(from: capture.timeCaptured)
    }
}

// MARK: - Fullscreen Image View

struct FullscreenImageView: View {
    let url: URL?
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let url {
                CachedAsyncImage(url: url) {
                    ProgressView().tint(.white)
                }
                .aspectRatio(contentMode: .fit)
                .scaleEffect(scale)
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            scale = lastScale * value
                        }
                        .onEnded { _ in
                            lastScale = max(scale, 1.0)
                            scale = max(scale, 1.0)
                        }
                )
                .onTapGesture(count: 2) {
                    withAnimation {
                        scale = scale > 1 ? 1 : 2.5
                        lastScale = scale
                    }
                }
            }

            VStack {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(12)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                }
                .padding(20)
                Spacer()
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Tag Chips Row (single line with overflow)

struct TagChipsRow: View {
    let tags: [String]

    var body: some View {
        GeometryReader { geo in
            let result = layoutTags(tags, maxWidth: geo.size.width)
            HStack(spacing: CaptureSpacing.tagGap) {
                ForEach(result.visible, id: \.self) { tag in
                    Text(tag)
                        .font(CaptureFont.monoXs)
                        .foregroundStyle(CaptureColors.textTertiary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(CaptureColors.text.opacity(0.03), in: RoundedRectangle(cornerRadius: CaptureRadius.sm))
                }
                if result.overflow > 0 {
                    Text("+\(result.overflow)")
                        .font(CaptureFont.monoXs)
                        .foregroundStyle(CaptureColors.textHint)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(CaptureColors.text.opacity(0.03), in: RoundedRectangle(cornerRadius: CaptureRadius.sm))
                }
            }
        }
        .frame(height: 24)
    }

    private func layoutTags(_ tags: [String], maxWidth: CGFloat) -> (visible: [String], overflow: Int) {
        var usedWidth: CGFloat = 0
        var visible: [String] = []
        let spacing: CGFloat = 6
        let overflowWidth: CGFloat = 40

        for (i, tag) in tags.enumerated() {
            let chipWidth = textWidth(tag) + 16
            let remaining = tags.count - visible.count - 1
            let needsOverflow = remaining > 0
            let reservedWidth = needsOverflow ? overflowWidth + spacing : 0

            if usedWidth + chipWidth + reservedWidth <= maxWidth || i == 0 {
                visible.append(tag)
                usedWidth += chipWidth + spacing
            } else {
                break
            }
        }
        return (visible, tags.count - visible.count)
    }

    private func textWidth(_ text: String) -> CGFloat {
        let font = CaptureFont.uiFont(size: 9.5, weight: .regular)
        let size = (text as NSString).size(withAttributes: [.font: font])
        return ceil(size.width)
    }
}

// MARK: - Flow Layout (wrapping tags for detail view)

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(subviews: subviews, in: proposal.width ?? 0)
        return CGSize(width: proposal.width ?? 0, height: result.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(subviews: subviews, in: bounds.width)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: ProposedViewSize(subviews[index].sizeThatFits(.unspecified))
            )
        }
    }

    private func arrange(subviews: Subviews, in width: CGFloat) -> (positions: [CGPoint], height: CGFloat) {
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
        return (positions, y + rowHeight)
    }
}

// MARK: - Preview

#Preview {
    HomeView()
}
