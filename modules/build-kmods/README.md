# Build Kmods Module

This module builds kernel modules from source (akmod SRPMs or Git repositories) for the currently installed kernel. It is designed to be portable and configurable for different kernel flavors (e.g., Fedora, CachyOS).

## Configuration

The module is configured via the `recipe.yaml` using the following schema:

### Options

| Option | Type | Description | Default |
| :--- | :--- | :--- | :--- |
| `kernel_package` | String | The name of the installed kernel package. | `kernel` |
| `devel_package` | String | The name of the kernel development package (without version). | `${kernel_package}-devel` |
| `copr_repos` | List<String> | List of COPR repositories to enable. | `[]` |
| `repos` | List<String> | List of URLs to `.repo` files to install. | `[]` |
| `build_deps` | List<String> | Additional packages to install for building. | `[]` |
| `modules` | List<Object> | List of modules to build. | `[]` |

### Module Object

| Field | Type | Description |
| :--- | :--- | :--- |
| `name` | String | (Optional) Name of the module (used for logging). Defaults to package name or git repo name. |
| `source` | Object | Source definition (see below). |
| `build_subdir` | String | (Optional) Subdirectory to build in. |
| `userspace_packages` | List<String> | (Optional) List of userspace RPMs to install. |

### Source Object

**Type: `akmod`**
| Field | Type | Description |
| :--- | :--- | :--- |
| `type` | String | Must be `akmod`. |
| `package` | String | The name of the akmod source RPM package. |

**Type: `git`**
| Field | Type | Description |
| :--- | :--- | :--- |
| `type` | String | Must be `git`. |
| `url` | String | Git repository URL. |
| `ref` | String | (Optional) Git ref (branch/tag/commit) to checkout. |

## Example Configuration

```yaml
modules:
  - type: local.build-kmods
    # Optional: Specify kernel package if auto-detection fails
    kernel_package: "kernel-cachyos"
    # Optional: Specify custom devel package name (e.g. for CachyOS)
    devel_package: "kernel-cachyos-devel-matched"
    repos:
      - "https://github.com/terrapkg/subatomic-repos/raw/main/terra.repo"
    copr_repos:
      - "hikariknight/looking-glass-kvmfr"
    build_deps:
      - "libsome-devel"
    modules:
      - name: "xone"
        source:
          type: "akmod"
          package: "akmod-xone"
        userspace_packages:
          - "xone"
          - "xone-firmware"
```