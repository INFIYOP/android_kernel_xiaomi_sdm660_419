# AnyKernel3 Ramdisk Mod Script (Aroma flavour, Tulip)
# osm0sis @ xda-developers
#
# Aroma flow, options and fdt patches are from San-Kernel (@user_why_red),
# who credits Panda Kernel. Adapted for this tree by make-aroma-zip.sh:
#   - the kernel is shipped as Image.gz + kernel.dtb (split from Image.gz-dtb)
#   - every Aroma value defaults to "no change" when the prop is missing
#   - a failing fdtput aborts the whole install before anything is flashed

## AnyKernel setup
# begin properties
properties() { '
kernel.string=@KERNEL_STRING@
do.devicecheck=1
do.modules=0
do.systemless=0
do.cleanup=1
do.cleanuponabort=0
device.name1=tulip
device.name2=twolip
supported.versions=
supported.patchlevels=
'; } # end properties

# shell variables
block=/dev/block/bootdevice/by-name/boot;
is_slot_device=0;
ramdisk_compression=auto;
patch_vbmeta_flag=auto;

## AnyKernel methods (DO NOT CHANGE)
# import patching functions/variables - see for reference
. tools/ak3-core.sh;

aroma_show_progress() {
  # aroma_show_progress <amount> <time>  (time is in ms under Aroma)
  show_progress $1 "-${2}"
}

# aroma_get_value <name>: value chosen in Aroma, empty if the screen was skipped
aroma_get_value() {
  [ -f /tmp/aroma/${1}.prop ] && cat /tmp/aroma/${1}.prop | head -n1 | cut -d'=' -f2 || echo ""
}

# apply_fdt_patch <dtb> <fdtp file>
# Runs in the main shell (no pipe) so abort really stops the install.
apply_fdt_patch() {
  [ -f "$2" ] || abort "! Can not find fdt patch file: $2!"
  local tmp=$home/fdtp.tmp line
  sed -e 's/[ 	]*#.*//' -e '/^[ 	]*$/d' "$2" > $tmp
  while read line; do
    $bin/fdtput $1 $line || abort "! Failed to apply fdt patch: $2"
  done < $tmp
  rm -f $tmp
}

# Aroma UV/OV level -> microvolts
parse_mv_level() {
  case "$1" in
    "2") echo 20000;;
    "3") echo 40000;;
    "4") echo 80000;;
    "5") echo 100000;;
    "6") echo 120000;;
    *) echo 0;;
  esac
}

# AnyKernel split boot install
split_boot;

ui_print "- Extracting files..."
set_progress 0.1
dtb_img=${home}/kernel.dtb
[ -f $dtb_img ] || abort "! kernel.dtb is missing from the zip!"
set_progress 0.3

# Values chosen in Aroma ("" = screen skipped = no change)
cpu_oc=$(aroma_get_value cpu_oc);                  cpu_oc=${cpu_oc:-0}
cpu_uc=$(aroma_get_value cpu_uc);                  cpu_uc=${cpu_uc:-0}
gpu_oc=$(aroma_get_value gpu_oc);                  gpu_oc=${gpu_oc:-0}
zram_size=$(aroma_get_value zram_size);            zram_size=${zram_size:-7}
uv_confirm=$(aroma_get_value uv_confirm);          uv_confirm=${uv_confirm:-1}
ov_confirm=$(aroma_get_value ov_confirm);          ov_confirm=${ov_confirm:-1}
ecpu_ov_level=$(aroma_get_value ecpu_ov_level);    ecpu_ov_level=${ecpu_ov_level:-1}
pcpu_ov_level=$(aroma_get_value pcpu_ov_level);    pcpu_ov_level=${pcpu_ov_level:-1}
ecpu_uv_level=$(aroma_get_value ecpu_uv_level);    ecpu_uv_level=${ecpu_uv_level:-1}
pcpu_uv_level=$(aroma_get_value pcpu_uv_level);    pcpu_uv_level=${pcpu_uv_level:-1}
energy_model=$(aroma_get_value energy_model);      energy_model=${energy_model:-1}

# EAS energy model (1 = the one built into this kernel's dtb)
fdt_patch_files=""
case "$energy_model" in
  1) ;;
  2)
    ui_print "- Use kdrag0n's EAS energy model (for sdm660)"
    if [ "$cpu_oc" -eq 1 ]; then
      fdt_patch_files="${home}/fdt_patches/kdrag0n-energy-model-sdm660-oc.fdtp"
    else
      fdt_patch_files="${home}/fdt_patches/kdrag0n-energy-model-sdm660-nooc.fdtp"
    fi;;
  3)
    ui_print "- Use kdrag0n's EAS energy model (for sdm636)"
    [ "$cpu_oc" -ne 0 ] && abort "! This energy model is not suitable with overclock!"
    fdt_patch_files="${home}/fdt_patches/kdrag0n-energy-model-sdm636-nooc.fdtp";;
  4)
    ui_print "- Use hypeartist's EAS energy model"
    if [ "$cpu_oc" -eq 1 ]; then
      fdt_patch_files="${home}/fdt_patches/hypeartist-energy-model-oc.fdtp"
    else
      fdt_patch_files="${home}/fdt_patches/hypeartist-energy-model-nooc.fdtp"
    fi;;
  *) abort "! Unknown parameter: energy_model: \"$energy_model\"";;
