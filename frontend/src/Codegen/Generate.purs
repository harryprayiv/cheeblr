module Codegen.Generate 
  ( generateAll
  , GeneratedModule
  ) where

import Prelude

import Codegen.Schema (DomainSchema, EnumDef, FieldDef, FieldType(..), RecordDef, TypeKind(..), Validation(..))
import Data.Array as Array
import Data.Array.NonEmpty as NEA
import Data.Foldable (for_)
import Data.Maybe (Maybe(..), fromMaybe)
import Data.String as String
import Data.Tuple (Tuple(..))
import Partial.Unsafe (unsafePartial)
import PureScript.CST.Types (Declaration, DoStatement, Expr, Type) as CST
import Tidy.Codegen (PrintOptions, binaryOp, binderCtor, binderInt, binderRecord, binderString, binderVar, binderWildcard, caseBranch, dataCtor, declData, declDerive, declInstance, declNewtype, declSignature, declType, declValue, defaultPrintOptions, doBind, exprApp, exprArray, exprBool, exprCase, exprCtor, exprDo, exprDot, exprIdent, exprIf, exprInt, exprLambda, exprNumber, exprOp, exprRecord, exprString, exprTyped, instValue, printModuleWithOptions, typeApp, typeArrow, typeCtor, typeRecord, typeWildcard)
import Tidy.Codegen.Monad (codegenModule, importClass, importCtor, importFrom, importOpen, importType, importTypeAll, importValue, write, writeAndExport)

type GeneratedModule =
  { path :: String
  , content :: String
  }

printOpts :: PrintOptions
printOpts = defaultPrintOptions { pageWidth = 100 }

generateAll :: DomainSchema -> Array GeneratedModule
generateAll schema =
  [ generateTypesModule schema
  , generateFieldConfigModule schema
  , generateValidationModule schema
  , generateFormInputModule schema
  ]

-- ============================================================================
-- Types Module Generation
-- ============================================================================

generateTypesModule :: DomainSchema -> GeneratedModule
generateTypesModule schema =
  { path: moduleNameToPath schema.moduleName
  , content: printModuleWithOptions printOpts $ unsafePartial $ codegenModule schema.moduleName do
      importOpen "Prelude"
      
      enumClass <- importFrom "Data.Enum" (importClass "Enum")
      boundedEnumClass <- importFrom "Data.Enum" (importClass "BoundedEnum")
      cardinalityCtor <- importFrom "Data.Enum" (importCtor "Cardinality" "Cardinality")
      
      maybeType <- importFrom "Data.Maybe" (importType "Maybe")
      justCtor <- importFrom "Data.Maybe" (importCtor "Maybe" "Just")
      nothingCtor <- importFrom "Data.Maybe" (importCtor "Maybe" "Nothing")
      
      genericClass <- importFrom "Data.Generic.Rep" (importClass "Generic")
      
      newtypeClass <- importFrom "Data.Newtype" (importClass "Newtype")
      unwrapFn <- importFrom "Data.Newtype" (importValue "unwrap")
      
      readForeignClass <- importFrom "Yoga.JSON" (importClass "ReadForeign")
      writeForeignClass <- importFrom "Yoga.JSON" (importClass "WriteForeign")
      readImplFn <- importFrom "Yoga.JSON" (importValue "readImpl")
      writeImplFn <- importFrom "Yoga.JSON" (importValue "writeImpl")
      
      foreignErrorCtor <- importFrom "Foreign" (importCtor "ForeignError" "ForeignError")
      failFn <- importFrom "Foreign" (importValue "fail")
      
      readPropFn <- importFrom "Foreign.Index" (importValue "readProp")
      
      usdType <- importFrom "Data.Finance.Currency" (importType "USD")
      discreteType <- importFrom "Data.Finance.Money" (importType "Discrete")
      
      uuidType <- importFrom "Types.UUID" (importType "UUID")
      parseUUIDFn <- importFrom "Types.UUID" (importValue "parseUUID")
      
      -- Generate enums
      for_ schema.enums \enum -> do
        writeAndExport $ generateEnumDecl enum
        write $ generateEnumDeriveEq enum
        write $ generateEnumDeriveOrd enum
        writeAndExport $ generateEnumShowInstance enum
        writeAndExport $ generateEnumBoundedInstance enum
        writeAndExport $ generateEnumEnumInstance enum
        writeAndExport $ generateEnumBoundedEnumInstance enum
        writeAndExport $ generateEnumWriteForeignInstance enum
        writeAndExport $ generateEnumReadForeignInstance enum
      
      -- Generate records
      for_ schema.records \rec -> do
        writeAndExport $ generateRecordDecl schema rec
        write $ generateRecordDeriveNewtype rec
        write $ generateRecordDeriveEq rec
        writeAndExport $ generateRecordWriteForeignInstance schema rec
        writeAndExport $ generateRecordReadForeignInstance schema rec
  }

