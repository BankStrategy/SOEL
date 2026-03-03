{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DeriveGeneric #-}
module Main where

import GHC.Generics (Generic)

-- | Represents one of four arithmetic operations: Add, Subtract, Multiply, or Divide.
data Operation = Add | Subtract | Multiply | Divide
  deriving (Show, Eq, Generic)

-- | Takes two numbers and an operation, and returns the result.
-- Returns Nothing when dividing by zero to indicate an error.
calculate :: Double -> Double -> Operation -> Maybe Double
calculate a b Add      = Just (a + b)
calculate a b Subtract = Just (a - b)
calculate a b Multiply = Just (a * b)
calculate a b Divide
  | b == 0    = Nothing
  | otherwise = Just (a / b)

-- | Prints a labeled calculation result, handling both Just and Nothing cases.
printResult :: String -> Maybe Double -> IO ()
printResult label (Just val) = putStrLn (label ++ " = " ++ show val)
printResult label Nothing    = putStrLn (label ++ " = Error (division by zero)")

-- | Demonstrates each arithmetic operation with sample numbers and prints the results,
-- including a division by zero case.
main :: IO ()
main = do
  -- Calculate 10 + 5 using calculate 10 5 Add and print the result
  printResult "10 + 5" (calculate 10 5 Add)

  -- Calculate 20 - 8 using calculate 20 8 Subtract and print the result
  printResult "20 - 8" (calculate 20 8 Subtract)

  -- Calculate 6 * 7 using calculate 6 7 Multiply and print the result
  printResult "6 * 7" (calculate 6 7 Multiply)

  -- Calculate 15 / 3 using calculate 15 3 Divide and print the result
  printResult "15 / 3" (calculate 15 3 Divide)

  -- Calculate 15 / 0 using calculate 15 0 Divide and print the result to demonstrate division by zero returning Nothing
  printResult "15 / 0" (calculate 15 0 Divide)
```

