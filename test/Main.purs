module Test.Main where

import Prelude

import Data.Argonaut (decodeJson, encodeJson, parseJson)
import Data.Array (length)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..))
import Effect (Effect)
import Test.Spec (describe, it)
import Test.Spec.Assertions (shouldEqual, fail)
import Test.Spec.Reporter.Console (consoleReporter)
import Test.Spec.Runner.Node (runSpecAndExitProcess)
import Types (Listen(..), ListenBrainzResponse(..), MbidMapping(..), Payload(..), Stats(..), StatsEntry(..), TrackMetadata(..))
import Db (FilterField(..), connect, initDb, checkExists, upsertScrobble, getScrobbles, initReleaseMetadata, upsertReleaseMetadata, getStats, dbBaseName, getOldestTs, getUnenrichedMbids, getEmptyGenreMbids, getArtistReleasesByMbids, touchGenreCheckedAt)
import Data.Argonaut.Core (Json)
import Foreign.Object as Object
import Main (listenBrainzUrl, lastfmTrackToListen, parseFilterField)
import Cover (sanitizeKey)
import S3 (getS3Url)

main :: Effect Unit
main = runSpecAndExitProcess [consoleReporter] do
    describe "Corpus Main Utils" do
      it "should build ListenBrainz URLs correctly" do
        listenBrainzUrl "user1" `shouldEqual` "https://api.listenbrainz.org/1/user/user1/listens"

      it "should sanitize S3 keys correctly" do
        sanitizeKey "hello world!" `shouldEqual` "hello_world_"
        sanitizeKey "T.est-123" `shouldEqual` "T.est-123"
        sanitizeKey "multiple   spaces" `shouldEqual` "multiple_spaces"

      describe "parseFilterField" do
        it "maps all valid field names" do
          parseFilterField "artist" `shouldEqual` Just FilterArtist
          parseFilterField "album" `shouldEqual` Just FilterAlbum
          parseFilterField "label" `shouldEqual` Just FilterLabel
          parseFilterField "year" `shouldEqual` Just FilterYear
          parseFilterField "genre" `shouldEqual` Just FilterGenre

        it "returns Nothing for unknown or empty input" do
          parseFilterField "unknown" `shouldEqual` Nothing
          parseFilterField "" `shouldEqual` Nothing

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
                , label: Nothing
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
                    , label: Nothing
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
                  , label: Nothing
                  }
              , listenedAt: Just 12345
              }
        upsertScrobble conn listen

        exists2 <- checkExists conn 12345
        exists2 `shouldEqual` true

        listens <- getScrobbles conn 10 0 Nothing Nothing
        length listens `shouldEqual` 1

        upsertReleaseMetadata conn "rb1" (Just "Rock") (Just "Label") (Just 2023)

        listensWithGenre <- getScrobbles conn 10 0 Nothing Nothing
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
        listensFiltered <- getScrobbles conn 10 0 (Just { field: FilterGenre, value: "Rock" }) Nothing
        length listensFiltered `shouldEqual` 1

        listensEmpty <- getScrobbles conn 10 0 (Just { field: FilterGenre, value: "Jazz" }) Nothing
        length listensEmpty `shouldEqual` 0

      it "upsertScrobble is idempotent" do
        conn <- connect ":memory:"
        initDb conn
        initReleaseMetadata conn
        let listen = Listen
              { listenedAt: Just 55555
              , trackMetadata: TrackMetadata
                  { trackName: Just "Song"
                  , artistName: Just "Artist"
                  , releaseName: Just "Album"
                  , mbidMapping: Just (MbidMapping { releaseMbid: Just "mb1", caaReleaseMbid: Nothing })
                  , genre: Nothing
                  , label: Nothing
                  }
              }
        upsertScrobble conn listen
        upsertScrobble conn listen
        listens <- getScrobbles conn 10 0 Nothing Nothing
        length listens `shouldEqual` 1

      describe "getScrobbles filter variants" do
        it "filters by artist" do
          conn <- connect ":memory:"
          initDb conn
          initReleaseMetadata conn
          let
            mkListen ts artist = Listen
              { listenedAt: Just ts
              , trackMetadata: TrackMetadata
                  { trackName: Just "Song"
                  , artistName: Just artist
                  , releaseName: Nothing
                  , mbidMapping: Nothing
                  , genre: Nothing
                  , label: Nothing
                  }
              }
          upsertScrobble conn (mkListen 1 "Alpha")
          upsertScrobble conn (mkListen 2 "Beta")
          listens <- getScrobbles conn 10 0 (Just { field: FilterArtist, value: "Alpha" }) Nothing
          length listens `shouldEqual` 1
          listensNone <- getScrobbles conn 10 0 (Just { field: FilterArtist, value: "Gamma" }) Nothing
          length listensNone `shouldEqual` 0

        it "filters by album" do
          conn <- connect ":memory:"
          initDb conn
          initReleaseMetadata conn
          let mkListen artist release = Listen
                { listenedAt: Just 1
                , trackMetadata: TrackMetadata
                    { trackName: Just "Track"
                    , artistName: Just artist
                    , releaseName: Just release
                    , mbidMapping: Nothing
                    , genre: Nothing
                    , label: Nothing
                    }
                }
          upsertScrobble conn (mkListen "Artist" "Album A")
          upsertScrobble conn (mkListen "Artist" "Album B")
          listens <- getScrobbles conn 10 0 (Just { field: FilterAlbum, value: "Album A" }) Nothing
          length listens `shouldEqual` 1
          listensNone <- getScrobbles conn 10 0 (Just { field: FilterAlbum, value: "Album C" }) Nothing
          length listensNone `shouldEqual` 0

        it "filters by label" do
          conn <- connect ":memory:"
          initDb conn
          initReleaseMetadata conn
          upsertScrobble conn
            ( Listen
                { listenedAt: Just 100
                , trackMetadata: TrackMetadata
                    { trackName: Just "Song"
                    , artistName: Just "Artist"
                    , releaseName: Just "Album"
                    , mbidMapping: Just (MbidMapping { releaseMbid: Just "mb-label", caaReleaseMbid: Nothing })
                    , genre: Nothing
                    , label: Nothing
                    }
                }
            )
          upsertReleaseMetadata conn "mb-label" Nothing (Just "Warp") (Just 2000)
          listens <- getScrobbles conn 10 0 (Just { field: FilterLabel, value: "Warp" }) Nothing
          length listens `shouldEqual` 1
          listensNone <- getScrobbles conn 10 0 (Just { field: FilterLabel, value: "Columbia" }) Nothing
          length listensNone `shouldEqual` 0

        it "filters by year" do
          conn <- connect ":memory:"
          initDb conn
          initReleaseMetadata conn
          upsertScrobble conn
            ( Listen
                { listenedAt: Just 200
                , trackMetadata: TrackMetadata
                    { trackName: Just "Song"
                    , artistName: Just "Artist"
                    , releaseName: Just "Album"
                    , mbidMapping: Just (MbidMapping { releaseMbid: Just "mb-year", caaReleaseMbid: Nothing })
                    , genre: Nothing
                    , label: Nothing
                    }
                }
            )
          upsertReleaseMetadata conn "mb-year" Nothing Nothing (Just 1994)
          listens <- getScrobbles conn 10 0 (Just { field: FilterYear, value: "1994" }) Nothing
          length listens `shouldEqual` 1
          listensNone <- getScrobbles conn 10 0 (Just { field: FilterYear, value: "1999" }) Nothing
          length listensNone `shouldEqual` 0

      describe "getOldestTs" do
        let
          listenAt ts = Listen
            { listenedAt: Just ts
            , trackMetadata: TrackMetadata
                { trackName: Just "T"
                , artistName: Just "A"
                , releaseName: Nothing
                , mbidMapping: Nothing
                , genre: Nothing
                , label: Nothing
                }
            }
        it "returns Nothing for an empty database" do
          conn <- connect ":memory:"
          initDb conn
          result <- getOldestTs conn
          result `shouldEqual` Nothing

        it "returns the minimum listened_at" do
          conn <- connect ":memory:"
          initDb conn
          upsertScrobble conn (listenAt 300)
          upsertScrobble conn (listenAt 100)
          upsertScrobble conn (listenAt 200)
          result <- getOldestTs conn
          result `shouldEqual` Just 100

      describe "getUnenrichedMbids" do
        let
          listenWith ts mbid = Listen
            { listenedAt: Just ts
            , trackMetadata: TrackMetadata
                { trackName: Just "T"
                , artistName: Just "A"
                , releaseName: Just "R"
                , mbidMapping: Just (MbidMapping { releaseMbid: Just mbid, caaReleaseMbid: Nothing })
                , genre: Nothing
                , label: Nothing
                }
            }
        it "returns MBIDs not yet in release_metadata" do
          conn <- connect ":memory:"
          initDb conn
          initReleaseMetadata conn
          upsertScrobble conn (listenWith 1000 "un-mbid")
          mbids <- getUnenrichedMbids conn 10
          mbids `shouldEqual` [ "un-mbid" ]

        it "excludes MBIDs already in release_metadata" do
          conn <- connect ":memory:"
          initDb conn
          initReleaseMetadata conn
          upsertScrobble conn (listenWith 2000 "enriched")
          upsertReleaseMetadata conn "enriched" (Just "Rock") (Just "Label") (Just 2020)
          mbids <- getUnenrichedMbids conn 10
          mbids `shouldEqual` []

        it "excludes scrobbles with empty release_mbid" do
          conn <- connect ":memory:"
          initDb conn
          initReleaseMetadata conn
          upsertScrobble conn
            ( Listen
                { listenedAt: Just 3000
                , trackMetadata: TrackMetadata
                    { trackName: Just "T"
                    , artistName: Just "A"
                    , releaseName: Nothing
                    , mbidMapping: Nothing
                    , genre: Nothing
                    , label: Nothing
                    }
                }
            )
          mbids <- getUnenrichedMbids conn 10
          mbids `shouldEqual` []

      describe "getEmptyGenreMbids" do
        let
          listenWith ts mbid = Listen
            { listenedAt: Just ts
            , trackMetadata: TrackMetadata
                { trackName: Just "T"
                , artistName: Just "A"
                , releaseName: Just "R"
                , mbidMapping: Just (MbidMapping { releaseMbid: Just mbid, caaReleaseMbid: Nothing })
                , genre: Nothing
                , label: Nothing
                }
            }
        it "returns MBIDs whose genre is null in release_metadata" do
          conn <- connect ":memory:"
          initDb conn
          initReleaseMetadata conn
          upsertScrobble conn (listenWith 4000 "eg-mbid")
          upsertReleaseMetadata conn "eg-mbid" Nothing (Just "Label") (Just 2020)
          mbids <- getEmptyGenreMbids conn 10
          mbids `shouldEqual` [ "eg-mbid" ]

        it "excludes MBIDs recently checked via touchGenreCheckedAt" do
          conn <- connect ":memory:"
          initDb conn
          initReleaseMetadata conn
          upsertScrobble conn (listenWith 5000 "touched")
          upsertReleaseMetadata conn "touched" Nothing Nothing Nothing
          touchGenreCheckedAt conn "touched"
          mbids <- getEmptyGenreMbids conn 10
          mbids `shouldEqual` []

      describe "getArtistReleasesByMbids" do
        it "returns empty object for empty input" do
          conn <- connect ":memory:"
          initDb conn
          result <- getArtistReleasesByMbids conn []
          result `shouldEqual` Object.empty

        it "returns artist and release name indexed by MBID" do
          conn <- connect ":memory:"
          initDb conn
          upsertScrobble conn
            ( Listen
                { listenedAt: Just 6000
                , trackMetadata: TrackMetadata
                    { trackName: Just "Song"
                    , artistName: Just "My Artist"
                    , releaseName: Just "My Album"
                    , mbidMapping: Just (MbidMapping { releaseMbid: Just "ar-mbid", caaReleaseMbid: Nothing })
                    , genre: Nothing
                    , label: Nothing
                    }
                }
            )
          result <- getArtistReleasesByMbids conn [ "ar-mbid" ]
          Object.lookup "ar-mbid" result `shouldEqual` Just { artist: "My Artist", release: "My Album" }

    describe "Corpus Backup" do
      describe "dbBaseName" do
        it "extracts base name from an absolute path" do
          dbBaseName "/app/data/corpus.db" `shouldEqual` "corpus"
        it "extracts base name from a nested path" do
          dbBaseName "/tmp/test/mymusic.db" `shouldEqual` "mymusic"
        it "returns the name without extension for a bare filename" do
          dbBaseName "corpus.db" `shouldEqual` "corpus"

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
            Nothing ->
              fail "Expected Just Listen, got Nothing"
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
            Nothing ->
              fail "Expected Just Listen, got Nothing"
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
            Nothing ->
              fail "Expected Just Listen, got Nothing"
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
            Nothing ->
              fail "lastfmTrackToListen returned Nothing"
            Just listen -> do
              upsertScrobble conn listen
              exists <- checkExists conn 1700000000
              exists `shouldEqual` true
              listens <- getScrobbles conn 10 0 Nothing Nothing
              length listens `shouldEqual` 1

    describe "Corpus S3" do
      it "should generate virtual-host style S3 URLs" do
        let
          cfg =
            { bucket: Just "my-bucket"
            , region: "us-east-1"
            , accessKeyId: Nothing
            , secretAccessKey: Nothing
            , endpointUrl: Just "https://s3.example.com"
            , addressingStyle: Just "virtual"
            }
        getS3Url cfg "covers/test.jpg" `shouldEqual` "https://my-bucket.s3.example.com/covers/test.jpg"

      it "should generate path-style S3 URLs" do
        let
          cfg =
            { bucket: Just "my-bucket"
            , region: "us-east-1"
            , accessKeyId: Nothing
            , secretAccessKey: Nothing
            , endpointUrl: Just "https://s3.example.com"
            , addressingStyle: Just "path"
            }
        getS3Url cfg "covers/test.jpg" `shouldEqual` "https://s3.example.com/my-bucket/covers/test.jpg"