generateEnumDecl :: EnumDef -> CST.Declaration Void
generateEnumDecl enum = unsafePartial $
  declData enum.name []
    (NEA.toArray $ map (\v -> dataCtor v []) enum.variants)

generateEnumDeriveEq :: EnumDef -> CST.Declaration Void
generateEnumDeriveEq enum = unsafePartial $
  declDerive Nothing [] "Eq" [typeCtor enum.name]

generateEnumDeriveOrd :: EnumDef -> CST.Declaration Void
generateEnumDeriveOrd enum = unsafePartial $
  declDerive Nothing [] "Ord" [typeCtor enum.name]

generateEnumShowInstance :: EnumDef -> CST.Declaration Void
generateEnumShowInstance enum = unsafePartial $
  declInstance Nothing [] "Show" [typeCtor enum.name]
    [ instValue "show" [] $ 
        exprLambda [binderVar "x"] $
          exprCase [exprIdent "x"] $
            NEA.toArray $ map (\v -> 
              caseBranch [binderCtor v []] (exprString v)
            ) enum.variants
    ]

generateEnumBoundedInstance :: EnumDef -> CST.Declaration Void
generateEnumBoundedInstance enum = unsafePartial $
  declInstance Nothing [] "Bounded" [typeCtor enum.name]
    [ instValue "bottom" [] (exprCtor (NEA.head enum.variants))
    , instValue "top" [] (exprCtor (NEA.last enum.variants))
    ]

generateEnumEnumInstance :: EnumDef -> CST.Declaration Void
generateEnumEnumInstance enum = unsafePartial $
  let
    variants = NEA.toArray enum.variants
    pairs = Array.zip variants (Array.drop 1 variants)
    lastVariant = fromMaybe "" $ Array.last variants
  in
    declInstance Nothing [] "Enum" [typeCtor enum.name]
      [ instValue "succ" [] $
          exprLambda [binderVar "x"] $
            exprCase [exprIdent "x"] $
              (map (\(Tuple curr next) -> 
                caseBranch [binderCtor curr []] (exprApp (exprCtor "Just") [exprCtor next])
              ) pairs) <>
              [caseBranch [binderCtor lastVariant []] (exprCtor "Nothing")]
      , instValue "pred" [] $
          exprLambda [binderVar "x"] $
            exprCase [exprIdent "x"] $
              [caseBranch [binderCtor (NEA.head enum.variants) []] (exprCtor "Nothing")] <>
              (map (\(Tuple curr next) ->
                caseBranch [binderCtor next []] (exprApp (exprCtor "Just") [exprCtor curr])
              ) pairs)
      ]

generateEnumBoundedEnumInstance :: EnumDef -> CST.Declaration Void
generateEnumBoundedEnumInstance enum = unsafePartial $
  let
    variants = NEA.toArray enum.variants
    len = Array.length variants
  in
    declInstance Nothing [] "BoundedEnum" [typeCtor enum.name]
      [ instValue "cardinality" [] $ 
          exprApp (exprCtor "Cardinality") [exprInt len]
      , instValue "fromEnum" [] $
          exprLambda [binderVar "x"] $
            exprCase [exprIdent "x"] $
              Array.mapWithIndex (\i v -> 
                caseBranch [binderCtor v []] (exprInt i)
              ) variants
      , instValue "toEnum" [] $
          exprLambda [binderVar "n"] $
            exprCase [exprIdent "n"] $
              (Array.mapWithIndex (\i v ->
                caseBranch [binderInt i] (exprApp (exprCtor "Just") [exprCtor v])
              ) variants) <>
              [caseBranch [binderWildcard] (exprCtor "Nothing")]
      ]

generateEnumWriteForeignInstance :: EnumDef -> CST.Declaration Void
generateEnumWriteForeignInstance enum = unsafePartial $
  declInstance Nothing [] "WriteForeign" [typeCtor enum.name]
    [ instValue "writeImpl" [] $
        exprOp (exprIdent "writeImpl") [binaryOp "<<<" (exprIdent "show")]
    ]

