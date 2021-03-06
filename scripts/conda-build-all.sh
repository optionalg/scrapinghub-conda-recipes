#!/bin/bash
set -euv

if [ -z "${CONDA_BUILDALL_MATRIX:-}" ]; then
  echo "Missing CONDA_BUILDALL_MATRIX environment variable"
  exit 1
fi

if [ -z "${TRAVIS_BUILD_DIR:-}" ]; then
  echo "Missing TRAVIS_BUILD_DIR environment variable"
  exit 1
fi

if [ -z "${BUILD_OUTPUT:-}" ]; then
  echo "Missing BUILD_OUTPUT environment variable"
  exit 1
fi

# We let conda-build-all figure out which packages are needed to be build
# based on the build cache and dependencies graph.
conda build-all $TRAVIS_BUILD_DIR --matrix-conditions "$CONDA_BUILDALL_MATRIX"

# We now proceed to convert the conda packages to all platforms. This will be
# fine as long we don't have packages with compiled code.
for META in $TRAVIS_BUILD_DIR/*/meta.yaml; do
  PACKAGE_DIR=$(dirname $META)
  PACKAGE_CONVERT="$PACKAGE_DIR/convert"
  PACKAGE_FILENAME=$(conda build --output $PACKAGE_DIR)
  # Packages may have been skipped due to skip build flag.
  if [[ $PACKAGE_FILENAME == Skipped* ]]; then
    echo "Skipped $(basename $PACKAGE_DIR)"
  elif [[ ! -f $PACKAGE_FILENAME ]]; then
    # This happens when recipe has conditional skip:True but output option
    # doesn't pick the condition.
    echo "File not found $PACKAGE_FILENAME"
  else
    # We can convert either to explicit platforms or all of them.
    if [ -f $PACKAGE_CONVERT ]; then
      CONVERT_TO=$(cat $PACKAGE_CONVERT)
    else
      CONVERT_TO=all
    fi
    for PLAT in $CONVERT_TO; do
      if [ ! "$PLAT" = "none" ]; then
        echo "Converting $(basename $PACKAGE_FILENAME) to platform: $PLAT"
        conda convert -q -p $PLAT -o $BUILD_OUTPUT $PACKAGE_FILENAME || exit 1
      fi
    done
  fi
done

# Given we convert the scrapy package from linux-* to win-*, the
# conditional dependencies for win-* are not included in the package,
# namely pywin32. So we hack the packages to include that dependency.
shopt -s nullglob   # avoid breaking the glob below finds  nothing.
for PKG in $BUILD_OUTPUT/win-*/scrapy-*.tar.bz2; do
  python scripts/conda-add-dep.py $PKG pywin32
done
