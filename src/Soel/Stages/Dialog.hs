{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards   #-}

module Soel.Stages.Dialog
  ( resolveAmbiguities
  , autoResolveAll
  , autoResolve
  ) where

import Control.Monad.IO.Class (liftIO)
import Control.Monad.Reader (ask)
import Data.Aeson (eitherDecode', encode, Value(..), (.:), object, (.=), toJSON)
import Data.Aeson.Types (parseMaybe)
import qualified Data.ByteString.Lazy as BL
import qualified Data.ByteString.Lazy.Char8 as BLC
import qualified Data.Text.Encoding as TE
import Data.List (maximumBy)
import Data.Maybe (isJust)
import Data.Ord (comparing)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import System.Console.Haskeline (runInputT, defaultSettings, getInputLine)
import System.IO (stderr, hFlush)
import Text.Read (readMaybe)

import Soel.Types (App, SoelConfig(..), requireApiKeyM)
import Soel.Config (CompilerConfig(..), OpenRouterConfig(..))
import Soel.IR.Types
import Soel.IR.Validate ()  -- import ToJSON/FromJSON orphan instances
import Soel.LLM.OpenRouter (llmRequest, extractJSON, LLMRequestOptions(..), LLMMessage(..), LLMRole(..))
import Soel.LLM.Prompts (getPrompt)
import Soel.Utils.Logger (logStage, logInfo, logWarn, logSuccess)

-- | Interactive dialog loop to resolve ambiguities with the user.
-- Returns resolved ambiguities with user's choices.
resolveAmbiguities :: [Ambiguity] -> Text -> App [Ambiguity]
resolveAmbiguities ambs sourceText = do
  if null ambs
    then do
      liftIO $ logInfo "No ambiguities to resolve"
      pure ambs
    else do
      cfg <- ask
      let maxRounds = ccMaxDialogRounds (cfgCompiler cfg)

      liftIO $ logStage "Dialogical ambiguity resolution"
      liftIO $ TIO.hPutStr stderr $
        "\n  " <> T.pack (show (length ambs)) <> " ambiguities need resolution. "
        <> "(max " <> T.pack (show maxRounds) <> " rounds)\n\n"
      liftIO $ hFlush stderr

      go cfg 0 maxRounds ambs []
  where
    go :: SoelConfig -> Int -> Int -> [Ambiguity] -> [Ambiguity] -> App [Ambiguity]
    go _   _     _         []         resolved = do
      let resCount = length (filter (isJust . ambResolution) resolved)
          total    = length resolved
      liftIO $ logSuccess $ "Resolved " <> T.pack (show resCount)
                         <> "/" <> T.pack (show total) <> " ambiguities"
      pure (reverse resolved)
    go cfg rnd maxRounds (amb:rest) resolved
      | rnd >= maxRounds = do
          liftIO $ logWarn $ "Max dialog rounds (" <> T.pack (show maxRounds)
                          <> ") reached, auto-resolving remaining"
          let remaining = map autoResolve (amb:rest)
          let resCount = length (filter (isJust . ambResolution) (resolved ++ remaining))
              total    = length resolved + length remaining
          liftIO $ logSuccess $ "Resolved " <> T.pack (show resCount)
                             <> "/" <> T.pack (show total) <> " ambiguities"
          pure (reverse resolved ++ remaining)
      | otherwise = do
          -- Show the ambiguity
          liftIO $ TIO.hPutStr stderr $
            "\n--- Ambiguity " <> ambId amb <> " [" <> categoryText (ambCategory amb) <> "] ---\n"
            <> "  " <> ambDescription amb <> "\n\n"
          liftIO $ hFlush stderr

          -- Show numbered options
          liftIO $ mapM_ (\(i, opt) -> do
            let conf = T.pack (show (round (aoConfidence opt * 100) :: Int)) <> "%"
            TIO.hPutStr stderr $
              "  " <> T.pack (show i) <> ") " <> aoLabel opt <> " (" <> conf <> ")\n"
            if aoDescription opt /= aoLabel opt
              then TIO.hPutStr stderr $ "     " <> aoDescription opt <> "\n"
              else pure ()
            ) (zip ([1..] :: [Int]) (ambOptions amb))

          let customIdx = length (ambOptions amb) + 1
          liftIO $ TIO.hPutStr stderr $
            "  " <> T.pack (show customIdx) <> ") Custom response...\n"
          liftIO $ hFlush stderr

          -- Get user input via haskeline
          mAnswer <- liftIO $ runInputT defaultSettings $ getInputLine "\n  Your choice: "

          case mAnswer of
            Nothing -> do
              -- EOF / no input => auto-resolve
              let resolved' = autoResolve amb
              liftIO $ TIO.hPutStr stderr "  -> Auto-resolved with highest confidence option\n"
              liftIO $ hFlush stderr
              go cfg (rnd + 1) maxRounds rest (resolved' : resolved)

            Just answer -> do
              let trimmed = T.strip (T.pack answer)
                  mChoice = readMaybe answer :: Maybe Int

              case mChoice of
                Just choice
                  | choice >= 1 && choice <= length (ambOptions amb) -> do
                      -- User selected a numbered option
                      let chosen = ambOptions amb !! (choice - 1)
                          resolved' = amb
                            { ambResolution = Just AmbiguityResolution
                                { arChosen    = aoLabel chosen
                                , arRationale = "User selected: " <> aoDescription chosen
                                }
                            }
                      liftIO $ TIO.hPutStr stderr $ "  -> Resolved: " <> aoLabel chosen <> "\n"
                      liftIO $ hFlush stderr
                      go cfg (rnd + 1) maxRounds rest (resolved' : resolved)

                  | choice == customIdx -> do
                      -- User wants custom response, prompt for it
                      mCustom <- liftIO $ runInputT defaultSettings $
                        getInputLine "  Describe your preference: "
                      handleCustomInput cfg amb rnd maxRounds rest resolved mCustom

                _ -> do
                  -- Not a valid number — treat as custom text input
                  if T.null trimmed
                    then do
                      let resolved' = autoResolve amb
                      liftIO $ TIO.hPutStr stderr "  -> Auto-resolved with highest confidence option\n"
                      liftIO $ hFlush stderr
                      go cfg (rnd + 1) maxRounds rest (resolved' : resolved)
                    else
                      handleCustomInput cfg amb rnd maxRounds rest resolved (Just answer)

    handleCustomInput :: SoelConfig -> Ambiguity -> Int -> Int
                      -> [Ambiguity] -> [Ambiguity] -> Maybe String -> App [Ambiguity]
    handleCustomInput cfg amb rnd maxRounds rest resolved mInput = case mInput of
      Nothing -> do
        let resolved' = autoResolve amb
        liftIO $ TIO.hPutStr stderr "  -> Auto-resolved with highest confidence option\n"
        liftIO $ hFlush stderr
        go cfg (rnd + 1) maxRounds rest (resolved' : resolved)
      Just input -> do
        let customText = T.strip (T.pack input)
        if T.null customText
          then do
            let resolved' = autoResolve amb
            liftIO $ TIO.hPutStr stderr "  -> Auto-resolved with highest confidence option\n"
            liftIO $ hFlush stderr
            go cfg (rnd + 1) maxRounds rest (resolved' : resolved)
          else do
            interpretation <- interpretCustomResponse amb customText sourceText cfg
            let resolved' = amb
                  { ambResolution = Just AmbiguityResolution
                      { arChosen    = interpretation
                      , arRationale = "User provided custom input: \"" <> customText <> "\""
                      }
                  }
            liftIO $ TIO.hPutStr stderr $ "  -> Resolved: " <> interpretation <> "\n"
            liftIO $ hFlush stderr
            go cfg (rnd + 1) maxRounds rest (resolved' : resolved)

-- | Use the LLM to interpret a custom user response for an ambiguity.
interpretCustomResponse :: Ambiguity -> Text -> Text -> SoelConfig -> App Text
interpretCustomResponse amb userInput sourceText cfg = do
  let systemPrompt = getPrompt "ambiguity-resolver"

  apiKey <- requireApiKeyM

  let userContentVal = ambiguityContext amb userInput sourceText
      userContent = T.pack $ BLC.unpack $ encode userContentVal

  result <- llmRequest LLMRequestOptions
    { lroApiKey      = apiKey
    , lroModel       = orModel (cfgOpenRouter cfg)
    , lroMessages    =
        [ LLMMessage RoleSystem systemPrompt
        , LLMMessage RoleUser userContent
        ]
    , lroTemperature = 0.2
    , lroMaxTokens   = Nothing
    , lroJsonMode    = False
    }

  let jsonText = extractJSON result
  case eitherDecode' (BL.fromStrict $ TE.encodeUtf8 jsonText) of
    Right (Object obj) -> case parseMaybe (.: "interpretation") obj of
      Just (String interp) -> pure interp
      _                    -> pure userInput
    _ -> pure userInput

  where
    ambiguityContext :: Ambiguity -> Text -> Text -> Value
    ambiguityContext a ui src = object
      [ "ambiguity"      .= toJSON a
      , "user_response"  .= ui
      , "source_context" .= T.take 2000 src
      ]

-- | Auto-resolve a single ambiguity by picking the highest-confidence option.
autoResolve :: Ambiguity -> Ambiguity
autoResolve amb
  | null (ambOptions amb) = amb
  | otherwise =
      let best = maximumBy (comparing aoConfidence) (ambOptions amb)
          pct  = T.pack (show (round (aoConfidence best * 100) :: Int)) <> "%"
      in  amb
            { ambResolution = Just AmbiguityResolution
                { arChosen    = aoLabel best
                , arRationale = "Auto-resolved: highest confidence option (" <> pct <> ")"
                }
            }

-- | Auto-resolve all ambiguities without user interaction.
autoResolveAll :: [Ambiguity] -> [Ambiguity]
autoResolveAll = map autoResolve