generateEnumReadForeignInstance :: EnumDef -> CST.Declaration Void
generateEnumReadForeignInstance enum = unsafePartial $
  declInstance Nothing [] "ReadForeign" [typeCtor enum.name]
    [ instValue "readImpl" [binderVar "f"] $
        exprDo
          [ doBind (binderVar "str") (exprApp (exprIdent "readImpl") [exprIdent "f"]) ]
          ( exprCase [exprIdent "str"] $
              (NEA.toArray $ map (\v ->
                caseBranch [binderString v] (exprApp (exprIdent "pure") [exprCtor v])
              ) enum.variants) <>
              [ caseBranch [binderWildcard] $
                  exprApp (exprIdent "fail") 
                    [ exprApp (exprCtor "ForeignError") 
                        [ exprOp (exprString $ "Invalid " <> enum.name <> ": ")
                            [binaryOp "<>" (exprIdent "str")]
                        ]
                    ]
              ]
          )
    ]

-- ============================================================================
-- Record Generation with JSON Instances
-- ============================================================================

generateRecordDecl :: DomainSchema -> RecordDef -> CST.Declaration Void
generateRecordDecl schema rec = unsafePartial $
  let
    fields = map (\f -> Tuple f.name (fieldTypeToType schema f.fieldType)) rec.fields
  in
    case rec.kind of
      RecordType ->
        declNewtype rec.name [] rec.name (typeRecord fields Nothing)
      NewtypeOver inner ->
        declNewtype rec.name [] rec.name (typeCtor inner)

generateRecordDeriveNewtype :: RecordDef -> CST.Declaration Void
generateRecordDeriveNewtype rec = unsafePartial $
  declDerive Nothing [] "Newtype" [typeCtor rec.name, typeWildcard]

generateRecordDeriveEq :: RecordDef -> CST.Declaration Void
generateRecordDeriveEq rec = unsafePartial $
  declDerive Nothing [] "Eq" [typeCtor rec.name]

generateRecordWriteForeignInstance :: DomainSchema -> RecordDef -> CST.Declaration Void
generateRecordWriteForeignInstance schema rec = unsafePartial $
  declInstance Nothing [] "WriteForeign" [typeCtor rec.name]
    [ instValue "writeImpl" [binderCtor rec.name [binderVar "r"]] $
        exprApp (exprIdent "writeImpl") 
          [ exprRecord $ map (\f -> 
              Tuple f.name (generateWriteField schema f)
            ) rec.fields
          ]
    ]

generateWriteField :: DomainSchema -> FieldDef -> CST.Expr Void
generateWriteField schema field = unsafePartial $
  let
    accessor = exprDot (exprIdent "r") [field.name]
  in
    case field.fieldType of
      FMoney -> 
        exprApp (exprIdent "unwrap") [accessor]
      FEnum _ ->
        exprApp (exprIdent "show") [accessor]
      FNested _ ->
        accessor
      _ ->
        accessor

generateRecordReadForeignInstance :: DomainSchema -> RecordDef -> CST.Declaration Void
generateRecordReadForeignInstance schema rec = unsafePartial $
  declInstance Nothing [] "ReadForeign" [typeCtor rec.name]
    [ instValue "readImpl" [binderVar "json"] $
        exprDo
          (map (generateReadField schema) rec.fields)
          ( exprApp (exprIdent "pure") 
              [ exprApp (exprCtor rec.name)
                  [ exprRecord $ map (\f -> Tuple f.name (exprIdent (camelCase f.name))) rec.fields
                  ]
              ]
          )
    ]

generateReadField :: DomainSchema -> FieldDef -> CST.DoStatement Void
generateReadField schema field = unsafePartial $
  let
    varName = camelCase field.name
  in
    doBind (binderVar varName) $
      exprOp 
        (exprApp (exprIdent "readProp") [exprString field.name, exprIdent "json"])
        [binaryOp ">>=" (exprIdent "readImpl")]

fieldTypeToType :: DomainSchema -> FieldType -> CST.Type Void
fieldTypeToType schema = unsafePartial $ case _ of
  FString -> typeCtor "String"
  FInt -> typeCtor "Int"
  FNumber -> typeCtor "Number"
  FBool -> typeCtor "Boolean"
  FMoney -> typeApp (typeCtor "Discrete") [typeCtor "USD"]
  FPercentage -> typeCtor "String"
  FUrl -> typeCtor "String"
  FUuid -> typeCtor "UUID"
  FDateTime -> typeCtor "DateTime"
  FEnum name -> typeCtor name
  FArray inner -> typeApp (typeCtor "Array") [fieldTypeToType schema inner]
  FMaybe inner -> typeApp (typeCtor "Maybe") [fieldTypeToType schema inner]
  FNested name -> typeCtor name

-- ============================================================================
-- Field Config Module Generation  
-- ============================================================================

