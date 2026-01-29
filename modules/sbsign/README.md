# Secure Boot Signing Module

This module signs the kernel image (`vmlinuz`) and all kernel modules (`.ko`) for Secure Boot compatibility. It is designed to run after kernel installation or module building steps.

It automatically detects installed kernels, signs the image using `sbsign`, and signs modules using the kernel's `sign-file` script. It also performs verification steps to ensure signatures are successfully applied.

## Configuration

The module is configured via `recipe.yaml`.

### Options

| Option | Type | Description | Required |
| :--- | :--- | :--- | :--- |
| `keys` | Object | Paths to signing keys (see below). | Yes |
| `kernel` | String/List | Specific kernel version(s) to sign. If omitted, auto-detects all kernels in `modules_dir`. | No |
| `modules_dir` | String | Path to the modules root directory. Defaults to `/lib/modules`. | No |

### Keys Object (`keys`)

| Field | Type | Description |
| :--- | :--- | :--- |
| `priv` | String | **Required**. Path to the private key (`.priv` or `.key`). |
| `pem` | String | Path to the public certificate in PEM format. |
| `der` | String | Path to the public certificate in DER format. |

> **Note:** At least one of `pem` or `der` must be provided.

## Behavior

1. **Dependency Check**: Automatically installs `sbsigntools`, `openssl`, and `jq` if missing.
2. **Kernel Signing**: Signs the `vmlinuz` binary found in the module directory.
3. **Module Signing**: Iterates through all `.ko` files in the kernel's module directory and signs them using the SHA256 algorithm.
4. **Verification**:
   - Verifies `vmlinuz` using `sbverify`.
   - Verifies modules by checking for the `~Module signature appended~` magic string.
5. **Cleanup**: Automatically removes the private key from the filesystem when the script exits to prevent it from leaking into the final image layer.

## Example Configuration

```yaml
  - type: sbsign
    source: local
    keys:
      priv: /usr/share/boppos/keys/boppos.priv
      pem: /usr/share/boppos/keys/boppos.pem
    # Optional:
    # kernel: "6.8.9-300.fc40.x86_64"
```