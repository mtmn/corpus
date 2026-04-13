module Test.Main where

import Prelude

import Data.Argonaut (decodeJson, encodeJson, parseJson)
import Data.Array (length)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..))
import Effect (Effect)
import Effect.Class (liftEffect)
import Node.Process as Process
import Test.Spec (describe, it)
import Test.Spec.Assertions (shouldEqual, fail)
import Test.Spec.Reporter.Console (consoleReporter)
import Test.Spec.Runner.Node (runSpecAndExitProcess)
import Types (Listen(..), ListenBrainzResponse(..), MbidMapping(..), Payload(..), Stats(..), StatsEntry(..), TrackMetadata(..))
import Db (connect, initDb, checkExists, upsertScrobble, getScrobbles, initReleaseMetadata, upsertReleaseMetadata, getStats)
import Main (sanitizeKey, listenBrainzUrl)
import S3 (getS3Url)

main :: Effect Unit
main = do
  Process.setEnv "AWS_ENDPOINT_URL" "https://s3.example.com"
  Process.setEnv "S3_BUCKET" "my-bucket"

  runSpecAndExitProcess [consoleReporter] do
    describe "Corpus Main Utils" do
      it "should build ListenBrainz URLs correctly" do
        listenBrainzUrl "user1" `shouldEqual` "https://api.listenbrainz.org/1/user/user1/listens"

      it "should sanitize S3 keys correctly" do
        sanitizeKey "hello world!" `shouldEqual` "hello_world_"
        sanitizeKey "T.est-123" `shouldEqual` "T.est-123"
        sanitizeKey "multiple   spaces" `shouldEqual` "multiple_spaces"

    describe "Corpus Types" do
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

    describe "Corpus Database" do
      it "should handle scrobble and metadata operations" do
        conn <- connect ":memory:"
        initDb conn
        initReleaseMetadata conn

        exists1 <- checkExists conn 12345
        exists1 `shouldEqual` false

        let listen = Listen
              { trackMetadata: TrackMetadata
                  { trackName: Just "Song"
                  , artistName: Just "Artist"
                  , releaseName: Just "Album"
                  , mbidMapping: Just (MbidMapping { releaseMbid: Just "rb1", caaReleaseMbid: Nothing })
                  , genre: Nothing
                  }
              , listenedAt: Just 12345
              }
        upsertScrobble conn listen

        exists2 <- checkExists conn 12345
        exists2 `shouldEqual` true

        listens <- getScrobbles conn 10 0 Nothing
        length listens `shouldEqual` 1

        upsertReleaseMetadata conn "rb1" (Just "Rock") (Just "Label") (Just 2023)

        listensWithGenre <- getScrobbles conn 10 0 Nothing
        case listensWithGenre of
          [Listen { trackMetadata: TrackMetadata m }] -> m.genre `shouldEqual` Just "Rock"
          _ -> fail "Expected 1 listen"

        Stats s <- getStats conn
        length s.genres `shouldEqual` 1
        length s.labels `shouldEqual` 1
        length s.years `shouldEqual` 1

        -- Test Filtering (as mentioned in architecture.md)
        listensFiltered <- getScrobbles conn 10 0 (Just { field: "genre", value: "Rock" })
        length listensFiltered `shouldEqual` 1

        listensEmpty <- getScrobbles conn 10 0 (Just { field: "genre", value: "Jazz" })
        length listensEmpty `shouldEqual` 0

    describe "Corpus S3" do
      it "should generate virtual-host style S3 URLs" do
        liftEffect $ Process.setEnv "AWS_S3_ADDRESSING_STYLE" "virtual"
        let url = getS3Url "covers/test.jpg"
        url `shouldEqual` "https://my-bucket.s3.example.com/covers/test.jpg"

      it "should generate path-style S3 URLs" do
        liftEffect $ Process.setEnv "AWS_S3_ADDRESSING_STYLE" "path"
        let url = getS3Url "covers/test.jpg"
        url `shouldEqual` "https://s3.example.com/my-bucket/covers/test.jpg"