generateFieldConfigModule :: DomainSchema -> GeneratedModule
generateFieldConfigModule schema =
  { path: moduleNameToPath schema.configModuleName
  , content: printModuleWithOptions printOpts $ unsafePartial $ codegenModule schema.configModuleName do
      importOpen "Prelude"
      
      maybeType <- importFrom "Data.Maybe" (importType "Maybe")
      justCtor <- importFrom "Data.Maybe" (importCtor "Maybe" "Just")
      nothingCtor <- importFrom "Data.Maybe" (importCtor "Maybe" "Nothing")
      
      trimFn <- importFrom "Data.String" (importValue "trim")
      
      fieldConfigType <- importFrom "Types.Common" (importType "FieldConfig")
      dropdownConfigType <- importFrom "Types.Common" (importType "DropdownConfig")
      validationRuleType <- importFrom "Types.Common" (importType "ValidationRule")
      
      nonEmptyFn <- importFrom "Utils.Validation" (importValue "nonEmpty")
      alphanumericFn <- importFrom "Utils.Validation" (importValue "alphanumeric")
      extendedAlphanumericFn <- importFrom "Utils.Validation" (importValue "extendedAlphanumeric")
      maxLengthFn <- importFrom "Utils.Validation" (importValue "maxLength")
      dollarAmountFn <- importFrom "Utils.Validation" (importValue "dollarAmount")
      percentageFn <- importFrom "Utils.Validation" (importValue "percentage")
      validUrlFn <- importFrom "Utils.Validation" (importValue "validUrl")
      validUUIDFn <- importFrom "Utils.Validation" (importValue "validUUID")
      nonNegativeIntegerFn <- importFrom "Utils.Validation" (importValue "nonNegativeInteger")
      commaListFn <- importFrom "Utils.Validation" (importValue "commaList")
      validMeasurementUnitFn <- importFrom "Utils.Validation" (importValue "validMeasurementUnit")
      allOfFn <- importFrom "Utils.Validation" (importValue "allOf")
      anyOfFn <- importFrom "Utils.Validation" (importValue "anyOf")
      
      getAllEnumValuesFn <- importFrom "Utils.Formatting" (importValue "getAllEnumValues")
      formatCentsToDisplayDollarsFn <- importFrom "Utils.Formatting" (importValue "formatCentsToDisplayDollars")
      
      -- Import enums from the types module
      for_ schema.enums \enum -> do
        _ <- importFrom schema.moduleName (importType enum.name)
        pure unit
      
      -- Generate field configs for each record's fields
      for_ schema.records \rec ->
        for_ rec.fields \field -> do
          writeAndExport $ generateFieldConfigSig field
          writeAndExport $ generateFieldConfig field
      
      -- Generate dropdown configs for each enum
      for_ schema.enums \enum -> do
        writeAndExport $ generateDropdownConfigSig enum
        writeAndExport $ generateDropdownConfig schema enum
  }

generateFieldConfigSig :: FieldDef -> CST.Declaration Void
generateFieldConfigSig field = unsafePartial $
  let
    fnName = camelCase field.name <> "Config"
  in
    declSignature fnName $ typeArrow [typeCtor "String"] (typeCtor "FieldConfig")

generateFieldConfig :: FieldDef -> CST.Declaration Void
generateFieldConfig field = unsafePartial $
  let
    fnName = camelCase field.name <> "Config"
    validationExpr = generateValidationExpr field.validations field.fieldType
    defaultValueExpr = generateDefaultValueExpr field.fieldType
  in
    declValue fnName [binderVar "defaultValue"]
      ( exprRecord
          [ Tuple "label" (exprString field.ui.label)
          , Tuple "placeholder" (exprString field.ui.placeholder)
          , Tuple "defaultValue" defaultValueExpr
          , Tuple "validation" validationExpr
          , Tuple "errorMessage" (exprString field.ui.errorMessage)
          , Tuple "formatInput" (generateFormatInput field.fieldType)
          ]
      )

generateDefaultValueExpr :: FieldType -> CST.Expr Void
generateDefaultValueExpr = unsafePartial $ case _ of
  FMoney ->
    exprApp (exprIdent "formatCentsToDisplayDollars") [exprIdent "defaultValue"]
  _ ->
    exprIdent "defaultValue"

generateValidationExpr :: Array Validation -> FieldType -> CST.Expr Void
generateValidationExpr validations fieldType = unsafePartial $
  let
    rules = Array.catMaybes $ map validationToExpr validations
    typeRules = fieldTypeValidation fieldType
    allRules = rules <> typeRules
  in
    case allRules of
      [] -> 
        exprApp (exprCtor "ValidationRule") 
          [exprLambda [binderWildcard] (exprBool true)]
      [single] -> single
      multiple -> exprApp (exprIdent "allOf") [exprArray multiple]

