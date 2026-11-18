package nixlog

import (
	"bytes"
	"fmt"
	"os"
)

const derivePrefix = "Derive("

func ReadInputDrvs(drvPath string) ([]string, error) {
	data, err := os.ReadFile(drvPath)
	if err != nil {
		return nil, fmt.Errorf("reading derivation %s: %w", drvPath, err)
	}
	inputs, err := ParseInputDrvs(data)
	if err != nil {
		return nil, fmt.Errorf("parsing derivation %s: %w", drvPath, err)
	}
	return inputs, nil
}

func ParseInputDrvs(data []byte) ([]string, error) {
	rest, ok := bytes.CutPrefix(data, []byte(derivePrefix))
	if !ok {
		return nil, fmt.Errorf("not an ATerm derivation: does not start with %q", derivePrefix)
	}
	p := &aterm{data: rest}
	if err := p.skipValue(); err != nil {
		return nil, fmt.Errorf("skipping the outputs: %w", err)
	}
	if err := p.expect(','); err != nil {
		return nil, err
	}
	if err := p.expect('['); err != nil {
		return nil, err
	}
	var inputs []string
	for {
		c, err := p.peek()
		if err != nil {
			return nil, err
		}
		if c == ']' {
			return inputs, nil
		}
		if len(inputs) > 0 {
			if err := p.expect(','); err != nil {
				return nil, err
			}
		}
		if err := p.expect('('); err != nil {
			return nil, err
		}
		path, err := p.str()
		if err != nil {
			return nil, fmt.Errorf("reading an input derivation path: %w", err)
		}
		inputs = append(inputs, path)
		if err := p.skipRest(')'); err != nil {
			return nil, err
		}
	}
}

type aterm struct {
	data []byte
	pos  int
}

func (p *aterm) peek() (byte, error) {
	if p.pos >= len(p.data) {
		return 0, fmt.Errorf("unexpected end of derivation at byte %d", p.pos)
	}
	return p.data[p.pos], nil
}

func (p *aterm) expect(want byte) error {
	c, err := p.peek()
	if err != nil {
		return err
	}
	if c != want {
		return fmt.Errorf("byte %d: got %q, want %q", p.pos, c, want)
	}
	p.pos++
	return nil
}

func (p *aterm) str() (string, error) {
	if err := p.expect('"'); err != nil {
		return "", err
	}
	start := p.pos
	escaped := false
	for p.pos < len(p.data) {
		c := p.data[p.pos]
		p.pos++
		switch {
		case escaped:
			escaped = false
		case c == '\\':
			escaped = true
		case c == '"':
			return string(p.data[start : p.pos-1]), nil
		}
	}
	return "", fmt.Errorf("unterminated string starting at byte %d", start)
}

func (p *aterm) skipValue() error {
	c, err := p.peek()
	if err != nil {
		return err
	}
	switch c {
	case '"':
		_, err := p.str()
		return err
	case '[':
		p.pos++
		return p.skipRest(']')
	case '(':
		p.pos++
		return p.skipRest(')')
	}
	return fmt.Errorf("byte %d: unexpected %q", p.pos, c)
}

func (p *aterm) skipRest(closing byte) error {
	for {
		c, err := p.peek()
		if err != nil {
			return err
		}
		switch c {
		case closing:
			p.pos++
			return nil
		case ',':
			p.pos++
		case '"', '[', '(':
			if err := p.skipValue(); err != nil {
				return err
			}
		default:
			return fmt.Errorf("byte %d: unexpected %q", p.pos, c)
		}
	}
}
