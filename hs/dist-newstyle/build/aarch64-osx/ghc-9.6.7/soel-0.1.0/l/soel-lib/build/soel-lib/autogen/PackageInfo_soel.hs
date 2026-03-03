{-# LANGUAGE NoRebindableSyntax #-}
{-# OPTIONS_GHC -fno-warn-missing-import-lists #-}
{-# OPTIONS_GHC -w #-}
module PackageInfo_soel (
    name,
    version,
    synopsis,
    copyright,
    homepage,
  ) where

import Data.Version (Version(..))
import Prelude

name :: String
name = "soel"
version :: Version
version = Version [0,1,0] []

synopsis :: String
synopsis = "SOEL \8212 Semantic Open-Ended Language compiler"
copyright :: String
copyright = ""
homepage :: String
homepage = ""
