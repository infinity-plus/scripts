#!/usr/bin/env bash
#
# Kernel compiling script
#
# Set timezone ( use "tzselect" to see what to export)
export TZ="Asia/Kolkata"

[ -f deldog ] && echo "deldog present" || curl -LSsO  https://github.com/infinity-plus/scripts/raw/master/deldog

[ -f telegram ] && echo "telegram present" || curl -LSsO  https://github.com/infinity-plus/scripts/raw/master/telegram


# Get toolchains if not already present

[ -d "$HOME/TC" ] || mkdir -p "$HOME/TC"

[ -d "$HOME/TC/gcc32" ] && echo "GCC 32bit present" || echo "Cloning GCC 32bit:" && git clone -q https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/arm/arm-linux-androideabi-4.9/ --depth=1 "$HOME"/TC/gcc32
[ -d "$HOME/TC/clang" ] && echo "Clang is present"  || echo "Cloning Clang: "    && git clone -q https://github.com/crdroidandroid/android_prebuilts_clang_host_linux-x86_clang-5900059 --depth=1 "$HOME"/TC/clang
[ -d "$HOME/TC/gcc64" ] && echo "GCC 64bit present" || echo "Cloning GCC 64bit:" && git clone https://github.com/WolfOSP/linaro-TC --depth=1 "$HOME"/TC/gcc64"


cd "$KERNELDIR" || exit 1

#
#  Fuctions
#

function check_toolchain() {
      TC="$(find "$TOOLCHAIN"/bin -type f -name '*-gcc')"
      export TC
      if [[ -f "$TC" ]]
      then
	  CROSS_COMPILE="$TOOLCHAIN/bin/$(echo "$TC" | awk -F '/' '{print $NF}' | sed -e 's/gcc//')"
          export CROSS_COMPILE
          echo -e "Using toolchain: $("${CROSS_COMPILE}"gcc --version | head -1)"
      else
	  telegram "No suitable toolchain found in $TOOLCHAIN"
	  exit 1
      fi
}


#evv() {
#   FILE="$OUTDIR"/include/generated/compile.h
#   export "$(grep "${1}" "${FILE}" | cut -d'"' -f1 | awk '{print $2}')"="$(grep "${1}" "${FILE}" | cut -d'"' -f2)"
#}

checkVar() {
    if [ ! "$@" ]
      then
        echo "Argument required" && exit 1
      fi
    if ! declare | grep "^$1" > /dev/null || [ "$1" = "" ]
      then
        echo "$1 is not set" 
        exit 1
      else
        echo "$1 is set"
    fi
}

changelog() {
    bash changelog-generator.sh |& deldog
}

#
#  Export variables for compilation
#


# Check necessary variables
checkVar TELEGRAM_CHAT
checkVar TELEGRAM_TOKEN
checkVar KERNELNAME
checkVar KERNELDIR

export OUTDIR="$KERNELDIR"/out
export ANYKERNEL=$KERNELDIR/AnyKernel3
export ARCH=arm64
export SUBARCH=arm64
TOOLCHAIN=$HOME/TC/gcc64
export TOOLCHAIN
export ZIP_DIR=$ANYKERNEL
export IMAGE=$OUTDIR/arch/$ARCH/boot/Image.gz-dtb
export DEFCONFIG=X00T_defconfig

check_toolchain
export CC="$HOME/TC/clang/bin/clang"
CLANG_VERSION="$($CC --version | head -n 1 | perl -pe 's/\(http.*?\)//gs' | sed -e 's/  */ /g' -e 's/[[:space:]]*$//')"
export CLANG_VERSION
export CLANG_TRIPLE="${CROSS_COMPILE}"

export MAKE="make O=$OUTDIR"
ZIPNAME="$KERNELNAME-$(date +%m%d-%H).zip"
export ZIPNAME
export FINAL_ZIP="$ZIP_DIR/$ZIPNAME"

[ -d "$OUTDIR" ] || mkdir -pv "$OUTDIR"

rm -fv "$IMAGE"

# Send Message about build started
# ================
echo -e "Build scheduled\n$KERNELNAME\nBranch: $BRANCH_NAME" | ./telegram -

# Export Custom Compiler name
export KBUILD_COMPILER_STRING=$CLANG_VERSION

# Make Config
# ================

$MAKE $DEFCONFIG

#
# Make clean if script is run with -clean
#

if [[ "$*" == *"-clean"* ]]
then
  make clean && make mrproper
fi


#
#  Start compilation
#

echo 'Beginning compilation'

PATH="$HOME/TC/clang/bin:$HOME/TC/clang/bin:$HOME/TC/gcc-linaro-7.5.0-2019.12-x86_64_aarch64-linux-gnu/bin:$PATH" \
$MAKE -j"$(nproc --all)" \
           ARCH=$ARCH \
           CC=clang \
           CLANG_TRIPLE="$CLANG_TRIPLE" \
           CROSS_COMPILE="$CROSS_COMPILE" \
           CROSS_COMPILE_ARM32="$HOME/TC/gcc32/bin/arm-linux-androideabi-" 2>&1 | tee build-log.txt

# Send log if build failed
# ================
if [[ ! -f $IMAGE ]]
then
    echo "Build failed " | ./telegram -
    exit 1
else
    echo -e "Build Succesful!"
fi

# Make ZIP using AnyKernel
# ================

[ -d "$ANYKERNEL" ] && echo 'Anykernel Present' || echo 'Cloning AnyKernel' && git clone https://github.com/infinity-plus/AnyKernel3 -b X00T --depth=1
echo -e "Copying kernel image"
cp -v "$IMAGE" "$ANYKERNEL/Image.gz-dtb"
cd "$ANYKERNEL" || exit 1
mv Image.gz-dtb zImage
zip -r9 "$ZIPNAME" ./* -x .git -x README.md -x placeholder
cd - || exit 1


# Push to telegram if successful
# ================
if [ -f "$FINAL_ZIP" ]
then
  Caption="
  *BUILD-DETAILS*

  *Name:*
  $KERNELNAME
  *Version:*
  $(head -n3 Makefile | sed -E 's/.*(^\w+\s[=]\s)//g' | xargs | sed -E 's/(\s)/./g')
  *Date:*
  $(date +%d/%m)
  *Toolchain:*
  $KBUILD_COMPILER_STRING
  *Changelog*:
  $(changelog)"
  echo "$Caption"hamge
  ./telegram -M -f "$FINAL_ZIP" "$Caption"
else
  echo "Zip Creation Failed" 
  exit 1;
fi
