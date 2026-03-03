{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards   #-}
{-# LANGUAGE DeriveGeneric     #-}

module Soel.LLM.OpenRouter
  ( LLMRole(..)
  , LLMMessage(..)
  , LLMRequestOptions(..)
  , llmRequest
  , extractJSON
  ) where

import Control.Monad.Except (throwError)
import Control.Monad.IO.Class (liftIO)
import Data.Aeson (ToJSON(..), FromJSON(..), Value(..), (.=), (.:), (.:?),
                   object, withObject, encode, eitherDecode')
import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Lazy as BL
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import GHC.Generics (Generic)
import Network.HTTP.Client
  (httpLbs, newManager, parseRequest, method, requestHeaders,
   requestBody, RequestBody(..), responseStatus, responseBody)
import Network.HTTP.Client.TLS (tlsManagerSettings)
import Network.HTTP.Types.Status (statusCode)
import Soel.Types (App, SoelError(..))
import Soel.Utils.Logger (logDebug)

--------------------------------------------------------------------------------
-- Types
--------------------------------------------------------------------------------

data LLMRole = RoleSystem | RoleUser | RoleAssistant
  deriving (Show, Eq, Generic)

instance ToJSON LLMRole where
  toJSON RoleSystem    = String "system"
  toJSON RoleUser      = String "user"
  toJSON RoleAssistant = String "assistant"

instance FromJSON LLMRole where
  parseJSON = Aeson.withText "LLMRole" $ \t -> case t of
    "system"    -> pure RoleSystem
    "user"      -> pure RoleUser
    "assistant" -> pure RoleAssistant
    other       -> fail $ "Unknown LLM role: " <> T.unpack other

data LLMMessage = LLMMessage
  { lmRole    :: !LLMRole
  , lmContent :: !Text
  } deriving (Show, Eq, Generic)

instance ToJSON LLMMessage where
  toJSON LLMMessage{..} = object
    [ "role"    .= lmRole
    , "content" .= lmContent
    ]

instance FromJSON LLMMessage where
  parseJSON = withObject "LLMMessage" $ \v ->
    LLMMessage <$> v .: "role" <*> v .: "content"

data LLMRequestOptions = LLMRequestOptions
  { lroApiKey      :: !Text
  , lroModel       :: !Text
  , lroMessages    :: ![LLMMessage]
  , lroTemperature :: !Double
  , lroMaxTokens   :: !(Maybe Int)
  , lroJsonMode    :: !Bool
  } deriving (Show, Eq)

--------------------------------------------------------------------------------
-- OpenRouter API Response
--------------------------------------------------------------------------------

data ORUsage = ORUsage
  { usagePromptTokens     :: !Int
  , usageCompletionTokens :: !Int
  , usageTotalTokens      :: !Int
  } deriving (Show, Generic)

instance FromJSON ORUsage where
  parseJSON = withObject "ORUsage" $ \v ->
    ORUsage <$> v .: "prompt_tokens"
            <*> v .: "completion_tokens"
            <*> v .: "total_tokens"

data ORChoice = ORChoice
  { choiceMessage :: !ORChoiceMessage
  } deriving (Show, Generic)

instance FromJSON ORChoice where
  parseJSON = withObject "ORChoice" $ \v ->
    ORChoice <$> v .: "message"

data ORChoiceMessage = ORChoiceMessage
  { cmContent :: !(Maybe Text)
  } deriving (Show, Generic)

instance FromJSON ORChoiceMessage where
  parseJSON = withObject "ORChoiceMessage" $ \v ->
    ORChoiceMessage <$> v .:? "content"

data ORResponse = ORResponse
  { orChoices :: ![ORChoice]
  , orUsage   :: !(Maybe ORUsage)
  } deriving (Show, Generic)

instance FromJSON ORResponse where
  parseJSON = withObject "ORResponse" $ \v ->
    ORResponse <$> v .: "choices" <*> v .:? "usage"

--------------------------------------------------------------------------------
-- API Endpoint
--------------------------------------------------------------------------------

openRouterURL :: String
openRouterURL = "https://openrouter.ai/api/v1/chat/completions"

--------------------------------------------------------------------------------
-- llmRequest
--------------------------------------------------------------------------------

llmRequest :: LLMRequestOptions -> App Text
llmRequest LLMRequestOptions{..} = do
  -- Build the request body
  let bodyObj = object $
        [ "model"      .= lroModel
        , "messages"   .= lroMessages
        , "temperature" .= lroTemperature
        ] ++ [ "max_tokens" .= n | Just n <- [lroMaxTokens]
             ] ++ [ "response_format" .= object ["type" .= ("json_object" :: Text)]
             | lroJsonMode
             ]

  let bodyBS = encode bodyObj

  -- Build HTTP request
  initReq <- liftIO $ parseRequest openRouterURL
  manager <- liftIO $ newManager tlsManagerSettings

  let req = initReq
        { method = "POST"
        , requestHeaders =
            [ ("Authorization", TE.encodeUtf8 $ "Bearer " <> lroApiKey)
            , ("Content-Type", "application/json")
            , ("HTTP-Referer", "https://github.com/soel-lang/soel")
            , ("X-Title", "SOEL Compiler")
            ]
        , requestBody = RequestBodyLBS bodyBS
        }

  -- Perform the request
  res <- liftIO $ httpLbs req manager

  let status = statusCode (responseStatus res)
      resBody = responseBody res
      resText = TE.decodeUtf8 $ BL.toStrict resBody

  -- Check for non-2xx status
  if status < 200 || status >= 300
    then throwError $ OpenRouterError
           ("OpenRouter API error: " <> T.pack (show status))
           status
           resText
    else pure ()

  -- Parse response JSON
  case eitherDecode' resBody :: Either String ORResponse of
    Left err -> throwError $ OpenRouterError
      ("Failed to parse OpenRouter response: " <> T.pack err)
      status
      resText
    Right orResp -> do
      -- Extract content from first choice
      let mContent = case orChoices orResp of
            (c:_) -> cmContent (choiceMessage c)
            []    -> Nothing

      case mContent of
        Nothing -> throwError $ OpenRouterError
          "Empty response from OpenRouter" 0 ""
        Just content -> do
          -- Log token usage at debug level
          case orUsage orResp of
            Just usage -> liftIO $ logDebug $
              "Tokens: " <> T.pack (show (usagePromptTokens usage))
              <> " in, " <> T.pack (show (usageCompletionTokens usage)) <> " out"
            Nothing -> pure ()
          pure content

--------------------------------------------------------------------------------
-- extractJSON
--------------------------------------------------------------------------------

-- | Extract JSON from an LLM response that may contain markdown fences or
-- extra text.
extractJSON :: Text -> Text
extractJSON input =
  case extractFenced input of
    Just result -> T.strip result
    Nothing     -> case extractRawJSON input of
      Just result -> T.strip result
      Nothing     -> T.strip input

-- | Try to find JSON inside ```json ... ``` or ``` ... ``` fences.
extractFenced :: Text -> Maybe Text
extractFenced s =
  let ls = T.lines s
      isOpenFence l = T.isPrefixOf "```" (T.stripStart l)
      isCloseFence l = T.strip l == "```"
  in case break isOpenFence ls of
       (_, [])       -> Nothing
       (_, _open:rest) ->
         case break isCloseFence (reverse rest) of
           (_, [])     -> Nothing
           (after, _)  -> let body = T.unlines (reverse after)
                          in if T.null (T.strip body) then Nothing else Just body

-- | Try to find a raw JSON object or array by finding first open and last close delimiter.
extractRawJSON :: Text -> Maybe Text
extractRawJSON s =
  case extractBracketed '{' '}' s of
    Just t  -> Just t
    Nothing -> extractBracketed '[' ']' s
  where
    extractBracketed :: Char -> Char -> Text -> Maybe Text
    extractBracketed open close txt = do
      start <- T.findIndex (== open) txt
      let rest = T.drop start txt
      -- Find last occurrence of close bracket by reversing
      endFromBack <- T.findIndex (== close) (T.reverse rest)
      let end = T.length rest - 1 - endFromBack
      if end >= 0
        then Just (T.take (end + 1) rest)
        else Nothing
