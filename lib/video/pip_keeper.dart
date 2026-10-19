/// Keeps a closed video page's playback alive while the small window plays it (port of PiPKeeper.swift): the restore
/// button pushes the page back on it, ✕ closes it, and another video starting releases it first. One per app, on
/// AppServices.
class PipKeeper {
  PipKeeper();
}
