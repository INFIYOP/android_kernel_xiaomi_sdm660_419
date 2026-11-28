#!/usr/bin/env bash
# Build an Aroma-based flashable zip (CPU/GPU OC, UC, UV/OV, zram size,
# EAS energy model) for Tulip from a normal Image.gz-dtb.
#
#   installer/make-aroma-zip.sh -i out/arch/arm64/boot/Image.gz-dtb \
#       -o kernel-aroma.zip -n "SanKernel BakaSU+SUSFS v1.1" [-b base.zip]
#
# The Aroma binary, theme, fonts and the aarch32 fdtput come from San-Kernel's
# public Veil Tulip release (pinned by sha256 below), so no binary blobs live
# in this repo. Our own anykernel.sh replaces his, and his splash/branding is
# dropped. Needs: bash, curl (unless -b), unzip, zip, python3, sha256sum.
set -euo pipefail

BASE_URL="https://github.com/user-why-red/san_kernel_releases/releases/download/veil-r1.1.104/San-Kernel-Veil-R1.1.104-Tulip.zip"
BASE_SHA256="95bfe4ec1406d43ae099e8d75017eb6cc938636f9f99a83e420c038e18ccd99e"

here=$(cd "$(dirname "$0")" && pwd)
img="" out="" name="" ver="" base=""
while getopts "i:o:n:v:b:" o; do
  case $o in
    i) img=$OPTARG;; o) out=$OPTARG;; n) name=$OPTARG;; v) ver=$OPTARG;; b) base=$OPTARG;;
    *) echo "usage: $0 -i Image.gz-dtb -o out.zip -n name [-v version] [-b base.zip]" >&2; exit 2;;
  esac
done
[ -f "${img:-}" ] && [ -n "${out:-}" ] && [ -n "${name:-}" ] || { echo "need -i (existing file), -o and -n" >&2; exit 2; }
ver=${ver:-$name}
# these end up inside sed replacement text and Aroma/edify strings
for v in "$name" "$ver"; do
  case "$v" in *[\"\\\&\|\$\`]*) echo "name/version must not contain \" \\ & | \$ \`" >&2; exit 2;; esac
done

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

if [ -z "$base" ]; then
  base=$work/base.zip
  curl -fsSL --retry 3 -o "$base" "$BASE_URL"
fi
echo "$BASE_SHA256  $base" | sha256sum -c - >/dev/null || { echo "base zip sha256 mismatch" >&2; exit 1; }

mkdir "$work/base" "$work/zip"
unzip -q "$base" -d "$work/base"
B=$work/base
Z=$work/zip

# What we take from the base zip: installer frontend, aroma resources, tools.
mkdir -p "$Z/META-INF/com/google/android" "$Z/tools"
cp -a "$B/META-INF/com/google/android/"{update-binary,update-binary-installer,updater-script,aroma,aroma-config} \
      "$Z/META-INF/com/google/android/"
cp -a "$B/tools/." "$Z/tools/"
cp -a "$B/fdt_patches" "$Z/fdt_patches"
chmod 755 "$Z/META-INF/com/google/android/update-binary" "$Z/META-INF/com/google/android/update-binary-installer"

# Split Image.gz-dtb into Image.gz + kernel.dtb. gzip stops at its own trailer;
# whatever follows is the appended DTB, which must be exactly one blob because
# the fdt patches only touch the first one.
python3 - "$img" "$Z" <<'PY'
import sys, zlib, struct
src, dst = sys.argv[1], sys.argv[2]
d = open(src, 'rb').read()
o = zlib.decompressobj(16 + zlib.MAX_WBITS)
o.decompress(d)
tail = o.unused_data
if len(tail) < 40 or tail[:4] != b'\xd0\x0d\xfe\xed':
    sys.exit("no appended DTB after the gzip stream (is this really an Image.gz-dtb?)")
total = struct.unpack('>I', tail[4:8])[0]
if total != len(tail):
    sys.exit("appended DTB data is %d bytes but the first FDT is %d: more than one DTB, refusing" % (len(tail), total))
open(dst + '/Image.gz', 'wb').write(d[:len(d) - len(tail)])
open(dst + '/kernel.dtb', 'wb').write(tail)
PY

# anykernel.sh from this repo
sed -e "s|@KERNEL_STRING@|$name|" "$here/anykernel.sh" > "$Z/anykernel.sh"

# Aroma: our identity, no San splash art / branding
cfg=$Z/META-INF/com/google/android/aroma-config
sed -i \
  -e "s|^ini_set(\"kernel_name\".*|ini_set(\"kernel_name\",             \"$name\");|" \
  -e "s|^ini_set(\"kernel_version\".*|ini_set(\"kernel_version\",          \"$ver\");|" \
  -e "s|^ini_set(\"kernel_author\".*|ini_set(\"kernel_author\",           \"INFIYOP\");|" \
  -e "s|^ini_set(\"kernel_date\".*|ini_set(\"kernel_date\",             \"$(date -u +%Y.%m.%d)\");|" \
  -e '/splash(/d' -e '/setvar("random_num"/d' "$cfg"
# zram labels: the kernel honours an explicit size as chosen (its half-of-RAM
# limit only applies to the default), so drop San's "Recommended/Overkill" tags
sed -i \
  -e 's|^\([[:space:]]*setvar("s_zram_s1",[[:space:]]*\)".*|\1"1GB");|' \
  -e 's|^\([[:space:]]*setvar("s_zram_s2",[[:space:]]*\)".*|\1"2GB (Default, or half of RAM if that is less)");|' \
  -e 's|^\([[:space:]]*setvar("s_zram_s3",[[:space:]]*\)".*|\1"3GB");|' \
  -e 's|^\([[:space:]]*setvar("s_zram_s4",[[:space:]]*\)".*|\1"4GB");|' \
  -e 's|^\([[:space:]]*setvar("s_zram_s5",[[:space:]]*\)".*|\1"5GB (Above half of RAM may lag)");|' \
  -e 's|^\([[:space:]]*setvar("s_zram_s6",[[:space:]]*\)".*|\1"6GB (Above half of RAM may lag)");|' \
  "$cfg"
rm -f "$Z"/META-INF/com/google/android/aroma/splash*.png "$Z"/META-INF/com/google/android/aroma/random_num.sh
grep -q 'splash(' "$cfg" && { echo "splash lines survived" >&2; exit 1; }

cp "$B/LICENSE" "$Z/LICENSE" 2>/dev/null || true
cat > "$Z/README.txt" <<EOF
$name
Installer flow and fdt patches: San-Kernel by @user_why_red (thanks Panda Kernel).
AROMA Installer by amarullz. AnyKernel3 by osm0sis.
EOF

mkdir -p "$(dirname "$out")"
out_abs=$(cd "$(dirname "$out")" && pwd)/$(basename "$out")
rm -f "$out_abs"
(cd "$Z" && zip -qr9 "$out_abs" .)
unzip -tq "$out_abs" >/dev/null
echo "built $out_abs ($(du -h "$out_abs" | cut -f1))"
