-----------------------------------------------------------------------------
-- | Module     :  Data.These
--
-- The 'These' type and associated operations. Now enhanced with "Control.Lens" magic!
{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE DeriveGeneric      #-}
{-# LANGUAGE OverloadedStrings  #-}
module Data.These (
      These(..)

    -- * Functions to get rid of 'These'
    , these
    , fromThese
    , mergeThese
    , mergeTheseWith

    -- * Traversals
    , here, there

    -- * Half selections
    , justHere
    , justThere

    -- * Prisms
    , _This, _That, _These

    -- * Case selections
    , justThis
    , justThat
    , justThese

    , catThis
    , catThat
    , catThese

    , partitionThese

    -- * Case predicates
    , isThis
    , isThat
    , isThese

    -- * Map operations
    , mapThese
    , mapThis
    , mapThat

    , bitraverseThese

    -- * Associativity and commutativity
    , swap
    , assoc
    , reassoc
    ) where

import Prelude ()
import Prelude.Compat

import Control.DeepSeq              (NFData (..))
import Control.Lens                 (Prism', Swapped (..), iso, prism)
import Data.Aeson                   (FromJSON (..), ToJSON (..), (.=))
import Data.Bifoldable              (Bifoldable (..))
import Data.Bifunctor               (Bifunctor (..))
import Data.Binary                  (Binary (..))
import Data.Bitraversable           (Bitraversable (..))
import Data.Data                    (Data, Typeable)
import Data.Functor.Bind            (Apply (..), Bind (..))
import Data.Hashable                (Hashable (..))
import Data.Maybe                   (isJust, mapMaybe)
import Data.Semigroup               (Semigroup (..))
import Data.Semigroup.Bifoldable    (Bifoldable1 (..))
import Data.Semigroup.Bitraversable (Bitraversable1 (..))
import GHC.Generics                 (Generic)
import Test.QuickCheck
       (Arbitrary (..), Arbitrary1 (..), Arbitrary2 (..), CoArbitrary (..),
       arbitrary1, oneof, shrink1)
import Test.QuickCheck.Function     (Function (..), functionMap)

import qualified Data.Aeson          as Aeson
import qualified Data.Aeson.Encoding as Aeson (pair)
import qualified Data.HashMap.Strict as HM

-- $setup
-- >>> import Control.Lens

-- --------------------------------------------------------------------------
-- | The 'These' type represents values with two non-exclusive possibilities.
--
--   This can be useful to represent combinations of two values, where the
--   combination is defined if either input is. Algebraically, the type
--   @'These' A B@ represents @(A + B + AB)@, which doesn't factor easily into
--   sums and products--a type like @'Either' A (B, 'Maybe' A)@ is unclear and
--   awkward to use.
--
--   'These' has straightforward instances of 'Functor', 'Monad', &c., and
--   behaves like a hybrid error/writer monad, as would be expected.
--
--   For zipping and unzipping of structures with 'These' values, see
--   "Data.Align".
data These a b = This a | That b | These a b
    deriving (Eq, Ord, Read, Show, Typeable, Data, Generic)

-- | Case analysis for the 'These' type.
these :: (a -> c) -> (b -> c) -> (a -> b -> c) -> These a b -> c
these l _ _ (This a) = l a
these _ r _ (That x) = r x
these _ _ lr (These a x) = lr a x

-- | Takes two default values and produces a tuple.
fromThese :: a -> b -> These a b -> (a, b)
fromThese _ x (This a   ) = (a, x)
fromThese a _ (That x   ) = (a, x)
fromThese _ _ (These a x) = (a, x)

-- | Coalesce with the provided operation.
mergeThese :: (a -> a -> a) -> These a a -> a
mergeThese = these id id

-- | BiMap and coalesce results with the provided operation.
mergeTheseWith :: (a -> c) -> (b -> c) -> (c -> c -> c) -> These a b -> c
mergeTheseWith f g op t = mergeThese op $ mapThese f g t

-- | A 'Control.Lens.Traversal' of the first half of a 'These', suitable for use with "Control.Lens".
--
-- @
-- 'here' :: 'Control.Lens.Traversal' ('These' a t) ('These' b t) a b
-- @
--
-- >>> over here show (That 1)
-- That 1
--
-- >>> over here show (These 'a' 2)
-- These "'a'" 2
--
here :: (Applicative f) => (a -> f b) -> These a t -> f (These b t)
here f (This x) = This <$> f x
here f (These x y) = flip These y <$> f x
here _ (That x) = pure (That x)

-- | A 'Control.Lens.Traversal' of the second half of a 'These', suitable for use with "Control.Lens".
--
-- @
-- 'there' :: 'Control.Lens.Traversal' ('These' t b) ('These' t b) a b
-- @
--
-- >>> over there show (That 1)
-- That "1"
--
-- >>> over there show (These 'a' 2)
-- These 'a' "2"
--
there :: (Applicative f) => (a -> f b) -> These t a -> f (These t b)
there _ (This x) = pure (This x)
there f (These x y) = These x <$> f y
there f (That x) = That <$> f x

-- | @'justHere' = 'Control.Lens.preview' 'here'@
--
-- >>> justHere (This 'x')
-- Just 'x'
--
-- >>> justHere (That 'y')
-- Nothing
--
-- >>> justHere (These 'x' 'y')
-- Just 'x'
--
justHere :: These a b -> Maybe a
justHere (This a)    = Just a
justHere (That _)    = Nothing
justHere (These a _) = Just a

-- | @'justThere' = 'Control.Lens.preview' 'there'@
--
-- >>> justThere (This 'x')
-- Nothing
--
-- >>> justThere (That 'y')
-- Just 'y'
--
-- >>> justThere (These 'x' 'y')
-- Just 'y'
--
justThere :: These a b -> Maybe b
justThere (This _)    = Nothing
justThere (That b)    = Just b
justThere (These _ b) = Just b

-- | A 'Control.Lens.Prism'' selecting the 'This' constructor.
--
-- /Note:/ cannot change type.
_This :: Prism' (These a b) a
_This = prism This (these Right (Left . That) (\x y -> Left $ These x y))

-- | A 'Control.Lens.Prism'' selecting the 'That' constructor.
--
-- /Note:/ cannot change type.
_That :: Prism' (These a b) b
_That = prism That (these (Left . This) Right (\x y -> Left $ These x y))

-- | A 'Control.Lens.Prism'' selecting the 'These' constructor. 'These' names are ridiculous!
--
-- /Note:/ cannot change type.
_These :: Prism' (These a b) (a, b)
_These = prism (uncurry These) (these (Left . This) (Left . That) (\x y -> Right (x, y)))


-- | @'justThis' = 'Control.Lens.preview' '_This'@
justThis :: These a b -> Maybe a
justThis (This a) = Just a
justThis _        = Nothing

-- | @'justThat' = 'Control.Lens.preview' '_That'@
justThat :: These a b -> Maybe b
justThat (That x) = Just x
justThat _        = Nothing

-- | @'justThese' = 'Control.Lens.preview' '_These'@
justThese :: These a b -> Maybe (a, b)
justThese (These a x) = Just (a, x)
justThese _           = Nothing


isThis, isThat, isThese :: These a b -> Bool
-- | @'isThis' = 'isJust' . 'justThis'@
isThis  = isJust . justThis

-- | @'isThat' = 'isJust' . 'justThat'@
isThat  = isJust . justThat

-- | @'isThese' = 'isJust' . 'justThese'@
isThese = isJust . justThese

-- | 'Bifunctor' map.
mapThese :: (a -> c) -> (b -> d) -> These a b -> These c d
mapThese f _ (This  a  ) = This (f a)
mapThese _ g (That    x) = That (g x)
mapThese f g (These a x) = These (f a) (g x)

-- | 'Bitraversable'.
--
-- @since 0.7.5
bitraverseThese :: Applicative f => (a -> f c) -> (b -> f d) -> These a b -> f (These c d)
bitraverseThese f _ (This x) = This <$> f x
bitraverseThese _ g (That x) = That <$> g x
bitraverseThese f g (These x y) = These <$> f x <*> g y

-- | @'mapThis' = 'Control.Lens.over' 'here'@
mapThis :: (a -> c) -> These a b -> These c b
mapThis f = mapThese f id

-- | @'mapThat' = 'Control.Lens.over' 'there'@
mapThat :: (b -> d) -> These a b -> These a d
mapThat f = mapThese id f

-- | Select all 'This' constructors from a list.
catThis :: [These a b] -> [a]
catThis = mapMaybe justThis

-- | Select all 'That' constructors from a list.
catThat :: [These a b] -> [b]
catThat = mapMaybe justThat

-- | Select all 'These' constructors from a list.
catThese :: [These a b] -> [(a, b)]
catThese = mapMaybe justThese

-- | Select each constructor and partition them into separate lists.
partitionThese :: [These a b] -> ( [(a, b)], ([a], [b]) )
partitionThese []             = ([], ([], []))
partitionThese (These x y:xs) = first ((x, y):)      $ partitionThese xs
partitionThese (This  x  :xs) = second (first  (x:)) $ partitionThese xs
partitionThese (That    y:xs) = second (second (y:)) $ partitionThese xs

-- | 'These' is commutative.
--
-- @
-- 'swap' . 'swap' = 'id'
-- @
--
-- @since 0.7.6
swap :: These a b -> These b a
swap (This a)    = That a
swap (That b)    = This b
swap (These a b) = These b a

-- | 'These' is associative.
--
-- @
-- 'assoc' . 'reassoc' = 'id'
-- 'reassoc' . 'assoc' = 'id'
-- @
--
-- @since 0.7.6
assoc :: These a (These b c) -> These (These a b) c
assoc (This a)              = This (This a)
assoc (That (This b))       = This (That b)
assoc (That (That c))       = That c
assoc (That (These b c))    = These (That b) c
assoc (These a (This b))    = This (These a b)
assoc (These a (That c))    = These (This a) c
assoc (These a (These b c)) = These (These a b) c

-- | 'These is associative. See 'assoc'.
--
-- @since 0.7.6
reassoc :: These (These a b) c -> These a (These b c)
reassoc (This (This a))       = This a
reassoc (This (That b))       = That (This b)
reassoc (That c)              = That (That c)
reassoc (These (That b) c)    = That (These b c)
reassoc (This (These a b))    = These a (This b)
reassoc (These (This a) c)    = These a (That c)
reassoc (These (These a b) c) = These a (These b c)

-------------------------------------------------------------------------------
-- Instances
-------------------------------------------------------------------------------

instance (Semigroup a, Semigroup b) => Semigroup (These a b) where
    This  a   <> This  b   = This  (a <> b)
    This  a   <> That    y = These  a             y
    This  a   <> These b y = These (a <> b)       y
    That    x <> This  b   = These       b   x
    That    x <> That    y = That           (x <> y)
    That    x <> These b y = These       b  (x <> y)
    These a x <> This  b   = These (a <> b)  x
    These a x <> That    y = These  a       (x <> y)
    These a x <> These b y = These (a <> b) (x <> y)

instance Functor (These a) where
    fmap _ (This x) = This x
    fmap f (That y) = That (f y)
    fmap f (These x y) = These x (f y)

instance Foldable (These a) where
    foldr _ z (This _) = z
    foldr f z (That x) = f x z
    foldr f z (These _ x) = f x z

instance Traversable (These a) where
    traverse _ (This a) = pure $ This a
    traverse f (That x) = That <$> f x
    traverse f (These a x) = These a <$> f x
    sequenceA (This a) = pure $ This a
    sequenceA (That x) = That <$> x
    sequenceA (These a x) = These a <$> x

instance Bifunctor These where
    bimap = mapThese
    first = mapThis
    second = mapThat

instance Bifoldable These where
    bifold = these id id mappend
    bifoldr f g z = these (`f` z) (`g` z) (\x y -> x `f` (y `g` z))
    bifoldl f g z = these (z `f`) (z `g`) (\x y -> (z `f` x) `g` y)

instance Bifoldable1 These where
    bifold1 = these id id (<>)

instance Bitraversable These where
    bitraverse = bitraverseThese

instance Bitraversable1 These where
    bitraverse1 f _ (This x) = This <$> f x
    bitraverse1 _ g (That x) = That <$> g x
    bitraverse1 f g (These x y) = These <$> f x <.> g y

-- | @since 0.7.6
instance Swapped These where
    swapped = iso swap swap

instance (Semigroup a) => Apply (These a) where
    This  a   <.> _         = This a
    That    _ <.> This  b   = This b
    That    f <.> That    x = That (f x)
    That    f <.> These b x = These b (f x)
    These a _ <.> This  b   = This (a <> b)
    These a f <.> That    x = These a (f x)
    These a f <.> These b x = These (a <> b) (f x)

instance (Semigroup a) => Applicative (These a) where
    pure = That
    (<*>) = (<.>)

instance (Semigroup a) => Bind (These a) where
    This  a   >>- _ = This a
    That    x >>- k = k x
    These a x >>- k = case k x of
                          This  b   -> This  (a <> b)
                          That    y -> These a y
                          These b y -> These (a <> b) y

instance (Semigroup a) => Monad (These a) where
    return = pure
    (>>=) = (>>-)

instance (Hashable a, Hashable b) => Hashable (These a b)

-- | @since 0.7.1
instance (NFData a, NFData b) => NFData (These a b) where
    rnf (This a)    = rnf a
    rnf (That b)    = rnf b
    rnf (These a b) = rnf a `seq` rnf b

-- | @since 0.7.1
instance (Binary a, Binary b) => Binary (These a b) where
    put (This a)    = put (0 :: Int) >> put a
    put (That b)    = put (1 :: Int) >> put b
    put (These a b) = put (2 :: Int) >> put a >> put b

    get = do
        i <- get
        case (i :: Int) of
            0 -> This <$> get
            1 -> That <$> get
            2 -> These <$> get <*> get
            _ -> fail "Invalid These index"

-- | @since 0.7.1
instance (ToJSON a, ToJSON b) => ToJSON (These a b) where
    toJSON (This a)    = Aeson.object [ "This" .= a ]
    toJSON (That b)    = Aeson.object [ "That" .= b ]
    toJSON (These a b) = Aeson.object [ "This" .= a, "That" .= b ]

    toEncoding (This a)    = Aeson.pairs $ "This" .= a
    toEncoding (That b)    = Aeson.pairs $ "That" .= b
    toEncoding (These a b) = Aeson.pairs $ "This" .= a <> "That" .= b

-- | @since 0.7.1
instance (FromJSON a, FromJSON b) => FromJSON (These a b) where
    parseJSON = Aeson.withObject "These a b" (p . HM.toList)
      where
        p [("This", a), ("That", b)] = These <$> parseJSON a <*> parseJSON b
        p [("That", b), ("This", a)] = These <$> parseJSON a <*> parseJSON b
        p [("This", a)] = This <$> parseJSON a
        p [("That", b)] = That <$> parseJSON b
        p _  = fail "Expected object with 'This' and 'That' keys only"

-- | @since 0.7.2
instance Aeson.ToJSON2 These where
    liftToJSON2  toa _ _tob _ (This a)    = Aeson.object [ "This" .= toa a ]
    liftToJSON2 _toa _  tob _ (That b)    = Aeson.object [ "That" .= tob b ]
    liftToJSON2  toa _  tob _ (These a b) = Aeson.object [ "This" .= toa a, "That" .= tob b ]

    liftToEncoding2  toa _ _tob _ (This a)    = Aeson.pairs $ Aeson.pair "This" (toa a)
    liftToEncoding2 _toa _  tob _ (That b)    = Aeson.pairs $ Aeson.pair "That" (tob b)
    liftToEncoding2  toa _  tob _ (These a b) = Aeson.pairs $ Aeson.pair "This" (toa a) <> Aeson.pair "That" (tob b)

-- | @since 0.7.2
instance ToJSON a => Aeson.ToJSON1 (These a) where
    liftToJSON _tob _ (This a)    = Aeson.object [ "This" .= a ]
    liftToJSON  tob _ (That b)    = Aeson.object [ "That" .= tob b ]
    liftToJSON  tob _ (These a b) = Aeson.object [ "This" .= a, "That" .= tob b ]

    liftToEncoding _tob _ (This a)    = Aeson.pairs $ "This" .= a
    liftToEncoding  tob _ (That b)    = Aeson.pairs $ Aeson.pair "That" (tob b)
    liftToEncoding  tob _ (These a b) = Aeson.pairs $ "This" .= a <> Aeson.pair "That" (tob b)

-- | @since 0.7.2
instance Aeson.FromJSON2 These where
    liftParseJSON2 pa _ pb _ = Aeson.withObject "These a b" (p . HM.toList)
      where
        p [("This", a), ("That", b)] = These <$> pa a <*> pb b
        p [("That", b), ("This", a)] = These <$> pa a <*> pb b
        p [("This", a)] = This <$> pa a
        p [("That", b)] = That <$> pb b
        p _  = fail "Expected object with 'This' and 'That' keys only"

-- | @since 0.7.2
instance FromJSON a => Aeson.FromJSON1 (These a) where
    liftParseJSON pb _ = Aeson.withObject "These a b" (p . HM.toList)
      where
        p [("This", a), ("That", b)] = These <$> parseJSON a <*> pb b
        p [("That", b), ("This", a)] = These <$> parseJSON a <*> pb b
        p [("This", a)] = This <$> parseJSON a
        p [("That", b)] = That <$> pb b
        p _  = fail "Expected object with 'This' and 'That' keys only"

-- | @since 0.7.4
instance Arbitrary2 These where
    liftArbitrary2 arbA arbB = oneof
        [ This <$> arbA
        , That <$> arbB
        , These <$> arbA <*> arbB
        ]

    liftShrink2  shrA _shrB (This x) = This <$> shrA x
    liftShrink2 _shrA  shrB (That y) = That <$> shrB y
    liftShrink2  shrA  shrB (These x y) =
        [This x, That y] ++ [These x' y' | (x', y') <- liftShrink2 shrA shrB (x, y)]

-- | @since 0.7.4
instance (Arbitrary a) => Arbitrary1 (These a) where
    liftArbitrary = liftArbitrary2 arbitrary
    liftShrink = liftShrink2 shrink

-- | @since 0.7.1
instance (Arbitrary a, Arbitrary b) => Arbitrary (These a b) where
    arbitrary = arbitrary1
    shrink = shrink1

-- | @since 0.7.1
instance (Function a, Function b) => Function (These a b) where
  function = functionMap g f
    where
      g (This a)    = Left a
      g (That b)    = Right (Left b)
      g (These a b) = Right (Right (a, b))

      f (Left a)               = This a
      f (Right (Left b))       = That b
      f (Right (Right (a, b))) = These a b

-- | @since 0.7.1
instance (CoArbitrary a, CoArbitrary b) => CoArbitrary (These a b)
