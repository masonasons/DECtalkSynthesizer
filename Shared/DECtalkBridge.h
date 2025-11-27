/*
 * DECtalkBridge.h
 * Bridge header for DECtalk speech synthesis
 */

#ifndef DECtalkBridge_h
#define DECtalkBridge_h

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// Audio format constants
#define DECTALK_SAMPLE_RATE 11025
#define DECTALK_SAMPLE_RATE_8K 8000

// Voice identifiers - Classic DECtalk voices
typedef enum {
    DECtalkVoicePaul = 0,    // Default male voice
    DECtalkVoiceBetty = 1,   // Female voice
    DECtalkVoiceHarry = 2,   // Large male voice
    DECtalkVoiceFrank = 3,   // Elderly male voice
    DECtalkVoiceDennis = 4,  // Nasal male voice
    DECtalkVoiceKit = 5,     // Child voice
    DECtalkVoiceUrsula = 6,  // Female voice 2
    DECtalkVoiceRita = 7,    // Female voice 3
    DECtalkVoiceWendy = 8,   // Female voice 4
    DECtalkVoiceCount = 9
} DECtalkVoice;

// Error codes
typedef enum {
    DECtalkErrorNone = 0,
    DECtalkErrorInitFailed = 1,
    DECtalkErrorSynthFailed = 2,
    DECtalkErrorInvalidVoice = 3,
    DECtalkErrorBufferFull = 4
} DECtalkError;

// Synthesis state
typedef struct {
    int16_t *audioBuffer;
    int32_t bufferSize;
    int32_t samplesWritten;
    bool isComplete;
} DECtalkSynthState;

// Initialize the DECtalk engine
// Returns 0 on success, error code otherwise
int dectalk_init(void);

// Shutdown the DECtalk engine
void dectalk_shutdown(void);

// Set the current voice
// Returns 0 on success, error code otherwise
int dectalk_set_voice(DECtalkVoice voice);

// Get the current voice
DECtalkVoice dectalk_get_voice(void);

// Synthesize text to audio buffer
// text: Input text (supports DECtalk commands embedded)
// buffer: Output buffer for 16-bit PCM audio samples
// bufferSize: Size of buffer in samples
// samplesWritten: Output - number of samples written
// Returns 0 on success, error code otherwise
int dectalk_synthesize(const char *text, int16_t *buffer, int32_t bufferSize, int32_t *samplesWritten);

// Synthesize text and call callback for each chunk of audio
// text: Input text
// callback: Called for each chunk of audio data
// userData: User data passed to callback
typedef void (*DECtalkAudioCallback)(int16_t *samples, int32_t count, void *userData);
int dectalk_synthesize_with_callback(const char *text, DECtalkAudioCallback callback, void *userData);

// Extract plain text from SSML
// ssml: Input SSML string
// plainText: Output buffer for plain text
// maxLength: Maximum length of output buffer
// Returns length of extracted text
int dectalk_extract_text_from_ssml(const char *ssml, char *plainText, int32_t maxLength);

// Get voice name for display
const char* dectalk_get_voice_name(DECtalkVoice voice);

// Get voice command string (e.g., "[:np]" for Paul)
const char* dectalk_get_voice_command(DECtalkVoice voice);

// Get sample rate
int dectalk_get_sample_rate(void);

// Reset the synthesis engine
int dectalk_reset(void);

// Sync/flush pending audio
int dectalk_sync(void);

// Set speaking rate (words per minute, 75-600)
int dectalk_set_rate(int wpm);

// Get speaking rate
int dectalk_get_rate(void);

// Set volume (0-100)
int dectalk_set_volume(int volume);

// Get version string
const char* dectalk_get_version(void);

#ifdef __cplusplus
}
#endif

#endif /* DECtalkBridge_h */
