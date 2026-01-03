(asdf:defsystem "clemacs"
  :description "SBCL-hosted clemacs bring-up scaffold"
  :version "0.0.1"
  :depends-on ("babel" "cffi" "fiveam")
  :serial t
  :components
  ((:file "package")
   (:file "errors")
   (:file "handles")
   (:file "buffer")
   (:file "elisp")
   (:file "elisp-compat")
   (:file "elisp-ert")
   (:file "main")
   (:file "substrate")
   (:file "tty")
   (:file "tests")))
