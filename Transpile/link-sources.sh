#!/bin/sh
# Rebuilds Sources/<target>/ as real folders of symbolic links, one link per file, to the portable core in ../Sources, so that this
# package builds the same sources the iOS package does (the transpiler does not follow a linked folder). The viewer contract
# (ScriptureText/Viewer) is linked like the rest: its Observation is carried by SkipModel. The Skip/skip.yml of
# each target is a real file and is kept. Run this again after a file is added, moved or removed in one of the four targets.
set -e
cd "$(dirname "$0")"
# link <target> <source folder (Sources)>: one link per Swift file of ../<folder>/<target>
link() {
    target=$1; kind=$2
    mkdir -p "$kind/$target"
    find "$kind/$target" -type l -delete
    find "$kind/$target" -type d -empty -not -path "$kind/$target/Skip" -not -path "$kind/$target" -delete
    (cd "../$kind/$target" && find . -type f -name '*.swift') | while read -r file; do
        file=${file#./}
        dir=$(dirname "$file")
        mkdir -p "$kind/$target/$dir"
        depth=$(printf '%s' "$target/$file" | tr -cd '/' | wc -c)
        up=""
        i=0
        while [ $i -lt $((depth + 2)) ]; do up="$up../"; i=$((i + 1)); done
        ln -s "${up}$kind/$target/$file" "$kind/$target/$file"
    done
}

for target in ScriptureText ScriptureTextMarkup ScriptureTextBuilding ScriptureTextOSIS; do
    link "$target" Sources
done

# The Android viewer's Kotlin, linked into the Skip module that wraps it for SwiftUI (one copy of the viewer).
mkdir -p Sources/ScriptureViewerSkip/Skip
find Sources/ScriptureViewerSkip/Skip -type l -delete
for file in ../Android/scriptureviewer/src/main/kotlin/scripture/viewer/*.kt; do
    ln -s "../../../$file" "Sources/ScriptureViewerSkip/Skip/$(basename "$file")"
done
