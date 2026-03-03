{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DeriveGeneric     #-}
{-# LANGUAGE RecordWildCards   #-}

module Soel.Cache.Store
  ( getCached
  , setCache
  ) where

import Control.Monad.Except (throwError)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Reader (ask)
import Data.Aeson (FromJSON, ToJSON, Value, eitherDecode, encode, object, (.=), withObject, (.:))
import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Lazy as BL
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time.Clock.POSIX (getPOSIXTime)
import GHC.Generics (Generic)
import System.Directory (createDirectoryIfMissing, doesFileExist, getCurrentDirectory)
import System.FilePath ((</>))

import Soel.Types (App, SoelError(..))
import Soel.Utils.Logger (logDebug)

-- | Cache directory name.
cacheDir :: String
cacheDir = ".soel-cache"

-- | A cache entry wrapping data with a hash and timestamp.
data CacheEntry = CacheEntry
  { ceHash      :: !Text
  , ceTimestamp  :: !Double
  , ceData      :: !Value
  } deriving (Show, Generic)

instance FromJSON CacheEntry where
  parseJSON = withObject "CacheEntry" $ \v -> do
    ceHash     <- v .: "hash"
    ceTimestamp <- v .: "timestamp"
    ceData     <- v .: "data"
    pure CacheEntry{..}

instance ToJSON CacheEntry where
  toJSON CacheEntry{..} = object
    [ "hash"      .= ceHash
    , "timestamp"  .= ceTimestamp
    , "data"       .= ceData
    ]

-- | Sanitize a cache key for use as a filename.
sanitizeKey :: Text -> String
sanitizeKey = T.unpack . T.map (\c -> if isAllowed c then c else '_')
  where
    isAllowed c = c `elem` (['a'..'z'] ++ ['A'..'Z'] ++ ['0'..'9'] ++ ['_', '-'])

-- | Get the cache directory path, creating it if needed.
getCacheDir :: IO FilePath
getCacheDir = do
  cwd <- getCurrentDirectory
  let dir = cwd </> cacheDir
  createDirectoryIfMissing True dir
  pure dir

-- | Get the path for a cache file.
cacheFilePath :: Text -> IO FilePath
cacheFilePath key = do
  dir <- getCacheDir
  pure $ dir </> sanitizeKey key <> ".json"

-- | Look up a cached value by key and hash. Returns Nothing on miss.
getCached :: FromJSON a => Text -> Text -> App (Maybe a)
getCached key hash = do
  _ <- ask  -- ensure we're in App context
  liftIO $ do
    path <- cacheFilePath key
    exists <- doesFileExist path
    if not exists
      then pure Nothing
      else do
        bs <- BL.readFile path
        case eitherDecode bs of
          Left _ -> pure Nothing
          Right entry ->
            if ceHash entry == hash
              then do
                logDebug $ "Cache hit: " <> key
                case Aeson.fromJSON (ceData entry) of
                  Aeson.Success val -> pure (Just val)
                  Aeson.Error _     -> pure Nothing
              else do
                logDebug $ "Cache miss (hash mismatch): " <> key
                pure Nothing

-- | Store a value in the cache.
setCache :: ToJSON a => Text -> Text -> a -> App ()
setCache key hash val = do
  _ <- ask
  liftIO $ do
    path <- cacheFilePath key
    now <- realToFrac <$> getPOSIXTime :: IO Double
    let entry = CacheEntry
          { ceHash     = hash
          , ceTimestamp = now * 1000  -- milliseconds like JS Date.now()
          , ceData     = Aeson.toJSON val
          }
    BL.writeFile path (encode entry)
    logDebug $ "Cached: " <> key
