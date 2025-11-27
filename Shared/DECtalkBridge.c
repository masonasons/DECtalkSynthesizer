/*
 * DECtalkBridge.c
 * Implementation of DECtalk bridge for macOS Speech Synthesis
 * Using the official DECtalk API
 */

#include "DECtalkBridge.h"
#include "dectalk/dtk/ttsapi.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <ctype.h>
#include <pthread.h>
#include <mach-o/dyld.h>
#include <libgen.h>
#include <limits.h>

// Buffer settings
#define BUFFER_SIZE 32768
#define NUM_BUFFERS 4
#define MAX_PHONEMES 128
#define MAX_INDEX_MARKS 128

// Thread-safe synthesis state
static LPTTS_HANDLE_T g_ttsHandle = NULL;
static DECtalkVoice g_currentVoice = DECtalkVoicePaul;
static bool g_initialized = false;
static bool g_inMemoryOpen = false;
static pthread_mutex_t g_mutex = PTHREAD_MUTEX_INITIALIZER;

// Callback-based synthesis state
static int16_t *g_outputBuffer = NULL;
static int32_t g_outputBufferSize = 0;
static int32_t g_outputSamplesWritten = 0;

// Internal buffers for in-memory synthesis
static TTS_BUFFER_T g_ttsBuffers[NUM_BUFFERS];
static char g_bufferData[NUM_BUFFERS][BUFFER_SIZE];

// Voice command strings for DECtalk
static const char* g_voiceCommands[] = {
    "[:np]",  // Paul
    "[:nb]",  // Betty
    "[:nh]",  // Harry
    "[:nf]",  // Frank
    "[:nd]",  // Dennis
    "[:nk]",  // Kit
    "[:nu]",  // Ursula
    "[:nr]",  // Rita
    "[:nw]"   // Wendy
};

static const char* g_voiceNames[] = {
    "Paul",
    "Betty",
    "Harry",
    "Frank",
    "Dennis",
    "Kit",
    "Ursula",
    "Rita",
    "Wendy"
};

// Callback function for DECtalk TTS messages
static void ttsCallback(LONG lParam1, LONG lParam2, DWORD dwInstanceData, UINT uiMsg) {
    // Handle buffer messages - audio data available
    if (uiMsg == TTS_MSG_BUFFER) {
        LPTTS_BUFFER_T pBuf = (LPTTS_BUFFER_T)lParam2;
        if (pBuf && pBuf->dwBufferLength > 0 && g_outputBuffer) {
            // Copy audio data to output buffer
            int32_t samplesToWrite = pBuf->dwBufferLength / sizeof(int16_t);
            int32_t remainingSpace = g_outputBufferSize - g_outputSamplesWritten;

            if (samplesToWrite > remainingSpace) {
                samplesToWrite = remainingSpace;
            }

            if (samplesToWrite > 0) {
                memcpy(g_outputBuffer + g_outputSamplesWritten,
                       pBuf->lpData,
                       samplesToWrite * sizeof(int16_t));
                g_outputSamplesWritten += samplesToWrite;
            }

            // Re-queue the buffer
            pBuf->dwBufferLength = 0;
            TextToSpeechAddBuffer(g_ttsHandle, pBuf);
        }
    }
}

// Helper function to get the path to the dictionary file
static char* get_dictionary_path(void) {
    static char dict_path[PATH_MAX] = {0};

    // Get the path to the current executable
    char exec_path[PATH_MAX];
    uint32_t size = sizeof(exec_path);

    if (_NSGetExecutablePath(exec_path, &size) != 0) {
        fprintf(stderr, "DECtalk: Failed to get executable path\n");
        return NULL;
    }

    // Get the directory containing the executable (MacOS folder)
    char *dir = dirname(exec_path);

    // The Resources folder is at ../Resources relative to the MacOS folder
    // Build the path to the dictionary file in Resources
    snprintf(dict_path, sizeof(dict_path), "%s/../Resources/dtalk_us.dic", dir);

    fprintf(stderr, "DECtalk: Dictionary path: %s\n", dict_path);

    // Check if the file exists
    FILE *f = fopen(dict_path, "r");
    if (f) {
        fclose(f);
        fprintf(stderr, "DECtalk: Dictionary file found\n");
        return dict_path;
    } else {
        fprintf(stderr, "DECtalk: Dictionary file NOT found at %s\n", dict_path);
        return NULL;
    }
}