validationToExpr :: Validation -> Maybe (CST.Expr Void)
validationToExpr = unsafePartial $ case _ of
  Required -> Just $ exprIdent "nonEmpty"
  MaxLength n -> Just $ exprApp (exprIdent "maxLength") [exprInt n]
  MinLength _ -> Nothing
  MinValue _ -> Nothing
  MaxValue _ -> Nothing
  NonNegative -> Just $ exprIdent "nonNegativeInteger"
  Alphanumeric -> Just $ exprIdent "alphanumeric"
  ExtendedAlphanumeric -> Just $ exprIdent "extendedAlphanumeric"
  CommaList -> Just $ exprIdent "commaList"
  Pattern _ -> Nothing
  ValidUrl -> Just $ exprIdent "validUrl"
  ValidUuid -> Just $ exprIdent "validUUID"
  ValidMeasurementUnit -> Just $ exprIdent "validMeasurementUnit"

fieldTypeValidation :: FieldType -> Array (CST.Expr Void)
fieldTypeValidation = unsafePartial $ case _ of
  FMoney -> [exprIdent "dollarAmount"]
  FPercentage -> [exprIdent "percentage"]
  FUrl -> [exprIdent "validUrl"]
  FUuid -> [exprIdent "validUUID"]
  _ -> []

generateFormatInput :: FieldType -> CST.Expr Void
generateFormatInput = unsafePartial $ case _ of
  FString -> exprIdent "trim"
  FInt -> exprIdent "trim"
  FNumber -> exprIdent "trim"
  FMoney -> exprIdent "trim"
  FPercentage -> exprIdent "trim"
  FUrl -> exprIdent "trim"
  FUuid -> exprIdent "trim"
  _ -> exprIdent "identity"

generateDropdownConfigSig :: EnumDef -> CST.Declaration Void
generateDropdownConfigSig enum = unsafePartial $
  let
    fnName = camelCase enum.name <> "Config"
  in
    declSignature fnName $ 
      typeArrow 
        [ typeRecord 
            [ Tuple "defaultValue" (typeCtor "String")
            , Tuple "forNewItem" (typeCtor "Boolean")
            ] 
            Nothing
        ] 
        (typeCtor "DropdownConfig")

generateDropdownConfig :: DomainSchema -> EnumDef -> CST.Declaration Void
generateDropdownConfig schema enum = unsafePartial $
  let
    fnName = camelCase enum.name <> "Config"
  in
    declValue fnName [binderRecord ["defaultValue", "forNewItem"]]
      ( exprRecord
          [ Tuple "label" (exprString enum.name)
          , Tuple "options" $
              exprApp (exprIdent "map")
                [ exprLambda [binderVar "val"] $
                    exprRecord
                      [ Tuple "value" (exprApp (exprIdent "show") [exprIdent "val"])
                      , Tuple "label" (exprApp (exprIdent "show") [exprIdent "val"])
                      ]
                , exprTyped 
                    (exprIdent "getAllEnumValues")
                    (typeApp (typeCtor "Array") [typeCtor enum.name])
                ]
          , Tuple "defaultValue" (exprIdent "defaultValue")
          , Tuple "emptyOption" $
              exprIf (exprIdent "forNewItem")
                (exprApp (exprCtor "Just") 
                  [exprRecord 
                    [ Tuple "value" (exprString "")
                    , Tuple "label" (exprString "Select...")
                    ]
                  ])
                (exprCtor "Nothing")
          ]
      )

-- ============================================================================
-- Form Input Type Generation
-- ============================================================================

generateFormInputModule :: DomainSchema -> GeneratedModule
generateFormInputModule schema =
  { path: moduleNameToPath (schema.moduleName <> ".FormInput")
  , content: printModuleWithOptions printOpts $ unsafePartial $ codegenModule (schema.moduleName <> ".FormInput") do
      importOpen "Prelude"
      
      -- Generate form input types for each record
      for_ schema.records \rec ->
        writeAndExport $ generateFormInputType rec
  }

generateFormInputType :: RecordDef -> CST.Declaration Void
generateFormInputType rec = unsafePartial $
  let
    typeName = rec.name <> "FormInput"
    fields = map (\f -> Tuple f.name (formInputFieldType f.fieldType)) rec.fields
  in
    declType typeName [] (typeRecord fields Nothing)

formInputFieldType :: FieldType -> CST.Type Void
formInputFieldType = unsafePartial $ case _ of
  FNested name -> typeCtor (name <> "FormInput")
  FArray _ -> typeCtor "String"
  _ -> typeCtor "String"

