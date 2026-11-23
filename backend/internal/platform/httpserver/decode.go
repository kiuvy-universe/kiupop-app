package httpserver

import (
	"encoding/json"
	"errors"
	"io"
	"net/http"
)

// MaxJSONBytes bounds JSON request bodies.
const MaxJSONBytes = 64 << 10

// DecodeJSON reads a single JSON object into dst, rejecting unknown fields
// (so clients cannot smuggle e.g. prices) and oversized bodies. On failure it
// writes a 400/413 response and returns false.
func DecodeJSON(w http.ResponseWriter, r *http.Request, dst any) bool {
	r.Body = http.MaxBytesReader(w, r.Body, MaxJSONBytes)
	dec := json.NewDecoder(r.Body)
	dec.DisallowUnknownFields()
	if err := dec.Decode(dst); err != nil {
		var tooBig *http.MaxBytesError
		if errors.As(err, &tooBig) {
			WriteError(w, http.StatusRequestEntityTooLarge, "payload_too_large", "La solicitud es demasiado grande.")
			return false
		}
		WriteError(w, http.StatusBadRequest, "invalid_json", "La solicitud no tiene un formato válido.")
		return false
	}
	if err := dec.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		WriteError(w, http.StatusBadRequest, "invalid_json", "La solicitud no tiene un formato válido.")
		return false
	}
	return true
}

// FieldError is the envelope for validation errors with per-field detail.
type FieldError struct {
	Error struct {
		Code    string            `json:"code"`
		Message string            `json:"message"`
		Fields  map[string]string `json:"fields,omitempty"`
	} `json:"error"`
}

// WriteValidation writes a 422 with field messages (es-CR).
func WriteValidation(w http.ResponseWriter, fields map[string]string) {
	var body FieldError
	body.Error.Code = "validation_failed"
	body.Error.Message = "Revisa los datos marcados."
	body.Error.Fields = fields
	WriteJSON(w, http.StatusUnprocessableEntity, body)
}