int dectalk_init(void) {
    pthread_mutex_lock(&g_mutex);

    if (g_initialized) {
        pthread_mutex_unlock(&g_mutex);
        return DECtalkErrorNone;
    }

    // Initialize buffers
    for (int i = 0; i < NUM_BUFFERS; i++) {
        memset(&g_ttsBuffers[i], 0, sizeof(TTS_BUFFER_T));
        g_ttsBuffers[i].lpData = g_bufferData[i];
        g_ttsBuffers[i].dwMaximumBufferLength = BUFFER_SIZE;
        g_ttsBuffers[i].lpPhonemeArray = NULL;
        g_ttsBuffers[i].lpIndexArray = NULL;
        g_ttsBuffers[i].dwMaximumNumberOfPhonemeChanges = 0;
        g_ttsBuffers[i].dwMaximumNumberOfIndexMarks = 0;
    }

    // Get the path to the dictionary file
    char *dict_path = get_dictionary_path();

    // Start DECtalk with no audio device (we'll use in-memory mode)
    // Use TextToSpeechStartupExFonix to specify the dictionary path
    DWORD devOptions = DO_NOT_USE_AUDIO_DEVICE;
    MMRESULT result = TextToSpeechStartupExFonix(&g_ttsHandle,
                                                  WAVE_MAPPER,
                                                  devOptions,
                                                  (void (*)(LONG, LONG, DWORD, UINT))ttsCallback,
                                                  0,
                                                  dict_path);

    if (result != MMSYSERR_NOERROR) {
        fprintf(stderr, "DECtalk TextToSpeechStartupExFonix failed: %d\n", result);
        pthread_mutex_unlock(&g_mutex);
        return DECtalkErrorInitFailed;
    }

    g_initialized = true;
    g_currentVoice = DECtalkVoicePaul;

    fprintf(stderr, "DECtalk: Initialization successful!\n");

    pthread_mutex_unlock(&g_mutex);
    return DECtalkErrorNone;
}

void dectalk_shutdown(void) {
    pthread_mutex_lock(&g_mutex);

    if (g_initialized && g_ttsHandle) {
        if (g_inMemoryOpen) {
            TextToSpeechCloseInMemory(g_ttsHandle);
            g_inMemoryOpen = false;
        }
        TextToSpeechShutdown(g_ttsHandle);
        g_ttsHandle = NULL;
        g_initialized = false;
    }

    pthread_mutex_unlock(&g_mutex);
}

int dectalk_set_voice(DECtalkVoice voice) {
    if (voice < 0 || voice >= DECtalkVoiceCount) {
        return DECtalkErrorInvalidVoice;
    }
    g_currentVoice = voice;

    // If initialized, set speaker immediately
    if (g_initialized && g_ttsHandle) {
        TextToSpeechSetSpeaker(g_ttsHandle, (SPEAKER_T)voice);
    }

    return DECtalkErrorNone;
}

DECtalkVoice dectalk_get_voice(void) {
    return g_currentVoice;
}

