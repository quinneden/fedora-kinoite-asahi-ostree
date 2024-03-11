# This is a justfile. See https://github.com/casey/just
# This is only used for local development. The builds made on the Fedora
# infrastructure are run via Pungi in a Koji runroot.

# Set a default for some recipes
default_variant := "kinoite"
# Current default in Pungi
force_nocache := "true"

# Default is to only validate the manifests
all: validate

# Basic validation to make sure the manifests are not completely broken
validate:
    ./ci/validate

# Comps-sync, but without pulling latest
sync:
    #!/bin/bash
    set -euxo pipefail

    if [[ ! -d fedora-comps ]]; then
        git clone https://pagure.io/fedora-comps.git
    fi

    default_variant={{default_variant}}
    version="$(rpm-ostree compose tree --print-only --repo=repo fedora-${default_variant}.yaml | jq -r '."mutate-os-release"')"
    ./comps-sync.py --save fedora-comps/comps-f${version}.xml.in

# Sync the manifests with the content of the comps groups
comps-sync:
    #!/bin/bash
    set -euxo pipefail

    if [[ ! -d fedora-comps ]]; then
        git clone https://pagure.io/fedora-comps.git
    else
        pushd fedora-comps > /dev/null || exit 1
        git fetch
        git reset --hard origin/main
        popd > /dev/null || exit 1
    fi

    default_variant={{default_variant}}
    version="$(rpm-ostree compose tree --print-only --repo=repo fedora-${default_variant}.yaml | jq -r '."mutate-os-release"')"
    ./comps-sync.py --save fedora-comps/comps-f${version}.xml.in

# Output the processed manifest for a given variant (defaults to Silverblue)
manifest variant=default_variant:
    #!/bin/bash
    set -euxo pipefail

    variant={{variant}}
    case "${variant}" in
        "silverblue")
            variant_pretty="Silverblue"
            ;;
        "kinoite"|"kinoite-nightly"|"kinoite-beta")
            variant_pretty="Kinoite"
            ;;
        "sericea")
            variant_pretty="Sericea"
            ;;
        "onyx")
            variant_pretty="Onyx"
            ;;
        "vauxite")
            variant_pretty="Vauxite"
            ;;
        "lazurite")
            variant_pretty="Lazurite"
            ;;
        "base")
            variant_pretty="Base"
            ;;
        "*")
            echo "Unknown variant"
            exit 1
            ;;
    esac

    rpm-ostree compose tree --print-only --repo=repo fedora-{{variant}}.yaml

# Alias/shortcut for compose-image command
compose variant=default_variant: (compose-image variant)

# Compose a variant using the legacy non container path (defaults to Silverblue)
compose-legacy variant=default_variant:
    #!/bin/bash
    set -euxo pipefail

    variant={{variant}}
    case "${variant}" in
        "silverblue")
            variant_pretty="Silverblue"
            ;;
        "kinoite"|"kinoite-nightly"|"kinoite-beta")
            variant_pretty="Kinoite"
            ;;
        "sericea")
            variant_pretty="Sericea"
            ;;
        "onyx")
            variant_pretty="Onyx"
            ;;
        "vauxite")
            variant_pretty="Vauxite"
            ;;
        "lazurite")
            variant_pretty="Lazurite"
            ;;
        "base")
            variant_pretty="Base"
            ;;
        "*")
            echo "Unknown variant"
            exit 1
            ;;
    esac

    #./ci/validate > /dev/null || (echo "Failed manifest validation" && exit 1)

    mkdir -p repo cache logs
    if [[ ! -f "repo/config" ]]; then
        pushd repo > /dev/null || exit 1
        ostree init --repo . --mode=bare-user
        popd > /dev/null || exit 1
    fi
    # Set option to reduce fsync for transient builds
    ostree --repo=repo config set 'core.fsync' 'false'

    buildid="$(date '+%Y%m%d.0')"
    timestamp="$(date --iso-8601=sec)"
    echo "${buildid}" > .buildid

    version="$(rpm-ostree compose tree --print-only --repo=repo fedora-${variant}.yaml | jq -r '."mutate-os-release"')"
    echo "Composing ${variant_pretty} ${version}.${buildid} ..."

    ARGS="--repo=repo --cachedir=cache"
    ARGS+=" --unified-core"
    if [[ {{force_nocache}} == "true" ]]; then
        ARGS+=" --force-nocache"
    fi
    CMD="rpm-ostree"
    if [[ ${EUID} -ne 0 ]]; then
        CMD="sudo rpm-ostree"
    fi

    ${CMD} compose tree ${ARGS} \
        --add-metadata-string="version=${variant_pretty} ${version}.${buildid}" \
        "fedora-${variant}.yaml" \
            |& tee "logs/${variant}_${version}_${buildid}.${timestamp}.log"

    if [[ ${EUID} -ne 0 ]]; then
        sudo chown --recursive "$(id --user --name):$(id --group --name)" repo cache
    fi

    ostree summary --repo=repo --update

