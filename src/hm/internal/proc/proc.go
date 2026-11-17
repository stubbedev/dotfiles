package proc

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"time"
)

const interruptGrace = 10 * time.Second

type Streams struct {
	Stdin  io.Reader
	Stdout io.Writer
	Stderr io.Writer
}

func (s Streams) Cmd(argv ...string) Cmd {
	return Cmd{Argv: argv, Stdin: s.Stdin, Stdout: s.Stdout, Stderr: s.Stderr}
}

type Cmd struct {
	Argv   []string
	Dir    string
	Env    []string
	Stdin  io.Reader
	Stdout io.Writer
	Stderr io.Writer
}

type Error struct {
	Argv []string
	Err  error
}

func (e *Error) Error() string {
	return fmt.Sprintf("running %s: %v", Quote(e.Argv), e.Err)
}

func (e *Error) Unwrap() error { return e.Err }

func Quote(argv []string) string {
	quoted := make([]string, len(argv))
	for i, arg := range argv {
		if arg == "" || strings.ContainsAny(arg, " \t\n\"'\\$`") {
			quoted[i] = strconv.Quote(arg)
			continue
		}
		quoted[i] = arg
	}
	return strings.Join(quoted, " ")
}

func Run(ctx context.Context, c Cmd) error {
	if len(c.Argv) == 0 {
		return errors.New("running a command: empty argv")
	}
	cmd := exec.CommandContext(ctx, c.Argv[0], c.Argv[1:]...)
	cmd.Dir = c.Dir
	if len(c.Env) > 0 {
		cmd.Env = append(os.Environ(), c.Env...)
	}
	cmd.Stdin, cmd.Stdout, cmd.Stderr = os.Stdin, os.Stdout, os.Stderr
	if c.Stdin != nil {
		cmd.Stdin = c.Stdin
	}
	if c.Stdout != nil {
		cmd.Stdout = c.Stdout
	}
	if c.Stderr != nil {
		cmd.Stderr = c.Stderr
	}
	cmd.Cancel = func() error { return cmd.Process.Signal(os.Interrupt) }
	cmd.WaitDelay = interruptGrace
	if err := cmd.Run(); err != nil {
		return &Error{Argv: c.Argv, Err: err}
	}
	return nil
}

func Output(ctx context.Context, c Cmd) ([]byte, error) {
	var out bytes.Buffer
	c.Stdout = &out
	err := Run(ctx, c)
	return out.Bytes(), err
}

func ExitCode(err error) (int, bool) {
	var exitErr *exec.ExitError
	if !errors.As(err, &exitErr) {
		return 0, false
	}
	return exitErr.ExitCode(), true
}
