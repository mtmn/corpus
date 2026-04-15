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
import Db (connect, initDb, checkExists, upsertScrobble, getScrobbles, initReleaseMetadata, upsertReleaseMetadata, getStats, dirName, performBackup)
import Data.Argonaut.Core (Json)
import Main (sanitizeKey, listenBrainzUrl, lastfmTrackToListen)
import S3 (getS3Url)
import Node.FS.Aff as FSA
import Node.FS.Perms (mkPerms, all, read) as Perms
import Effect.Aff (try)

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
                , artists: [StatsEntry { name: "Artist", count: 7 }]
                , tracks: [StatsEntry { name: "Artist — Song", count: 3 }]
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

        Stats s <- getStats conn Nothing Nothing Nothing Nothing
        length s.genres `shouldEqual` 1
        length s.labels `shouldEqual` 1
        length s.years `shouldEqual` 1
        length s.artists `shouldEqual` 1
        length s.tracks `shouldEqual` 1

        -- Test Filtering (as mentioned in architecture.md)
        listensFiltered <- getScrobbles conn 10 0 (Just { field: "genre", value: "Rock" })
        length listensFiltered `shouldEqual` 1

        listensEmpty <- getScrobbles conn 10 0 (Just { field: "genre", value: "Jazz" })
        length listensEmpty `shouldEqual` 0

    describe "Corpus Backup" do
      describe "dirName" do
        it "extracts directory from an absolute path" do
          dirName "/app/data/corpus.db" `shouldEqual` "/app/data/"
        it "extracts directory from a nested path" do
          dirName "/tmp/test/corpus.db" `shouldEqual` "/tmp/test/"
        it "returns ./ for a bare filename" do
          dirName "corpus.db" `shouldEqual` "./"

      it "local backup creates a file in backup/ alongside the db" do
        let testDir = "/tmp/corpus-backup-test"
        let dbPath = testDir <> "/corpus.db"
        let backupDir = testDir <> "/backup"
        -- clean up any previous run
        void $ try $ FSA.rm' testDir { force: true, recursive: true, maxRetries: 0, retryDelay: 100 }
        FSA.mkdir' testDir { recursive: true, mode: Perms.mkPerms Perms.all Perms.all Perms.read }
        conn <- connect dbPath
        initDb conn
        initReleaseMetadata conn
        performBackup conn dbPath
        files <- FSA.readdir backupDir
        length files `shouldEqual` 1
        -- cleanup
        void $ try $ FSA.rm' testDir { force: true, recursive: true, maxRetries: 0, retryDelay: 100 }

    describe "Last.fm Support" do
      let parseTrack :: String -> Json
          parseTrack s = case parseJson s of
            Right j -> j
            Left _ -> encodeJson ([] :: Array Int)  -- fallback that will produce Nothing

      describe "lastfmTrackToListen" do
        it "parses a valid track with MBID" do
          let j = parseTrack """
            {
              "name": "Test Track",
              "artist": { "#text": "Test Artist" },
              "album": { "#text": "Test Album", "mbid": "album-mbid-123" },
              "date": { "uts": "1600000000", "#text": "13 Sep 2020, 12:00" }
            }
          """
          case lastfmTrackToListen j of
            Nothing -> fail "Expected Just Listen, got Nothing"
            Just (Listen { listenedAt, trackMetadata: TrackMetadata m }) -> do
              listenedAt `shouldEqual` Just 1600000000
              m.trackName `shouldEqual` Just "Test Track"
              m.artistName `shouldEqual` Just "Test Artist"
              m.releaseName `shouldEqual` Just "Test Album"
              m.mbidMapping `shouldEqual` Just (MbidMapping { releaseMbid: Just "album-mbid-123", caaReleaseMbid: Just "album-mbid-123" })

        it "treats empty album MBID as Nothing" do
          let j = parseTrack """
            {
              "name": "Track",
              "artist": { "#text": "Artist" },
              "album": { "#text": "Album", "mbid": "" },
              "date": { "uts": "1600000001", "#text": "13 Sep 2020, 12:01" }
            }
          """
          case lastfmTrackToListen j of
            Nothing -> fail "Expected Just Listen, got Nothing"
            Just (Listen { trackMetadata: TrackMetadata m }) ->
              m.mbidMapping `shouldEqual` Just (MbidMapping { releaseMbid: Nothing, caaReleaseMbid: Nothing })

        it "skips nowplaying tracks (no date field)" do
          let j = parseTrack """
            {
              "@attr": { "nowplaying": "true" },
              "name": "Now Playing Track",
              "artist": { "#text": "Artist" },
              "album": { "#text": "Album", "mbid": "" }
            }
          """
          lastfmTrackToListen j `shouldEqual` Nothing

        it "returns Nothing when artist field is missing" do
          let j = parseTrack """
            {
              "name": "Track",
              "album": { "#text": "Album", "mbid": "" },
              "date": { "uts": "1600000002", "#text": "13 Sep 2020, 12:02" }
            }
          """
          lastfmTrackToListen j `shouldEqual` Nothing

        it "returns Nothing when date.uts is not a valid integer" do
          let j = parseTrack """
            {
              "name": "Track",
              "artist": { "#text": "Artist" },
              "album": { "#text": "Album", "mbid": "" },
              "date": { "uts": "not-a-number", "#text": "?" }
            }
          """
          lastfmTrackToListen j `shouldEqual` Nothing

        it "uses album MBID for both releaseMbid and caaReleaseMbid" do
          let j = parseTrack """
            {
              "name": "Track",
              "artist": { "#text": "Artist" },
              "album": { "#text": "Album", "mbid": "mbid-xyz" },
              "date": { "uts": "1600000003", "#text": "13 Sep 2020, 12:03" }
            }
          """
          case lastfmTrackToListen j of
            Nothing -> fail "Expected Just Listen, got Nothing"
            Just (Listen { trackMetadata: TrackMetadata m }) ->
              m.mbidMapping `shouldEqual` Just (MbidMapping { releaseMbid: Just "mbid-xyz", caaReleaseMbid: Just "mbid-xyz" })

        it "inserts and retrieves a Last.fm-style listen from the database" do
          conn <- connect ":memory:"
          initDb conn
          initReleaseMetadata conn
          let j = parseTrack """
            {
              "name": "Last.fm Track",
              "artist": { "#text": "Last.fm Artist" },
              "album": { "#text": "Last.fm Album", "mbid": "" },
              "date": { "uts": "1700000000", "#text": "14 Nov 2023, 22:13" }
            }
          """
          case lastfmTrackToListen j of
            Nothing -> fail "lastfmTrackToListen returned Nothing"
            Just listen -> do
              upsertScrobble conn listen
              exists <- checkExists conn 1700000000
              exists `shouldEqual` true
              listens <- getScrobbles conn 10 0 Nothing
              length listens `shouldEqual` 1

    describe "Corpus S3" do
      it "should generate virtual-host style S3 URLs" do
        liftEffect $ Process.setEnv "AWS_S3_ADDRESSING_STYLE" "virtual"
        let url = getS3Url "covers/test.jpg"
        url `shouldEqual` "https://my-bucket.s3.example.com/covers/test.jpg"

      it "should generate path-style S3 URLs" do
        liftEffect $ Process.setEnv "AWS_S3_ADDRESSING_STYLE" "path"
        let url = getS3Url "covers/test.jpg"
        url `shouldEqual` "https://s3.example.com/my-bucket/covers/test.jpg"
