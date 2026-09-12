enum MediaSize {
  thumbnail,
  full;

  /// Max width/height in pixels a thumbnail is downscaled to before
  /// being written to disk cache.
  static const int thumbnailMaxDimension = 320;
}
