## How BoppOS differs from Bazzite

While this image is based on Bazzite-dx, it uses the **CachyOS kernel** and a specific set of kernel arguments to prioritize gaming latency and hardware control for AMD users:

* **Kernel Preemption:** Set to `full`. This makes the system more responsive during heavy CPU load, prioritizing game frames over background tasks.
* **Memory Management:** Uses `transparent_hugepage=madvise`. This gives a performance boost to games and apps that support huge pages without the high RAM overhead of the `always` setting.
* **AMD Optimizations:** Includes `iommu=pt` for better DMA performance and `amdgpu.ppfeaturemask=0xffffffff` so you can undervolt or overclock your GPU using tools like LACT.
* **Compatibility:** Disables `split_lock_detect` to prevent performance drops in older game engines that can trigger kernel-level slowdowns.
* **Extra Drivers:** Includes `xone` and `xpad-noone` for Xbox controller support, and the `KVMFR` module for Looking Glass users.

### Secure Boot

Since this uses the CachyOS kernel, I’ve included a custom signing system so that **Secure Boot** remains functional even with these custom modules. The kernel and modules are signed with a private key; you can enroll the keys using:

```bash
ujust enroll-secure-boot-keys
```

### Optional Virtualization Extras

I've included some optional configurations in `/usr/share/boppos/unused_files` for users who need advanced virtualization features like **Looking Glass (KVMFR)** or **Nested Virtualization**. These are disabled by default to keep the core image lean and avoid issues with some anti-cheat systems.

### Activating Extras
To enable these features, you can use the built-in `ujust` command:

```bash
ujust setup-kvm-extras
```

### Performance Toggling
BoppOS defaults to `preempt=full` for the lowest gaming latency. If you need a different balance, you can switch modes instantly without a reboot:

```bash
ujust toggle-preempt
```

## Installation

> [!WARNING]  
> [This is an experimental feature](https://www.fedoraproject.org/wiki/Changes/OstreeNativeContainerStable), try at your own discretion.

To rebase an existing atomic Fedora installation to the latest build:

- First rebase to the unsigned image, to get the proper signing keys and policies installed:
  ```
  rpm-ostree rebase ostree-unverified-registry:ghcr.io/ripps818/boppos-bluebuild:latest
  ```
- Reboot to complete the rebase:
  ```
  systemctl reboot
  ```
- Then rebase to the signed image, like so:
  ```
  rpm-ostree rebase ostree-image-signed:docker://ghcr.io/ripps818/boppos-bluebuild:latest
  ```
- Reboot again to complete the installation
  ```
  systemctl reboot
  ```

The `latest` tag will automatically point to the latest build. That build will still always use the Fedora version specified in `recipe.yml`, so you won't get accidentally updated to the next major version.

## Verification

These images are signed with [Sigstore](https://www.sigstore.dev/)'s [cosign](https://github.com/sigstore/cosign). You can verify the signature by downloading the `cosign.pub` file from this repo and running the following command:

```bash
cosign verify --key cosign.pub ghcr.io/ripps818/boppos-bluebuild
```