# Compose an Ostree Native Container OCI image
compose-image variant=default_variant:
    #!/bin/bash
    set -euxo pipefail

    variant={{variant}}
    case "${variant}" in
        "silverblue")
            variant_pretty="Silverblue"
            ;;
        "kinoite"|"kinoite-nightly"|"kinoite-beta")
            variant_pretty="Kinoite"
            ;;
        "sericea")
            variant_pretty="Sericea"
            ;;
        "onyx")
            variant_pretty="Onyx"
            ;;
        "vauxite")
            variant_pretty="Vauxite"
            ;;
        "lazurite")
            variant_pretty="Lazurite"
            ;;
        "base")
            variant_pretty="Base"
            ;;
        "*")
            echo "Unknown variant"
            exit 1
            ;;
    esac

    #./ci/validate > /dev/null || (echo "Failed manifest validation" && exit 1)

    mkdir -p repo cache
    if [[ ! -f "repo/config" ]]; then
        pushd repo > /dev/null || exit 1
        ostree init --repo . --mode=bare-user
        popd > /dev/null || exit 1
    fi
    # Set option to reduce fsync for transient builds
    ostree --repo=repo config set 'core.fsync' 'false'

    buildid="$(date '+%Y%m%d.0')"
    timestamp="$(date --iso-8601=sec)"
    echo "${buildid}" > .buildid

    version="$(rpm-ostree compose tree --print-only --repo=repo fedora-${variant}.yaml | jq -r '."mutate-os-release"')"
    echo "Composing ${variant_pretty} ${version}.${buildid} ..."

    ARGS="--cachedir=cache --initialize"
    if [[ {{force_nocache}} == "true" ]]; then
        ARGS+=" --force-nocache"
    fi
    # To debug with gdb, use: gdb --args ...
    CMD="rpm-ostree"
    if [[ ${EUID} -ne 0 ]]; then
        CMD="sudo rpm-ostree"
    fi

    ${CMD} compose image ${ARGS} \
         --label="quay.expires-after=4w" \
        "fedora-${variant}.yaml" \
        "fedora-${variant}.ociarchive"

# Clean up everything
clean-all:
    just clean-repo
    just clean-cache

# Only clean the ostree repo
clean-repo:
    rm -rf ./repo

# Only clean the package and repo caches
clean-cache:
    rm -rf ./cache

# Run from inside a container
podman:
    podman run --rm -ti --volume $PWD:/srv:rw --workdir /srv --privileged quay.io/fedora-ostree-desktops/buildroot

# Update the container image
podman-pull:
    podman pull quay.io/fedora-ostree-desktops/buildroot

# Build an ISO
lorax variant=default_variant:
    #!/bin/bash
    set -euxo pipefail

    rm -rf iso
    # Do not create the iso directory or lorax will fail
    mkdir -p tmp cache/lorax

    variant={{variant}}
    case "${variant}" in
        "silverblue")
            variant_pretty="Silverblue"
            volid_sub="SB"
            ;;
        "kinoite"|"kinoite-nightly"|"kinoite-beta")
            variant_pretty="Kinoite"
            volid_sub="Knt"
            ;;
        "sericea")
            variant_pretty="Sericea"
            volid_sub="Src"
            ;;
        "onyx")
            variant_pretty="Onyx"
            volid_sub="Onyx"
            ;;
        "vauxite")
            variant_pretty="Vauxite"
            volid_sub="Vxt"
            ;;
        "lazurite")
            variant_pretty="Lazurite"
            volid_sub="Lzr"
            ;;
        "base")
            variant_pretty="Base"
            volid_sub="Base"
            ;;
        "*")
            echo "Unknown variant"
            exit 1
            ;;
    esac

    if [[ ! -d fedora-lorax-templates ]]; then
        git clone https://pagure.io/fedora-lorax-templates.git
    else
        pushd fedora-lorax-templates > /dev/null || exit 1
        git fetch
        git reset --hard origin/main
        popd > /dev/null || exit 1
    fi

    version_number="$(rpm-ostree compose tree --print-only --repo=repo fedora-${variant}.yaml | jq -r '."mutate-os-release"')"
    if [[ "$(git rev-parse --abbrev-ref HEAD)" == "main" ]] || [[ -f "fedora-rawhide.repo" ]]; then
        version_pretty="Rawhide"
        version="rawhide"
    else
        version_pretty="${version_number}"
        version="${version_number}"
    fi
    source_url="https://kojipkgs.fedoraproject.org/compose/${version}/latest-Fedora-${version_pretty}/compose/Everything/x86_64/os/"
    volid="Fedora-${volid_sub}-x86_64-${version_pretty}"

    buildid=""
    if [[ -f ".buildid" ]]; then
        buildid="$(< .buildid)"
    else
        buildid="$(date '+%Y%m%d.0')"
        echo "${buildid}" > .buildid
    fi

    # Stick to the latest stable runtime available here
    # Only include a subset of Flatpaks here
    # Exhaustive list in https://pagure.io/pungi-fedora/blob/main/f/fedora.conf
    # flatpak_remote_refs="runtime/org.fedoraproject.Platform/x86_64/f39"
    # flatpak_apps=(
    #     "app/org.gnome.Calculator/x86_64/stable"
    #     "app/org.gnome.Calendar/x86_64/stable"
    #     "app/org.gnome.Extensions/x86_64/stable"
    #     "app/org.gnome.TextEditor/x86_64/stable"
    #     "app/org.gnome.clocks/x86_64/stable"
    #     "app/org.gnome.eog/x86_64/stable"
    # )
    # for ref in ${flatpak_refs[@]}; do
    #     flatpak_remote_refs+=" ${ref}"
    # done
    # FLATPAK_ARGS=""
    # FLATPAK_ARGS+=" --add-template=${pwd}/fedora-lorax-templates/ostree-based-installer/lorax-embed-flatpaks.tmpl"
    # FLATPAK_ARGS+=" --add-template-var=flatpak_remote_name=fedora"
    # FLATPAK_ARGS+=" --add-template-var=flatpak_remote_url=oci+https://registry.fedoraproject.org"
    # FLATPAK_ARGS+=" --add-template-var=flatpak_remote_refs=${flatpak_remote_refs}"

    pwd="$(pwd)"

    lorax \
        --product=Fedora \
        --version=${version_pretty} \
        --release=${buildid} \
        --source="${source_url}" \
        --variant="${variant_pretty}" \
        --nomacboot \
        --isfinal \
        --buildarch=x86_64 \
        --volid="${volid}" \
        --logfile=${pwd}/logs/lorax.log \
        --tmp=${pwd}/tmp \
        --cachedir=cache/lorax \
        --rootfs-size=8 \
        --add-template=${pwd}/fedora-lorax-templates/ostree-based-installer/lorax-configure-repo.tmpl \
        --add-template=${pwd}/fedora-lorax-templates/ostree-based-installer/lorax-embed-repo.tmpl \
        --add-template-var=ostree_install_repo=file://${pwd}/repo \
        --add-template-var=ostree_update_repo=file://${pwd}/repo \
        --add-template-var=ostree_osname=fedora \
        --add-template-var=ostree_oskey=fedora-${version_number}-primary \
        --add-template-var=ostree_contenturl=mirrorlist=https://ostree.fedoraproject.org/mirrorlist \
        --add-template-var=ostree_install_ref=fedora/${version}/x86_64/${variant} \
        --add-template-var=ostree_update_ref=fedora/${version}/x86_64/${variant} \
        ${pwd}/iso/linux

