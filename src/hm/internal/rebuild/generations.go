package rebuild

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"time"

	"github.com/stubbedev/dotfiles/src/hm/internal/closure"
	"github.com/stubbedev/dotfiles/src/hm/internal/config"
	"github.com/stubbedev/dotfiles/src/hm/internal/ui"
)

const DateLayout = "2006-01-02 15:04:05Z"

type Generation struct {
	ID              int       `json:"generation"`
	Path            string    `json:"path"`
	Date            time.Time `json:"date"`
	NixOSVersion    string    `json:"nixosVersion,omitempty"`
	Kernel          string    `json:"kernelVersion,omitempty"`
	Specialisations []string  `json:"specialisations,omitempty"`
	ClosureSize     int64     `json:"closureSize,omitempty"`
	Boot            bool      `json:"boot"`
	Running         bool      `json:"running"`
}

func RunningLink(p config.Platform) string {
	if p == config.Android {
		return ""
	}
	return currentSystem
}

func generationPath(profile string, id int) string {
	return fmt.Sprintf("%s-%d-link", profile, id)
}

func generationID(profileName, entry string) (int, bool) {
	rest, ok := strings.CutPrefix(entry, profileName+"-")
	if !ok {
		return 0, false
	}
	digits, ok := strings.CutSuffix(rest, "-link")
	if !ok {
		return 0, false
	}
	id, err := strconv.Atoi(digits)
	if err != nil || id <= 0 || strconv.Itoa(id) != digits {
		return 0, false
	}
	return id, true
}

func ListGenerations(profile, runningLink string) ([]Generation, error) {
	dir, name := filepath.Split(profile)
	boot, err := os.Readlink(profile)
	if err != nil {
		return nil, fmt.Errorf("reading the current generation of %s: %w", profile, err)
	}
	running := ""
	if runningLink != "" {
		if running, err = filepath.EvalSymlinks(runningLink); err != nil {
			return nil, fmt.Errorf("resolving the running system %s: %w", runningLink, err)
		}
	}
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil, fmt.Errorf("listing generations of %s: %w", profile, err)
	}
	var gens []Generation
	for _, e := range entries {
		id, ok := generationID(name, e.Name())
		if !ok {
			continue
		}
		info, err := e.Info()
		if err != nil {
			return nil, fmt.Errorf("reading generation %d of %s: %w", id, profile, err)
		}
		path, err := filepath.EvalSymlinks(filepath.Join(dir, e.Name()))
		if err != nil {
			return nil, fmt.Errorf("resolving generation %d of %s: %w", id, profile, err)
		}
		g := Generation{ID: id, Path: path, Date: info.ModTime().UTC(), Boot: e.Name() == filepath.Base(boot)}
		g.Running = g.Boot
		if running != "" {
			g.Running = path == running
		}
		gens = append(gens, g)
	}
	if len(gens) == 0 {
		return nil, fmt.Errorf("listing generations of %s: none found", profile)
	}
	slices.SortFunc(gens, func(a, b Generation) int { return b.ID - a.ID })
	return gens, nil
}

func currentGeneration(profile string) (int, error) {
	target, err := os.Readlink(profile)
	if err != nil {
		return 0, fmt.Errorf("reading the current generation of %s: %w", profile, err)
	}
	id, ok := generationID(filepath.Base(profile), filepath.Base(target))
	if !ok {
		return 0, fmt.Errorf("profile link %s points at %s, not a generation", profile, target)
	}
	return id, nil
}

func previousGeneration(profile string) (string, error) {
	gens, err := ListGenerations(profile, "")
	if err != nil {
		return "", err
	}
	i := slices.IndexFunc(gens, func(g Generation) bool { return g.Boot })
	if i < 0 {
		return "", fmt.Errorf("profile link %s does not point at one of its generations", profile)
	}
	if i == len(gens)-1 {
		return "", fmt.Errorf("generation %d of %s has no predecessor", gens[i].ID, profile)
	}
	return generationPath(profile, gens[i+1].ID), nil
}

func ResolveGeneration(profile, arg string) (string, error) {
	id, err := strconv.Atoi(arg)
	if err != nil {
		return arg, nil
	}
	path := generationPath(profile, id)
	if _, err := os.Lstat(path); err != nil {
		return "", fmt.Errorf("generation %d of %s: %w", id, profile, err)
	}
	return path, nil
}

