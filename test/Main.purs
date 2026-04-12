module Test.Main where

import Prelude

import Data.Argonaut (decodeJson, encodeJson, parseJson)
import Data.Array (length)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..))
import Effect (Effect)
import Effect.Aff (launchAff_)
import Test.Spec (describe, it)
import Test.Spec.Assertions (shouldEqual, fail)
import Test.Spec.Reporter.Console (consoleReporter)
import Test.Spec.Runner (runSpec)
import Types (Listen(..), ListenBrainzResponse(..), MbidMapping(..), Payload(..), Stats(..), StatsEntry(..), TrackMetadata(..))
import Db (connect, initDb, checkExists, upsertScrobble, getScrobbles, initReleaseMetadata, upsertReleaseMetadata, getStats)

main :: Effect Unit
main = launchAff_ $ runSpec [consoleReporter] do
  describe "Scorpus Types" do
    describe "MbidMapping Codecs" do
      it "should roundtrip MbidMapping" do
        let mbid = MbidMapping { releaseMbid: Just "release-123", caaReleaseMbid: Just "caa-456" }
        decodeJson (encodeJson mbid) `shouldEqual` Right mbid

      it "should decode MbidMapping with missing fields" do
        let jsonStr = "{\"release_mbid\": \"abc\"}"
        let expected = MbidMapping { releaseMbid: Just "abc", caaReleaseMbid: Nothing }
        (parseJson jsonStr >>= decodeJson) `shouldEqual` Right expected

    describe "TrackMetadata Codecs" do
      it "should roundtrip TrackMetadata" do
        let meta = TrackMetadata
              { trackName: Just "Song"
              , artistName: Just "Artist"
              , releaseName: Just "Album"
              , mbidMapping: Just (MbidMapping { releaseMbid: Just "rb", caaReleaseMbid: Nothing })
              , genre: Just "Rock"
              }
        decodeJson (encodeJson meta) `shouldEqual` Right meta

    describe "Listen Codecs" do
      it "should roundtrip Listen" do
        let listen = Listen
              { trackMetadata: TrackMetadata
                  { trackName: Just "Song"
                  , artistName: Just "Artist"
                  , releaseName: Nothing
                  , mbidMapping: Nothing
                  , genre: Nothing
                  }
              , listenedAt: Just 1600000000
              }
        decodeJson (encodeJson listen) `shouldEqual` Right listen

    describe "Stats Codecs" do
      it "should roundtrip Stats" do
        let stats = Stats
              { genres: [StatsEntry { name: "Rock", count: 10 }]
              , labels: [StatsEntry { name: "Label", count: 5 }]
              , years: [StatsEntry { name: "2023", count: 15 }]
              }
        decodeJson (encodeJson stats) `shouldEqual` Right stats

    describe "ListenBrainzResponse Codecs" do
      it "should decode a full ListenBrainz response" do
        let jsonStr = """
        {
          "payload": {
            "listens": [
              {
                "listened_at": 123456789,
                "track_metadata": {
                  "track_name": "Test Track",
                  "artist_name": "Test Artist",
                  "release_name": "Test Album",
                  "mbid_mapping": {
                    "release_mbid": "rel-mbid",
                    "caa_release_mbid": "caa-mbid"
                  }
                }
              }
            ]
          }
        }
        """
        let result = parseJson jsonStr >>= decodeJson
        case result of
          Right (ListenBrainzResponse { payload: Payload { listens } }) -> do
            length listens `shouldEqual` 1
          Left err ->
            fail $ "Decoding failed: " <> show err