-- ============================================================================
-- Validation Module Generation
-- ============================================================================

generateValidationModule :: DomainSchema -> GeneratedModule
generateValidationModule schema =
  { path: moduleNameToPath schema.validationModuleName
  , content: printModuleWithOptions printOpts $ unsafePartial $ codegenModule schema.validationModuleName do
      importOpen "Prelude"
      
      eitherType <- importFrom "Data.Either" (importType "Either")
      leftCtor <- importFrom "Data.Either" (importCtor "Either" "Left")
      rightCtor <- importFrom "Data.Either" (importCtor "Either" "Right")
      
      vType <- importFrom "Data.Validation.Semigroup" (importType "V")
      invalidFn <- importFrom "Data.Validation.Semigroup" (importValue "invalid")
      toEitherFn <- importFrom "Data.Validation.Semigroup" (importValue "toEither")
      andThenFn <- importFrom "Data.Validation.Semigroup" (importValue "andThen")
      
      joinWithFn <- importFrom "Data.String" (importValue "joinWith")
      trimFn <- importFrom "Data.String" (importValue "trim")
      
      intFromStringFn <- importFrom "Data.Int" (importValue "fromString")
      numFromStringFn <- importFrom "Data.Number" (importValue "fromString")
      
      discreteCtor <- importFrom "Data.Finance.Money" (importCtor "Discrete" "Discrete")
      floorFn <- importFrom "Data.Int" (importValue "floor")
      
      parseUUIDFn <- importFrom "Types.UUID" (importValue "parseUUID")
      parseCommaListFn <- importFrom "Utils.Formatting" (importValue "parseCommaList")
      
      -- Import types and form inputs
      for_ schema.enums \enum -> do
        _ <- importFrom schema.moduleName (importType enum.name)
        pure unit
        
      for_ schema.records \rec -> do
        _ <- importFrom schema.moduleName (importTypeAll rec.name)
        _ <- importFrom (schema.moduleName <> ".FormInput") (importType (rec.name <> "FormInput"))
        pure unit
      
      -- Generate base validators
      writeAndExport generateValidateString
      writeAndExport generateValidateInt
      writeAndExport generateValidateNumber
      writeAndExport generateValidateMoney
      writeAndExport generateValidatePercentage
      writeAndExport generateValidateUUID
      writeAndExport generateValidateUrl
      
      -- Generate enum validators
      for_ schema.enums \enum ->
        writeAndExport $ generateEnumValidator enum
      
      -- Generate record validators
      for_ schema.records \rec ->
        writeAndExport $ generateRecordValidator schema rec
  }

generateValidateString :: CST.Declaration Void
generateValidateString = unsafePartial $
  declValue "validateString" [binderVar "fieldName", binderVar "str"]
    ( exprIf 
        (exprOp (exprApp (exprIdent "trim") [exprIdent "str"]) [binaryOp "==" (exprString "")])
        (exprApp (exprIdent "invalid") 
          [exprArray [exprOp (exprIdent "fieldName") [binaryOp "<>" (exprString " is required")]]])
        (exprApp (exprIdent "pure") [exprIdent "str"])
    )

generateValidateInt :: CST.Declaration Void
generateValidateInt = unsafePartial $
  declValue "validateInt" [binderVar "fieldName", binderVar "str"]
    ( exprCase [exprApp (exprIdent "fromString") [exprApp (exprIdent "trim") [exprIdent "str"]]]
        [ caseBranch [binderCtor "Just" [binderVar "n"]] $
            exprIf (exprOp (exprIdent "n") [binaryOp ">=" (exprInt 0)])
              (exprApp (exprIdent "pure") [exprIdent "n"])
              (exprApp (exprIdent "invalid") 
                [exprArray [exprOp (exprIdent "fieldName") [binaryOp "<>" (exprString " must be non-negative")]]])
        , caseBranch [binderWildcard] $
            exprApp (exprIdent "invalid") 
              [exprArray [exprOp (exprIdent "fieldName") [binaryOp "<>" (exprString " must be a valid integer")]]]
        ]
    )

generateValidateNumber :: CST.Declaration Void
generateValidateNumber = unsafePartial $
  declValue "validateNumber" [binderVar "fieldName", binderVar "str"]
    ( exprCase [exprApp (exprIdent "fromString") [exprApp (exprIdent "trim") [exprIdent "str"]]]
        [ caseBranch [binderCtor "Just" [binderVar "n"]] $
            exprIf (exprOp (exprIdent "n") [binaryOp ">=" (exprNumber 0.0)])
              (exprApp (exprIdent "pure") [exprIdent "n"])
              (exprApp (exprIdent "invalid") 
                [exprArray [exprOp (exprIdent "fieldName") [binaryOp "<>" (exprString " must be non-negative")]]])
        , caseBranch [binderWildcard] $
            exprApp (exprIdent "invalid") 
              [exprArray [exprOp (exprIdent "fieldName") [binaryOp "<>" (exprString " must be a valid number")]]]
        ]
    )

