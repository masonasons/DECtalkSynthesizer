import Foundation
import AVFoundation

/// Voice information for UI display
struct DECtalkVoiceInfo: Identifiable {
    let id = UUID()
    let name: String
    let identifier: String
    let icon: String
    let gender: String
    let description: String
}

/// View model for DECtalk synthesizer UI
@MainActor
class DECtalkViewModel: ObservableObject {
    @Published var voices: [DECtalkVoiceInfo] = []
    @Published var selectedVoice: DECtalkVoiceInfo?
    @Published var isAvailable: Bool = false
    @Published var statusMessage: String = ""

    /// All DECtalk voice definitions
    private let voiceDefinitions: [DECtalkVoiceInfo] = [
        DECtalkVoiceInfo(name: "Paul", identifier: "com.dectalk.voice.paul",
                         icon: "person.fill", gender: "Male",
                         description: "Default male voice"),
        DECtalkVoiceInfo(name: "Betty", identifier: "com.dectalk.voice.betty",
                         icon: "person.fill", gender: "Female",
                         description: "Female voice"),
        DECtalkVoiceInfo(name: "Harry", identifier: "com.dectalk.voice.harry",
                         icon: "person.fill", gender: "Male",
                         description: "Large male voice"),
        DECtalkVoiceInfo(name: "Frank", identifier: "com.dectalk.voice.frank",
                         icon: "person.fill", gender: "Male",
                         description: "Elderly male voice"),
        DECtalkVoiceInfo(name: "Dennis", identifier: "com.dectalk.voice.dennis",
                         icon: "person.fill", gender: "Male",
                         description: "Nasal male voice"),
        DECtalkVoiceInfo(name: "Kit", identifier: "com.dectalk.voice.kit",
                         icon: "figure.child", gender: "Child",
                         description: "Child voice"),
        DECtalkVoiceInfo(name: "Ursula", identifier: "com.dectalk.voice.ursula",
                         icon: "person.fill", gender: "Female",
                         description: "Female voice 2"),
        DECtalkVoiceInfo(name: "Rita", identifier: "com.dectalk.voice.rita",
                         icon: "person.fill", gender: "Female",
                         description: "Female voice 3"),
        DECtalkVoiceInfo(name: "Wendy", identifier: "com.dectalk.voice.wendy",
                         icon: "person.fill", gender: "Female",
                         description: "Female voice 4")
    ]

    /// Load available voices
    func loadVoices() {
        voices = voiceDefinitions

        // Select Paul as default
        if selectedVoice == nil {
            selectedVoice = voices.first
        }

        // Check if DECtalk voices are available in the system
        checkAvailability()

        // Register/update voices with the system
        updateSystemVoices()
    }

    /// Select a voice
    func selectVoice(_ voice: DECtalkVoiceInfo) {
        selectedVoice = voice
    }

    /// Check if DECtalk voices are available
    private func checkAvailability() {
        let availableVoices = AVSpeechSynthesisVoice.speechVoices()
        isAvailable = availableVoices.contains { voice in
            voice.identifier.hasPrefix("com.dectalk.voice.")
        }
    }

    /// Update voices registered with the system
    private func updateSystemVoices() {
        // Notify the system that voices have been updated
        AVSpeechSynthesisProviderVoice.updateSpeechVoices()
        statusMessage = "Voice list updated"
    }
}
