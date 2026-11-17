package rebuild

import (
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"text/tabwriter"
	"time"

	"github.com/stubbedev/dotfiles/src/hm/internal/config"
)

const dateLayout = "2006-01-02 15:04:05Z"

type Generation struct {
	ID           int       `json:"generation"`
	Date         time.Time `json:"date"`
	NixOSVersion string    `json:"nixosVersion,omitempty"`
	Kernel       string    `json:"kernelVersion,omitempty"`
	Current      bool      `json:"current"`
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

func ListGenerations(profile string, platform config.Platform) ([]Generation, error) {
	dir, name := filepath.Split(profile)
	current, err := os.Readlink(profile)
	if err != nil {
		return nil, fmt.Errorf("reading the current generation of %s: %w", profile, err)
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
		g := Generation{ID: id, Date: info.ModTime().UTC(), Current: e.Name() == filepath.Base(current)}
		if platform == config.NixOS {
			path := generationPath(profile, id)
			if g.NixOSVersion, err = readNixOSVersion(path); err != nil {
				return nil, err
			}
			if g.Kernel, err = readKernelVersion(path); err != nil {
				return nil, err
			}
		}
		gens = append(gens, g)
	}
	if len(gens) == 0 {
		return nil, fmt.Errorf("listing generations of %s: none found", profile)
	}
	slices.SortFunc(gens, func(a, b Generation) int { return b.ID - a.ID })
	return gens, nil
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

func WriteGenerations(w io.Writer, gens []Generation, platform config.Platform) error {
	tw := tabwriter.NewWriter(w, 0, 0, 2, ' ', 0)
	header := "Generation\tBuild-date\tCurrent"
	if platform == config.NixOS {
		header = "Generation\tBuild-date\tNixOS version\tKernel\tCurrent"
	}
	fmt.Fprintln(tw, header)
	for _, g := range gens {
		current := ""
		if g.Current {
			current = "*"
		}
		if platform == config.NixOS {
			fmt.Fprintf(tw, "%d\t%s\t%s\t%s\t%s\n", g.ID, g.Date.Format(dateLayout), g.NixOSVersion, g.Kernel, current)
			continue
		}
		fmt.Fprintf(tw, "%d\t%s\t%s\n", g.ID, g.Date.Format(dateLayout), current)
	}
	if err := tw.Flush(); err != nil {
		return fmt.Errorf("writing generations: %w", err)
	}
	return nil
}

func WriteGenerationsJSON(w io.Writer, gens []Generation) error {
	enc := json.NewEncoder(w)
	enc.SetIndent("", "  ")
	if err := enc.Encode(gens); err != nil {
		return fmt.Errorf("writing generations as JSON: %w", err)
	}
	return nil
}
