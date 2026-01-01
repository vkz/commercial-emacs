/* Elisp native compiler stubs.

This file is NOT part of GNU Emacs.

This fork disables the Emacs Lisp native compiler (libgccjit).  Keep a
minimal stub API so Lisp can reliably detect that native compilation is
unavailable.  */

#include <config.h>

#include "lisp.h"

DEFUN ("native-comp-available-p", Fnative_comp_available_p,
       Snative_comp_available_p, 0, 0, 0,
       doc: /* Return non-nil if this build supports ELisp native compilation.
This fork disables native compilation, so this always returns nil.  */)
  (void)
{
  return Qnil;
}

void
syms_of_comp (void)
{
  defsubr (&Snative_comp_available_p);
}
