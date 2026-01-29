# Build Kmods Module

This module builds kernel modules from source (akmod SRPMs, Git repositories, or custom commands) for the currently installed kernel. It is primarily intended for **Fedora-based OCI images** (e.g., Universal Blue, Bazzite) using `dnf5`, though it may be adapted for other distributions in the future.

## Configuration

The module is configured via the `recipe.yaml` using the following schema:

### Top-Level Options

| Option | Type | Description |
| :--- | :--- | :--- |
| `kernel` | Object | Configuration for the target kernel (see below). |
| `repos` | Object | Configuration for repositories needed for build deps (see below). |
| `build_deps` | List<String> | Additional build dependencies to install. |
| `cleanup` | Object | Packages and files to remove after building. |
| `modules` | List<Object> | List of modules to build. |

### Kernel Object (`kernel`)

| Field | Type | Description |
| :--- | :--- | :--- |
| `package` | String | The name of the installed kernel package (e.g., `kernel`, `kernel-cachyos`). |
| `devel` | String/Object | The name of the devel package, or an object containing `package` (list) or `src` (list of paths). |
| `src` | String | (Optional) Direct path to kernel sources if not using a devel package. |

### Repos Object (`repos`)

| Field | Type | Description |
| :--- | :--- | :--- |
| `copr` | List<String> | List of COPR repositories to enable. |
| `files` | List<String> | List of URLs or local paths to `.repo` files. Supports `%fedora` substitution. |
| `gpg_keys` | List<String> | List of GPG keys to import. |
| `nonfree` | String | Set to `"rpmfusion"` to quickly enable RPMFusion free/nonfree repos. |

### Cleanup Object (`cleanup`)

| Field | Type | Description |
| :--- | :--- | :--- |
| `packages` | List<String> | Packages to explicitly remove after the build process. |
| `files` | List<String> | Files to explicitly remove after the build process. |

### Module Object

| Field | Type | Description |
| :--- | :--- | :--- |
| `name` | String | (Optional) Name of the module (used for logging). Defaults to package name or git repo name. |
| `source` | Object | Source definition (see Source Object below). |
| `builddir` | String | (Optional) Subdirectory to build in. |
| `extras` | List<String> | (Optional) List of userspace RPMs to download and install alongside the module. |
| `script` | String | (Optional) Name of a custom script in `files/` to run for building. |
| `cmd` | List<String> | (Optional) List of custom shell commands to run for building. |

### Source Object

**Type: `akmod` / `kmod`**
| Field | Type | Description |
| :--- | :--- | :--- |
| `type` | String | `akmod` or `kmod`. |
| `package` | String | The name of the source RPM package (e.g., `akmod-xone`). |

**Type: `git`**
| Field | Type | Description |
| :--- | :--- | :--- |
| `type` | String | `git`. |
| `url` | String | Git repository URL. |
| `ref` | String | (Optional) Git ref (branch/tag/commit) to checkout. |

## Example Configuration

```yaml
  - type: build-kmods
    source: local
    kernel:
      package: "kernel-cachyos"
      devel: "kernel-cachyos-devel-matched"
    repos:
      files:
        - "https://github.com/terrapkg/subatomic-repos/raw/main/terra.repo"
      copr:
        - "hikariknight/looking-glass-kvmfr"
    build_deps:
      - "libsome-devel"
    modules:
      - name: "xone"
        source:
          type: "akmod"
          package: "akmod-xone"
        extras:
          - "xone"
          - "xone-firmware"
```