{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DeriveGeneric #-}
module Main where

import Data.List (intercalate)
import Text.Printf (printf)

-- | Monetary amount stored as integer cents to avoid floating-point precision issues.
newtype Price = Price Integer
  deriving (Show, Eq, Ord)

-- | A customer with a name, email address, and VIP status.
data Customer = Customer
  { customerName  :: String
  , customerEmail :: String
  , customerIsVIP :: Bool
  } deriving (Show, Eq)

-- | A product with a name, price in cents, and stock quantity.
data Product = Product
  { productName  :: String
  , productPrice :: Price
  , productStock :: Int
  } deriving (Show, Eq)

-- | A single item in a shopping cart.
data CartItem = CartItem
  { cartItemProduct  :: Product
  , cartItemQuantity :: Int
  } deriving (Show, Eq)

-- | A shopping cart belonging to a customer.
data Cart = Cart
  { cartCustomer :: Customer
  , cartItems    :: [CartItem]
  } deriving (Show, Eq)

-- | The result of attempting to add an item to a cart.
data AddItemResult
  = AddSuccess { updatedCart :: Cart }
  | AddFailure { failureReason :: String }
  deriving (Show, Eq)

-- | Constructs a Price from a dollar amount and a cents amount, converting to total cents.
mkPrice :: Int -> Int -> Price
mkPrice dollars cents = Price (fromIntegral dollars * 100 + fromIntegral cents)

-- | Converts a Price (in cents) to a Double representing dollars for display purposes.
priceToDouble :: Price -> Double
priceToDouble (Price c) = fromIntegral c / 100.0

-- | Checks whether a product is currently in stock (stock quantity > 0).
isInStock :: Product -> Bool
isInStock p = productStock p > 0

-- | Checks whether a customer has VIP status.
isVIP :: Customer -> Bool
isVIP = customerIsVIP

-- | Creates an empty cart for a given customer.
emptyCart :: Customer -> Cart
emptyCart c = Cart { cartCustomer = c, cartItems = [] }

-- | Attempts to add a specified quantity of a product to a cart.
addItemToCart :: Cart -> Product -> Int -> AddItemResult
addItemToCart cart product qty
  | not (isInStock product) =
      AddFailure $ "Product '" ++ productName product ++ "' is out of stock."
  | qty <= 0 =
      AddFailure "Quantity must be greater than zero."
  | otherwise =
      AddSuccess $ cart { cartItems = cartItems cart ++ [CartItem product qty] }

-- | Calculates the subtotal for a single cart item.
cartItemSubtotal :: CartItem -> Price
cartItemSubtotal item =
  let (Price unitCents) = productPrice (cartItemProduct item)
      qty = fromIntegral (cartItemQuantity item)
  in Price (unitCents * qty)

-- | Calculates the total price of all items in a cart before any discounts.
calculateSubtotal :: Cart -> Price
calculateSubtotal cart =
  let totals = map (\item -> let (Price c) = cartItemSubtotal item in c) (cartItems cart)
  in Price (sum totals)

-- | Calculates the discount amount for a cart (10% if VIP, otherwise zero).
calculateDiscount :: Cart -> Price
calculateDiscount cart
  | isVIP (cartCustomer cart) =
      let (Price sub) = calculateSubtotal cart
      in Price (sub `div` 10)
  | otherwise = Price 0

-- | Calculates the grand total of a cart, applying VIP discount if applicable.
calculateTotal :: Cart -> Price
calculateTotal cart =
  let (Price sub) = calculateSubtotal cart
      (Price disc) = calculateDiscount cart
  in Price (sub - disc)

-- | Formats a Price value as a dollar string (e.g., "$999.99").
formatPrice :: Price -> String
formatPrice p =
  let d = priceToDouble p
  in printf "$%.2f" d

-- | Formats a single cart item as a receipt line.
formatReceiptLine :: CartItem -> String
formatReceiptLine item =
  let name = productName (cartItemProduct item)
      qty  = cartItemQuantity item
      unit = formatPrice (productPrice (cartItemProduct item))
      sub  = formatPrice (cartItemSubtotal item)
  in "  " ++ name ++ " x" ++ show qty ++ "  @ " ++ unit ++ "  = " ++ sub

-- | Generates a complete formatted receipt string for a cart.
formatReceipt :: Cart -> String
formatReceipt cart =
  let cust = cartCustomer cart
      header = "========================================\n" ++
               "  Receipt for: " ++ customerName cust ++ "\n" ++
               "  Email: " ++ customerEmail cust ++ "\n" ++
               (if isVIP cust then "  Status: VIP Customer\n" else "  Status: Regular Customer\n") ++
               "========================================\n" ++
               "Items:\n"
      items = cartItems cart
      itemLines = if null items
                  then "  (no items)\n"
                  else unlines (map formatReceiptLine items)
      subtotal = calculateSubtotal cart
      discount = calculateDiscount cart
      total    = calculateTotal cart
      separator = "----------------------------------------\n"
      subtotalLine = "  Subtotal:  " ++ formatPrice subtotal ++ "\n"
      discountLine = if isVIP cust
                     then "  VIP Discount (10%): -" ++ formatPrice discount ++ "\n"
                     else ""
      totalLine = "  Grand Total: " ++ formatPrice total ++ "\n"
      footer = "========================================"
  in header ++ itemLines ++ separator ++ subtotalLine ++ discountLine ++ totalLine ++ footer

-- | Prints a formatted receipt for the given cart to standard output.
printReceipt :: Cart -> IO ()
printReceipt cart = putStrLn (formatReceipt cart)

-- | Main entry point.
main :: IO ()
main = do
  -- Step 1: Create a regular customer (Alice) and a VIP customer (Bob)
  let alice = Customer
        { customerName  = "Alice Johnson"
        , customerEmail = "alice@example.com"
        , customerIsVIP = False
        }
  let bob = Customer
        { customerName  = "Bob Smith"
        , customerEmail = "bob@example.com"
        , customerIsVIP = True
        }

  -- Step 2: Create three products
  let laptop = Product
        { productName  = "Laptop"
        , productPrice = mkPrice 999 99
        , productStock = 10
        }
  let headphones = Product
        { productName  = "Headphones"
        , productPrice = mkPrice 49 99
        , productStock = 25
        }
  let book = Product
        { productName  = "Book"
        , productPrice = mkPrice 15 0
        , productStock = 50
        }

  -- Step 3: Create empty carts
  let aliceCart0 = emptyCart alice
  let bobCart0   = emptyCart bob

  -- Step 4: Add items to Alice's cart (headphones and a book)
  let aliceCart1 = case addItemToCart aliceCart0 headphones 1 of
        AddSuccess c -> c
        AddFailure r -> error r
  let aliceCart2 = case addItemToCart aliceCart1 book 1 of
        AddSuccess c -> c
        AddFailure r -> error r

  -- Step 5: Add items to Bob's cart (laptop and headphones)
  let bobCart1 = case addItemToCart bobCart0 laptop 1 of
        AddSuccess c -> c
        AddFailure r -> error r
  let bobCart2 = case addItemToCart bobCart1 headphones 1 of
        AddSuccess c -> c
        AddFailure r -> error r

  -- Step 6: Print receipt for Alice (no discount)
  printReceipt aliceCart2
  putStrLn ""

  -- Step 7: Print receipt for Bob (with 10% VIP discount)
  printReceipt bobCart2
```