int dectalk_synthesize(const char *text, int16_t *buffer, int32_t bufferSize, int32_t *samplesWritten) {
    pthread_mutex_lock(&g_mutex);

    if (!g_initialized) {
        pthread_mutex_unlock(&g_mutex);
        int result = dectalk_init();
        if (result != DECtalkErrorNone) {
            return result;
        }
        pthread_mutex_lock(&g_mutex);
    }

    if (text == NULL || buffer == NULL || samplesWritten == NULL) {
        pthread_mutex_unlock(&g_mutex);
        return DECtalkErrorSynthFailed;
    }

    // Set up output buffer
    g_outputBuffer = buffer;
    g_outputBufferSize = bufferSize;
    g_outputSamplesWritten = 0;

    // Open in-memory mode if not already open
    if (!g_inMemoryOpen) {
        MMRESULT result = TextToSpeechOpenInMemory(g_ttsHandle, WAVE_FORMAT_1M16);
        if (result != MMSYSERR_NOERROR) {
            fprintf(stderr, "TextToSpeechOpenInMemory failed: %d\n", result);
            pthread_mutex_unlock(&g_mutex);
            return DECtalkErrorSynthFailed;
        }
        g_inMemoryOpen = true;
    }

    // Reset and queue buffers
    for (int i = 0; i < NUM_BUFFERS; i++) {
        g_ttsBuffers[i].dwBufferLength = 0;
        TextToSpeechAddBuffer(g_ttsHandle, &g_ttsBuffers[i]);
    }

    // Set the voice
    TextToSpeechSetSpeaker(g_ttsHandle, (SPEAKER_T)g_currentVoice);

    // Build text with voice command prefix
    size_t voiceCmdLen = strlen(g_voiceCommands[g_currentVoice]);
    size_t textLen = strlen(text);
    size_t totalLen = voiceCmdLen + textLen + 1;

    char *fullText = (char*)malloc(totalLen);
    if (!fullText) {
        pthread_mutex_unlock(&g_mutex);
        return DECtalkErrorSynthFailed;
    }

    strcpy(fullText, g_voiceCommands[g_currentVoice]);
    strcat(fullText, text);

    // Synthesize with TTS_FORCE to start immediately
    MMRESULT result = TextToSpeechSpeak(g_ttsHandle, fullText, TTS_FORCE);
    if (result != MMSYSERR_NOERROR) {
        fprintf(stderr, "TextToSpeechSpeak failed: %d\n", result);
        free(fullText);
        pthread_mutex_unlock(&g_mutex);
        return DECtalkErrorSynthFailed;
    }

    // Sync to ensure all audio is generated
    TextToSpeechSync(g_ttsHandle);

    // Get any remaining buffer data
    LPTTS_BUFFER_T pLastBuffer = NULL;
    while (TextToSpeechReturnBuffer(g_ttsHandle, &pLastBuffer) == MMSYSERR_NOERROR && pLastBuffer) {
        if (pLastBuffer->dwBufferLength > 0) {
            int32_t samplesToWrite = pLastBuffer->dwBufferLength / sizeof(int16_t);
            int32_t remainingSpace = g_outputBufferSize - g_outputSamplesWritten;

            if (samplesToWrite > remainingSpace) {
                samplesToWrite = remainingSpace;
            }

            if (samplesToWrite > 0) {
                memcpy(g_outputBuffer + g_outputSamplesWritten,
                       pLastBuffer->lpData,
                       samplesToWrite * sizeof(int16_t));
                g_outputSamplesWritten += samplesToWrite;
            }
        }
        pLastBuffer = NULL;
    }

    free(fullText);

    *samplesWritten = g_outputSamplesWritten;

    pthread_mutex_unlock(&g_mutex);
    return DECtalkErrorNone;
}

int dectalk_synthesize_with_callback(const char *text, DECtalkAudioCallback callback, void *userData) {
    if (!callback) {
        return DECtalkErrorSynthFailed;
    }

    // Use a temporary buffer and call the callback
    int32_t bufferSize = DECTALK_SAMPLE_RATE * 60; // 60 seconds max
    int16_t *buffer = (int16_t*)malloc(bufferSize * sizeof(int16_t));
    if (!buffer) {
        return DECtalkErrorSynthFailed;
    }

    int32_t samplesWritten = 0;
    int result = dectalk_synthesize(text, buffer, bufferSize, &samplesWritten);

    if (result == DECtalkErrorNone && samplesWritten > 0) {
        callback(buffer, samplesWritten, userData);
    }

    free(buffer);
    return result;
}

