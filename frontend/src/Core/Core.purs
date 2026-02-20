-- | Cheeblr.Core: Pure domain logic for the dispensary POS.
-- |
-- | This module re-exports the complete Core API.
-- | Nothing here depends on Deku, Aff, Fetch, or any UI framework.
-- |
-- | Module structure:
-- |   Tag        — Phantom-typed string tags and registries
-- |   Domain     — Cannabis-specific registries (Category, Species, etc.)
-- |   Product    — Product types, serialization, accessors
-- |   Money      — Currency conversions and formatting
-- |   Tax        — Tax rules and computation
-- |   Cart       — Pure cart math and inventory checks
-- |   Validation — Validation combinators and product validation
-- |   Schema     — Form field descriptors (drives UI generically)
-- |   Auth       — Roles, capabilities, permission checks
module Cheeblr.Core
  ( module Cheeblr.Core.Tag
  , module Cheeblr.Core.Domain
  , module Cheeblr.Core.Product
  , module Cheeblr.Core.Money
  , module Cheeblr.Core.Tax
  , module Cheeblr.Core.Cart
  , module Cheeblr.Core.Validation
  , module Cheeblr.Core.Schema
  , module Cheeblr.Core.Auth
  ) where

import Cheeblr.Core.Tag (Tag, Registry, mkRegistry, mkTag, unTag, unsafeTag, member, memberStr, values, entries, label, ordinal, compareByRegistry, toOptions)
import Cheeblr.Core.Domain (Category, Species, MeasureUnit, categoryRegistry, speciesRegistry, measureUnitRegistry, isTaxableCategory, productClassName)
import Cheeblr.Core.Product (Product(..), ProductRecord, ProductMeta, ProductList(..), ProductResponse(..), emptyMeta, productSku, productName, productPrice, productCategory, productQuantity, productSpecies, productInStock, findBySku, findNameBySku)
import Cheeblr.Core.Money (fromDollars, toDollars, parseDollars, cents, zeroCents, formatCurrency, formatAmount, formatCentsAsDecimal, formatCentsAsDollars, formatCentsStrToDecimal, toMoney, fromMoney, formatMoney, formatMoney')
import Cheeblr.Core.Tax (TaxCategory(..), TaxRule, TaxResult, salesTaxRule, cannabisTaxRule, defaultTaxRules, calculateTaxes, totalTax, defaultTaxes)
import Cheeblr.Core.Cart (CartItem, CartTotals, Cart, emptyTotals, emptyCart, mkCartItem, calculateTotals, addItem, removeItem, removeBySku, updateQuantity, clearItems, cartQuantityForSku, canAddToCart, availableToAdd, findUnavailable, totalPayments, remainingBalance, isFullyPaid)
import Cheeblr.Core.Validation (ValidationRule(..), runValidation, allOf, anyOf, alwaysValid, nonEmpty, alphanumeric, extendedAlphanumeric, percentage, dollarAmount, nonNegativeInteger, positiveInteger, fraction, commaList, validUUID, maxLength, validUrl, validMeasurementUnit, inRegistry, ProductFormInput, validateProduct)
import Cheeblr.Core.Schema (FieldType(..), FieldDescriptor, FormSchema, productSchema, findField, dropdownFields, defaults, extractAll)
import Cheeblr.Core.Auth (Role(..), Capabilities, allRoles, roleAtLeast, noCapabilities, allCapabilities, capabilitiesFor, hasCapability, roleLabel, roleIcon, roleBadgeClass, capabilitySummary)