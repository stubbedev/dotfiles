package cli

import (
	"bytes"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"strings"

	"github.com/spf13/cobra"
	"golang.org/x/term"

	"github.com/stubbedev/dotfiles/src/hm/internal/config"
	"github.com/stubbedev/dotfiles/src/hm/internal/sops"
	"github.com/stubbedev/dotfiles/src/hm/internal/ui"
	"github.com/stubbedev/dotfiles/src/hm/internal/usage"
)

func (a *App) store(cfg config.Config) sops.Store {
	return sops.Store{Flake: cfg.Flake, Console: a.console}
}

func shortHostname() (string, error) {
	host, err := os.Hostname()
	if err != nil {
		return "", fmt.Errorf("reading the hostname: %w", err)
	}
	short, _, _ := strings.Cut(host, ".")
	return short, nil
}

func (a *App) whoamiCmd() *cobra.Command {
	return &cobra.Command{
		Use:               "whoami",
		Short:             `Print "<hostname> <age-pubkey>" for this machine`,
		GroupID:           groupMaintain,
		Args:              noArgs,
		ValidArgsFunction: cobra.NoFileCompletions,
		RunE: func(cmd *cobra.Command, _ []string) error {
			cfg, err := a.config()
			if err != nil {
				return err
			}
			host, err := shortHostname()
			if err != nil {
				return err
			}
			pubkey, err := sops.AgePubkey(cmd.Context(), a.console.Streams, cfg.SSHPublicKey())
			if err != nil {
				return err
			}
			fmt.Fprintf(a.console.Stdout, "%s %s\n", host, pubkey)
			return nil
		},
	}
}

func (a *App) trustCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "trust [name] <pubkey>",
		Short: "Add an age recipient to .sops.yaml and re-wrap secrets/*",
		Long: `Add an age recipient to .sops.yaml and re-wrap every file under secrets/.

  hm trust <name> <pubkey>
  hm trust <pubkey>           name it after this host if the key is ours, else the key's last 8 characters
  cmd | hm trust              read "<name> <pubkey>" from stdin, e.g. ssh other hm whoami | hm trust`,
		GroupID:           groupMaintain,
		ValidArgsFunction: cobra.NoFileCompletions,
		RunE: func(cmd *cobra.Command, args []string) error {
			cfg, err := a.config()
			if err != nil {
				return err
			}
			req, err := sops.ParseTrustArgs(args, a.console.Stdin, a.terminal.StdinTTY)
			if err != nil {
				return err
			}
			if req.Name == "" {
				if req.Name, err = a.autoName(cmd, cfg, req.Pubkey); err != nil {
					return err
				}
			}
			return a.store(cfg).Trust(cmd.Context(), req)
		},
	}
}

func (a *App) autoName(cmd *cobra.Command, cfg config.Config, pubkey string) (string, error) {
	host, err := shortHostname()
	if err != nil {
		return "", err
	}
	local := ""
	if _, err := os.Stat(cfg.SSHPublicKey()); err == nil {
		if local, err = sops.AgePubkey(cmd.Context(), a.console.Streams, cfg.SSHPublicKey()); err != nil {
			return "", err
		}
	} else if !errors.Is(err, fs.ErrNotExist) {
		return "", fmt.Errorf("checking for %s: %w", cfg.SSHPublicKey(), err)
	}
	return sops.AutoName(pubkey, local, host), nil
}

func (a *App) secretCmd() *cobra.Command {
	parent := &cobra.Command{
		Use:     "secret <edit|set|rotate> <name>",
		Short:   "Edit, set or rotate an encrypted file under secrets/",
		GroupID: groupMaintain,
		Args:    cobra.ArbitraryArgs,
		RunE: func(_ *cobra.Command, args []string) error {
			if len(args) == 0 {
				return usage.Errorf("secret needs an action: edit, set or rotate")
			}
			return usage.Errorf("secret: unknown action %q (want edit, set or rotate)", args[0])
		},
	}
	parent.AddCommand(
		a.secretAction("edit", "Open secrets/<name> in $EDITOR through sops, binary mode (creates it if absent)", func(cmd *cobra.Command, s sops.Store, path string) error {
			return s.Edit(cmd.Context(), path)
		}),
		a.secretAction("set", "Replace secrets/<name> with a new value (prompts on a TTY, reads stdin otherwise)", func(cmd *cobra.Command, s sops.Store, path string) error {
			value, err := a.readSecretValue(filepath.Base(path))
			if err != nil {
				return err
			}
			if err := s.Set(cmd.Context(), path, value); err != nil {
				return err
			}
			a.console.Out().Done("Updated secrets/%s. Run %s to deploy, then commit.", filepath.Base(path), a.console.OutStyle.Paint("hm switch", ui.Cyan))
			return nil
		}),
		a.secretAction("rotate", "Re-roll the data key of secrets/<name>, recipients unchanged", func(cmd *cobra.Command, s sops.Store, path string) error {
			if err := s.Rotate(cmd.Context(), path); err != nil {
				return err
			}
			a.console.Out().Done("Re-rolled data key for %s. Recipients unchanged.", filepath.Base(path))
			return nil
		}),
	)
	return parent
}

func (a *App) secretAction(name, short string, run func(*cobra.Command, sops.Store, string) error) *cobra.Command {
	return &cobra.Command{
		Use:               name + " <name>",
		Short:             short,
		Args:              exactArgs(1),
		ValidArgsFunction: a.completeSecretNames,
		RunE: func(cmd *cobra.Command, args []string) error {
			cfg, err := a.config()
			if err != nil {
				return err
			}
			store := a.store(cfg)
			path, err := store.ResolveSecret(args[0])
			if err != nil {
				return err
			}
			return run(cmd, store, path)
		},
	}
}

func (a *App) readSecretValue(name string) ([]byte, error) {
	if !a.terminal.StdinTTY {
		data, err := io.ReadAll(a.console.Stdin)
		if err != nil {
			return nil, fmt.Errorf("reading the value of %s from stdin: %w", name, err)
		}
		return sops.ParsePipedValue(data)
	}
	tty, ok := a.console.Stdin.(*os.File)
	if !ok {
		return nil, errors.New("reading a secret: stdin is a terminal but not a file")
	}
	value, err := a.prompt(tty, "New value for "+name+": ")
	if err != nil {
		return nil, err
	}
	confirm, err := a.prompt(tty, "Confirm: ")
	if err != nil {
		return nil, err
	}
	if !bytes.Equal(value, confirm) {
		return nil, errors.New("secret set: values do not match")
	}
	if len(value) == 0 {
		return nil, errors.New("secret set: refusing to write an empty value")
	}
	return value, nil
}

func (a *App) prompt(tty *os.File, label string) ([]byte, error) {
	fmt.Fprint(a.console.Stderr, label)
	value, err := term.ReadPassword(int(tty.Fd()))
	fmt.Fprintln(a.console.Stderr)
	if err != nil {
		return nil, fmt.Errorf("reading a secret from the terminal: %w", err)
	}
	return value, nil
}
