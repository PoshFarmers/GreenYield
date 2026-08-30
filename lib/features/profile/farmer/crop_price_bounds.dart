/// Hardcoded market min/max price-per-kg bounds, by crop name.
/// Deliberately client-side only for now, not enforced at the DB level —
/// see `context folder/CROP_AND_LISTING_DESIGN.md` §4.
const Map<String, ({double min, double max})> cropPriceBounds = {
  'Tomato': (min: 150, max: 250),
  'Carrot': (min: 120, max: 200),
  'Cabbage': (min: 80, max: 150),
  'Brinjal': (min: 100, max: 180),
  'Okra': (min: 150, max: 220),
  'Pumpkin': (min: 60, max: 120),
  'Cucumber': (min: 80, max: 150),
  'Green Beans': (min: 200, max: 300),
  'Potato': (min: 180, max: 280),
  'Onion': (min: 200, max: 320),
  'Beetroot': (min: 150, max: 220),
  'Capsicum': (min: 250, max: 400),
  'Banana': (min: 100, max: 180),
  'Mango': (min: 150, max: 350),
  'Papaya': (min: 80, max: 150),
  'Pineapple': (min: 100, max: 200),
  'Watermelon': (min: 60, max: 120),
  'Orange': (min: 150, max: 280),
  'Guava': (min: 120, max: 200),
  'Jackfruit': (min: 80, max: 150),
  'Rambutan': (min: 200, max: 350),
  'Mangosteen': (min: 400, max: 700),
};

const ({double min, double max}) _defaultPriceBounds = (min: 100, max: 300);

({double min, double max}) priceBoundsFor(String cropName) =>
    cropPriceBounds[cropName] ?? _defaultPriceBounds;
