(asdf:defsystem "clemacs"
  :description "SBCL-hosted clemacs bring-up scaffold"
  :version "0.0.1"
  :depends-on ("babel" "cffi" "cl-ppcre" "fiveam")
  :serial t
  :components
  ((:file "package")
   (:file "errors")
   (:file "handles")
   (:file "buffer")
   (:file "elisp")
   (:file "elisp-inventory")
   (:module "elisp-compat"
    :serial t
    :components
    ((:file "00-core")
     (:file "10-strings")
     (:file "20-regexp-rx-print")
     (:file "30-pcase")
     (:file "40-cl-lib-and-charset")
     (:file "50-keymaps-runtime-help")
     (:file "60-files")
     (:file "70-buffers-and-editor")
     (:file "80-ewoc")
     (:file "90-messages-and-macroexp")
     (:file "99-rest")
     (:file "55-command-loop")))
   (:file "elisp-load")
   (:file "elisp-ert")
   (:file "ert-upstream")
   (:file "main")
   (:file "substrate")
   (:file "display")
   (:file "tty")
   (:file "tests")))
