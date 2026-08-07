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

Exercise rootless dependency resolution and verify that two builds with the
same inputs and `SOURCE_DATE_EPOCH` are byte-identical:

```sh
tests/test-dependency-resolution.sh
```

This test uses a recording package-client fixture so it can assert the exact
root, database, cache and non-interactive arguments without a network
repository. `tests/test-transactions.sh` separately validates the generated
packages with pacman and `repo-add`.

Reject dependency arrays that accidentally put several package names in one
entry with:

```sh
tests/test-dependency-lint.sh
```

The container test uses `SigLevel = Never` only for its local, ephemeral
repository. Published VitaSDK repositories will be accepted only after the
signed channel manifest and database hash have been verified.

Build five synthetic Vita packages and exercise versioned dependency solving,
repository upgrade, database-hash rejection of a corrupted package, stale-lock
recovery, file-conflict rejection and shared-directory ownership with:

```sh
tests/test-transactions.sh
```

Both container tests pin the same pacman 7.1 image by digest.
