# Package format spike

Build the zlib recipe with the current `vita-makepkg`, then validate the
archive locally:

```sh
tests/validate-zlib-package.sh ../packages/zlib/zlib-1.3.2-2-vita.pkg.tar.xz
```

Pass `--pacman` to create a repository with `repo-add` and exercise install,
query and removal with pacman 7.1 in an isolated Docker root:

```sh
tests/validate-zlib-package.sh \
  ../packages/zlib/zlib-1.3.2-2-vita.pkg.tar.xz --pacman
```

The container test uses `SigLevel = Never` only for its local, ephemeral
repository. Published VitaSDK repositories will be accepted only after the
signed channel manifest and database hash have been verified.

Build four synthetic Vita packages and exercise repository upgrade, file
conflict rejection and shared-directory ownership with:

```sh
tests/test-transactions.sh
```

Both container tests pin the same pacman 7.1 image by digest.
