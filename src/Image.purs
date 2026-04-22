module Image (convertToAvif) where

import Prelude
import Control.Promise (Promise, toAffE)
import Effect (Effect)
import Effect.Aff (Aff)
import Data.ArrayBuffer.Types (ArrayBuffer)

foreign import convertToAvifImpl :: ArrayBuffer -> Effect (Promise ArrayBuffer)

convertToAvif :: ArrayBuffer -> Aff ArrayBuffer
convertToAvif = toAffE <<< convertToAvifImpl
