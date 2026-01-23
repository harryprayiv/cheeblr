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
import Tidy.Codegen (PrintOptions, binaryOp, binderCtor, binderInt, binderParens, binderRecord, binderString, binderVar, binderWildcard, caseBranch, dataCtor, declData, declDerive, declInstance, declNewtype, declSignature, declType, declValue, defaultPrintOptions, doBind, exprApp, exprArray, exprBool, exprCase, exprCtor, exprDo, exprDot, exprIdent, exprIf, exprInt, exprLambda, exprNumber, exprOp, exprRecord, exprString, exprTyped, instValue, printModuleWithOptions, typeApp, typeArrow, typeCtor, typeRecord, typeWildcard)
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
      fType <- importFrom "Foreign" (importType "F")

      readPropFn <- importFrom "Foreign.Index" (importValue "readProp")

      usdType <- importFrom "Data.Finance.Currency" (importType "USD")
      discreteType <- importFrom "Data.Finance.Money" (importType "Discrete")
      discreteCtor <- importFrom "Data.Finance.Money" (importCtor "Discrete" "Discrete")

      uuidType <- importFrom "Types.UUID" (importType "UUID")
      parseUUIDFn <- importFrom "Types.UUID" (importValue "parseUUID")

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
    [ instValue "writeImpl" [binderParens (binderCtor rec.name [binderVar "r"])] $
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
                  [ exprRecord $ map (\f -> Tuple f.name (generateReadFieldExpr f)) rec.fields
                  ]
              ]
          )
    ]

generateReadField :: DomainSchema -> FieldDef -> CST.DoStatement Void
generateReadField schema field = unsafePartial $
  let
    varName = snakeToCamel field.name
    baseExpr = exprOp
      (exprApp (exprIdent "readProp") [exprString field.name, exprIdent "json"])
      [binaryOp ">>=" (exprIdent "readImpl")]
    readExpr = case field.fieldType of
      FMoney -> exprTyped baseExpr (typeApp (typeCtor "F") [typeCtor "Int"])
      _ -> baseExpr
  in
    doBind (binderVar varName) readExpr

generateReadFieldExpr :: FieldDef -> CST.Expr Void
generateReadFieldExpr field = unsafePartial $
  let
    varExpr = exprIdent (snakeToCamel field.name)
  in
    case field.fieldType of
      FMoney -> exprApp (exprCtor "Discrete") [varExpr]
      _ -> varExpr

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
      validationRuleCtor <- importFrom "Types.Common" (importCtor "ValidationRule" "ValidationRule")

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

      for_ schema.enums \enum -> do
        _ <- importFrom schema.moduleName (importType enum.name)
        pure unit

      for_ schema.records \rec ->
        for_ rec.fields \field -> do
          case field.fieldType of
            FEnum _ -> pure unit
            FNested _ -> pure unit
            _ -> do
              writeAndExport $ generateFieldConfigSig field
              writeAndExport $ generateFieldConfig field

      for_ schema.enums \enum -> do
        writeAndExport $ generateDropdownConfigSig enum
        writeAndExport $ generateDropdownConfig schema enum
  }

generateFieldConfigSig :: FieldDef -> CST.Declaration Void
generateFieldConfigSig field = unsafePartial $
  let
    fnName = snakeToCamel field.name <> "Config"
  in
    declSignature fnName $ typeArrow [typeCtor "String"] (typeCtor "FieldConfig")

generateFieldConfig :: FieldDef -> CST.Declaration Void
generateFieldConfig field = unsafePartial $
  let
    fnName = snakeToCamel field.name <> "Config"
    validationExpr = generateConfigValidationExpr field.validations field.fieldType
    defaultValueExpr = generateDefaultValueExpr field.fieldType
    formatInputExpr = generateFormatInput field.fieldType field.validations
  in
    declValue fnName [binderVar "defaultValue"]
      ( exprRecord
          [ Tuple "label" (exprString field.ui.label)
          , Tuple "placeholder" (exprString field.ui.placeholder)
          , Tuple "defaultValue" defaultValueExpr
          , Tuple "validation" validationExpr
          , Tuple "errorMessage" (exprString field.ui.errorMessage)
          , Tuple "formatInput" formatInputExpr
          ]
      )

