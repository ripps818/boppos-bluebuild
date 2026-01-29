#!/usr/bin/env bash
set -ouex pipefail

# The configuration is passed as the first argument
CONFIG="${1:-}"

# Ensure CONFIG is set to avoid unbound variable errors
if [[ -z "${CONFIG}" ]]; then
    CONFIG="{}"
fi

# Global to track installed dependencies for cleanup
INSTALLED_DEPS=()

# --- Helper Functions ---

# Retrieves the kernel package name from CONFIG or defaults to "kernel"
get_kernel_package() {
    local kpkg
    kpkg=$(echo "$CONFIG" | jq -r '.kernel.package // empty')
    if [[ -z "$kpkg" ]]; then
        kpkg="kernel"
    fi
    echo "$kpkg"
}

# Determines the installed version of the specified kernel package
get_kernel_version() {
    local kpkg=$1
    rpm -qa "$kpkg" --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}\n' | sort -V | tail -n 1
}

# Sets up repositories defined in the configuration
setup_repos() {
    echo "--- Setting up Repositories ---"
    
    # Handle COPR repositories
    if echo "$CONFIG" | jq -e '.repos.copr' >/dev/null; then
        local coprs
        mapfile -t coprs < <(echo "$CONFIG" | jq -r '.repos.copr[]')
        for copr in "${coprs[@]}"; do
            echo "Enabling COPR: $copr"
            dnf5 -y copr enable "$copr"
        done
    fi

    # Handle repo files
    if echo "$CONFIG" | jq -e '.repos.files' >/dev/null; then
        local files
        mapfile -t files < <(echo "$CONFIG" | jq -r '.repos.files[]')
        for file in "${files[@]}"; do
            if [[ "$file" =~ ^https?:// ]]; then
                echo "Downloading repo: $file"
                local filename
                filename=$(basename "$file")
                curl -fsSL "$file" -o "/etc/yum.repos.d/$filename"
            elif [[ "$file" == /* ]]; then
                if [[ -f "$file" ]]; then
                    echo "Installing repo file: $file"
                    cp "$file" "/etc/yum.repos.d/"
                else
                    echo "WARNING: Repo file '$file' not found"
                fi
            else
                # Look in /tmp/files/build-kmods/
                local src_file="/tmp/files/build-kmods/$file"
                
                if [[ -f "$src_file" ]]; then
                    echo "Installing repo file: $file"
                    cp "$src_file" "/etc/yum.repos.d/"
                else
                    echo "WARNING: Repo file '$file' not found in /tmp/files/build-kmods/"
                fi
            fi
        done
    fi
    
    # Handle RPMFusion shortcut
    if echo "$CONFIG" | jq -e '.repos.nonfree' >/dev/null; then
        local nonfree
        nonfree=$(echo "$CONFIG" | jq -r '.repos.nonfree')
        if [[ "$nonfree" == "rpmfusion" ]]; then
             echo "Installing RPMFusion..."
             local fedora_ver
             fedora_ver=$(rpm -E %fedora)
             dnf5 install -y "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${fedora_ver}.noarch.rpm" \
                             "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${fedora_ver}.noarch.rpm"
        fi
    fi
}

# Installs necessary build dependencies and kernel headers
install_deps() {
    echo "--- Installing Build Dependencies ---"
    local kpkg=$1
    local kver=$2
    
    # Check for source directories (list or string)
    local kernel_src_list=()
    if echo "$CONFIG" | jq -e '.kernel.devel.src' >/dev/null; then
        mapfile -t kernel_src_list < <(echo "$CONFIG" | jq -r '.kernel.devel.src[]')
    elif echo "$CONFIG" | jq -e '.kernel.src' >/dev/null; then
        local src_val
        src_val=$(echo "$CONFIG" | jq -r '.kernel.src')
        if [[ -n "$src_val" ]]; then
             kernel_src_list+=("$src_val")
        fi
    fi

    local required_deps=("git" "make" "gcc" "gcc-c++" "rpm-build" "dnf-plugins-core" "elfutils-libelf-devel" "kmodtool" "kernel-rpm-macros")

    # Only install devel packages if no source directory is specified
    if [[ ${#kernel_src_list[@]} -eq 0 ]]; then
        local devel_pkgs=()
        
        # Try new list format
        if echo "$CONFIG" | jq -e '.kernel.devel.package' >/dev/null; then
            mapfile -t devel_pkgs < <(echo "$CONFIG" | jq -r '.kernel.devel.package[]')
        # Try old string format
        elif echo "$CONFIG" | jq -e '.kernel.devel' >/dev/null; then
             local d
             d=$(echo "$CONFIG" | jq -r '.kernel.devel')
             if [[ -n "$d" ]]; then devel_pkgs+=("$d"); fi
        fi

        # Default if empty
        if [[ ${#devel_pkgs[@]} -eq 0 ]]; then
            devel_pkgs+=("${kpkg}-devel")
        fi

        # Append version and add to build_deps
        for pkg in "${devel_pkgs[@]}"; do
            required_deps+=("${pkg}-${kver}")
        done
    fi

    if echo "$CONFIG" | jq -e '.build_deps' >/dev/null; then
        local extra_deps
        mapfile -t extra_deps < <(echo "$CONFIG" | jq -r '.build_deps[]?')
        required_deps+=("${extra_deps[@]}")
    fi

    # Filter: Only install/track packages that are NOT currently installed
    local pkgs_to_install=()
    for pkg in "${required_deps[@]}"; do
        if ! rpm -q "$pkg" &>/dev/null; then
            pkgs_to_install+=("$pkg")
        else
            echo "Package '$pkg' is already installed. Skipping removal later."
        fi
    done

    # Install deps
    if [[ ${#pkgs_to_install[@]} -gt 0 ]]; then
        dnf5 install -y --allowerasing "${pkgs_to_install[@]}"
        INSTALLED_DEPS+=("${pkgs_to_install[@]}")
    fi
}

# Downloads userspace RPMs specified in module configurations
download_userspace_pkgs() {
    local download_dir=$1
    local pkgs=()
    
    mapfile -t pkgs < <(echo "$CONFIG" | jq -r '.modules[]?.extras[]? // empty')
    
    if [[ ${#pkgs[@]} -gt 0 ]]; then
        echo "--- Downloading Userspace Packages: ${pkgs[*]} ---"
        dnf5 download -y --destdir="$download_dir" --resolve \
            --arch x86_64 --arch noarch \
            "${pkgs[@]}"
    fi
}

# Builds a single kernel module from source (akmod or git) and installs it
build_kmod() {
    local module_json=$1
    local kver=$2
    local kdir=$3
    local install_mod_dir="/usr/lib/modules/${kver}/extra"
    
    local source_type
    source_type=$(echo "$module_json" | jq -r '.source.type // empty')

    # Auto-detect source type if missing
    if [[ -z "$source_type" || "$source_type" == "null" ]]; then
        if echo "$module_json" | jq -e '.source.package' >/dev/null; then
            source_type="kmod"
        elif echo "$module_json" | jq -e '.source.url' >/dev/null; then
            source_type="git"
        fi
    fi

    local name
    name=$(echo "$module_json" | jq -r '.name // empty')
    if [[ -z "$name" ]]; then
        if [[ "$source_type" =~ ^(akmod|dkms|kmod)$ ]]; then
            name=$(echo "$module_json" | jq -r '.source.package')
        elif [[ "$source_type" == "git" ]]; then
            name=$(basename "$(echo "$module_json" | jq -r '.source.url')" .git)
        fi
    fi

    local builddir
    builddir=$(echo "$module_json" | jq -r '.builddir // ""')

    local script
    script=$(echo "$module_json" | jq -r '.script // empty')

    local cmds
    mapfile -t cmds < <(echo "$module_json" | jq -r '.cmd[]? // empty')
    echo "--- Building Module: ${name} (${source_type}) ---"

    # Create temp build env for this module
    local tmp_workdir
    tmp_workdir=$(mktemp -d)
    local rpmbuild_dir="${tmp_workdir}/rpmbuild"
    mkdir -p "${rpmbuild_dir}"/{SPECS,SOURCES,BUILD,RPMS,SRPMS}

    local build_pwd=""

    if [[ "$source_type" =~ ^(akmod|dkms|kmod)$ ]]; then
        local pkg
        pkg=$(echo "$module_json" | jq -r '.source.package')
        
        echo "Fetching source RPM for ${pkg}..."
        # Download source RPM
        dnf5 download -y --source --enablerepo="*-source" --nogpgcheck --destdir="${tmp_workdir}" "$pkg"
        
        local src_rpm
        src_rpm=$(find "${tmp_workdir}" -maxdepth 1 -name "*.src.rpm" | head -n 1)
        if [[ -z "$src_rpm" ]]; then
            echo "ERROR: Source RPM for ${pkg} not found."
            return 1
        fi

        # Install build dependencies from source RPM
        echo "Installing build dependencies for ${pkg}..."
        dnf5 builddep -y --nogpgcheck "$src_rpm"

        # Install source RPM
        rpm -ivh --define "_topdir ${rpmbuild_dir}" "$src_rpm"

        # Prepare sources (unpack)
        local spec_file
        spec_file=$(find "${rpmbuild_dir}/SPECS" -name "*.spec" | head -n 1)
        rpmbuild -bp --define "_topdir ${rpmbuild_dir}" "${spec_file}" --nodeps

        # Locate source dir
        cd "${rpmbuild_dir}/BUILD" || exit
        # Handle wrapper dirs
        local wrapper_dir
        wrapper_dir=$(find . -maxdepth 1 -mindepth 1 -type d | grep -v "SPECPARTS" | head -n 1)
        if [[ -n "$wrapper_dir" ]]; then cd "$wrapper_dir" || exit; fi
        
        # Some akmods have another layer
        local src_dir
        src_dir=$(find . -maxdepth 1 -mindepth 1 -type d | grep -v "SPECPARTS" | head -n 1)
        if [[ -n "${src_dir}" ]]; then cd "${src_dir}" || exit; fi

        if [[ -n "${builddir}" ]]; then cd "${builddir}" || exit; fi
        build_pwd="$PWD"

    elif [[ "$source_type" == "git" ]]; then
        local url
        url=$(echo "$module_json" | jq -r '.source.url')
        local ref
        ref=$(echo "$module_json" | jq -r '.source.ref // ""')

        echo "Cloning ${url}..."
        cd "${tmp_workdir}" || exit
        git clone --depth 1 "${url}" src
        cd src || exit
        
        if [[ -n "$ref" ]]; then
            git fetch --depth 1 origin "$ref" && git checkout FETCH_HEAD
        fi

        if [[ -n "${builddir}" ]]; then cd "${builddir}" || exit; fi
        build_pwd="$PWD"
    fi

    # Compile
    if [[ -z "$build_pwd" ]]; then
        echo "ERROR: Build directory not determined. Check source configuration."
        return 1
    fi

    # Export variables for custom commands
    export KERNEL_VERSION="${kver}"
    export KERNEL_DIR="${kdir}"
    export INSTALL_MOD_DIR="${install_mod_dir}"

    if [[ -n "$script" ]]; then
        local script_path="/tmp/files/build-kmods/${script}"

        if [[ ! -f "$script_path" ]]; then
            echo "ERROR: Build script '$script' not found at '$script_path'"
            return 1
        fi
        echo "Running build script: ${script}"
        cd "${build_pwd}" || exit
        chmod +x "$script_path"
        "$script_path"
    elif [[ ${#cmds[@]} -gt 0 ]]; then
        echo "Running custom commands..."
        cd "${build_pwd}" || exit
        for cmd in "${cmds[@]}"; do
            echo "Executing: ${cmd}"
            eval "${cmd}"
        done
    else
        echo "Compiling in ${build_pwd}..."
        make -C "${kdir}" M="${build_pwd}" modules

        # Default Install & Strip
        mkdir -p "${install_mod_dir}"
        find "${build_pwd}" -type f -name "*.ko" -exec strip --strip-debug {} \;
        find "${build_pwd}" -type f -name "*.ko" -exec install -Dm644 {} "${install_mod_dir}/" \;
    fi

    # Cleanup this module build
    rm -rf "$tmp_workdir"
}

# Installs the downloaded userspace RPMs
install_userspace_pkgs() {
    local download_dir=$1
    echo "--- Installing Userspace Packages ---"
    
    # Find all RPMs in download dir (excluding src.rpm)
    # Filter out akmod packages and build tools pulled by --resolve
    local rpms
    rpms=$(find "$download_dir" -name "*.rpm" ! -name "*.src.rpm" | grep -vE "/(akmod-|akmods-|kmodtool-|fakeroot-|rpmdevtools-|grubby-|systemd-rpm-macros-)")
    
    if [[ -n "$rpms" ]]; then
        # shellcheck disable=SC2086
        rpm -Uvh --force --nodeps $rpms
    else
        echo "No userspace packages to install (after filtering)."
    fi
}

# Removes temporary directories and build dependencies
cleanup() {
    echo "--- Cleaning Up ---"
    local download_dir=$1
    rm -rf "$download_dir" /usr/src/akmods

    # Cleanup extra packages defined in config
    if echo "$CONFIG" | jq -e '.cleanup.packages' >/dev/null; then
        local pkgs
        mapfile -t pkgs < <(echo "$CONFIG" | jq -r '.cleanup.packages[]')
        if [[ ${#pkgs[@]} -gt 0 ]]; then
            echo "Removing cleanup packages: ${pkgs[*]}"
            dnf5 remove -y "${pkgs[@]}" || true
        fi
    fi

    # Cleanup extra files defined in config
    if echo "$CONFIG" | jq -e '.cleanup.files' >/dev/null; then
        echo "$CONFIG" | jq -r '.cleanup.files[]' | while read -r file; do
            echo "Removing file: $file"
            rm -f $file
        done
    fi

    if [[ ${#INSTALLED_DEPS[@]} -gt 0 ]]; then
        echo "Removing build dependencies: ${INSTALLED_DEPS[*]}"
        dnf5 remove -y "${INSTALLED_DEPS[@]}"
    fi
}

# --- Main Execution ---

# Orchestrates the entire build process
main() {
    local kernel_pkg
    kernel_pkg=$(get_kernel_package)
    local kernel_version
    kernel_version=$(get_kernel_version "$kernel_pkg")

    if [[ -z "$kernel_version" ]]; then
        echo "ERROR: Unable to determine version for kernel package: $kernel_pkg"
        exit 1
    fi
    echo "Detected Kernel: ${kernel_pkg} (${kernel_version})"

    setup_repos

    install_deps "$kernel_pkg" "$kernel_version"
    
    echo "--- Debugging Repositories for Source Download ---"
    dnf5 repolist --enabled
    dnf5 repolist --all | grep "source" || echo "No source repos found in repolist"

    local download_dir
    download_dir=$(mktemp -d)

    download_userspace_pkgs "$download_dir"

    # Determine Kernel Directory (Source or Headers)
    local kernel_dir=""
    local kernel_src_list=()
    
    # Check for source directories (list or string)
    if echo "$CONFIG" | jq -e '.kernel.devel.src' >/dev/null; then
        mapfile -t kernel_src_list < <(echo "$CONFIG" | jq -r '.kernel.devel.src[]')
    elif echo "$CONFIG" | jq -e '.kernel.src' >/dev/null; then
        local src_val
        src_val=$(echo "$CONFIG" | jq -r '.kernel.src')
        if [[ -n "$src_val" ]]; then
             kernel_src_list+=("$src_val")
        fi
    fi

    # Find first existing directory
    for dir in "${kernel_src_list[@]}"; do
        if [[ -d "$dir" ]]; then
            kernel_dir="$dir"
            break
        fi
    done

    if [[ -z "$kernel_dir" ]]; then
        kernel_dir="/usr/src/kernels/${kernel_version}"
    fi

    # Iterate and build
    echo "$CONFIG" | jq -c '.modules[]?' | while read -r module_json; do
        build_kmod "$module_json" "$kernel_version" "$kernel_dir"
    done

    install_userspace_pkgs "$download_dir"
    
    local perform_cleanup="true"
    if echo "$CONFIG" | jq -e '.repo.cleanup' >/dev/null; then
        perform_cleanup=$(echo "$CONFIG" | jq -r '.repo.cleanup')
    fi

    if [[ "$perform_cleanup" == "true" ]]; then
        cleanup "$download_dir"
    else
        echo "--- Skipping Dependency Cleanup ---"
        rm -rf "$download_dir"
    fi

    echo "--- Running depmod ---"
    depmod -a -b / "${kernel_version}"
    echo "--- Module Build Complete ---"
}

main
