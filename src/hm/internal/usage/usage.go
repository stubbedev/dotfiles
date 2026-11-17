package usage

import (
	"errors"
	"fmt"
)

type Error struct {
	err error
}

func (e *Error) Error() string { return e.err.Error() }

func (e *Error) Unwrap() error { return e.err }

func Errorf(format string, args ...any) error {
	return &Error{err: fmt.Errorf(format, args...)}
}

func Wrap(err error) error {
	return &Error{err: err}
}

func Is(err error) bool {
	var u *Error
	return errors.As(err, &u)
}
