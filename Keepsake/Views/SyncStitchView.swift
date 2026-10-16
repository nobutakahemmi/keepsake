import AVKit
import SwiftUI

struct SyncStitchView: View {
    @ObservedObject var library: LibraryStore
    @StateObject private var stitchSession = StitchSession()
    @State private var clipAID: UUID?
    @State private var clipBID: UUID?
    @State private var nudge: Double = 0
    @State private var layout: LayoutKind = .sideBySide
    @State private var includeTitle = true
    @State private var player = AVPlayer()
    @State private var previewMessage: String?
    @State private var isPreviewLoading = false
    @State private var errorMessage: String?
    @State private var savedTape: TapeRecord?
    @State private var showSaved = false
    @State private var showPlayer = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                clipPickers
                alignmentSection
                pictureSection
                previewSection
                stitchSection
            }
            .padding()
        }
        .navigationTitle("Make a Keepsake")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: selectDefaults)
        .task(id: previewToken) {
            await loadPreview()
        }
        .navigationDestination(isPresented: $showPlayer) {
            if let savedTape {
                TapePlayerView(url: library.tapeURL(savedTape), title: savedTape.title)
            }
        }
        .alert("Keepsake saved", isPresented: $showSaved) {
            Button("Watch") { showPlayer = true }
            Button("Done", role: .cancel) { dismiss() }
        } message: {
            Text("It's in the Tapes tab. You can share it from there.")
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var clipA: ClipRecord? {
        library.clips.first { $0.id == clipAID }
    }

    private var clipB: ClipRecord? {
        library.clips.first { $0.id == clipBID }
    }

    private var plan: SyncPlan? {
        guard let clipA, let clipB, clipA.id != clipB.id else { return nil }
        return SyncMath.plan(clipA: clipA.timing, clipB: clipB.timing, nudgeSeconds: nudge)
    }

    private var previewToken: String {
        let milliseconds = SyncMath.snappedNudge(milliseconds: Int64((nudge * 1000).rounded()))
        return "\(clipAID?.uuidString ?? "-")|\(clipBID?.uuidString ?? "-")|\(milliseconds)|\(layout.rawValue)|\(includeTitle)"
    }

    private var snappedNudgeText: String {
        let milliseconds = SyncMath.snappedNudge(milliseconds: Int64((nudge * 1000).rounded()))
        return SyncMath.signedSeconds(milliseconds: milliseconds)
    }

    private var clipPickers: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Clips")
                .font(.headline)
            Picker("This phone", selection: $clipAID) {
                Text("Choose").tag(nil as UUID?)
                ForEach(library.clips) { clip in
                    Text(clip.displayName).tag(clip.id as UUID?)
                }
            }
            .accessibilityLabel("Clip from this phone")

            Picker("Other phone", selection: $clipBID) {
                Text("Choose").tag(nil as UUID?)
                ForEach(library.clips) { clip in
                    Text(clip.displayName).tag(clip.id as UUID?)
                }
            }
            .accessibilityLabel("Clip from the other phone")
        }
    }

    private var alignmentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sync")
                .font(.headline)
            if let plan, let clipA, let clipB {
                Text("\(clipA.displayName) started \(TimeFormat.dateTime(milliseconds: clipA.startMilliseconds)).")
                Text("\(clipB.displayName) started \(TimeFormat.dateTime(milliseconds: clipB.startMilliseconds)).")
                Text(leadSentence(plan: plan, nameA: clipA.displayName, nameB: clipB.displayName))
                if plan.overlapDuration.milliseconds == 0 {
                    Text("These clips do not overlap, so each person will appear alone. Record them at the same time, or check the start times.")
                        .font(.footnote)
                } else {
                    Text(String(format: "They overlap for %.2f seconds.", Double(plan.overlapDuration.milliseconds) / 1000))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if clipA.startTimeSource == .importedAt || clipB.startTimeSource == .importedAt {
                    Text("One clip has no start time saved in the file, so the alignment may be off.")
                        .font(.footnote)
                }
            } else {
                Text("Choose two different clips.")
            }

            Text("Nudge the other clip: \(snappedNudgeText)")
            Slider(value: $nudge, in: -2...2, step: 0.05) {
                Text("Nudge")
            } minimumValueLabel: {
                Text("-2 s")
            } maximumValueLabel: {
                Text("+2 s")
            }
            .accessibilityLabel("Nudge the other clip")
            .accessibilityValue(Text(snappedNudgeText))
            Text("Positive nudge makes the other clip start later. Each step is 0.05 seconds, up to 2 seconds either way.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var pictureSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Picture")
                .font(.headline)
            Text("Layout")
                .font(.body)
            Picker("Layout", selection: $layout) {
                ForEach(LayoutKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("Layout")

            Toggle("Title card", isOn: $includeTitle)
            Text("Shows both names and the date for the first 3 seconds. The sound keeps playing underneath.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Preview")
                .font(.headline)
            ZStack {
                VideoPlayer(player: player)
                    .frame(maxWidth: .infinity)
                    .frame(height: layout == .stacked ? 360 : 220)
                    .accessibilityLabel("Preview of the keepsake")
                if isPreviewLoading {
                    ProgressView("Updating preview")
                        .padding()
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            if let previewMessage {
                Text(previewMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Button("Play Preview") {
                player.play()
            }
            .disabled(player.currentItem == nil)
            .accessibilityHint("Plays the lined-up clips without saving.")
            Text("If the title card is on, the two clips appear after 3 seconds.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var stitchSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button("Make the Keepsake") {
                Task { await makeKeepsake() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(plan == nil || stitchSession.isRunning)
            .frame(maxWidth: .infinity)
            .accessibilityHint("Saves a new video in the Tapes tab.")

            if stitchSession.isRunning {
                ProgressView(value: stitchSession.progress) {
                    Text("Making your keepsake")
                } currentValueLabel: {
                    Text("\(Int((stitchSession.progress * 100).rounded())) percent")
                }
                .accessibilityLabel("Making your keepsake")
                .accessibilityValue(Text("\(Int((stitchSession.progress * 100).rounded())) percent"))
            }
        }
    }

    private func selectDefaults() {
        if clipAID == nil {
            clipAID = library.clips.first?.id
        }
        if clipBID == nil {
            clipBID = library.clips.first { $0.id != clipAID }?.id
        }
    }

    private func leadSentence(plan: SyncPlan, nameA: String, nameB: String) -> String {
        let lead = SyncMath.otherClipLeadMilliseconds(plan)
        if lead == 0 {
            return "\(nameA) and \(nameB) start at the same moment."
        }
        let seconds = String(format: "%.2f", abs(Double(lead)) / 1000)
        if lead > 0 {
            return "\(nameB) starts \(seconds) seconds later than \(nameA)."
        }
        return "\(nameB) starts \(seconds) seconds earlier than \(nameA)."
    }

    private func makeRequest() -> StitchRequest? {
        guard let clipA, let clipB, clipA.id != clipB.id else { return nil }
        return StitchRequest(
            urlA: library.clipURL(clipA),
            urlB: library.clipURL(clipB),
            nameA: clipA.displayName,
            nameB: clipB.displayName,
            startA: clipA.startDate,
            startB: clipB.startDate,
            nudgeSeconds: nudge,
            layout: layout,
            includeTitleCard: includeTitle
        )
    }

    private func loadPreview() async {
        guard !stitchSession.isRunning else { return }
        try? await Task.sleep(nanoseconds: 250_000_000)
        guard !Task.isCancelled, !stitchSession.isRunning else { return }
        guard let request = makeRequest() else {
            player.replaceCurrentItem(with: nil)
            previewMessage = "Choose two different clips."
            return
        }
        isPreviewLoading = true
        defer { isPreviewLoading = false }
        do {
            let build = try await Stitcher.build(request)
            guard !Task.isCancelled, !stitchSession.isRunning else { return }
            let item = AVPlayerItem(asset: build.composition)
            item.videoComposition = build.videoComposition
            player.replaceCurrentItem(with: item)
            _ = await player.seek(to: .zero)
            previewMessage = nil
        } catch {
            guard !Task.isCancelled else { return }
            player.replaceCurrentItem(with: nil)
            previewMessage = error.localizedDescription
        }
    }

    private func makeKeepsake() async {
        guard let request = makeRequest() else { return }
        player.pause()
        player.replaceCurrentItem(with: nil)
        stitchSession.begin()
        defer { stitchSession.end() }
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        do {
            let build = try await Stitcher.build(request)
            try await Stitcher.export(build, to: temp) { value in
                Task { @MainActor in
                    stitchSession.progress = value
                }
            }
            let tape = try library.addTape(
                from: temp,
                nameA: request.nameA,
                nameB: request.nameB,
                originMilliseconds: build.plan.origin.milliseconds,
                layout: request.layout,
                nudgeMilliseconds: build.plan.nudge.milliseconds,
                includesTitleCard: request.includeTitleCard
            )
            savedTape = tape
            showSaved = true
        } catch {
            try? FileManager.default.removeItem(at: temp)
            errorMessage = error.localizedDescription
        }
    }
}
