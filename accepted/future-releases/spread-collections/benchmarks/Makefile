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

# See https://japhr.blogspot.com/2014/07/command-line-arguments-with-nodejs-and.html.
DART2JS_MAIN := 'function dartMainRunner(main, args) { main(process.argv.slice(2)); }'

all: aot dart2js jit

aot:
	@ mkdir -p out
	@ $(SDK)/pkg/vm/tool/precompiler2 bin/profile.dart out/profile.snapshot
	@ $(SDK)/pkg/vm/tool/dart_precompiled_runtime2 out/profile.snapshot "VM AoT" 0 --csv
	@ $(SDK)/pkg/vm/tool/dart_precompiled_runtime2 out/profile.snapshot "VM AoT" 5 --csv
	@ $(SDK)/pkg/vm/tool/dart_precompiled_runtime2 out/profile.snapshot "VM AoT" 50 --csv

dart2js:
	@ mkdir -p out
	@ $(SDK)/sdk/bin/dart2js -O4 bin/profile.dart -o out/profile.js
	@ echo $(DART2JS_MAIN) >> out/profile.js
	@ node out/profile.js "dart2js -O4" 0 --csv
	@ node out/profile.js "dart2js -O4" 5 --csv
	@ node out/profile.js "dart2js -O4" 50 --csv

jit:
	@ $(SDK)/sdk/bin/dart bin/profile.dart "VM JIT" 0 --csv
	@ $(SDK)/sdk/bin/dart bin/profile.dart "VM JIT" 5 --csv
	@ $(SDK)/sdk/bin/dart bin/profile.dart "VM JIT" 50 --csv

.PHONY: all aot dart2js jit