int dectalk_extract_text_from_ssml(const char *ssml, char *plainText, int32_t maxLength) {
    if (ssml == NULL || plainText == NULL || maxLength <= 0) {
        return 0;
    }

    const char *src = ssml;
    char *dst = plainText;
    int32_t written = 0;
    bool inTag = false;

    while (*src && written < maxLength - 1) {
        if (*src == '<') {
            inTag = true;
            src++;
            continue;
        }

        if (*src == '>') {
            inTag = false;
            src++;
            continue;
        }

        if (!inTag) {
            // Handle HTML entities
            if (*src == '&') {
                if (strncmp(src, "&amp;", 5) == 0) {
                    *dst++ = '&';
                    written++;
                    src += 5;
                    continue;
                } else if (strncmp(src, "&lt;", 4) == 0) {
                    *dst++ = '<';
                    written++;
                    src += 4;
                    continue;
                } else if (strncmp(src, "&gt;", 4) == 0) {
                    *dst++ = '>';
                    written++;
                    src += 4;
                    continue;
                } else if (strncmp(src, "&quot;", 6) == 0) {
                    *dst++ = '"';
                    written++;
                    src += 6;
                    continue;
                } else if (strncmp(src, "&apos;", 6) == 0) {
                    *dst++ = '\'';
                    written++;
                    src += 6;
                    continue;
                } else if (strncmp(src, "&#91;", 5) == 0) {
                    // Numeric entity for [
                    *dst++ = '[';
                    written++;
                    src += 5;
                    continue;
                } else if (strncmp(src, "&#93;", 5) == 0) {
                    // Numeric entity for ]
                    *dst++ = ']';
                    written++;
                    src += 5;
                    continue;
                } else if (strncmp(src, "&#58;", 5) == 0) {
                    // Numeric entity for :
                    *dst++ = ':';
                    written++;
                    src += 5;
                    continue;
                } else if (*src == '&' && *(src+1) == '#') {
                    // Generic numeric entity &#NNN;
                    const char *semi = strchr(src, ';');
                    if (semi && semi - src < 8) {
                        int code = 0;
                        if (sscanf(src + 2, "%d", &code) == 1 && code > 0 && code < 256) {
                            *dst++ = (char)code;
                            written++;
                            src = semi + 1;
                            continue;
                        }
                    }
                }
            }

            *dst++ = *src;
            written++;
        }
        src++;
    }

    *dst = '\0';
    return written;
}

const char* dectalk_get_voice_name(DECtalkVoice voice) {
    if (voice < 0 || voice >= DECtalkVoiceCount) {
        return "Unknown";
    }
    return g_voiceNames[voice];
}

const char* dectalk_get_voice_command(DECtalkVoice voice) {
    if (voice < 0 || voice >= DECtalkVoiceCount) {
        return "[:np]";
    }
    return g_voiceCommands[voice];
}

int dectalk_get_sample_rate(void) {
    return DECTALK_SAMPLE_RATE;
}

int dectalk_reset(void) {
    if (g_initialized && g_ttsHandle) {
        // Reset the TTS engine - this clears any pending speech
        MMRESULT result = TextToSpeechReset(g_ttsHandle, FALSE);

        // Close and reopen in-memory mode to clear buffers
        if (g_inMemoryOpen) {
            TextToSpeechCloseInMemory(g_ttsHandle);
            g_inMemoryOpen = false;
        }

        return result == MMSYSERR_NOERROR ? 0 : -1;
    }
    return 0;
}

int dectalk_sync(void) {
    if (g_initialized && g_ttsHandle) {
        return TextToSpeechSync(g_ttsHandle) == MMSYSERR_NOERROR ? 0 : -1;
    }
    return 0;
}

int dectalk_set_rate(int wpm) {
    if (g_initialized && g_ttsHandle) {
        // Clamp to valid range
        if (wpm < 75) wpm = 75;
        if (wpm > 600) wpm = 600;
        return TextToSpeechSetRate(g_ttsHandle, (DWORD)wpm) == MMSYSERR_NOERROR ? 0 : -1;
    }
    return -1;
}

int dectalk_get_rate(void) {
    if (g_initialized && g_ttsHandle) {
        DWORD rate = 0;
        if (TextToSpeechGetRate(g_ttsHandle, &rate) == MMSYSERR_NOERROR) {
            return (int)rate;
        }
    }
    return 180; // Default rate
}

int dectalk_set_volume(int volume) {
    if (g_initialized && g_ttsHandle) {
        // Clamp to valid range
        if (volume < 0) volume = 0;
        if (volume > 100) volume = 100;
        // DECtalk volume is 0-100
        DWORD vol = (DWORD)volume;
        // Set both left and right channels
        vol = vol | (vol << 16);
        return TextToSpeechSetVolume(g_ttsHandle, VOLUME_MAIN, vol) == MMSYSERR_NOERROR ? 0 : -1;
    }
    return -1;
}

const char* dectalk_get_version(void) {
    return "DECtalk 5.0 (macOS)";
}
