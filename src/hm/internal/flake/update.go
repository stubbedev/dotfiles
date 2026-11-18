package flake

import (
	"context"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/stubbedev/dotfiles/src/hm/internal/proc"
	"github.com/stubbedev/dotfiles/src/hm/internal/ui"
)

const (
	networkTimeout = 2 * time.Minute
	lockFile       = "flake.lock"
)

type Repo struct {
	Dir     string
	Ref     string
	Console ui.Console
}

func (r Repo) git(args ...string) proc.Cmd {
	argv := append([]string{
		"git", "-C", r.Dir,
		"-c", "merge.flakelock.name=keep current flake.lock (regenerated)",
		"-c", "merge.flakelock.driver=true",
	}, args...)
	return r.Console.Cmd(argv...)
}

func (r Repo) runGit(ctx context.Context, timeout time.Duration, args ...string) error {
	if timeout > 0 {
		var cancel context.CancelFunc
		ctx, cancel = context.WithTimeout(ctx, timeout)
		defer cancel()
	}
	return proc.Run(ctx, r.git(args...))
}

func Update(ctx context.Context, r Repo) error {
	r.Console.Log().Step("Updating flake inputs")
	if _, err := os.Stat(filepath.Join(r.Dir, ".git")); errors.Is(err, fs.ErrNotExist) {
		return r.updateLock(ctx)
	} else if err != nil {
		return fmt.Errorf("checking whether %s is a git checkout: %w", r.Dir, err)
	}

	upstream, err := r.hasUpstream(ctx)
	if err != nil {
		return err
	}
	if upstream {
		if err := r.pull(ctx); err != nil {
			r.Console.Log().Warn("pulling %s from upstream failed, updating against the local checkout: %v", r.Dir, err)
		}
	}
	if err := r.updateLock(ctx); err != nil {
		return err
	}
	return r.commitLock(ctx, upstream)
}

func (r Repo) updateLock(ctx context.Context) error {
	argv := []string{"nix", "--extra-experimental-features", "nix-command flakes", "flake", "update", "--flake", r.Ref, "--quiet"}
	return proc.Run(ctx, r.Console.Cmd(argv...))
}

func (r Repo) hasUpstream(ctx context.Context) (bool, error) {
	cmd := r.git("rev-parse", "--verify", "--quiet", "@{u}")
	cmd.Stdout = io.Discard
	err := proc.Run(ctx, cmd)
	if err == nil {
		return true, nil
	}
	if code, ok := proc.ExitCode(err); ok && code == 1 {
		return false, nil
	}
	return false, fmt.Errorf("looking up the upstream of %s: %w", r.Dir, err)
}

func (r Repo) pull(ctx context.Context) error {
	pullErr := r.runGit(ctx, networkTimeout, "pull", "--rebase", "--autostash", "--quiet")
	if pullErr == nil {
		return nil
	}
	inRebase, err := r.rebaseInProgress(ctx)
	if err != nil {
		return errors.Join(pullErr, err)
	}
	if !inRebase {
		return pullErr
	}
	if err := r.runGit(ctx, 0, "rebase", "--abort"); err != nil {
		return errors.Join(pullErr, fmt.Errorf("aborting the failed rebase: %w", err))
	}
	return pullErr
}

func (r Repo) rebaseInProgress(ctx context.Context) (bool, error) {
	out, err := proc.Output(ctx, r.git("rev-parse", "--git-path", "rebase-merge", "--git-path", "rebase-apply"))
	if err != nil {
		return false, fmt.Errorf("locating rebase state in %s: %w", r.Dir, err)
	}
	for _, p := range strings.Fields(string(out)) {
		if !filepath.IsAbs(p) {
			p = filepath.Join(r.Dir, p)
		}
		if _, err := os.Stat(p); err == nil {
			return true, nil
		} else if !errors.Is(err, fs.ErrNotExist) {
			return false, fmt.Errorf("checking rebase state %s: %w", p, err)
		}
	}
	return false, nil
}

func (r Repo) commitLock(ctx context.Context, upstream bool) error {
	err := r.runGit(ctx, 0, "diff", "--quiet", "--", lockFile)
	if err == nil {
		return nil
	}
	if code, ok := proc.ExitCode(err); !ok || code != 1 {
		return fmt.Errorf("checking %s for changes: %w", lockFile, err)
	}
	if err := r.runGit(ctx, 0, "commit", "--quiet", "-m", "chore: update flake.lock", "--", lockFile); err != nil {
		return fmt.Errorf("committing %s: %w", lockFile, err)
	}
	r.Console.Log().Done("Committed the updated %s", lockFile)
	if !upstream {
		return nil
	}
	firstPush := r.git("push", "--quiet")
	firstPush.Stderr = io.Discard
	pushCtx, cancel := context.WithTimeout(ctx, networkTimeout)
	defer cancel()
	if proc.Run(pushCtx, firstPush) == nil {
		return nil
	}
	if err := r.pull(ctx); err != nil {
		r.Console.Log().Warn("%s committed locally; pulling before the push retry failed, resolve manually: %v", lockFile, err)
		return nil
	}
	if err := r.runGit(ctx, networkTimeout, "push", "--quiet"); err != nil {
		r.Console.Log().Warn("%s committed locally; push failed, resolve manually: %v", lockFile, err)
	}
	return nil
}
