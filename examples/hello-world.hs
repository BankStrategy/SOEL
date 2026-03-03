{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DeriveGeneric #-}
module Main where

import GHC.Generics (Generic)

-- | A greeter entity that has a name and a greeting message.
data Greeter = Greeter
  { greeterName    :: String
  , greeterMessage :: String
  } deriving (Show, Eq, Generic)

-- | Creates a Greeter with the given name and greeting message.
makeGreeter :: String -> String -> Greeter
makeGreeter name msg = Greeter { greeterName = name, greeterMessage = msg }

-- | Produces a personalized greeting string in the form 'Nice to meet you, [name]!'.
personalGreeting :: String -> String
personalGreeting name = "Nice to meet you, " ++ name ++ "!"

-- | Prints the greeter's message to the screen.
displayGreeting :: Greeter -> IO ()
displayGreeting g = putStrLn (greeterMessage g)

-- | Prompts the user for their name and reads the input.
askUserName :: IO String
askUserName = do
  putStrLn "What is your name?"
  getLine

-- | Prints a personalized greeting using the user's name.
greetPersonally :: String -> IO ()
greetPersonally name = putStrLn (personalGreeting name)

-- | Main entry point: creates a greeter named 'SOEL' with the message 'Hello, World!',
-- displays the greeting, asks the user for their name, and greets them personally.
main :: IO ()
main = do
  let greeter = makeGreeter "SOEL" "Hello, World!"
  displayGreeting greeter
  name <- askUserName
  greetPersonally name
```

