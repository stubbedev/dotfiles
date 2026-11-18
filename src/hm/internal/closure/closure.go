package closure

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"path/filepath"
	"strings"
	"sync"

	"github.com/stubbedev/dotfiles/src/hm/internal/proc"
	"github.com/stubbedev/dotfiles/src/hm/internal/storepath"
	"github.com/stubbedev/dotfiles/src/hm/internal/ui"
)

const systemPathSuffix = "-system-path"

type Closure struct {
	Sizes    map[string]int64
	Selected map[string]bool
}

type pathInfo struct {
	NarSize     int64    `json:"narSize"`
	ClosureSize int64    `json:"closureSize"`
	References  []string `json:"references"`
}

func pathInfoJSON(ctx context.Context, flags []string, paths ...string) ([]byte, error) {
	argv := append([]string{"nix", "--extra-experimental-features", "nix-command", "path-info", "--json"}, flags...)
	var stderr bytes.Buffer
	out, err := proc.Output(ctx, proc.Cmd{Argv: append(argv, paths...), Stdin: strings.NewReader(""), Stderr: &stderr})
	if err != nil {
		return nil, fmt.Errorf("%w: %s", err, strings.TrimSpace(stderr.String()))
	}
	return out, nil
}

func Load(ctx context.Context, root string) (Closure, error) {
	top, err := filepath.EvalSymlinks(root)
	if err != nil {
		return Closure{}, fmt.Errorf("resolving %s: %w", root, err)
	}
	out, err := pathInfoJSON(ctx, []string{"--recursive"}, top)
	if err != nil {
		return Closure{}, fmt.Errorf("querying the closure of %s: %w", top, err)
	}
	return Parse(top, out)
}

func ClosureSizes(ctx context.Context, paths []string) (map[string]int64, error) {
	if len(paths) == 0 {
		return map[string]int64{}, nil
	}
	out, err := pathInfoJSON(ctx, []string{"--closure-size"}, paths...)
	if err != nil {
		return nil, fmt.Errorf("querying closure sizes: %w", err)
	}
	var infos map[string]pathInfo
	if err := json.Unmarshal(out, &infos); err != nil {
		return nil, fmt.Errorf("decoding closure sizes: %w", err)
	}
	sizes := make(map[string]int64, len(paths))
	for _, p := range paths {
		info, ok := infos[p]
		if !ok {
			return nil, fmt.Errorf("querying closure sizes: nix reported nothing for %s", p)
		}
		sizes[p] = info.ClosureSize
	}
	return sizes, nil
}

func WriteHeader(w io.Writer, st ui.Style, oldPath, newPath string) {
	fmt.Fprintf(w, "%s %s\n%s %s\n\n", st.Paint("<<<", ui.Bold, ui.Red), oldPath, st.Paint(">>>", ui.Bold, ui.Green), newPath)
}

func Compare(ctx context.Context, w io.Writer, st ui.Style, oldPath, newPath string, opts RenderOptions) error {
	paths := []string{oldPath, newPath}
	closures := make([]Closure, len(paths))
	errs := make([]error, len(paths))
	var wg sync.WaitGroup
	for i, p := range paths {
		wg.Go(func() { closures[i], errs[i] = Load(ctx, p) })
	}
	wg.Wait()
	if err := errors.Join(errs...); err != nil {
		return fmt.Errorf("comparing closures: %w", err)
	}
	return Render(w, st, Diff(closures[0], closures[1]), opts)
}

func Parse(top string, pathInfoJSON []byte) (Closure, error) {
	var infos map[string]pathInfo
	if err := json.Unmarshal(pathInfoJSON, &infos); err != nil {
		return Closure{}, fmt.Errorf("decoding the closure of %s: %w", top, err)
	}
	root, ok := infos[top]
	if !ok {
		return Closure{}, fmt.Errorf("decoding the closure of %s: the path itself is missing from it", top)
	}
	c := Closure{Sizes: make(map[string]int64, len(infos)), Selected: make(map[string]bool)}
	for path, info := range infos {
		if !storepath.Valid(path) {
			return Closure{}, fmt.Errorf("decoding the closure of %s: %q is not a store path", top, path)
		}
		c.Sizes[path] = info.NarSize
	}
	for _, ref := range root.References {
		if !strings.HasSuffix(ref, systemPathSuffix) {
			continue
		}
		for _, pkg := range infos[ref].References {
			c.Selected[storepath.Package(pkg)] = true
		}
	}
	return c, nil
}
