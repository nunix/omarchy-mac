#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const picker = requireFromRoot('shell/plugins/image-picker/ImagePickerModel.js')

assertEqual(picker.nameForPath('/themes/nord-river.png'), 'nord-river', 'image picker strips directory and extension')
assertEqual(picker.labelForPath('/themes/nord_river.png'), 'Nord River', 'image picker builds display labels')

const rows = [
  '/themes/a/nord-river.png\t/cache/nord-river.jpg',
  '/themes/b/nord-river.png\t/cache/duplicate.jpg',
  '/themes/a/gruvbox-dark.jpeg',
  '',
  '\t/cache/no-path.jpg',
  '/themes/a/plain',
  '/intros/fire.mp4\t/cache/fire.jpg'
].join('\n')

const images = picker.loadRows(rows)
assertDeepEqual(
  images,
  [
    { filePath: '/themes/a/nord-river.png', fileName: 'nord-river.png', thumbnailPath: '/cache/nord-river.jpg', videoPath: '' },
    { filePath: '/themes/a/gruvbox-dark.jpeg', fileName: 'gruvbox-dark.jpeg', thumbnailPath: '/themes/a/gruvbox-dark.jpeg', videoPath: '' },
    { filePath: '/themes/a/plain', fileName: 'plain', thumbnailPath: '/themes/a/plain', videoPath: '' },
    { filePath: '/intros/fire.mp4', fileName: 'fire.mp4', thumbnailPath: '/cache/fire.jpg', videoPath: '/intros/fire.mp4' }
  ],
  'image picker parses rows and dedupes by file name'
)

assert(picker.isVideoPath('/intros/fire.mp4'), 'image picker recognizes a video extension')
assert(picker.isVideoPath('/themes/a/preview.WEBM'), 'image picker matches video extensions case-insensitively')
assert(!picker.isVideoPath('/themes/a/preview.png'), 'image picker does not flag a still image as video')

assert(picker.itemMatches(images, 0, 'river'), 'image picker matches file names')
assert(picker.itemMatches(images, 1, 'Gruvbox Dark'), 'image picker matches labels case-insensitively')
assert(!picker.itemMatches(images, 2, 'river'), 'image picker rejects non-matching filters')
assertEqual(picker.firstMatchingIndex(images, 'plain'), 2, 'image picker finds first matching index')
assertEqual(picker.indexForSelectedImage(images, '/themes/a/gruvbox-dark.jpeg'), 1, 'image picker finds selected image')
assertEqual(picker.indexForSelectedImage(images, '/missing.png'), 0, 'image picker defaults selected image to first row')

assertEqual(picker.filteredPosition(images, 2, 'dark'), 1, 'image picker computes filtered position')
assertEqual(picker.selectedFilteredPosition(images, 2, 'dark'), 0, 'image picker selected filtered position falls back when selected is hidden')
assertEqual(picker.nextSelectedIndexForFilter(images, 0, 'dark'), 1, 'image picker moves selection to first match when filter hides current item')

const imagePickerQml = fs.readFileSync(path.join(root, 'shell/plugins/image-picker/ImagePicker.qml'), 'utf8')
assert(
  /function preloadRows[\s\S]*if \(opened \|\| requestActive\) return/.test(imagePickerQml),
  'image picker ignores cache preloads while a request is visible'
)
assert(
  /if \(args\.source === "themes"\) \{\s*openThemes\(\)/.test(imagePickerQml) &&
    /function openThemes\(\) \{\s*if \(themeRows\) \{\s*openThemeRows\(\)[\s\S]*refreshThemeRows\(\)/.test(imagePickerQml),
  'image picker opens themes from held rows before refreshing them'
)
assert(
  /command: \[root\.omarchyPath \+ "\/bin\/omarchy-theme-switcher", "--print-rows"\]/.test(imagePickerQml),
  'image picker refreshes theme rows from the theme switcher'
)
assert(
  /if \(themeMode\) \{[\s\S]*Util\.execArgv\(\["omarchy-theme-set", nameForPath\(path\)\]\)/.test(imagePickerQml),
  'image picker applies a chosen theme itself'
)
assert(
  /function cancel\(\) \{\s*themeOpenPending = false/.test(imagePickerQml) &&
    /function closeSelector\(nextDoneFile\) \{\s*requestSerial \+= 1\s*themeOpenPending = false/.test(imagePickerQml),
  'image picker drops a pending theme open once dismissed'
)
assert(
  /function openSelector[\s\S]*?themeMode = false/.test(imagePickerQml),
  'image picker leaves theme mode when another caller opens it'
)
assert(
  /PanelWindow \{[\s\S]*?visible: true[\s\S]*?mask: root\.opened && !root\.previewing \? null : closedMask[\s\S]*?WlrLayershell\.layer: root\.opened && !root\.previewing \? WlrLayer\.Overlay : WlrLayer\.Bottom/.test(imagePickerQml) &&
    /Region \{ id: closedMask \}/.test(imagePickerQml),
  'image picker keeps its surface mapped, parked input-less below windows while closed or previewing'
)
assert(
  /function videoPathForCurrent\(\) \{[\s\S]*?return imageArray\[selectedIndex\]\.videoPath \|\| ""/.test(imagePickerQml),
  'image picker reads videoPath from the selected row'
)
assert(
  /function startPreview\(\) \{[\s\S]*?if \(root\.previewing\) return[\s\S]*?var video = videoPathForCurrent\(\)[\s\S]*?if \(!video\) return[\s\S]*?root\.previewing = true[\s\S]*?previewProc\.running = true/.test(imagePickerQml),
  'image picker only starts a preview when the selected row has a video'
)
assert(
  /id: previewProc[\s\S]*?onExited: \{[\s\S]*?root\.previewing = false[\s\S]*?root\.focusPicker\(\)/.test(imagePickerQml),
  'image picker returns focus to the carousel when a preview ends'
)
assert(
  /event\.key === Qt\.Key_Space && root\.videoPathForCurrent\(\)\) \{\s*root\.startPreview\(\)/.test(imagePickerQml),
  'image picker plays the selected row\'s video on Space'
)
assert(
  /WlrLayershell\.keyboardFocus: root\.opened && root\.imagesLoaded && !root\.previewing \? WlrKeyboardFocus\.Exclusive/.test(imagePickerQml),
  'image picker releases keyboard focus to the preview player while previewing'
)
assert(
  /function openSelector[\s\S]*?targetScreen = focusedScreen\(\) \|\| targetScreen/.test(imagePickerQml) &&
    /screen: root\.targetScreen/.test(imagePickerQml),
  'image picker follows the focused monitor on each open'
)
assert(
  /source: item\.sourceActivated && item\.thumbnailPath \? Util\.fileUrl\(item\.thumbnailPath\) : ""[\s\S]*asynchronous: false/.test(imagePickerQml),
  'image picker loads activated thumbnails synchronously to avoid carousel flicker'
)
JS
