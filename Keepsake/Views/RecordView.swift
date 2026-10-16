import SwiftUI
import UIKit

struct RecordView: View {
    @ObservedObject var recorder: Recorder
    @ObservedObject var library: LibraryStore
    @State private var isBusy = false
    @State private var alertMessage: String?
    @State private var showSaved = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                CameraPreview(session: recorder.session)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .aspectRatio(3.0 / 4.0, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .accessibilityHidden(true)

                if recorder.phase == .failed {
                    Text(recorder.failureMessage ?? "The camera could not start.")
                        .font(.body)
                        .multilineTextAlignment(.center)
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .accessibilityHint("Opens Settings so you can allow the camera and microphone.")
                    Button("Try Again") {
                        recorder.prepare()
                    }
                } else {
                    TextField("Your name", text: $recorder.displayName)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.words)
                        .disabled(recorder.phase == .recording || recorder.phase == .saving)
                        .accessibilityLabel("Your name")
                        .accessibilityHint("Saved with this recording and shown on the title card.")

                    status

                    Button(action: toggleRecording) {
                        Text(buttonTitle)
                            .font(.title2)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(recorder.phase == .recording ? Color.red : Color.accentColor)
                    .disabled(recordButtonDisabled)
                    .accessibilityHint(recorder.phase == .recording
                        ? "Saves the video on this iPhone."
                        : "Records the front camera and microphone.")

                    Text("Keep this screen open while you record. Your name is saved with the video.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding()
            .navigationTitle("Record")
            .onAppear { recorder.prepare() }
            .onDisappear { recorder.pauseIfIdle() }
            .alert("Recording saved", isPresented: $showSaved) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Find it on the Clips tab. Use Share to AirDrop it to the other iPhone.")
            }
            .alert(
                "Something went wrong",
                isPresented: Binding(
                    get: { alertMessage != nil },
                    set: { if !$0 { alertMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(alertMessage ?? "")
            }
        }
    }

    @ViewBuilder
    private var status: some View {
        switch recorder.phase {
        case .idle, .preparing:
            ProgressView("Getting the camera ready")
                .accessibilityLabel("Getting the camera ready")
        case .recording:
            if let start = recorder.recordingStartedAt {
                TimelineView(.periodic(from: start, by: 0.1)) { context in
                    Text("Recording \(TimeFormat.clock(context.date.timeIntervalSince(start)))")
                        .font(.title2)
                        .monospacedDigit()
                        .accessibilityLabel("Recording")
                        .accessibilityValue(TimeFormat.clock(context.date.timeIntervalSince(start)))
                }
            } else {
                Text("Recording")
                    .font(.title2)
                    .accessibilityLabel("Recording")
            }
        case .saving:
            ProgressView("Saving")
                .accessibilityLabel("Saving the recording")
        case .ready:
            Text("Ready")
                .font(.body)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Ready to record")
        case .failed:
            EmptyView()
        }
    }

    private var buttonTitle: String {
        recorder.phase == .recording ? "Stop Recording" : "Start Recording"
    }

    private var recordButtonDisabled: Bool {
        switch recorder.phase {
        case .ready, .recording:
            return false
        case .idle, .preparing, .saving, .failed:
            return true
        }
    }

    private func toggleRecording() {
        if recorder.phase == .recording {
            recorder.stop()
            return
        }
        guard recorder.phase == .ready, !isBusy else { return }
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                let clip = try await recorder.record()
                try library.addRecording(clip)
                showSaved = true
            } catch {
                alertMessage = error.localizedDescription
            }
        }
    }
}
