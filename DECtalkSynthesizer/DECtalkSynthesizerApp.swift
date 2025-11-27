import SwiftUI
import AVFoundation
import AudioToolbox
import OSLog

fileprivate let log = Logger(subsystem: "com.dectalk.synthesizer", category: "App")

@main
struct DECtalkSynthesizerApp: App {
    @StateObject private var audioUnitManager = AudioUnitManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(audioUnitManager)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        #if os(macOS)
        Settings {
            SettingsView()
        }
        #endif
    }
}

/// Manages connection to the DECtalk Audio Unit extension
class AudioUnitManager: ObservableObject {
    @Published var isConnected = false
    @Published var errorMessage: String?
    private var audioUnit: AVAudioUnit?

    init() {
        connectToAudioUnit()
    }

    func connectToAudioUnit() {
        let componentDescription = AudioComponentDescription(
            componentType: kAudioUnitType_SpeechSynthesizer,
            componentSubType: fourCharCode("dcsp"),
            componentManufacturer: fourCharCode("DCTK"),
            componentFlags: 0,
            componentFlagsMask: 0
        )

        Task {
            do {
                let unit = try await AVAudioUnit.instantiate(
                    with: componentDescription,
                    options: .loadOutOfProcess
                )
                await MainActor.run {
                    self.audioUnit = unit
                    self.isConnected = true
                    self.errorMessage = nil
                    log.info("Audio Unit instantiated successfully, calling updateSpeechVoices()")
                    // Now that the AU is loaded, update speech voices
                    AVSpeechSynthesisProviderVoice.updateSpeechVoices()
                    log.info("updateSpeechVoices() called successfully")
                    print("DECtalk Audio Unit connected successfully")
                }
            } catch {
                await MainActor.run {
                    self.isConnected = false
                    self.errorMessage = error.localizedDescription
                    print("Failed to connect to DECtalk Audio Unit: \(error)")
                }
            }
        }
    }

    private func fourCharCode(_ string: String) -> FourCharCode {
        var result: FourCharCode = 0
        for char in string.utf8.prefix(4) {
            result = result << 8 | FourCharCode(char)
        }
        return result
    }
}
