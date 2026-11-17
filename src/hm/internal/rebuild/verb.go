package rebuild

import "fmt"

type Verb int

const (
	Switch Verb = iota + 1
	Boot
	Test
	Build
	DryBuild
	DryActivate
	BuildVM
	BuildVMWithBootloader
)

var verbNames = []struct {
	verb Verb
	name string
}{
	{Switch, "switch"},
	{Boot, "boot"},
	{Test, "test"},
	{Build, "build"},
	{DryBuild, "dry-build"},
	{DryActivate, "dry-activate"},
	{BuildVM, "build-vm"},
	{BuildVMWithBootloader, "build-vm-with-bootloader"},
}

func Verbs() []Verb {
	out := make([]Verb, len(verbNames))
	for i, v := range verbNames {
		out[i] = v.verb
	}
	return out
}

func (v Verb) String() string {
	for _, n := range verbNames {
		if n.verb == v {
			return n.name
		}
	}
	return fmt.Sprintf("Verb(%d)", int(v))
}

func (v Verb) Activates() bool {
	switch v {
	case Switch, Boot, Test, DryActivate:
		return true
	}
	return false
}

func (v Verb) setsProfile() bool {
	return v == Switch || v == Boot
}

func (v Verb) linksResult() bool {
	switch v {
	case Build, BuildVM, BuildVMWithBootloader:
		return true
	}
	return false
}

func (v Verb) buildsVM() bool {
	return v == BuildVM || v == BuildVMWithBootloader
}

func (v Verb) nixosAttr() string {
	switch v {
	case BuildVM:
		return "config.system.build.vm"
	case BuildVMWithBootloader:
		return "config.system.build.vmWithBootLoader"
	}
	return "config.system.build.toplevel"
}
