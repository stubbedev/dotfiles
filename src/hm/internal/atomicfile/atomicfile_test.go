package atomicfile

import (
	"errors"
	"io"
	"os"
	"path/filepath"
	"testing"
)

func TestWriteKeepingMode(t *testing.T) {
	path := filepath.Join(t.TempDir(), "f")
	if err := os.WriteFile(path, []byte("old"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := WriteKeepingMode(path, []byte("new")); err != nil {
		t.Fatal(err)
	}
	info, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	data, _ := os.ReadFile(path)
	if string(data) != "new" || info.Mode().Perm() != 0o600 {
		t.Fatalf("content %q mode %v", data, info.Mode())
	}
	entries, _ := os.ReadDir(filepath.Dir(path))
	if len(entries) != 1 {
		t.Fatalf("temporary files left behind: %v", entries)
	}
}

func TestReplaceLeavesTargetOnFailure(t *testing.T) {
	path := filepath.Join(t.TempDir(), "f")
	if err := os.WriteFile(path, []byte("old"), 0o644); err != nil {
		t.Fatal(err)
	}
	boom := errors.New("boom")
	err := Replace(path, 0o644, func(w io.Writer) error {
		if _, err := w.Write([]byte("half")); err != nil {
			return err
		}
		return boom
	})
	if !errors.Is(err, boom) {
		t.Fatalf("Replace err = %v", err)
	}
	data, _ := os.ReadFile(path)
	entries, _ := os.ReadDir(filepath.Dir(path))
	if string(data) != "old" || len(entries) != 1 {
		t.Fatalf("failed replace touched the target: %q, %v", data, entries)
	}
}