generateValidateMoney :: CST.Declaration Void
generateValidateMoney = unsafePartial $
  declValue "validateMoney" [binderVar "fieldName", binderVar "str"]
    ( exprCase [exprApp (exprIdent "fromString") [exprApp (exprIdent "trim") [exprIdent "str"]]]
        [ caseBranch [binderCtor "Just" [binderVar "n"]] $
            exprIf (exprOp (exprIdent "n") [binaryOp ">=" (exprNumber 0.0)])
              (exprApp (exprIdent "pure") 
                [exprApp (exprCtor "Discrete") 
                  [exprApp (exprIdent "floor") 
                    [exprOp (exprIdent "n") [binaryOp "*" (exprNumber 100.0)]]
                  ]
                ])
              (exprApp (exprIdent "invalid") 
                [exprArray [exprOp (exprIdent "fieldName") [binaryOp "<>" (exprString " must be non-negative")]]])
        , caseBranch [binderWildcard] $
            exprApp (exprIdent "invalid") 
              [exprArray [exprOp (exprIdent "fieldName") [binaryOp "<>" (exprString " must be a valid dollar amount")]]]
        ]
    )

generateValidatePercentage :: CST.Declaration Void
generateValidatePercentage = unsafePartial $
  declValue "validatePercentage" [binderVar "fieldName", binderVar "str"]
    ( exprIf 
        (exprOp (exprApp (exprIdent "trim") [exprIdent "str"]) [binaryOp "==" (exprString "")])
        (exprApp (exprIdent "invalid") 
          [exprArray [exprOp (exprIdent "fieldName") [binaryOp "<>" (exprString " is required")]]])
        (exprApp (exprIdent "pure") [exprIdent "str"])
    )

generateValidateUUID :: CST.Declaration Void
generateValidateUUID = unsafePartial $
  declValue "validateUUID" [binderVar "fieldName", binderVar "str"]
    ( exprCase [exprApp (exprIdent "parseUUID") [exprApp (exprIdent "trim") [exprIdent "str"]]]
        [ caseBranch [binderCtor "Just" [binderVar "uuid"]] $
            exprApp (exprIdent "pure") [exprIdent "uuid"]
        , caseBranch [binderWildcard] $
            exprApp (exprIdent "invalid") 
              [exprArray [exprOp (exprIdent "fieldName") [binaryOp "<>" (exprString " must be a valid UUID")]]]
        ]
    )

generateValidateUrl :: CST.Declaration Void
generateValidateUrl = unsafePartial $
  declValue "validateUrl" [binderVar "fieldName", binderVar "str"]
    ( exprIf 
        (exprOp (exprApp (exprIdent "trim") [exprIdent "str"]) [binaryOp "==" (exprString "")])
        (exprApp (exprIdent "invalid") 
          [exprArray [exprOp (exprIdent "fieldName") [binaryOp "<>" (exprString " is required")]]])
        (exprApp (exprIdent "pure") [exprIdent "str"])
    )

generateEnumValidator :: EnumDef -> CST.Declaration Void
generateEnumValidator enum = unsafePartial $
  let
    fnName = "validate" <> enum.name
  in
    declValue fnName [binderVar "fieldName", binderVar "str"]
      ( exprCase [exprIdent "str"]
          ( (NEA.toArray $ map (\v ->
              caseBranch [binderString v] (exprApp (exprIdent "pure") [exprCtor v])
            ) enum.variants) <>
            [ caseBranch [binderWildcard] $
                exprApp (exprIdent "invalid") 
                  [exprArray 
                    [exprOp (exprIdent "fieldName") 
                      [binaryOp "<>" (exprString $ " has invalid " <> enum.name <> " value")]
                    ]
                  ]
            ]
          )
      )

generateRecordValidator :: DomainSchema -> RecordDef -> CST.Declaration Void
generateRecordValidator schema rec = unsafePartial $
  let
    fnName = "validate" <> rec.name
  in
    declValue fnName [binderVar "input"]
      ( exprCase 
          [exprApp (exprIdent "toEither") [generateValidationChain schema rec]]
          [ caseBranch [binderCtor "Left" [binderVar "errors"]] $
              exprApp (exprCtor "Left") 
                [exprApp (exprIdent "joinWith") [exprString ", ", exprIdent "errors"]]
          , caseBranch [binderCtor "Right" [binderVar "result"]] $
              exprApp (exprCtor "Right") [exprIdent "result"]
          ]
      )

