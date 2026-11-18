package sops

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"go.yaml.in/yaml/v3"

	"github.com/stubbedev/dotfiles/src/hm/internal/usage"
)

const (
	firstKey  = "age1ph82fy2jgjsmcsaufsrlzsql65g0ca954elacmqlsesz9ladwd0sgxsxj8"
	secondKey = "age1grkukkq0j3sgj84suvxftywmlgltrncp577ekgua9yv3cfrrfvrq7rycsh"
	newKey    = "age1qyqszqgpqyqszqgpqyqszqgpqyqszqgpqyqszqgpqyqszqgpqyqs3290gq"
)

func recipients(t *testing.T, doc []byte) map[string]string {
	t.Helper()
	var root yaml.Node
	if err := yaml.Unmarshal(doc, &root); err != nil {
		t.Fatal(err)
	}
	lists, err := ageLists(&root)
	if err != nil {
		t.Fatal(err)
	}
	out := map[string]string{}
	for _, l := range lists {
		for _, n := range l.Content {
			out[n.Value] = strings.TrimSpace(strings.TrimPrefix(n.LineComment, "#"))
		}
	}
	return out
}

func TestAddRecipient(t *testing.T) {
	doc, err := os.ReadFile(filepath.Join("testdata", "sops.yaml"))
	if err != nil {
		t.Fatal(err)
	}
	updated, added, err := AddRecipient(doc, newKey, "laptop")
	if err != nil || !added {
		t.Fatalf("AddRecipient: added=%v err=%v", added, err)
	}
	got := recipients(t, updated)
	if got[newKey] != "laptop" || len(got) != 3 {
		t.Fatalf("recipients = %v", got)
	}
	if _, ok := got[firstKey]; !ok {
		t.Fatalf("existing recipient lost: %v", got)
	}
	for _, kept := range []string{"# Per-machine age recipients.", "# Host key (/etc/ssh/ssh_host_ed25519_key)", "# Every file under secrets/"} {
		if !strings.Contains(string(updated), kept) {
			t.Errorf("comment %q lost:\n%s", kept, updated)
		}
	}
	if !strings.Contains(string(updated), "\n  - path_regex: secrets/[^/]+$\n    key_groups:\n      - age:\n") {
		t.Errorf("layout changed:\n%s", updated)
	}

	again, added, err := AddRecipient(updated, newKey, "other")
	if err != nil || added || again != nil {
		t.Fatalf("re-adding: added=%v err=%v", added, err)
	}
	if _, added, _ := AddRecipient(doc, secondKey, "x"); added {
		t.Fatal("existing recipient added twice")
	}
}

func TestAddRecipientEveryList(t *testing.T) {
	doc := []byte("creation_rules:\n  - key_groups:\n      - age:\n          - a\n      - age:\n          - b\n  - path_regex: x\n    key_groups:\n      - age: []\n")
	updated, added, err := AddRecipient(doc, "c", "n")
	if err != nil || !added {
		t.Fatal(added, err)
	}
	if strings.Count(string(updated), "- c # n\n") != 3 {
		t.Fatalf("not appended to every list:\n%s", updated)
	}
}

func TestAddRecipientRejectsMalformed(t *testing.T) {
	for _, doc := range []string{"", "foo: bar\n", "creation_rules: x\n", "creation_rules:\n  - key_groups: x\n", "creation_rules:\n  - path_regex: x\n", ":\n- ["} {
		if _, _, err := AddRecipient([]byte(doc), "k", "n"); err == nil {
			t.Errorf("AddRecipient accepted %q", doc)
		}
	}
}

func TestParsePipedValue(t *testing.T) {
	v, err := ParsePipedValue([]byte("hunter2\n\n"))
	if err != nil || string(v) != "hunter2" {
		t.Fatalf("ParsePipedValue = %q, %v", v, err)
	}
	if v, err := ParsePipedValue([]byte("a\nb\n")); err != nil || string(v) != "a\nb" {
		t.Fatalf("multi-line = %q, %v", v, err)
	}
	for _, bad := range []string{"", "\n\n", "a\x00b"} {
		if _, err := ParsePipedValue([]byte(bad)); err == nil {
			t.Errorf("ParsePipedValue(%q) succeeded", bad)
		}
	}
}

