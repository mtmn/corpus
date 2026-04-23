module Test.Main where

import Prelude

import Unsafe.Coerce (unsafeCoerce)
import Data.Argonaut (decodeJson, encodeJson, parseJson)
import Data.Array (length)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..))
import Effect (Effect)
import Test.Spec (describe, it)
import Test.Spec.Assertions (shouldEqual, fail)
import Test.Spec.Reporter.Console (consoleReporter)
import Test.Spec.Runner.Node (runSpecAndExitProcess)
import Types (Listen(..), ListenBrainzResponse(..), MbidMapping(..), Payload(..), Stats(..), StatsEntry(..), TrackMetadata(..), ListenBrainzSubmitPayload(..), ListenBrainzSubmitListen(..), ListenBrainzSubmitTrackMetadata(..), ListenBrainzAdditionalInfo(..))
import Db (FilterField(..), connect, initDb, checkExists, upsertScrobble, getScrobbles, initReleaseMetadata, upsertReleaseMetadata, getStats, dbBaseName, getOldestTs, getUnenrichedMbids, getEmptyGenreMbids, getArtistReleasesByMbids, touchGenreCheckedAt, getOrCreateToken, getTokenUser)
import Data.Argonaut.Core (Json)
import Foreign.Object as Object
import Main (parseFilterField, submitListenToListen, findUserByToken)
import Cover (sanitizeKey)
import Sync (listenBrainzUrl, lastfmTrackToListen, parseLastfmResponse)
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

    describe "ListenBrainz Submission" do
      it "should decode a ListenBrainz submission payload" do
        let jsonStr = """
        {
          "listen_type": "single",
          "payload": [
            {
              "listened_at": 123456789,
              "track_metadata": {
                "track_name": "Song Name",
                "artist_name": "Artist Name",
                "release_name": "Album Name",
                "additional_info": {
                  "release_mbid": "rel-mbid",
                  "artist_mbids": ["art-mbid"],
                  "recording_mbid": "rec-mbid"
                }
              }
            }
          ]
        }
        """
        let result = parseJson jsonStr >>= decodeJson
        case result of
          Right (ListenBrainzSubmitPayload { listenType, payload }) -> do
            listenType `shouldEqual` "single"
            length payload `shouldEqual` 1
            case payload of
              [ListenBrainzSubmitListen { listenedAt, trackMetadata: ListenBrainzSubmitTrackMetadata m }] -> do
                listenedAt `shouldEqual` Just 123456789
                m.trackName `shouldEqual` "Song Name"
                m.artistName `shouldEqual` "Artist Name"
                m.releaseName `shouldEqual` Just "Album Name"
                case m.additionalInfo of
                  Just (ListenBrainzAdditionalInfo info) -> do
                    info.releaseMbid `shouldEqual` Just "rel-mbid"
                  Nothing -> do
                    fail "Expected additional_info"
              _ -> do
                fail "Expected 1 listen"
          Left err -> do
            fail $ "Decoding failed: " <> show err

      it "should convert ListenBrainzSubmitListen to Listen correctly" do
        let submission = ListenBrainzSubmitListen
              { listenedAt: Just 123456789
              , trackMetadata: ListenBrainzSubmitTrackMetadata
                  { trackName: "Song Name"
                  , artistName: "Artist Name"
                  , releaseName: Just "Album Name"
                  , additionalInfo: Just (ListenBrainzAdditionalInfo
                      { releaseMbid: Just "rel-mbid"
                      , artistMbids: Just ["art-mbid"]
                      , recordingMbid: Just "rec-mbid"
                      })
                  }
              }
        case submitListenToListen "single" submission of
          Just (Listen { listenedAt, trackMetadata: TrackMetadata m }) -> do
            listenedAt `shouldEqual` Just 123456789
            m.trackName `shouldEqual` Just "Song Name"
            m.artistName `shouldEqual` Just "Artist Name"
            m.releaseName `shouldEqual` Just "Album Name"
            m.mbidMapping `shouldEqual` Just (MbidMapping { releaseMbid: Just "rel-mbid", caaReleaseMbid: Just "rel-mbid" })
          Nothing -> do
            fail "Conversion failed"

      it "should ignore playing_now listens" do
        let submission = ListenBrainzSubmitListen
              { listenedAt: Nothing
              , trackMetadata: ListenBrainzSubmitTrackMetadata
                  { trackName: "Song Name"
                  , artistName: "Artist Name"
                  , releaseName: Nothing
                  , additionalInfo: Nothing
                  }
              }
        submitListenToListen "playing_now" submission `shouldEqual` Nothing

    describe "Token Authentication" do
      it "should create and verify tokens" do
        conn <- connect ":memory:"
        initDb conn
        mToken <- getOrCreateToken conn "user1"
        case mToken of
          Nothing -> do
            fail "Failed to create token"
          Just token -> do
            mSlug <- getTokenUser conn token
            mSlug `shouldEqual` Just "user1"

            mSlugWrong <- getTokenUser conn "wrong-token"
            mSlugWrong `shouldEqual` Nothing

      it "should find user by token across multiple contexts" do
        conn1 <- connect ":memory:"
        initDb conn1
        conn2 <- connect ":memory:"
        initDb conn2

        mToken1 <- getOrCreateToken conn1 "user1"
        mToken2 <- getOrCreateToken conn2 "user2"

        case mToken1, mToken2 of
          Just token1, Just token2 -> do
            let
              dummyConfig =
                { listenbrainzUser: Nothing
                , lastfmUser: Nothing
                , lastfmApiKey: Nothing
                , discogsToken: Nothing
                , cosineApiKey: Nothing
                , databaseFile: ""
                , s3Bucket: Nothing
                , s3Region: ""
                , awsAccessKeyId: Nothing
                , awsSecretAccessKey: Nothing
                , awsEndpointUrl: Nothing
                , awsS3AddressingStyle: Nothing
                , coverCacheEnabled: false
                , backupEnabled: false
                , backupIntervalHours: 0
                }
              ctx1 = { conn: conn1, writeLock: unsafeCoerce unit, config: dummyConfig, slug: "user1", displayName: "User 1", enrichMetadataFiber: Nothing, backupFiber: Nothing }
              ctx2 = { conn: conn2, writeLock: unsafeCoerce unit, config: dummyConfig, slug: "user2", displayName: "User 2", enrichMetadataFiber: Nothing, backupFiber: Nothing }
              contexts = [ ctx1, ctx2 ]

            res1 <- findUserByToken contexts token1
            map _.slug res1 `shouldEqual` Just "user1"

            res2 <- findUserByToken contexts token2
            map _.slug res2 `shouldEqual` Just "user2"

            resNone <- findUserByToken contexts "invalid"
            map _.slug resNone `shouldEqual` Nothing
          _, _ -> do
            fail "Failed to create tokens"

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

      describe "parseLastfmResponse" do
        it "parses standard response with multiple tracks" do
          let j = parseTrack """
            {
              "recenttracks": {
                "track": [
                  { "name": "Track 1" },
                  { "name": "Track 2" }
                ],
                "@attr": { "totalPages": "10" }
              }
            }
          """
          case parseLastfmResponse j of
            Just { tracks, totalPages } -> do
              length tracks `shouldEqual` 2
              totalPages `shouldEqual` 10
            Nothing -> do
              fail "Should have parsed"

        it "parses response with a single track (as object)" do
          let j = parseTrack """
            {
              "recenttracks": {
                "track": { "name": "Single Track" },
                "@attr": { "totalPages": "1" }
              }
            }
          """
          case parseLastfmResponse j of
            Just { tracks, totalPages } -> do
              length tracks `shouldEqual` 1
              totalPages `shouldEqual` 1
            Nothing -> do
              fail "Should have parsed single track object"

        it "parses response with no tracks" do
          let j = parseTrack """
            {
              "recenttracks": {
                "@attr": { "totalPages": "0" }
              }
            }
          """
          case parseLastfmResponse j of
            Just { tracks, totalPages } -> do
              length tracks `shouldEqual` 0
              totalPages `shouldEqual` 0
            Nothing -> do
              fail "Should have parsed empty tracks"

        it "parses response where totalPages is a number" do
          let j = parseTrack """
            {
              "recenttracks": {
                "track": [],
                "@attr": { "totalPages": 5 }
              }
            }
          """
          case parseLastfmResponse j of
            Just { totalPages } -> do
              totalPages `shouldEqual` 5
            Nothing -> do
              fail "Should have parsed numeric totalPages"

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
