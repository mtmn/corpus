module Image (arrayBufferByteLength, convertToAvif) where

import Prelude

import Control.Promise (Promise, toAffE)
import Data.ArrayBuffer.Types (ArrayBuffer)
import Effect (Effect)
import Effect.Aff (Aff)

foreign import convertToAvifImpl :: ArrayBuffer -> Effect (Promise ArrayBuffer)
foreign import arrayBufferByteLengthImpl :: ArrayBuffer -> Effect Number

-- | Convert an image buffer to AVIF.
convertToAvif :: ArrayBuffer -> Aff ArrayBuffer
convertToAvif = toAffE <<< convertToAvifImpl

-- | Return an array buffer's byte length.
arrayBufferByteLength :: ArrayBuffer -> Effect Number
arrayBufferByteLength = arrayBufferByteLengthImpl
