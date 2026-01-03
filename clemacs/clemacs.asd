(asdf:defsystem "clemacs"
  :description "SBCL-hosted clemacs bring-up scaffold"
  :version "0.0.1"
  :depends-on ("cffi")
  :serial t
  :components
  ((:file "package")
   (:file "errors")
   (:file "handles")
   (:file "elisp")
   (:file "elisp-compat")
   (:file "main")
   (:file "substrate")
   (:file "tty")
   (:file "tests")))