func TestParseTrustArgs(t *testing.T) {
	cases := []struct {
		args  []string
		stdin string
		tty   bool
		want  TrustRequest
	}{
		{[]string{"n", "k"}, "", true, TrustRequest{Name: "n", Pubkey: "k"}},
		{[]string{"k"}, "", true, TrustRequest{Pubkey: "k"}},
		{nil, "host k\nignored\n", false, TrustRequest{Name: "host", Pubkey: "k"}},
		{nil, "k", false, TrustRequest{Pubkey: "k"}},
	}
	for _, c := range cases {
		got, err := ParseTrustArgs(c.args, strings.NewReader(c.stdin), c.tty)
		if err != nil || got != c.want {
			t.Errorf("ParseTrustArgs(%v, %q) = %+v, %v", c.args, c.stdin, got, err)
		}
	}
	for _, c := range []struct {
		args  []string
		stdin string
		tty   bool
	}{{nil, "", true}, {nil, "\n", false}, {[]string{"a", "b", "c"}, "", true}} {
		if _, err := ParseTrustArgs(c.args, strings.NewReader(c.stdin), c.tty); !usage.Is(err) {
			t.Errorf("ParseTrustArgs(%v, %q, tty=%v) = %v, want a usage error", c.args, c.stdin, c.tty, err)
		}
	}
}

func TestAutoName(t *testing.T) {
	if got := AutoName(firstKey, firstKey, "desktop"); got != "desktop" {
		t.Fatalf("own key named %q", got)
	}
	if got := AutoName(firstKey, "", "desktop"); got != firstKey[len(firstKey)-8:] {
		t.Fatalf("foreign key named %q", got)
	}
}

func TestValidateNames(t *testing.T) {
	for _, ok := range []string{"token", "github-token", "a.b_c", "0x"} {
		if err := ValidateSecretName(ok); err != nil {
			t.Errorf("ValidateSecretName(%q) = %v", ok, err)
		}
	}
	for _, bad := range []string{"", "../escape", "/etc/escape", ".hidden", "sub/dir", "-flag"} {
		if err := ValidateSecretName(bad); !usage.Is(err) {
			t.Errorf("ValidateSecretName(%q) = %v, want a usage error", bad, err)
		}
	}
	if err := ValidateTrustName("bad name"); !usage.Is(err) {
		t.Errorf("ValidateTrustName accepted a space: %v", err)
	}
}

func TestResolveSecret(t *testing.T) {
	flake := t.TempDir()
	secrets := filepath.Join(flake, "secrets")
	for _, name := range []string{"token", "ssh.yaml", "aws.json", "aws.ini"} {
		if err := os.MkdirAll(secrets, 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(secrets, name), nil, 0o644); err != nil {
			t.Fatal(err)
		}
	}
	s := Store{Flake: flake}
	cases := map[string]string{"token": "token", "ssh": "ssh.yaml", "new": "new", "ssh.yaml": "ssh.yaml"}
	for in, want := range cases {
		got, err := s.ResolveSecret(in)
		if err != nil || got != filepath.Join(secrets, want) {
			t.Errorf("ResolveSecret(%q) = %q, %v", in, got, err)
		}
	}
	if _, err := s.ResolveSecret("aws"); !usage.Is(err) || !strings.Contains(err.Error(), "ambiguous") {
		t.Errorf("ResolveSecret(aws) = %v", err)
	}
	names, err := s.SecretNames()
	if err != nil || strings.Join(names, ",") != "aws.ini,aws.json,ssh.yaml,token" {
		t.Errorf("SecretNames = %v, %v", names, err)
	}
}
