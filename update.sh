#!/usr/bin/env bash
set -Eeuo pipefail
shopt -s nullglob

cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

declare branches=(
    "stable"
    "mainline"
)

declare -A nginx=(
    [mainline]='1.19.10'
    [stable]='1.20.0'
)

defaultnjs='0.5.3'
declare -A njs=(
#    [stable]='0.4.4'
)

defaultpkg='1'
declare -A pkg=(
#    [stable]=2
)

defaultubuntu='focal'
declare -A ubuntu=(
#   [stable]='bionic'
)

# When we bump njs version in a stable release we don't move the tag in the
# mercurial repo.  This setting allows us to specify a revision to check out
# when building alpine packages on architectures not supported by nginx.org
defaultrev='${NGINX_VERSION}-${PKG_RELEASE}-ubuntu'
declare -A rev=(
    #[stable]='-r 500'
)

get_packages() {
    local distro="$1"; shift;
    local branch="$1"; shift;
    local perl="nginx-module-perl"
    local r=
    local sep="+"

    case "$distro" in
        *-perl)
            perl="nginx-module-perl"
            ;;
    esac

    echo -n ' \\\n'
    for p in nginx nginx-module-xslt nginx-module-geoip nginx-module-image-filter $perl; do
        echo -n '        '"$p"'=${NGINX_VERSION}-'"$r"'${PKG_RELEASE} \\\n'
    done
    for p in nginx-module-njs; do
        echo -n '        '"$p"'=${NGINX_VERSION}'"$sep"'${NJS_VERSION}-'"$r"'${PKG_RELEASE} \\'
    done
}

get_packagerepo() {
    local distro="${1%-perl}"; shift;
    local branch="$1"; shift;

    [ "$branch" = "mainline" ] && branch="$branch/" || branch=""

    echo "https://nginx.org/packages/${branch}${distro}/"
}

get_packagever() {
    local distro="${1%-perl}"; shift;
    local branch="$1"; shift;
    local suffix=

    [ "${distro}" = "ubuntu" ] && suffix="~${ubuntuver}"

    echo ${pkg[$branch]:-$defaultpkg}${suffix}
}

generated_warning() {
    cat << __EOF__
#
# NOTE: THIS DOCKERFILE IS GENERATED VIA "update.sh"
#
# PLEASE DO NOT EDIT IT DIRECTLY.
#
__EOF__
}

for branch in "${branches[@]}"; do
    for variant in \
        ubuntu{,-perl} \
    ; do
        echo "$branch: $variant"
        dir="$branch/$variant"
        variant="$(basename "$variant")"

        [ -d "$dir" ] || continue

        template="Dockerfile-${variant%-perl}.template"
        { generated_warning; cat "$template"; } > "$dir/Dockerfile"

        ubuntuver="${ubuntu[$branch]:-$defaultubuntu}"
        nginxver="${nginx[$branch]}"
        njsver="${njs[${branch}]:-$defaultnjs}"
        pkgver="${pkg[${branch}]:-$defaultpkg}"
        revver="${rev[${branch}]:-$defaultrev}"

        packagerepo=$(get_packagerepo "$variant" "$branch")
        packages=$(get_packages "$variant" "$branch")
        packagever=$(get_packagever "$variant" "$branch")

        sed -i \
            -e 's,%%UBUNTU_VERSION%%,'"$ubuntuver"',' \
            -e 's,%%NGINX_VERSION%%,'"$nginxver"',' \
            -e 's,%%NJS_VERSION%%,'"$njsver"',' \
            -e 's,%%PKG_RELEASE%%,'"$packagever"',' \
            -e 's,%%PACKAGES%%,'"$packages"',' \
            -e 's,%%PACKAGEREPO%%,'"$packagerepo"',' \
            -e 's,%%REVISION%%,'"$revver"',' \
            "$dir/Dockerfile"

        cp -a entrypoint/*.sh "$dir/"

    done
done
