package elevate

import (
	"context"
	"fmt"
	"io"
	"strings"
	"time"

	"github.com/stubbedev/dotfiles/src/hm/internal/proc"
)

const refreshInterval = 50 * time.Second

func Command(argv ...string) []string {
	return append([]string{"sudo"}, argv...)
}

type Session struct {
	cancel context.CancelFunc
	done   chan struct{}
}

func Start(ctx context.Context, s proc.Streams) (*Session, error) {
	fmt.Fprintln(s.Stderr, "Requesting sudo...")
	validate := proc.Cmd{Argv: Command("-v"), Stdin: s.Stdin, Stdout: s.Stderr, Stderr: s.Stderr}
	if err := proc.Run(ctx, validate); err != nil {
		return nil, fmt.Errorf("validating sudo credentials: %w", err)
	}
	ctx, cancel := context.WithCancel(ctx)
	session := &Session{cancel: cancel, done: make(chan struct{})}
	go session.keepAlive(ctx, s.Stderr)
	return session, nil
}

func (s *Session) keepAlive(ctx context.Context, stderr io.Writer) {
	defer close(s.done)
	ticker := time.NewTicker(refreshInterval)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			refresh := proc.Cmd{Argv: Command("-n", "-v"), Stdin: strings.NewReader(""), Stdout: io.Discard, Stderr: io.Discard}
			if err := proc.Run(ctx, refresh); err != nil && ctx.Err() == nil {
				fmt.Fprintf(stderr, "hm: refreshing sudo credentials failed, sudo may prompt again: %v\n", err)
			}
		}
	}
}

func (s *Session) Stop() {
	s.cancel()
	<-s.done
}
