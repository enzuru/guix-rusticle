(use-modules (guix packages)
             (guix download)
             (guix build-system gnu)
             (guix build-system python)
             (guix build-system cargo)
             (guix licenses)
             (gnu packages bash)
             (gnu packages gl)
             (gnu packages rust)
             (gnu packages crates-io)
             (gnu packages games)
             (gnu packages vulkan)
             (gnu packages xdisorg)
             (gnu packages python-xyz)
             (gnu packages python)
             (gnu packages ninja)
             (gnu packages rust-apps)
             (gnu packages llvm)
             (guix utils)
             (guix gexp)
             (guix licenses))


(define-public meson-1.2.0
  (package
   (name "meson")
   (version "1.2.0")
   (source (origin
            (method url-fetch)
            (uri (string-append "https://github.com/mesonbuild/meson/"
                                "releases/download/" version  "/meson-"
                                version ".tar.gz"))
            (sha256
             (base32
              "0vzd1nmms2049pj2mjd5d1q5fj1076zz2iw674p0g9xnwr7n62qw"))))
   (build-system python-build-system)
   (arguments
    (list #:tests? #f            ;disabled to avoid extra dependencies
          #:phases
          #~(modify-phases %standard-phases
                           ;; Meson calls the various executables in out/bin through the
                           ;; Python interpreter, so we cannot use the shell wrapper.
                           (replace 'wrap
                                    (lambda* (#:key inputs outputs #:allow-other-keys)
                                      (substitute* (search-input-file outputs "bin/meson")
                                                   (("# EASY-INSTALL-ENTRY-SCRIPT")
                                                    (format #f "\
import sys
sys.path.insert(0, '~a')
# EASY-INSTALL-ENTRY-SCRIPT" (site-packages inputs outputs)))))))))
   (inputs (list python ninja))
   (home-page "https://mesonbuild.com/")
   (synopsis "Build system designed to be fast and user-friendly")
   (description
    "The Meson build system is focused on user-friendliness and speed.
It can compile code written in C, C++, Fortran, Java, Rust, and other
languages.  Meson provides features comparable to those of the
Autoconf/Automake/make combo.  Build specifications, also known as @dfn{Meson
files}, are written in a custom domain-specific language (@dfn{DSL}) that
resembles Python.")
   (license asl2.0)))

;; (define-public rust-clang-sys-1
;;   (package
;;    (name "rust-clang-sys")
;;    (version "1.0.0")
;;    (source
;;     (origin
;;      (method url-fetch)
;;      (uri (crate-uri "clang-sys" version))
;;      (file-name (string-append name "-" version ".tar.gz"))
;;      (sha256
;;       (base32
;;        "0695kfrqx7n091fzm6msbqg2q2kyhka64q08lm63f3l9d964i8cx"))))
;;    (build-system cargo-build-system)
;;    (inputs
;;     (list clang-15))
;;    (arguments
;;     `(#:cargo-inputs
;;       (("rust-glob" ,rust-glob-0.3)
;;        ("rust-libc" ,rust-libc-0.2)
;;        ("rust-libloading" ,rust-libloading-0.6))))
;;    (home-page "https://github.com/KyleMayes/clang-sys")
;;    (synopsis "Rust bindings for libclang")
;;    (description "This package provides Rust bindings for libclang.")
;;    (license asl2.0)))

;; (define-public rust-bindgen-0.64
;;   (package
;;     (inherit rust-bindgen-0.66)
;;     (name "rust-bindgen")
;;     (version "0.64.0")
;;     (source
;;      (origin
;;        (method url-fetch)
;;        (uri (crate-uri "bindgen" version))
;;        (file-name (string-append name "-" version ".tar.gz"))
;;        (sha256
;;         (base32 "1d0zmfc5swjgaydbamxb4xm687ahgv18dbcpvrzbf39665h3w964"))))
;;     (arguments
;;      `(#:skip-build? #t
;;        #:cargo-inputs
;;        (("rust-bitflags" ,rust-bitflags-1)
;;         ("rust-cexpr" ,rust-cexpr-0.6)
;;         ("rust-clang-sys" ,rust-clang-sys-1)
;;         ("rust-lazy-static" ,rust-lazy-static-1)
;;         ("rust-lazycell" ,rust-lazycell-1)
;;         ("rust-log" ,rust-log-0.4)
;;         ("rust-peeking-take-while" ,rust-peeking-take-while-0.1)
;;         ("rust-proc-macro2" ,rust-proc-macro2-1)
;;         ("rust-quote" ,rust-quote-1)
;;         ("rust-regex" ,rust-regex-1)
;;         ("rust-rustc-hash" ,rust-rustc-hash-1)
;;         ("rust-shlex" ,rust-shlex-1)
;;         ("rust-syn" ,rust-syn-1)
;;         ("rust-which" ,rust-which-4))))))

(define-public rust-bindgen-cli
  (package
   (name "rust-bindgen-cli")
   (version "0.69.4")
   (source
    (origin
     (method url-fetch)
     (uri (crate-uri "bindgen-cli" version))
     (file-name (string-append name "-" version ".tar.gz"))
     (sha256
      (base32 "00dfny07m4xfnqbfn7yr7cqwilj6935lbyg5d39yxjfj8jglfcax"))))
   (build-system cargo-build-system)
   (arguments
    `(#:install-source? #f
      #:cargo-inputs (("rust-bindgen" ,rust-bindgen-0.69)
                      ("rust-clap" ,rust-clap-4)
                      ("rust-clap-complete" ,rust-clap-complete-4)
                      ("rust-env-logger" ,rust-env-logger-0.10)
                      ("rust-log" ,rust-log-0.4)
                      ("rust-shlex" ,rust-shlex-1))
      #:phases
      (modify-phases %standard-phases
                     (replace 'install
                              (lambda* (#:key inputs outputs #:allow-other-keys)
                                (let* ((bin (string-append (assoc-ref outputs "out") "/bin"))
                                       (bindgen (string-append bin "/bindgen"))
                                       (llvm-dir (string-append
                                                  (assoc-ref inputs "clang") "/lib")))
                                  (install-file "target/release/bindgen" bin)
                                  (wrap-program bindgen
                                                `("LIBCLANG_PATH" = (,llvm-dir))))))
                     (add-after 'install 'install-completions
                                (lambda* (#:key native-inputs outputs #:allow-other-keys)
                                  (let* ((out (assoc-ref outputs "out"))
                                         (share (string-append out "/share"))
                                         (bindgen (string-append out "/bin/bindgen")))
                                    (mkdir-p (string-append share "/bash-completion/completions"))
                                    (with-output-to-file
                                        (string-append share "/bash-completion/completions/bindgen")
                                      (lambda _ (invoke bindgen "--generate-shell-completions" "bash")))
                                    (mkdir-p (string-append share "/fish/vendor_completions.d"))
                                    (with-output-to-file
                                        (string-append share "/fish/vendor_completions.d/bindgen.fish")
                                      (lambda _ (invoke bindgen "--generate-shell-completions" "fish")))
                                    (mkdir-p (string-append share "/zsh/site-functions"))
                                    (with-output-to-file
                                        (string-append share "/zsh/site-functions/_bindgen")
                                      (lambda _ (invoke bindgen "--generate-shell-completions" "zsh")))
                                    (mkdir-p (string-append share "/elvish/lib"))
                                    (with-output-to-file
                                        (string-append share "/elvish/lib/bindgen")
                                      (lambda _
                                        (invoke bindgen "--generate-shell-completions" "elvish")))))))))
   (inputs (list bash-minimal clang-15))
   (home-page "https://rust-lang.github.io/rust-bindgen/")
   (synopsis "Generate Rust FFI bindings to C and C++ libraries")
   (description "This package can be used to automatically generate Rust FFI
bindings to C and C++ libraries.  This package provides the @command{bindgen}
command.")
   (license bsd-3)))

(package/inherit mesa-opencl
                 (name "mesa-opencl-rusticle")
                 (source (origin (inherit (package-source mesa-opencl))))
                 (arguments
                  (substitute-keyword-arguments (package-arguments mesa-opencl)
                                                ((#:configure-flags flags)
                                                 #~(cons "-Dgallium-opencl=disabled -Dgallium-rusticl=true -Dllvm=enabled -Drust_std=2021" #$flags))))
                 (native-inputs
                  (modify-inputs (package-native-inputs mesa-opencl)
                                 (prepend rust
                                          rust-bindgen-0.64
                                          rust-bindgen-cli
                                          rust-spirv-types-0.4
                                          rust-spirv-std-0.4
                                          rust-spirv-std-macros-0.4
                                          spirv-headers
                                          spirv-cross
                                          spirv-tools
                                          libdrm
                                          python-ply
                                          meson-1.2.0))))

;; reinstall meca-opencl and mesa-opencl-icd when done
;;update libdrm to 2.4.119
