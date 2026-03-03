{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DeriveGeneric #-}
module Main where

import GHC.Generics (Generic)

-- | Represents a greeter entity that has a name and a greeting message
data Greeter = Greeter
  { greeterName    :: String
  , greeterMessage :: String
  } deriving (Show, Eq, Generic)

-- | Creates a Greeter with the given name and greeting message
mkGreeter :: String -> String -> Greeter
mkGreeter name message = Greeter { greeterName = name, greeterMessage = message }

-- | Produces a personalized greeting string in the form 'Nice to meet you, [name]!'
personalGreeting :: String -> String
personalGreeting name = "Nice to meet you, " ++ name ++ "!"

-- | Prints the greeter's message to the screen (stdout)
displayGreeting :: Greeter -> IO ()
displayGreeting greeter = putStrLn (greeterMessage greeter)

-- | Prompts the user for their name and reads it from stdin
askUserName :: IO String
askUserName = do
  putStr "What is your name? "
  getLine

-- | Prints a personalized greeting for the user using their name
greetPersonally :: String -> IO ()
greetPersonally name = putStrLn (personalGreeting name)

-- | Main entry point: creates a greeter named 'SOEL' with the message 'Hello, World!',
-- displays the greeting, asks the user for their name, and greets them personally.
main :: IO ()
main = do
  -- Create a Greeter with name 'SOEL' and message 'Hello, World!'
  let greeter = mkGreeter "SOEL" "Hello, World!"
  -- Display the greeter's message by printing it to the screen
  displayGreeting greeter
  -- Ask the user for their name by reading from stdin
  name <- askUserName
  -- Greet the user personally by printing 'Nice to meet you, [name]!'
  greetPersonally name
```

