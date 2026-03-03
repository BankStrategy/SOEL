{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DeriveGeneric #-}

module Main where

-- | Represents one of four arithmetic operations: Add, Subtract, Multiply, or Divide.
data Operation
  = Add
  | Subtract
  | Multiply
  | Divide
  deriving (Show, Eq)

-- | Takes two numbers and an operation, and returns the result.
-- Returns Nothing when dividing by zero to indicate an error.
calculate :: Double -> Double -> Operation -> Maybe Double
calculate x y Add      = Just (x + y)
calculate x y Subtract = Just (x - y)
calculate x y Multiply = Just (x * y)
calculate x y Divide
  | y == 0    = Nothing
  | otherwise = Just (x / y)

-- | Prints a labeled calculation result, handling the Nothing case for division by zero.
printResult :: String -> Maybe Double -> IO ()
printResult label Nothing  = putStrLn $ label ++ " = Error: Division by zero (Nothing)"
printResult label (Just v) = putStrLn $ label ++ " = " ++ show v

-- | Entry point: demonstrates each arithmetic operation with sample numbers and prints the results.
main :: IO ()
main = do
  let result1 = calculate 10 5 Add
  printResult "10 + 5" result1

  let result2 = calculate 20 8 Subtract
  printResult "20 - 8" result2

  let result3 = calculate 6 7 Multiply
  printResult "6 * 7" result3

  let result4 = calculate 15 3 Divide
  printResult "15 / 3" result4

  let result5 = calculate 15 0 Divide
  printResult "15 / 0" result5
