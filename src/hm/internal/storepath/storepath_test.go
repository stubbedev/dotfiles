package storepath

import (
	"strings"
	"testing"
)

const hash = "lbn72v74by31g9w4dxxmw5ac1yklq6z6"

func TestName(t *testing.T) {
	cases := map[string]string{
		Dir + hash + "-hm-fixture-1.drv": "hm-fixture-1",
		Dir + hash + "-sl-5.05":          "sl-5.05",
		"short":                          "short",
	}
	for in, want := range cases {
		if got := Name(in); got != want {
			t.Errorf("Name(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestValid(t *testing.T) {
	for p, want := range map[string]bool{
		Dir + hash + "-x":                    true,
		Dir + hash + "-x/bin/y":              false,
		Dir + hash:                           false,
		"/tmp/" + hash + "-x":                false,
		Dir + strings.Repeat("a", 31) + "-x": false,
	} {
		if Valid(p) != want {
			t.Errorf("Valid(%q) = %v", p, !want)
		}
	}
}

func TestSplitVersion(t *testing.T) {
	cases := map[string]string{
		"hello-2.12.3":           "hello 2.12.3",
		"linux-firmware-2026020": "linux-firmware 2026020",
		"source":                 "source -",
		"vim-plugin-abc1234":     "vim-plugin abc1234",
		"python3.13-foo-1.0-dev": "python3.13-foo 1.0-dev",
		"etc-hosts":              "etc-hosts -",
	}
	for in, want := range cases {
		name, v, ok := SplitVersion(in)
		got := name + " -"
		if ok {
			got = name + " " + v
		}
		if got != want {
			t.Errorf("SplitVersion(%q) = %q, want %q", in, got, want)
		}
	}
	if got := Package(Dir + hash + "-gcc-16.2.0.drv"); got != "gcc" {
		t.Errorf("Package = %q", got)
	}
}
