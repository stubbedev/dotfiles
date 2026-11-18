package ui

import (
	"context"
	"os"
	"os/signal"
	"syscall"

	"golang.org/x/term"
)

func WatchSize(ctx context.Context, f *os.File) <-chan Size {
	sizes := make(chan Size, 1)
	signals := make(chan os.Signal, 1)
	signal.Notify(signals, syscall.SIGWINCH)
	go func() {
		defer signal.Stop(signals)
		for {
			select {
			case <-ctx.Done():
				return
			case <-signals:
			}
			width, height, err := term.GetSize(int(f.Fd()))
			if err != nil {
				continue
			}
			select {
			case <-sizes:
			default:
			}
			sizes <- Size{Width: width, Height: height}
		}
	}()
	return sizes
}
