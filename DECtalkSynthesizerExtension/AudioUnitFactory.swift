import AVFoundation
import CoreAudioKit

/// Factory class for creating the DECtalk Audio Unit
/// This is the entry point specified in the extension's Info.plist
@objc(AudioUnitFactory)
public class AudioUnitFactory: NSObject, AUAudioUnitFactory {

    /// Component description for the audio unit
    private static let componentDescription = AudioComponentDescription(
        componentType: kAudioUnitType_SpeechSynthesizer,
        componentSubType: FourCharCode("dcsp"),  // DECtalk SPeech
        componentManufacturer: FourCharCode("DCTK"), // DECTalK
        componentFlags: 0,
        componentFlagsMask: 0
    )

    /// Required initializer for NSExtensionRequestHandling
    public override init() {
        super.init()
    }

    /// Creates an instance of the DECtalk audio unit
    public func createAudioUnit(with componentDescription: AudioComponentDescription) throws -> AUAudioUnit {
        return try DECtalkSynthesizerAudioUnit(componentDescription: componentDescription)
    }

    /// Required by NSExtensionRequestHandling protocol
    public func beginRequest(with context: NSExtensionContext) {
        // Audio Unit extensions don't use the standard extension request handling
    }
}

// MARK: - FourCharCode Extension

private extension FourCharCode {
    init(_ string: String) {
        var result: FourCharCode = 0
        for char in string.utf8.prefix(4) {
            result = result << 8 | FourCharCode(char)
        }
        self = result
    }
}
