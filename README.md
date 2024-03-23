# Guix Rusticle

This is the [Rusticle](https://docs.mesa3d.org/rusticl.html#rusticl) [OpenCL](https://www.khronos.org/opencl/) [installable client driver](https://www.khronos.org/news/permalink/opencl-installable-client-driver-icd-loader) (ICD) for [Mesa](https://mesa3d.org) packaged for [Guix](https://guix.gnu.org). If you don't know what any of those things are, you're in the wrong place.

Pull this repo and install it using:

```
guix package --install-from-file=rusticle.scm
```

Once this works and is stable, I will submit it upstream to Guix.

## Notes

- Needs Meson 1.2.0
- Needs a rust-genbind-cli compiled against Clang 15

## Compiling manually

```
meson setup builddir/
meson configure ./builddir -Dgallium-rusticl=true -Dllvm=enabled -Drust_std=2021
meson compile -C ./builddir
meson devenv -C builddir clinfo -l
```