esac

if [ -n "$fdt_patch_files" ]; then
  ui_print "- Patching dtb file..."
  for fdt_patch_file in $fdt_patch_files; do
    apply_fdt_patch $dtb_img $fdt_patch_file
  done
  sync
fi

# Undervolt
if [ "$uv_confirm" -eq 2 ]; then
  ui_print "- Applying UV changes..."
  ecpu_uv=$(parse_mv_level $ecpu_uv_level)
  pcpu_uv=$(parse_mv_level $pcpu_uv_level)
  if [ "$ecpu_uv" -ne 0 ]; then
    $bin/fdtput $dtb_img /soc/cprh-ctrl@179c8000/thread@0/regulator qcom,custom-voltage-reduce $ecpu_uv -tu || abort "! UV patch failed (LITTLE)"
  fi
  if [ "$pcpu_uv" -ne 0 ]; then
    $bin/fdtput $dtb_img /soc/cprh-ctrl@179c4000/thread@0/regulator qcom,custom-voltage-reduce $pcpu_uv -tu || abort "! UV patch failed (BIG)"
  fi
  ui_print "- $ecpu_uv uV is reduced for LITTLE-cluster!"
  ui_print "- $pcpu_uv uV is reduced for BIG-cluster!"
  sync
fi

# Overvolt
if [ "$ov_confirm" -eq 2 ]; then
  ui_print "- Applying OV changes..."
  ecpu_ov=$(parse_mv_level $ecpu_ov_level)
  pcpu_ov=$(parse_mv_level $pcpu_ov_level)
  if [ "$ecpu_ov" -ne 0 ]; then
    $bin/fdtput $dtb_img /soc/cprh-ctrl@179c8000/thread@0/regulator qcom,custom-voltage-increase $ecpu_ov -tu || abort "! OV patch failed (LITTLE)"
  fi
  if [ "$pcpu_ov" -ne 0 ]; then
    $bin/fdtput $dtb_img /soc/cprh-ctrl@179c4000/thread@0/regulator qcom,custom-voltage-increase $pcpu_ov -tu || abort "! OV patch failed (BIG)"
  fi
  ui_print "- $ecpu_ov uV is increased for LITTLE-cluster!"
  ui_print "- $pcpu_ov uV is increased for BIG-cluster!"
  sync
fi
if [ "$uv_confirm" -eq 2 ] && [ "$ov_confirm" -eq 2 ]; then
  ui_print "- Final voltage = reference voltage - undervoltage + overvoltage."
fi
set_progress 0.3

# Kernel command line. Every switch is rewritten on each flash, so
# reflashing with "No" clears an earlier choice.
if [ "$cpu_oc" -eq 1 ]; then
  ui_print "- CPU is overclocked to 2.2Ghz!"
  patch_cmdline "overclock.cpu" "overclock.cpu=1"
elif [ "$cpu_oc" -eq 2 ]; then
  ui_print "- CPU is overclocked to 2.4Ghz!"
  patch_cmdline "overclock.cpu" "overclock.cpu=2"
else
  patch_cmdline "overclock.cpu" ""
fi

if [ "$gpu_oc" -eq 1 ]; then
  ui_print "- GPU is overclocked to 630Mhz!"
  patch_cmdline "overclock.gpu" "overclock.gpu=1"
else
  patch_cmdline "overclock.gpu" ""
fi

if [ "$cpu_uc" -eq 1 ]; then
  ui_print "- CPU is underclocked to 1.4Ghz!"
  patch_cmdline "underclock.cpu" "underclock.cpu=1"
elif [ "$cpu_uc" -eq 2 ]; then
  ui_print "- CPU is underclocked to 1.8Ghz!"
  patch_cmdline "underclock.cpu" "underclock.cpu=2"
else
  patch_cmdline "underclock.cpu" ""
fi

if [ "$zram_size" -ne 7 ]; then
  ui_print "- ZRAM is resized to $zram_size GB (the kernel caps it at half of RAM)!"
  patch_cmdline "zram.resize" "zram.resize=$zram_size"
else
  patch_cmdline "zram.resize" ""
fi
sync

# The patched dtb is appended to the kernel by flash_boot
cp -f $dtb_img ${split_img}/kernel_dtb
sync

ui_print "- Everything is set, Installation going on :)"
aroma_show_progress 0.5 3500

flash_boot;
flash_dtbo;
## end boot install
