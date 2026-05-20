package server

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"image"
	_ "image/gif"
	"image/jpeg"
	_ "image/png"
	"io"
	"mime/multipart"
	"net/http"
	"strings"
	"time"
)

// IPFSRelay handles media compression, color extraction, and uploading to IPFS via Pinata.
type IPFSRelay struct {
	jwt      string
	maxBytes int64
	client   *http.Client
}

// IPFSRelayConfig holds configuration for the IPFS relay.
type IPFSRelayConfig struct {
	Enabled  bool
	JWT      string // Pinata JWT
	MaxBytes int64
}

func (c IPFSRelayConfig) Active() bool {
	return c.Enabled && c.JWT != ""
}

// NewIPFSRelay returns a new IPFS relay.
func NewIPFSRelay(cfg IPFSRelayConfig) *IPFSRelay {
	if !cfg.Active() {
		return nil
	}
	return &IPFSRelay{
		jwt:      cfg.JWT,
		maxBytes: cfg.MaxBytes,
		client:   &http.Client{Timeout: 2 * time.Minute},
	}
}

// UploadResult holds the CID and dominant color of an uploaded file.
type UploadResult struct {
	CID           string
	DominantColor string
	MediaType     string // "IMAGE" or "VIDEO"
}

// ProcessAndUpload compresses the media, extracts color, and pins to IPFS.
func (r *IPFSRelay) ProcessAndUpload(ctx context.Context, body []byte, mimeType string) (UploadResult, error) {
	if r == nil {
		return UploadResult{}, fmt.Errorf("ipfs relay disabled")
	}

	result := UploadResult{
		MediaType: "IMAGE",
	}
	if strings.HasPrefix(mimeType, "video/") {
		result.MediaType = "VIDEO"
	}

	var processedBody []byte
	var err error

	if result.MediaType == "IMAGE" {
		processedBody, result.DominantColor, err = r.processImage(body)
		if err != nil {
			// Fallback: use original body if processing fails, color defaults to grey
			processedBody = body
			result.DominantColor = "#808080"
		}
	} else {
		processedBody = body
		result.DominantColor = "#000000" // Default for video
	}

	if r.maxBytes > 0 && int64(len(processedBody)) > r.maxBytes {
		return UploadResult{}, ErrTooLarge // Assuming ErrTooLarge is defined elsewhere in the package
	}

	cid, err := r.pinToPinata(ctx, processedBody, result.MediaType)
	if err != nil {
		return UploadResult{}, fmt.Errorf("pinata upload: %w", err)
	}
	result.CID = cid

	return result, nil
}

func (r *IPFSRelay) processImage(body []byte) ([]byte, string, error) {
	img, _, err := image.Decode(bytes.NewReader(body))
	if err != nil {
		return nil, "", err
	}

	// 1. Extract dominant (average) color
	domColor := getAverageColor(img)

	// 2. Compress to JPEG (WebP removed for Windows compatibility)
	var buf bytes.Buffer
	err = jpeg.Encode(&buf, img, &jpeg.Options{Quality: 50}) // High compression for DNS readers
	if err != nil {
		return nil, "", err
	}

	return buf.Bytes(), domColor, nil
}

func getAverageColor(img image.Image) string {
	var r, g, b, count uint32
	bounds := img.Bounds()
	// Sample pixels to save CPU
	step := 1
	if bounds.Dx()*bounds.Dy() > 10000 {
		step = 4
	}

	for y := bounds.Min.Y; y < bounds.Max.Y; y += step {
		for x := bounds.Min.X; x < bounds.Max.X; x += step {
			c := img.At(x, y)
			r1, g1, b1, _ := c.RGBA()
			r += r1 >> 8
			g += g1 >> 8
			b += b1 >> 8
			count++
		}
	}
	if count == 0 {
		return "#808080"
	}
	return fmt.Sprintf("#%02x%02x%02x", r/count, g/count, b/count)
}

func (r *IPFSRelay) pinToPinata(ctx context.Context, body []byte, mediaType string) (string, error) {
	url := "https://api.pinata.cloud/pinning/pinFileToIPFS"

	var buf bytes.Buffer
	writer := multipart.NewWriter(&buf)

	// Changed extension to .jpeg since we are encoding as JPEG now
	part, err := writer.CreateFormFile("file", "media.jpeg")
	if err != nil {
		return "", err
	}
	if _, err := io.Copy(part, bytes.NewReader(body)); err != nil {
		return "", err
	}
	writer.Close()

	req, err := http.NewRequestWithContext(ctx, "POST", url, &buf)
	if err != nil {
		return "", err
	}

	req.Header.Set("Content-Type", writer.FormDataContentType())
	req.Header.Set("Authorization", "Bearer "+r.jwt)

	resp, err := r.client.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		errBody, _ := io.ReadAll(resp.Body)
		return "", fmt.Errorf("status %d: %s", resp.StatusCode, string(errBody))
	}

	var pinResp struct {
		IpfsHash string `json:"IpfsHash"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&pinResp); err != nil {
		return "", err
	}

	return pinResp.IpfsHash, nil
}