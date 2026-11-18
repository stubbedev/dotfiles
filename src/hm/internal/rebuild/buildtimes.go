package rebuild

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"maps"
	"os"
	"path/filepath"
	"time"

	"github.com/stubbedev/dotfiles/src/hm/internal/atomicfile"
)

const (
	buildTimesFile   = "build-times.json"
	minRecordedBuild = time.Second
)

func buildTimesPath() (string, error) {
	dir, err := os.UserCacheDir()
	if err != nil {
		return "", fmt.Errorf("locating the build time cache: %w", err)
	}
	return filepath.Join(dir, "hm", buildTimesFile), nil
}

func loadBuildTimes(path string) (map[string]time.Duration, error) {
	data, err := os.ReadFile(path)
	if errors.Is(err, fs.ErrNotExist) {
		return map[string]time.Duration{}, nil
	}
	if err != nil {
		return nil, fmt.Errorf("reading %s: %w", path, err)
	}
	var seconds map[string]float64
	if err := json.Unmarshal(data, &seconds); err != nil {
		return nil, fmt.Errorf("decoding %s: %w", path, err)
	}
	times := make(map[string]time.Duration, len(seconds))
	for name, s := range seconds {
		times[name] = time.Duration(s * float64(time.Second))
	}
	return times, nil
}

func mergeBuildTimes(known, measured map[string]time.Duration) map[string]time.Duration {
	merged := maps.Clone(known)
	for name, d := range measured {
		if d < minRecordedBuild {
			continue
		}
		if old, ok := merged[name]; ok {
			d = (old + d) / 2
		}
		merged[name] = d
	}
	return merged
}

func saveBuildTimes(path string, times map[string]time.Duration) error {
	seconds := make(map[string]float64, len(times))
	for name, d := range times {
		seconds[name] = d.Round(time.Second).Seconds()
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return fmt.Errorf("creating the build time cache directory: %w", err)
	}
	return atomicfile.Replace(path, 0o644, func(w io.Writer) error {
		return json.NewEncoder(w).Encode(seconds)
	})
}
