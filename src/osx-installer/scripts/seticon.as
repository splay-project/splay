set theFilePath to "Applications/SPLAY"
set theIcon to (load image "splay.icns")
set sharedWorkspace to call method "sharedWorkspace" of class "NSWorkspace" --> kinda important
set didSetIcon to call method "setIcon:forFile:options:" of sharedWorkspace with parameters {theIcon, theFilePath, 0}
