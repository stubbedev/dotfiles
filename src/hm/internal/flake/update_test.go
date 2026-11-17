package flake

import (
	"bytes"
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/stubbedev/dotfiles/src/hm/internal/proc"
)

func git(t *testing.T, dir string, args ...string) string {
	t.Helper()
	cmd := exec.Command("git", append([]string{"-C", dir}, args...)...)
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("git %v: %v\n%s", args, err, out)
	}
	return strings.TrimSpace(string(out))
}

func setupRepos(t *testing.T) (string, string) {
	t.Helper()
	if _, err := exec.LookPath("git"); err != nil {
		t.Fatalf("git is required: %v", err)
	}
	t.Setenv("GIT_CONFIG_GLOBAL", os.DevNull)
	t.Setenv("GIT_CONFIG_NOSYSTEM", "1")
	t.Setenv("GIT_AUTHOR_NAME", "t")
	t.Setenv("GIT_AUTHOR_EMAIL", "t@example.invalid")
	t.Setenv("GIT_COMMITTER_NAME", "t")
	t.Setenv("GIT_COMMITTER_EMAIL", "t@example.invalid")
	dir := t.TempDir()
	upstream := filepath.Join(dir, "upstream.git")
	work := filepath.Join(dir, "work")
	git(t, dir, "init", "--quiet", "--bare", "--initial-branch=master", upstream)
	git(t, dir, "clone", "--quiet", upstream, work)
	if err := os.WriteFile(filepath.Join(work, lockFile), []byte("{}\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	git(t, work, "add", lockFile)
	git(t, work, "commit", "--quiet", "-m", "init")
	git(t, work, "push", "--quiet", "-u", "origin", "master")
	return upstream, work
}

func repoFor(dir string) (Repo, *bytes.Buffer) {
	var out bytes.Buffer
	return Repo{Dir: dir, Ref: "path:" + dir, Streams: proc.Streams{Stdin: strings.NewReader(""), Stdout: &out, Stderr: &out}}, &out
}

func TestCommitLockPushes(t *testing.T) {
	upstream, work := setupRepos(t)
	r, out := repoFor(work)
	ctx := context.Background()

	if has, err := r.hasUpstream(ctx); err != nil || !has {
		t.Fatalf("hasUpstream = %v, %v", has, err)
	}
	if err := r.commitLock(ctx, true); err != nil {
		t.Fatal(err)
	}
	if strings.Contains(out.String(), "Committed") {
		t.Fatalf("committed an unchanged lock: %s", out)
	}

	if err := os.WriteFile(filepath.Join(work, lockFile), []byte(`{"v":2}`+"\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := r.commitLock(ctx, true); err != nil {
		t.Fatal(err)
	}
	if got := git(t, upstream, "log", "-1", "--format=%s"); got != "chore: update flake.lock" {
		t.Fatalf("upstream head = %q, output: %s", got, out)
	}
}

func TestCommitLockRebasesBeforeRetry(t *testing.T) {
	upstream, work := setupRepos(t)
	other := filepath.Join(t.TempDir(), "other")
	git(t, filepath.Dir(other), "clone", "--quiet", upstream, other)
	if err := os.WriteFile(filepath.Join(other, "README"), []byte("x\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	git(t, other, "add", "README")
	git(t, other, "commit", "--quiet", "-m", "elsewhere")
	git(t, other, "push", "--quiet")

	r, out := repoFor(work)
	if err := os.WriteFile(filepath.Join(work, lockFile), []byte(`{"v":3}`+"\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := r.commitLock(context.Background(), true); err != nil {
		t.Fatal(err)
	}
	log := git(t, upstream, "log", "--format=%s")
	if log != "chore: update flake.lock\nelsewhere\ninit" {
		t.Fatalf("upstream log = %q, output: %s", log, out)
	}
}

func TestHasUpstreamWithoutTracking(t *testing.T) {
	_, work := setupRepos(t)
	git(t, work, "branch", "--quiet", "--unset-upstream")
	r, _ := repoFor(work)
	if has, err := r.hasUpstream(context.Background()); err != nil || has {
		t.Fatalf("hasUpstream = %v, %v", has, err)
	}
}