func DefaultDiffPair(profile string) (string, string, error) {
	previous, err := previousGeneration(profile)
	if err != nil {
		return "", "", err
	}
	return previous, profile, nil
}

func AddClosureSizes(ctx context.Context, gens []Generation) error {
	paths := make([]string, len(gens))
	for i, g := range gens {
		paths[i] = g.Path
	}
	sizes, err := closure.ClosureSizes(ctx, paths)
	if err != nil {
		return err
	}
	for i := range gens {
		gens[i].ClosureSize = sizes[gens[i].Path]
	}
	return nil
}

func AddSystemInfo(profile string, gens []Generation) error {
	for i := range gens {
		path := generationPath(profile, gens[i].ID)
		var err error
		if gens[i].NixOSVersion, err = readNixOSVersion(path); err != nil {
			return err
		}
		if gens[i].Kernel, err = readKernelVersion(path); err != nil {
			return err
		}
		if gens[i].Specialisations, err = readSpecialisations(path); err != nil {
			return err
		}
	}
	return nil
}

func readSpecialisations(generation string) ([]string, error) {
	entries, err := os.ReadDir(filepath.Join(generation, "specialisation"))
	if errors.Is(err, fs.ErrNotExist) {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("reading the specialisations of %s: %w", generation, err)
	}
	names := make([]string, len(entries))
	for i, e := range entries {
		names[i] = e.Name()
	}
	return names, nil
}

func readNixOSVersion(generation string) (string, error) {
	data, err := os.ReadFile(filepath.Join(generation, "nixos-version"))
	if err != nil {
		return "", fmt.Errorf("reading the NixOS version of %s: %w", generation, err)
	}
	return strings.TrimSpace(string(data)), nil
}

func readKernelVersion(generation string) (string, error) {
	dir := filepath.Join(generation, "kernel-modules", "lib", "modules")
	entries, err := os.ReadDir(dir)
	if err != nil {
		return "", fmt.Errorf("reading the kernel version of %s: %w", generation, err)
	}
	if len(entries) != 1 {
		return "", fmt.Errorf("reading the kernel version of %s: %d entries in %s, want 1", generation, len(entries), dir)
	}
	return entries[0].Name(), nil
}

func WriteGenerations(w io.Writer, st ui.Style, gens []Generation, platform config.Platform) error {
	specialised := slices.ContainsFunc(gens, func(g Generation) bool { return len(g.Specialisations) > 0 })
	t := ui.Table{Header: []string{"Generation", "Build date"}}
	if platform == config.NixOS {
		t.Header = append(t.Header, "NixOS version", "Kernel")
	}
	if specialised {
		t.Header = append(t.Header, "Specialisations")
	}
	t.Header = append(t.Header, "Closure size")
	for _, g := range gens {
		row := []string{generationLabel(st, g), st.Paint(g.Date.Format(DateLayout), ui.Gray)}
		if platform == config.NixOS {
			row = append(row, st.Paint(g.NixOSVersion, ui.Cyan), st.Paint(g.Kernel, ui.Yellow))
		}
		if specialised {
			row = append(row, st.Paint(strings.Join(g.Specialisations, " "), ui.Magenta))
		}
		row = append(row, ui.Bytes(g.ClosureSize))
		t.Rows = append(t.Rows, row)
	}
	if err := t.Render(w, st); err != nil {
		return fmt.Errorf("writing generations: %w", err)
	}
	return nil
}

func generationLabel(st ui.Style, g Generation) string {
	id := strconv.Itoa(g.ID)
	switch {
	case g.Running && g.Boot:
		return st.Paint(id+" (current)", ui.Bold, ui.Green)
	case g.Running:
		return st.Paint(id+" (running)", ui.Bold, ui.Yellow)
	case g.Boot:
		return st.Paint(id+" (boot)", ui.Bold, ui.Cyan)
	}
	return st.Paint(id, ui.Bold)
}

func WriteGenerationsJSON(w io.Writer, gens []Generation) error {
	enc := json.NewEncoder(w)
	enc.SetIndent("", "  ")
	if err := enc.Encode(gens); err != nil {
		return fmt.Errorf("writing generations as JSON: %w", err)
	}
	return nil
}
