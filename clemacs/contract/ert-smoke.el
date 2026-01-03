(ert-reset)

(ert-deftest ert-smoke-plists ()
  (should (= (plist-get (plist-put nil 'a 1) 'a) 1)))

(ert-deftest ert-smoke-vectors ()
  (should (equal [1 2 3] [1 2 3])))

(ert-deftest ert-smoke-setq ()
  (should (= (progn (setq x 1) (symbol-value 'x)) 1)))
