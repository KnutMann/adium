Do not remove the .css files under any style's Contents/Resources/Variants/.

They are never named anywhere in the source. The Variants directory is enumerated at
runtime and each file name becomes an entry in the style's variant menu, so a sweep that
looks for textual references will report every one of them as unused. Deleting them
removes visible choices from the message style preferences.