# Upload the containers to a registry (Quay.io)
upload-container variant=default_variant:
    #!/bin/bash
    set -euxo pipefail

    variant={{variant}}
    case "${variant}" in
        "silverblue")
            variant_pretty="Silverblue"
            ;;
        "kinoite"|"kinoite-nightly"|"kinoite-beta")
            variant_pretty="Kinoite"
            ;;
        "sericea")
            variant_pretty="Sericea"
            ;;
        "onyx")
            variant_pretty="Onyx"
            ;;
        "vauxite")
            variant_pretty="Vauxite"
            ;;
        "lazurite")
            variant_pretty="Lazurite"
            ;;
        "base")
            variant_pretty="Base"
            ;;
        "*")
            echo "Unknown variant"
            exit 1
            ;;
    esac

    if [[ -z ${CI_REGISTRY_USER+x} ]] || [[ -z ${CI_REGISTRY_PASSWORD+x} ]]; then
        echo "Skipping artifact archiving: Not in CI"
        exit 0
    fi
    if [[ "${CI}" != "true" ]]; then
        echo "Skipping artifact archiving: Not in CI"
        exit 0
    fi

    version=""
    if [[ "$(git rev-parse --abbrev-ref HEAD)" == "main" ]] || [[ -f "fedora-rawhide.repo" ]]; then
        version="rawhide"
    else
        version="$(rpm-ostree compose tree --print-only --repo=repo fedora-${variant}.yaml | jq -r '."mutate-os-release"')"
    fi

    image="quay.io/fedora-ostree-desktops/${variant}"
    buildid=""
    if [[ -f ".buildid" ]]; then
        buildid="$(< .buildid)"
    else
        buildid="$(date '+%Y%m%d.0')"
        echo "${buildid}" > .buildid
    fi

    git_commit=""
    if [[ -n "${CI_COMMIT_SHORT_SHA}" ]]; then
        git_commit="${CI_COMMIT_SHORT_SHA}"
    else
        git_commit="$(git rev-parse --short HEAD)"
    fi

    skopeo login --username "${CI_REGISTRY_USER}" --password "${CI_REGISTRY_PASSWORD}" quay.io
    # Copy fully versioned tag (major version, build date/id, git commit)
    skopeo copy --retry-times 3 "oci-archive:fedora-${variant}.ociarchive" "docker://${image}:${version}.${buildid}.${git_commit}"
    # Update "un-versioned" tag (only major version)
    skopeo copy --retry-times 3 "docker://${image}:${version}.${buildid}.${git_commit}" "docker://${image}:${version}"
    if [[ "${variant}" == "kinoite-nightly" ]]; then
        # Update latest tag for kinoite-nightly only
        skopeo copy --retry-times 3 "docker://${image}:${version}.${buildid}.${git_commit}" "docker://${image}:latest"
    fi
