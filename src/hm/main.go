package main

import (
	"os"

	"github.com/stubbedev/dotfiles/src/hm/internal/cli"
)

func main() {
	os.Exit(cli.Main(os.Args[1:]))
}
