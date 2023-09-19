(use-modules (guix packages)
             (guix download)
             (guix build-system gnu)
             (guix licenses)
             (gnu packages gl)
             (gnu packages rust)
             (gnu packages crates-io)
             (gnu packages games)
             (gnu packages vulkan)
             (guix utils)
             (guix gexp))

(package/inherit mesa-opencl
  (name "mesa-opencl-rusticle")
  (source (origin (inherit (package-source mesa-opencl))))
  (arguments
   (substitute-keyword-arguments (package-arguments mesa-opencl)
     ((#:configure-flags flags)
      #~(cons "-Dgallium-opencl=standalone -Dgallium-rusticl=true -Dllvm=enabled -Drust_std=2021" #$flags))))
  (native-inputs
   (modify-inputs (package-native-inputs mesa-opencl)
     (prepend rust
              rust-bindgen-0.64
              rust-spirv-types-0.4
              rust-spirv-std-0.4
              rust-spirv-std-macros-0.4
              spirv-headers
              spirv-cross
              spirv-tools))))
