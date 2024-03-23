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
             (guix licenses)
             (guix build-system)
             (guix build-system glib-or-gtk)
             (guix search-paths)
             (guix monads)
             (guix store))

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
     (list #:tests? #f           ;disabled to avoid extra dependencies
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

(define (make-machine-alist triplet)
  "Make an association list describing what should go into
the ‘host_machine’ section of the cross file when cross-compiling
for TRIPLET."
  `((system . ,(cond ((target-hurd? triplet) "gnu")
                     ((target-linux? triplet) "linux")
                     ((target-mingw? triplet) "windows")
                     ((target-avr? triplet) "none")
                     (#t (error "meson: unknown operating system"))))
    (cpu_family . ,(cond ((target-x86-32? triplet) "x86")
                         ((target-x86-64? triplet) "x86_64")
                         ((target-arm32? triplet) "arm")
                         ((target-aarch64? triplet) "aarch64")
                         ((target-avr? triplet) "avr")
                         ((target-mips64el? triplet) "mips64")
                         ((target-powerpc? triplet)
                          (if (target-64bit? triplet)
                              "ppc64"
                              "ppc"))
                         ((target-riscv64? triplet) "riscv64")
                         (#t (error "meson: unknown architecture"))))
    (cpu . ,(cond ((target-x86-32? triplet) ; i386, ..., i686
                   (substring triplet 0 4))
                  ((target-x86-64? triplet) "x86_64")
                  ((target-aarch64? triplet) "armv8-a")
                  ((target-arm32? triplet) "armv7")
                  ((target-avr? triplet) "avr")
                  ;; According to #mesonbuild on OFTC, there does not appear
                  ;; to be an official-ish list of CPU types recognised by
                  ;; Meson, the "cpu" field is not used by Meson itself and
                  ;; most software doesn't look at this field, except perhaps
                  ;; for selecting optimisations, so set it to something
                  ;; arbitrary.
                  (#t "strawberries")))
    (endian . ,(if (target-little-endian? triplet)
                   "little"
                   "big"))))

(define (make-binaries-alist triplet)
  "Make an associatoin list describing what should go into
the ‘binaries’ section of the cross file when cross-compiling for
TRIPLET."
  `((c . ,(cc-for-target triplet))
    (cpp . ,(cxx-for-target triplet))
    (pkgconfig . ,(pkg-config-for-target triplet))
    (objcopy . ,(string-append triplet "-objcopy"))
    (ar . ,(string-append triplet "-ar"))
    (ld . ,(string-append triplet "-ld"))
    (strip . ,(string-append triplet "-strip"))))

(define (make-built-in-options-alist triplet)
  (if (target-avr? triplet)
      `((b_pie . #f)
        (b_staticpic . #f)
        (default_library . "static"))
       '()))

(define (make-cross-file triplet)
  (computed-file "cross-file"
    (with-imported-modules '((guix build meson-configuration))
      #~(begin
          (use-modules (guix build meson-configuration))
          (call-with-output-file #$output
            (lambda (port)
              (write-section-header port "host_machine")
              (write-assignments port '#$(make-machine-alist triplet))
              (write-section-header port "binaries")
              (write-assignments port '#$(make-binaries-alist triplet))
              (write-section-header port "built-in options")
              (write-assignments port '#$(make-built-in-options-alist triplet))))))))

(define %meson-build-system-modules
  ;; Build-side modules imported by default.
  `((guix build meson-build-system)
    ;; The modules from glib-or-gtk contains the modules from gnu-build-system,
    ;; so there is no need to import that too.
    ,@%glib-or-gtk-build-system-modules))

(define (default-ninja)
  "Return the default ninja package."
  ;; Lazily resolve the binding to avoid a circular dependency.
  (let ((module (resolve-interface '(gnu packages ninja))))
    (module-ref module 'ninja)))

(define (default-meson)
  "Return the default meson package."
  ;; Lazily resolve the binding to avoid a circular dependency.
  (let ((module (resolve-interface '(gnu packages build-tools))))
    (module-ref module 'meson)))

(define* (lower name
                #:key source inputs native-inputs outputs system target
                (meson (default-meson))
                ;;(meson (meson-1.2.0))
                (ninja (default-ninja))
                (glib-or-gtk? #f)
                #:allow-other-keys
                #:rest arguments)
  "Return a bag for NAME."
  (define private-keywords
    `(#:meson #:ninja #:inputs #:native-inputs #:outputs
      ,@(if target
            '()
            '(#:target))))

  (bag
    (name name)
    (system system) (target target)
    (build-inputs `(("meson" ,meson-1.2.0)
                    ("ninja" ,ninja)
                    ,@native-inputs
                    ,@(if target '() inputs)
                    ;; Keep the standard inputs of 'gnu-build-system'.
                    ,@(if target
                          (standard-cross-packages target 'host)
                          '())
                    ,@(standard-packages)))
    (host-inputs `(,@(if source
                         `(("source" ,source))
                         '())
                   ,@(if target inputs '())))
    ;; Keep the standard inputs of 'gnu-buid-system'.
    (target-inputs (if target
                       (standard-cross-packages target 'target)
                       '()))
    (outputs outputs)
    (build (if target meson-cross-build meson-build))
    (arguments (strip-keyword-arguments private-keywords arguments))))

(define* (meson-build name inputs
                      #:key
                      guile source
                      (outputs '("out"))
                      (configure-flags ''())
                      (search-paths '())
                      (build-type "debugoptimized")
                      (tests? #t)
                      (test-options ''())
                      (glib-or-gtk? #f)
                      (parallel-build? #t)
                      (parallel-tests? #f)
                      (validate-runpath? #t)
                      (patch-shebangs? #t)
                      (strip-binaries? #t)
                      (strip-flags %strip-flags)
                      (strip-directories %strip-directories)
                      (elf-directories ''("lib" "lib64" "libexec"
                                          "bin" "sbin"))
                      (phases '%standard-phases)
                      (system (%current-system))
                      (imported-modules %meson-build-system-modules)
                      (modules '((guix build meson-build-system)
                                 (guix build utils)))
                      (substitutable? #t)
                      allowed-references
                      disallowed-references)
  "Build SOURCE using MESON, and with INPUTS, assuming that SOURCE
has a 'meson.build' file."
  (define builder
    (with-imported-modules imported-modules
      #~(begin
          (use-modules #$@(sexp->gexp modules))

          (define build-phases
            #$(let ((phases (if (pair? phases) (sexp->gexp phases) phases)))
                (if glib-or-gtk?
                    phases
                    #~(modify-phases #$phases
                        (delete 'glib-or-gtk-compile-schemas)
                        (delete 'glib-or-gtk-wrap)))))

          #$(with-build-variables inputs outputs
              #~(meson-build #:source #+source
                             #:system #$system
                             #:outputs %outputs
                             #:inputs %build-inputs
                             #:search-paths '#$(sexp->gexp
                                                (map search-path-specification->sexp
                                                     search-paths))
                             #:phases build-phases
                             #:configure-flags
                             #$(if (pair? configure-flags)
                                   (sexp->gexp configure-flags)
                                   configure-flags)
                             #:build-type #$build-type
                             #:tests? #$tests?
                             #:test-options #$(sexp->gexp test-options)
                             #:parallel-build? #$parallel-build?
                             #:parallel-tests? #$parallel-tests?
                             #:validate-runpath? #$validate-runpath?
                             #:patch-shebangs? #$patch-shebangs?
                             #:strip-binaries? #$strip-binaries?
                             #:strip-flags #$strip-flags
                             #:strip-directories #$strip-directories
                             #:elf-directories #$(sexp->gexp elf-directories))))))

  (mlet %store-monad ((guile (package->derivation (or guile (default-guile))
                                                  system #:graft? #f)))
    (gexp->derivation name builder
                      #:system system
                      #:target #f
                      #:graft? #f
                      #:substitutable? substitutable?
                      #:allowed-references allowed-references
                      #:disallowed-references disallowed-references
                      #:guile-for-build guile)))

(define* (meson-cross-build name
                            #:key
                            target
                            build-inputs host-inputs target-inputs
                            guile source
                            (outputs '("out"))
                            (configure-flags ''())
                            (search-paths '())
                            (native-search-paths '())

                            (build-type "debugoptimized")
                            (tests? #f)
                            (test-options ''())
                            (glib-or-gtk? #f)
                            (parallel-build? #t)
                            (parallel-tests? #f)
                            (validate-runpath? #t)
                            (patch-shebangs? #t)
                            (strip-binaries? #t)
                            (strip-flags %strip-flags)
                            (strip-directories %strip-directories)
                            (elf-directories ''("lib" "lib64" "libexec"
                                                "bin" "sbin"))
                            ;; See 'gnu-cross-build' for why this needs to be
                            ;; disabled when cross-compiling.
                            (make-dynamic-linker-cache? #f)
                            (phases '%standard-phases)
                            (system (%current-system))
                            (imported-modules %meson-build-system-modules)
                            (modules '((guix build meson-build-system)
                                       (guix build utils)))
                            (substitutable? #t)
                            allowed-references
                            disallowed-references)
  "Cross-build SOURCE for TARGET using MESON, and with INPUTS, assuming that
SOURCE has a 'meson.build' file."
  (define cross-file
    (make-cross-file target))
  (define inputs
    (if (null? target-inputs)
        (input-tuples->gexp host-inputs)
        #~(append #$(input-tuples->gexp host-inputs)
              #+(input-tuples->gexp target-inputs))))
  (define builder
    (with-imported-modules imported-modules
      #~(begin
          (use-modules #$@(sexp->gexp modules))

          (define %build-host-inputs
            #+(input-tuples->gexp build-inputs))

          (define %build-target-inputs
            (append #$(input-tuples->gexp host-inputs)
                    #+(input-tuples->gexp target-inputs)))

          (define %build-inputs
            (append %build-host-inputs %build-target-inputs))

          (define %outputs
            #$(outputs->gexp outputs))

          (define build-phases
            #$(let ((phases (if (pair? phases) (sexp->gexp phases) phases)))
                (if glib-or-gtk?
                    phases
                    #~(modify-phases #$phases
                        (delete 'glib-or-gtk-compile-schemas)
                        (delete 'glib-or-gtk-wrap)))))

          ;; Do not use 'with-build-variables', as there should be
          ;; no reason to use %build-inputs and friends.
          (meson-build #:source #+source
                       #:system #$system
                       #:build #$(nix-system->gnu-triplet system)
                       #:target #$target
                       #:outputs #$(outputs->gexp outputs)
                       #:inputs #$inputs
                       #:native-inputs #+(input-tuples->gexp build-inputs)
                       #:search-paths '#$(sexp->gexp
                                          (map search-path-specification->sexp
                                               search-paths))
                       #:native-search-paths '#$(sexp->gexp
                                                 (map search-path-specification->sexp
                                                      native-search-paths))
                       #:phases build-phases
                       #:make-dynamic-linker-cache? #$make-dynamic-linker-cache?
                       #:configure-flags `("--cross-file" #+cross-file
                                           ,@#$(if (pair? configure-flags)
                                                   (sexp->gexp configure-flags)
                                                   configure-flags))
                       #:build-type #$build-type
                       #:tests? #$tests?
                       #:test-options #$(sexp->gexp test-options)
                       #:parallel-build? #$parallel-build?
                       #:parallel-tests? #$parallel-tests?
                       #:validate-runpath? #$validate-runpath?
                       #:patch-shebangs? #$patch-shebangs?
                       #:strip-binaries? #$strip-binaries?
                       #:strip-flags #$strip-flags
                       #:strip-directories #$strip-directories
                       #:elf-directories #$(sexp->gexp elf-directories)))))

  (mlet %store-monad ((guile (package->derivation (or guile (default-guile))
                                                  system #:graft? #f)))
    (gexp->derivation name builder
                      #:system system
                      #:target target
                      #:graft? #f
                      #:substitutable? substitutable?
                      #:allowed-references allowed-references
                      #:disallowed-references disallowed-references
                      #:guile-for-build guile)))

(define meson-build-system
  (build-system
    (name 'meson)
    (description "The standard Meson build system")
    (lower lower)))

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
  (build-system meson-build-system)
                 ;; (source (origin (inherit (package-source mesa-opencl))))
                 (arguments
                  (substitute-keyword-arguments (package-arguments mesa-opencl)
                                                ((#:configure-flags flags)
                                                 #~(cons "-Dgallium-rusticl=true" ;; "-Dllvm=enabled" "-Drust_std=2021"
                                                         (delete "-Dgallium-opencl=standalone" #$flags)))
        ((#:phases phases)
         #~(modify-phases #$phases
            (add-after 'install 'mesa-icd-absolute-path
              (lambda _
                ;; Use absolute path for OpenCL platform library.
                ;; Otherwise we would have to set LD_LIBRARY_PATH=LIBRARY_PATH
                ;; for ICD in our applications to find OpenCL platform.
                (use-modules (guix build utils)
                             (ice-9 textual-ports))
                (let* ((out #$output)
                       (rusticl-icd (string-append out "/etc/OpenCL/vendors/rusticl.icd"))
                       (old-path (call-with-input-file rusticl-icd get-string-all))
                       (new-path (string-append out "/lib/" (string-trim-both old-path))))
                  (if (file-exists? new-path)
                    (call-with-output-file rusticl-icd
                      (lambda (port) (format port "~a\n" new-path)))))))))))
                 (native-inputs
                  (modify-inputs (package-native-inputs mesa-opencl)
                                 (prepend
                                  clang-15
                                  clang-runtime-15
                                  rust
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