generateValidationChain :: DomainSchema -> RecordDef -> CST.Expr Void
generateValidationChain schema rec = unsafePartial $
  case Array.uncons rec.fields of
    Nothing -> 
      exprApp (exprIdent "pure") 
        [exprApp (exprCtor rec.name) [exprRecord ([] :: Array (Tuple String (CST.Expr Void)))]]
    Just { head: firstField, tail: restFields } ->
      buildValidationChain schema rec.name firstField restFields

buildValidationChain :: DomainSchema -> String -> FieldDef -> Array FieldDef -> CST.Expr Void
buildValidationChain schema recName firstField restFields = unsafePartial $
  let
    firstValidation = generateSingleFieldValidation schema firstField
  in
    case Array.uncons restFields of
      Nothing ->
        -- Single field - validate and build record
        -- andThen firstValidation (\firstField -> pure (RecName { field: firstField }))
        exprApp
          (exprApp (exprIdent "andThen") [firstValidation])
          [ exprLambda [binderVar (camelCase firstField.name)] $
              exprApp (exprIdent "pure")
                [ exprApp (exprCtor recName)
                    [ exprRecord [Tuple firstField.name (exprIdent (camelCase firstField.name))]
                    ]
                ]
          ]
      Just { head: _, tail: _ } ->
        -- Multiple fields - chain them
        let allFields = Array.cons firstField restFields
        in buildNestedAndThen schema recName allFields

buildNestedAndThen :: DomainSchema -> String -> Array FieldDef -> CST.Expr Void
buildNestedAndThen schema recName fields = unsafePartial $
  case Array.uncons fields of
    Nothing ->
      exprApp (exprIdent "pure")
        [exprApp (exprCtor recName) [exprRecord ([] :: Array (Tuple String (CST.Expr Void)))]]
    Just { head: field, tail: rest } ->
      exprApp
        (exprApp (exprIdent "andThen") [generateSingleFieldValidation schema field])
        [ exprLambda [binderVar (camelCase field.name)] $
            case Array.uncons rest of
              Nothing ->
                -- Last field
                exprApp (exprIdent "pure")
                  [ exprApp (exprCtor recName)
                      [ exprRecord $ map (\f -> Tuple f.name (exprIdent (camelCase f.name))) fields
                      ]
                  ]
              Just _ ->
                -- More fields to go
                buildNestedAndThenContinue schema recName fields rest
        ]

buildNestedAndThenContinue :: DomainSchema -> String -> Array FieldDef -> Array FieldDef -> CST.Expr Void
buildNestedAndThenContinue schema recName allFields remainingFields = unsafePartial $
  case Array.uncons remainingFields of
    Nothing ->
      exprApp (exprIdent "pure")
        [ exprApp (exprCtor recName)
            [ exprRecord $ map (\f -> Tuple f.name (exprIdent (camelCase f.name))) allFields
            ]
        ]
    Just { head: field, tail: rest } ->
      exprApp
        (exprApp (exprIdent "andThen") [generateSingleFieldValidation schema field])
        [ exprLambda [binderVar (camelCase field.name)] $
            buildNestedAndThenContinue schema recName allFields rest
        ]

generateSingleFieldValidation :: DomainSchema -> FieldDef -> CST.Expr Void
generateSingleFieldValidation schema field = unsafePartial $
  let
    accessor = exprDot (exprIdent "input") [field.name]
    validatorName = fieldTypeToValidator field.fieldType
  in
    exprApp (exprIdent validatorName) [exprString field.ui.label, accessor]

fieldTypeToValidator :: FieldType -> String
fieldTypeToValidator = case _ of
  FString -> "validateString"
  FInt -> "validateInt"
  FNumber -> "validateNumber"
  FBool -> "validateBool"
  FMoney -> "validateMoney"
  FPercentage -> "validatePercentage"
  FUrl -> "validateUrl"
  FUuid -> "validateUUID"
  FDateTime -> "validateDateTime"
  FEnum name -> "validate" <> name
  FArray _ -> "validateArray"
  FMaybe _ -> "validateMaybe"
  FNested name -> "validate" <> name

-- ============================================================================
-- Utilities
-- ============================================================================

moduleNameToPath :: String -> String
moduleNameToPath modName = 
  "src/" <> String.replaceAll (String.Pattern ".") (String.Replacement "/") modName <> ".purs"

camelCase :: String -> String
camelCase s = case String.uncons s of
  Nothing -> s
  Just { head, tail } -> String.toLower (String.singleton head) <> tail