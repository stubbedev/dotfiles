package storepath

import (
	"path"
	"strings"
)

const (
	Dir     = "/nix/store/"
	hashLen = 32
)

func Valid(p string) bool {
	rest, ok := strings.CutPrefix(p, Dir)
	return ok && len(rest) > hashLen+1 && rest[hashLen] == '-' && !strings.Contains(rest, "/")
}

func Name(p string) string {
	base := strings.TrimSuffix(path.Base(p), ".drv")
	if len(base) > hashLen && base[hashLen] == '-' {
		return base[hashLen+1:]
	}
	return base
}

func SplitVersion(name string) (string, string, bool) {
	for i := 1; i < len(name); i++ {
		if name[i] != '-' {
			continue
		}
		suffix := name[i+1:]
		if suffix != "" && (IsDigit(suffix[0]) || IsGitHash(suffix)) {
			return name[:i], suffix, true
		}
	}
	return name, "", false
}

func Package(p string) string {
	pname, _, _ := SplitVersion(Name(p))
	return pname
}

func IsDigit(c byte) bool { return c >= '0' && c <= '9' }

func IsGitHash(s string) bool { return IsHex(s) && HasHexLetter(s) }

func IsHex(s string) bool {
	if len(s) < 7 || len(s) > 40 {
		return false
	}
	for i := range len(s) {
		c := s[i]
		if !IsDigit(c) && (c < 'a' || c > 'f') && (c < 'A' || c > 'F') {
			return false
		}
	}
	return true
}

func HasHexLetter(s string) bool { return strings.ContainsAny(s, "abcdefABCDEF") }