generateDefaultValueExpr :: FieldType -> CST.Expr Void
generateDefaultValueExpr = unsafePartial $ case _ of
  FMoney ->
    exprApp (exprIdent "formatCentsToDisplayDollars") [exprIdent "defaultValue"]
  _ ->
    exprIdent "defaultValue"

generateConfigValidationExpr :: Array Validation -> FieldType -> CST.Expr Void
generateConfigValidationExpr validations fieldType = unsafePartial $
  let
    hasValidations = not (Array.null validations)
    hasRequired = Array.elem Required validations
    
    explicitRules = Array.catMaybes $ map validationToExpr validations
    
    typeRules = if hasRequired then fieldTypeValidation fieldType else []
    
    allRules = explicitRules <> typeRules
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

generateFormatInput :: FieldType -> Array Validation -> CST.Expr Void
generateFormatInput fieldType validations = unsafePartial $
  case fieldType of
    FArray _ -> exprIdent "identity"
    _ | Array.null validations -> exprIdent "identity"
    _ -> exprIdent "trim"

generateDropdownConfigSig :: EnumDef -> CST.Declaration Void
generateDropdownConfigSig enum = unsafePartial $
  let
    fnName = lowerFirst enum.displayName <> "Config"
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
    fnName = lowerFirst enum.displayName <> "Config"
  in
    declValue fnName [binderRecord ["defaultValue", "forNewItem"]]
      ( exprRecord
          [ Tuple "label" (exprString enum.displayName)
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

generateFormInputModule :: DomainSchema -> GeneratedModule
generateFormInputModule schema =
  { path: moduleNameToPath (schema.moduleName <> ".FormInput")
  , content: printModuleWithOptions printOpts $ unsafePartial $ codegenModule (schema.moduleName <> ".FormInput") do
      importOpen "Prelude"

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

generateValidationModule :: DomainSchema -> GeneratedModule
generateValidationModule schema =
  { path: moduleNameToPath schema.validationModuleName
  , content: printModuleWithOptions printOpts $ unsafePartial $ codegenModule schema.validationModuleName do
      importOpen "Prelude"

      eitherType <- importFrom "Data.Either" (importType "Either")
      leftCtor <- importFrom "Data.Either" (importCtor "Either" "Left")
      rightCtor <- importFrom "Data.Either" (importCtor "Either" "Right")

      maybeType <- importFrom "Data.Maybe" (importType "Maybe")
      justCtor <- importFrom "Data.Maybe" (importCtor "Maybe" "Just")
      nothingCtor <- importFrom "Data.Maybe" (importCtor "Maybe" "Nothing")

      vType <- importFrom "Data.Validation.Semigroup" (importType "V")
      invalidFn <- importFrom "Data.Validation.Semigroup" (importValue "invalid")
      toEitherFn <- importFrom "Data.Validation.Semigroup" (importValue "toEither")
      andThenFn <- importFrom "Data.Validation.Semigroup" (importValue "andThen")

      joinWithFn <- importFrom "Data.String" (importValue "joinWith")
      trimFn <- importFrom "Data.String" (importValue "trim")

      intFromStringFn <- importFrom "Data.Int" (importValue "fromString")
      floorFn <- importFrom "Data.Int" (importValue "floor")

      numberFromStringFn <- importFrom "Data.Number" (importValue "Number.fromString")

      discreteCtor <- importFrom "Data.Finance.Money" (importCtor "Discrete" "Discrete")
      discreteType <- importFrom "Data.Finance.Money" (importType "Discrete")
      usdType <- importFrom "Data.Finance.Currency" (importType "USD")

      uuidType <- importFrom "Types.UUID" (importType "UUID")
      parseUUIDFn <- importFrom "Types.UUID" (importValue "parseUUID")
      parseCommaListFn <- importFrom "Utils.Formatting" (importValue "parseCommaList")

      for_ schema.enums \enum -> do
        _ <- importFrom schema.moduleName (importTypeAll enum.name)
        pure unit

      for_ schema.records \rec -> do
        _ <- importFrom schema.moduleName (importTypeAll rec.name)
        _ <- importFrom (schema.moduleName <> ".FormInput") (importType (rec.name <> "FormInput"))
        pure unit

      writeAndExport $ generateValidateStringSig
      writeAndExport generateValidateString
      writeAndExport $ generateValidateIntSig
      writeAndExport generateValidateInt
      writeAndExport $ generateValidateNumberSig
      writeAndExport generateValidateNumber
      writeAndExport $ generateValidateMoneySig
      writeAndExport generateValidateMoney
      writeAndExport $ generateValidatePercentageSig
      writeAndExport generateValidatePercentage
      writeAndExport $ generateValidateUUIDSig
      writeAndExport generateValidateUUID
      writeAndExport $ generateValidateUrlSig
      writeAndExport generateValidateUrl

      for_ schema.enums \enum -> do
        writeAndExport $ generateEnumValidatorSig enum
        writeAndExport $ generateEnumValidator enum

      for_ schema.records \rec -> do
        writeAndExport $ generateRecordValidatorSig schema rec
        writeAndExport $ generateRecordValidator schema rec
  }

generateValidateStringSig :: CST.Declaration Void
generateValidateStringSig = unsafePartial $
  declSignature "validateString" $
    typeArrow 
      [ typeCtor "String"
      , typeCtor "String" 
      ]
      (typeApp (typeCtor "V") [typeApp (typeCtor "Array") [typeCtor "String"], typeCtor "String"])

generateValidateString :: CST.Declaration Void
generateValidateString = unsafePartial $
  declValue "validateString" [binderVar "fieldName", binderVar "str"]
    ( exprIf
        (exprOp (exprApp (exprIdent "trim") [exprIdent "str"]) [binaryOp "==" (exprString "")])
        (exprApp (exprIdent "invalid")
          [exprArray [exprOp (exprIdent "fieldName") [binaryOp "<>" (exprString " is required")]]])
        (exprApp (exprIdent "pure") [exprIdent "str"])
    )

generateValidateIntSig :: CST.Declaration Void
generateValidateIntSig = unsafePartial $
  declSignature "validateInt" $
    typeArrow 
      [ typeCtor "String"
      , typeCtor "String" 
      ]
      (typeApp (typeCtor "V") [typeApp (typeCtor "Array") [typeCtor "String"], typeCtor "Int"])

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

generateValidateNumberSig :: CST.Declaration Void
generateValidateNumberSig = unsafePartial $
  declSignature "validateNumber" $
    typeArrow 
      [ typeCtor "String"
      , typeCtor "String" 
      ]
      (typeApp (typeCtor "V") [typeApp (typeCtor "Array") [typeCtor "String"], typeCtor "Number"])

generateValidateNumber :: CST.Declaration Void
generateValidateNumber = unsafePartial $
  declValue "validateNumber" [binderVar "fieldName", binderVar "str"]
    ( exprCase [exprApp (exprIdent "Number.fromString") [exprApp (exprIdent "trim") [exprIdent "str"]]]
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

generateValidateMoneySig :: CST.Declaration Void
generateValidateMoneySig = unsafePartial $
  declSignature "validateMoney" $
    typeArrow 
      [ typeCtor "String"
      , typeCtor "String" 
      ]
      (typeApp (typeCtor "V") 
        [ typeApp (typeCtor "Array") [typeCtor "String"]
        , typeApp (typeCtor "Discrete") [typeCtor "USD"]
        ])

generateValidateMoney :: CST.Declaration Void
generateValidateMoney = unsafePartial $
  declValue "validateMoney" [binderVar "fieldName", binderVar "str"]
    ( exprCase [exprApp (exprIdent "Number.fromString") [exprApp (exprIdent "trim") [exprIdent "str"]]]
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

generateValidatePercentageSig :: CST.Declaration Void
generateValidatePercentageSig = unsafePartial $
  declSignature "validatePercentage" $
    typeArrow 
      [ typeCtor "String"
      , typeCtor "String" 
      ]
      (typeApp (typeCtor "V") [typeApp (typeCtor "Array") [typeCtor "String"], typeCtor "String"])

generateValidatePercentage :: CST.Declaration Void
generateValidatePercentage = unsafePartial $
  declValue "validatePercentage" [binderVar "fieldName", binderVar "str"]
    ( exprIf
        (exprOp (exprApp (exprIdent "trim") [exprIdent "str"]) [binaryOp "==" (exprString "")])
        (exprApp (exprIdent "invalid")
          [exprArray [exprOp (exprIdent "fieldName") [binaryOp "<>" (exprString " is required")]]])
        (exprApp (exprIdent "pure") [exprIdent "str"])
    )

generateValidateUUIDSig :: CST.Declaration Void
generateValidateUUIDSig = unsafePartial $
  declSignature "validateUUID" $
    typeArrow 
      [ typeCtor "String"
      , typeCtor "String" 
      ]
      (typeApp (typeCtor "V") [typeApp (typeCtor "Array") [typeCtor "String"], typeCtor "UUID"])

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

generateValidateUrlSig :: CST.Declaration Void
generateValidateUrlSig = unsafePartial $
  declSignature "validateUrl" $
    typeArrow 
      [ typeCtor "String"
      , typeCtor "String" 
      ]
      (typeApp (typeCtor "V") [typeApp (typeCtor "Array") [typeCtor "String"], typeCtor "String"])

generateValidateUrl :: CST.Declaration Void
generateValidateUrl = unsafePartial $
  declValue "validateUrl" [binderVar "fieldName", binderVar "str"]
    ( exprIf
        (exprOp (exprApp (exprIdent "trim") [exprIdent "str"]) [binaryOp "==" (exprString "")])
        (exprApp (exprIdent "invalid")
          [exprArray [exprOp (exprIdent "fieldName") [binaryOp "<>" (exprString " is required")]]])
        (exprApp (exprIdent "pure") [exprIdent "str"])
    )

generateEnumValidatorSig :: EnumDef -> CST.Declaration Void
generateEnumValidatorSig enum = unsafePartial $
  let
    fnName = "validate" <> enum.name
  in
    declSignature fnName $
      typeArrow 
        [ typeCtor "String"
        , typeCtor "String" 
        ]
        (typeApp (typeCtor "V") [typeApp (typeCtor "Array") [typeCtor "String"], typeCtor enum.name])

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

data FieldValidationKind
  = ValidatedRequired    -- Required field, validate with andThen
  | ValidatedOptional    -- Has validations but not Required
  | PassThrough          -- No validations, pass through directly
  | ArrayPassThrough     -- Array field, use parseCommaList
  | NestedValidation     -- Nested record, call nested validator

getFieldValidationKind :: FieldDef -> FieldValidationKind
getFieldValidationKind field = case field.fieldType of
  FNested _ -> NestedValidation
  FArray _ -> ArrayPassThrough
  _ | Array.elem Required field.validations -> ValidatedRequired
    | not (Array.null field.validations) -> ValidatedOptional
    | otherwise -> PassThrough

isNestedRecord :: DomainSchema -> String -> Boolean
isNestedRecord schema recName =
  Array.any (\rec -> Array.any (isNestedField recName) rec.fields) schema.records
  where
  isNestedField name field = case field.fieldType of
    FNested n -> n == name
    _ -> false

generateRecordValidatorSig :: DomainSchema -> RecordDef -> CST.Declaration Void
generateRecordValidatorSig schema rec = unsafePartial $
  let
    fnName = "validate" <> rec.name
    inputType = typeCtor (rec.name <> "FormInput")
    isNested = isNestedRecord schema rec.name
    returnType = 
      if isNested then
        typeApp (typeCtor "V") 
          [ typeApp (typeCtor "Array") [typeCtor "String"]
          , typeCtor rec.name
          ]
      else
        typeApp (typeCtor "Either") 
          [ typeCtor "String"
          , typeCtor rec.name
          ]
  in
    declSignature fnName $ typeArrow [inputType] returnType

generateRecordValidator :: DomainSchema -> RecordDef -> CST.Declaration Void
generateRecordValidator schema rec = unsafePartial $
  let
    fnName = "validate" <> rec.name
    isNested = isNestedRecord schema rec.name
    
    validatedFields = Array.filter (\f -> 
      case getFieldValidationKind f of
        ValidatedRequired -> true
        NestedValidation -> true
        _ -> false
      ) rec.fields
    
    passThroughFields = Array.filter (\f ->
      case getFieldValidationKind f of
        PassThrough -> true
        ValidatedOptional -> true
        ArrayPassThrough -> true
        _ -> false
      ) rec.fields
  in
    if isNested then
      declValue fnName [binderVar "input"]
        (generateValidationChainForNested schema rec validatedFields passThroughFields)
    else
      declValue fnName [binderVar "input"]
        ( exprCase
            [exprApp (exprIdent "toEither") [generateValidationChainForNested schema rec validatedFields passThroughFields]]
            [ caseBranch [binderCtor "Left" [binderVar "errors"]] $
                exprApp (exprCtor "Left")
                  [exprApp (exprIdent "joinWith") [exprString ", ", exprIdent "errors"]]
            , caseBranch [binderCtor "Right" [binderVar "result"]] $
                exprApp (exprCtor "Right") [exprIdent "result"]
            ]
        )

generateValidationChainForNested :: DomainSchema -> RecordDef -> Array FieldDef -> Array FieldDef -> CST.Expr Void
generateValidationChainForNested schema rec validatedFields passThroughFields = unsafePartial $
  case Array.uncons validatedFields of
    Nothing ->
      exprApp (exprIdent "pure")
        [exprApp (exprCtor rec.name)
          [exprRecord $ map (\f -> Tuple f.name (generatePassThroughExpr f)) rec.fields]
        ]
    Just { head: firstField, tail: restValidated } ->
      buildAndThenChain schema rec.name firstField restValidated passThroughFields rec.fields

buildAndThenChain :: DomainSchema -> String -> FieldDef -> Array FieldDef -> Array FieldDef -> Array FieldDef -> CST.Expr Void
buildAndThenChain schema recName currentField remainingValidated passThroughFields allFields = unsafePartial $
  let
    validationExpr = generateSingleFieldValidation schema currentField
    varName = snakeToCamel currentField.name
  in
    exprApp
      (exprApp (exprIdent "andThen") [validationExpr])
      [ exprLambda [binderVar varName] $
          case Array.uncons remainingValidated of
            Nothing ->
              exprApp (exprIdent "pure")
                [ exprApp (exprCtor recName)
                    [ exprRecord $ map (\f -> Tuple f.name (fieldToRecordExpr f)) allFields
                    ]
                ]
            Just { head: nextField, tail: rest } ->
              buildAndThenChain schema recName nextField rest passThroughFields allFields
      ]

fieldToRecordExpr :: FieldDef -> CST.Expr Void
fieldToRecordExpr field = unsafePartial $
  case getFieldValidationKind field of
    ValidatedRequired -> exprIdent (snakeToCamel field.name)
    NestedValidation -> exprIdent (snakeToCamel field.name)
    ArrayPassThrough -> 
      exprApp (exprIdent "parseCommaList") 
        [exprDot (exprIdent "input") [field.name]]
    PassThrough -> exprDot (exprIdent "input") [field.name]
    ValidatedOptional -> exprDot (exprIdent "input") [field.name]

generatePassThroughExpr :: FieldDef -> CST.Expr Void
generatePassThroughExpr field = unsafePartial $
  case field.fieldType of
    FArray _ -> exprApp (exprIdent "parseCommaList") [exprDot (exprIdent "input") [field.name]]
    _ -> exprDot (exprIdent "input") [field.name]

generateSingleFieldValidation :: DomainSchema -> FieldDef -> CST.Expr Void
generateSingleFieldValidation schema field = unsafePartial $
  let
    accessor = exprDot (exprIdent "input") [field.name]
    validatorName = fieldTypeToValidator field.fieldType
  in
    case field.fieldType of
      FNested _ -> exprApp (exprIdent validatorName) [accessor]
      _ -> exprApp (exprIdent validatorName) [exprString field.ui.label, accessor]

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

moduleNameToPath :: String -> String
moduleNameToPath modName =
  "src/" <> String.replaceAll (String.Pattern ".") (String.Replacement "/") modName <> ".purs"

snakeToCamel :: String -> String
snakeToCamel s =
  let
    parts = String.split (String.Pattern "_") s
  in
    case Array.uncons parts of
      Nothing -> s
      Just { head, tail } ->
        lowerFirst head <> String.joinWith "" (map capitalize tail)

lowerFirst :: String -> String
lowerFirst s = case String.uncons s of
  Nothing -> s
  Just { head, tail } -> String.toLower (String.singleton head) <> tail

capitalize :: String -> String
capitalize s = case String.uncons s of
  Nothing -> s
  Just { head, tail } -> String.toUpper (String.singleton head) <> tail

camelCase :: String -> String
camelCase = lowerFirst