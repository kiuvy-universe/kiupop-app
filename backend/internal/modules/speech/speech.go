// Package speech turns a merchant's voice note into editable text
// (KPOP-WOW-001). Audio is validated, sent to the provider and discarded: it is
// never written to disk, the bucket or logs. Transcripts are returned to the
// caller only; logs and analytics carry numbers (duration, latency, cost).
package speech

import (
	"context"
	"encoding/binary"
	"errors"
	"fmt"
	"math"
	"time"
)

// Audio is one recording as received from the app.
type Audio struct {
	Data       []byte
	Format     string // wav | webm | ogg
	SampleRate int    // known for wav; 48000 for opus containers
	Duration   time.Duration
}

// Result is the provider's answer.
type Result struct {
	Text          string
	Confidence    float64
	BilledSeconds int
	Provider      string
	Language      string
}

// Transcriber converts speech to text (SpeechTranscriber in the brief).
type Transcriber interface {
	Transcribe(ctx context.Context, a Audio) (Result, error)
	Provider() string
}

// Errors the handler maps to friendly messages.
var (
	ErrDisabled    = errors.New("speech disabled")
	ErrUnsupported = errors.New("unsupported audio")
	ErrTooShort    = errors.New("audio too short")
	ErrTooLong     = errors.New("audio too long")
	ErrSilent      = errors.New("audio silent")
	ErrNoSpeech    = errors.New("no speech recognised")
)

// Disabled is the adapter for tests and environments without a provider.
type Disabled struct{}

// Transcribe implements Transcriber.
func (Disabled) Transcribe(context.Context, Audio) (Result, error) { return Result{}, ErrDisabled }

// Provider implements Transcriber.
func (Disabled) Provider() string { return "disabled" }

// DevEcho is a development-only stand-in (never in demo/production): it proves
// the microphone → WAV → upload → validation path without a provider and says
// plainly that it did not transcribe anything.
type DevEcho struct{}

// Transcribe implements Transcriber.
func (DevEcho) Transcribe(_ context.Context, a Audio) (Result, error) {
	secs := a.Duration.Seconds()
	return Result{
		Text:     fmt.Sprintf("[Prueba local: recibí %.1f s de audio. Sin proveedor de transcripción: escribí aquí lo que dijiste.]", secs),
		Provider: "dev-echo", Language: "es-CR", BilledSeconds: 0,
	}, nil
}

// Provider implements Transcriber.
func (DevEcho) Provider() string { return "dev-echo" }

// MinDuration rejects taps that recorded nothing useful.
const MinDuration = 700 * time.Millisecond

// Inspect validates the container by its bytes (never the client's header) and,
// for WAV, measures duration and loudness so silence is rejected before any
// paid call.
func Inspect(data []byte, maxDur time.Duration) (Audio, error) {
	switch {
	case len(data) >= 12 && string(data[0:4]) == "RIFF" && string(data[8:12]) == "WAVE":
		return inspectWAV(data, maxDur)
	case len(data) >= 4 && data[0] == 0x1A && data[1] == 0x45 && data[2] == 0xDF && data[3] == 0xA3:
		if len(data) < 2048 {
			return Audio{}, ErrTooShort
		}
		return Audio{Data: data, Format: "webm", SampleRate: 48000}, nil
	case len(data) >= 4 && string(data[0:4]) == "OggS":
		if len(data) < 2048 {
			return Audio{}, ErrTooShort
		}
		return Audio{Data: data, Format: "ogg", SampleRate: 48000}, nil
	}
	return Audio{}, ErrUnsupported
}

func inspectWAV(data []byte, maxDur time.Duration) (Audio, error) {
	var channels, bits uint16
	var rate uint32
	var pcm []byte
	for off := 12; off+8 <= len(data); {
		id := string(data[off : off+4])
		size := int(binary.LittleEndian.Uint32(data[off+4 : off+8]))
		body := off + 8
		end := body + size
		if size < 0 || end > len(data) || size == 0xFFFFFFFF {
			end = len(data) // streaming writers may leave the size open
		}
		switch id {
		case "fmt ":
			if end-body < 16 {
				return Audio{}, ErrUnsupported
			}
			if binary.LittleEndian.Uint16(data[body:]) != 1 { // PCM only
				return Audio{}, ErrUnsupported
			}
			channels = binary.LittleEndian.Uint16(data[body+2:])
			rate = binary.LittleEndian.Uint32(data[body+4:])
			bits = binary.LittleEndian.Uint16(data[body+14:])
		case "data":
			pcm = data[body:end]
		}
		off = end + (end-body)%2
		if pcm != nil {
			break
		}
	}
	if channels != 1 || bits != 16 || rate < 8000 || rate > 48000 || pcm == nil {
		return Audio{}, ErrUnsupported
	}
	dur := time.Duration(len(pcm)/2) * time.Second / time.Duration(rate)
	switch {
	case dur < MinDuration:
		return Audio{}, ErrTooShort
	case dur > maxDur:
		return Audio{}, ErrTooLong
	}
	if rms(pcm) < 60 { // about -55 dBFS: nothing but room noise
		return Audio{}, ErrSilent
	}
	return Audio{Data: data, Format: "wav", SampleRate: int(rate), Duration: dur}, nil
}

func rms(pcm []byte) float64 {
	n := len(pcm) / 2
	if n == 0 {
		return 0
	}
	var sum float64
	for i := 0; i < n; i++ {
		v := float64(int16(binary.LittleEndian.Uint16(pcm[2*i:])))
		sum += v * v
	}
	return math.Sqrt(sum / float64(n))
}
