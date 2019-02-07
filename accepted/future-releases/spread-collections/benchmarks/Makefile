# Runs the benchmarks on a few platforms.

# Note: this assumes:
#
# - The language repo's root directory is adjacent to the root directory of the
#   Dart SDK repo, which is named "dart".
#
# - "node" is on your PATH.
#
# - You have built the AoT runtime by running this from the SDK root directory:
#
#   tools/build.py -m release runtime dart_precompiled_runtime

SDK := "../../../../../dart/sdk"

all: jit dart2js aot

aot:
	@ echo "AoT"
	@ mkdir -p out
	@ $(SDK)/pkg/vm/tool/precompiler2 bin/profile_list_spread.dart out/profile_list_spread.snapshot
	@ $(SDK)/pkg/vm/tool/dart_precompiled_runtime2 out/profile_list_spread.snapshot

dart2js:
	@ echo "dart2js"
	@ mkdir -p out
	@ $(SDK)/sdk/bin/dart2js bin/profile_list_spread.dart -o out/profile_list_spread.js
	@ node out/profile_list_spread.js

jit:
	@ echo "VM JIT"
	@ $(SDK)/sdk/bin/dart bin/profile_list_spread.dart

.PHONY: all aot dart2js jit
