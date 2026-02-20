module Cheeblr.Core.Domain where

import Prelude

import Cheeblr.Core.Tag (Registry, Tag, mkRegistry, unTag)
import Cheeblr.Core.Tag as Cheeblr.Core.Tag
import Data.Set (Set)
import Data.Set as Set
import Data.String as Data.String

-- | Convenient type aliases. These provide readable signatures
-- | while the phantom Symbol prevents mixing at compile time.
type Category = Tag "category"
type Species = Tag "species"
type MeasureUnit = Tag "measure_unit"

----------------------------------------------------------------------
-- Category Registry
----------------------------------------------------------------------

categoryRegistry :: Registry "category"
categoryRegistry = mkRegistry
  [ { value: "Flower",       label: "Flower" }
  , { value: "PreRolls",     label: "Pre-Rolls" }
  , { value: "Vaporizers",   label: "Vaporizers" }
  , { value: "Edibles",      label: "Edibles" }
  , { value: "Drinks",       label: "Drinks" }
  , { value: "Concentrates", label: "Concentrates" }
  , { value: "Topicals",     label: "Topicals" }
  , { value: "Tinctures",    label: "Tinctures" }
  , { value: "Accessories",  label: "Accessories" }
  ]

-- | Categories subject to cannabis excise tax.
-- | Adding a new taxable product type is a one-line change here,
-- | not a pattern match update across the codebase.
taxableCategories :: Set Category
taxableCategories = Set.fromFoldable $ map (\s -> (unsafeTag s) :: Category)
  [ "Flower"
  , "PreRolls"
  , "Vaporizers"
  , "Edibles"
  , "Drinks"
  , "Concentrates"
  , "Topicals"
  , "Tinctures"
  ]
  where
  -- local import to avoid circular; Tag constructor is just a newtype
  unsafeTag :: forall k. String -> Tag k
  unsafeTag = Cheeblr.Core.Tag.unsafeTag

isTaxableCategory :: Category -> Boolean
isTaxableCategory cat = Set.member cat taxableCategories

----------------------------------------------------------------------
-- Species Registry
----------------------------------------------------------------------

speciesRegistry :: Registry "species"
speciesRegistry = mkRegistry
  [ { value: "Indica",               label: "Indica" }
  , { value: "IndicaDominantHybrid", label: "Indica Dominant Hybrid" }
  , { value: "Hybrid",               label: "Hybrid" }
  , { value: "SativaDominantHybrid", label: "Sativa Dominant Hybrid" }
  , { value: "Sativa",               label: "Sativa" }
  ]

----------------------------------------------------------------------
-- Measure Unit Registry
----------------------------------------------------------------------

measureUnitRegistry :: Registry "measure_unit"
measureUnitRegistry = mkRegistry
  [ { value: "g",       label: "Grams" }
  , { value: "mg",      label: "Milligrams" }
  , { value: "kg",      label: "Kilograms" }
  , { value: "oz",      label: "Ounces" }
  , { value: "lb",      label: "Pounds" }
  , { value: "ml",      label: "Milliliters" }
  , { value: "l",       label: "Liters" }
  , { value: "ea",      label: "Each" }
  , { value: "unit",    label: "Unit" }
  , { value: "units",   label: "Units" }
  , { value: "pack",    label: "Pack" }
  , { value: "packs",   label: "Packs" }
  , { value: "eighth",  label: "Eighth" }
  , { value: "quarter", label: "Quarter" }
  , { value: "half",    label: "Half" }
  , { value: "1/8",     label: "⅛ oz" }
  , { value: "1/4",     label: "¼ oz" }
  , { value: "1/2",     label: "½ oz" }
  ]

----------------------------------------------------------------------
-- CSS class generation from tags
----------------------------------------------------------------------

-- | Generate a CSS class string from product attributes.
-- | Uses tag values directly instead of Show instances on ADTs.
productClassName :: Category -> String -> Species -> String
productClassName category subcategory species =
  "species-" <> toCSS (unTag species)
    <> " category-" <> toCSS (unTag category)
    <> " subcategory-" <> toCSS subcategory
  where
  toCSS :: String -> String
  toCSS str = Data.String.toLower
    (Data.String.replace
      (Data.String.Pattern " ")
      (Data.String.Replacement "-")
      str)