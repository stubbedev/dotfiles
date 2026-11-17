package sops

import (
	"bytes"
	"errors"
	"fmt"

	"go.yaml.in/yaml/v3"
)

const yamlIndent = 2

func AddRecipient(doc []byte, pubkey, name string) ([]byte, bool, error) {
	var root yaml.Node
	if err := yaml.Unmarshal(doc, &root); err != nil {
		return nil, false, fmt.Errorf("parsing .sops.yaml: %w", err)
	}
	lists, err := ageLists(&root)
	if err != nil {
		return nil, false, err
	}
	for _, list := range lists {
		for _, item := range list.Content {
			if item.Value == pubkey {
				return nil, false, nil
			}
		}
	}
	for _, list := range lists {
		list.Style &^= yaml.FlowStyle
		list.Content = append(list.Content, &yaml.Node{
			Kind:        yaml.ScalarNode,
			Tag:         "!!str",
			Value:       pubkey,
			LineComment: name,
		})
	}
	var out bytes.Buffer
	enc := yaml.NewEncoder(&out)
	enc.SetIndent(yamlIndent)
	if err := enc.Encode(&root); err != nil {
		return nil, false, fmt.Errorf("encoding .sops.yaml: %w", err)
	}
	if err := enc.Close(); err != nil {
		return nil, false, fmt.Errorf("encoding .sops.yaml: %w", err)
	}
	return out.Bytes(), true, nil
}

func ageLists(root *yaml.Node) ([]*yaml.Node, error) {
	if root.Kind != yaml.DocumentNode || len(root.Content) != 1 {
		return nil, errors.New(".sops.yaml is not a single YAML document")
	}
	rules := mappingValue(root.Content[0], "creation_rules")
	if rules == nil || rules.Kind != yaml.SequenceNode {
		return nil, errors.New(".sops.yaml has no creation_rules list")
	}
	var lists []*yaml.Node
	for _, rule := range rules.Content {
		groups := mappingValue(rule, "key_groups")
		if groups == nil {
			continue
		}
		if groups.Kind != yaml.SequenceNode {
			return nil, errors.New(".sops.yaml: key_groups is not a list")
		}
		for _, group := range groups.Content {
			age := mappingValue(group, "age")
			if age == nil {
				continue
			}
			if age.Kind != yaml.SequenceNode {
				return nil, errors.New(".sops.yaml: a key group's age entry is not a list")
			}
			lists = append(lists, age)
		}
	}
	if len(lists) == 0 {
		return nil, errors.New(".sops.yaml has no creation_rules[].key_groups[].age list")
	}
	return lists, nil
}

func mappingValue(n *yaml.Node, key string) *yaml.Node {
	if n.Kind != yaml.MappingNode {
		return nil
	}
	for i := 0; i+1 < len(n.Content); i += 2 {
		if n.Content[i].Value == key {
			return n.Content[i+1]
		}
	}
	return nil
}
